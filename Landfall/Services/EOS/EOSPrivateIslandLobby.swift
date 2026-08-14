#if EOS_SDK_AVAILABLE && !targetEnvironment(simulator)
import EOSSDK
import Foundation

enum EOSPrivateIslandLobbySessionError: LocalizedError, Equatable {
    case missingSessionLocator
    case invalidSessionLocator(actualBytes: Int, minimumBytes: Int, maximumBytes: Int)
    case ambiguousSessionLocator

    var errorDescription: String? {
        switch self {
        case .missingSessionLocator:
            return "The EOS private-island session locator is missing."
        case let .invalidSessionLocator(actualBytes, minimumBytes, maximumBytes):
            return "The EOS private-island session locator is invalid (\(actualBytes) bytes; expected \(minimumBytes)...\(maximumBytes) printable ASCII bytes)."
        case .ambiguousSessionLocator:
            return "More than one EOS lobby matched the private-island session locator."
        }
    }
}

/// Owns one authenticated user's EOS Lobby membership.
///
/// The locator is an opaque, high-entropy control-plane value. It must remain
/// independent from all user-facing room identifiers.
/// All EOS calls, including handle release, are confined to `EOSSDKRuntime`'s
/// worker thread.
@MainActor
final class EOSPrivateIslandLobbySession {
    struct Snapshot {
        let lobbyID: String
        let ownerProductUserID: EOS_ProductUserId
        let memberProductUserIDs: [EOS_ProductUserId]
    }

    /// Notifications only signal that cached membership should be refreshed.
    /// The callback is delivered on the main actor and carries no trusted data.
    var onMembershipChanged: (@Sendable () -> Void)?

    private static let maximumMembers: UInt32 = 8
    private static let minimumLocatorBytes = 32
    private static let maximumLocatorBytes = 64
    private static let locatorAttributeKey = "sessionLocator"
    private static let bucketID = "landfall-private-island-v1"
    // A cryptographically random, exact-match locator should have at most one
    // result. Keep the SDK response bounded even if a bad deployment contains
    // duplicate or hostile metadata.
    private static let maximumSearchResults: UInt32 = 10

    private struct ActiveLobby {
        let sessionLocator: String
        let lobbyID: String
        let localUserID: EOS_ProductUserId
    }

    private struct SearchMatch {
        let lobbyID: String
        let detailsHandle: EOS_HLobbyDetails
    }

    private struct NotificationRegistration {
        let identifier: EOS_NotificationId
        let clientData: UnsafeMutableRawPointer
    }

    private final class StringCallbackBox {
        let operation: String
        let continuation: CheckedContinuation<String, Error>

        init(
            operation: String,
            continuation: CheckedContinuation<String, Error>
        ) {
            self.operation = operation
            self.continuation = continuation
        }
    }

    private final class ResultCallbackBox {
        let operation: String
        let expectedLobbyID: String?
        let continuation: CheckedContinuation<Void, Error>

        init(
            operation: String,
            expectedLobbyID: String? = nil,
            continuation: CheckedContinuation<Void, Error>
        ) {
            self.operation = operation
            self.expectedLobbyID = expectedLobbyID
            self.continuation = continuation
        }
    }

    private final class MembershipNotificationBox {
        weak var session: EOSPrivateIslandLobbySession?

        init(session: EOSPrivateIslandLobbySession) {
            self.session = session
        }

        func signal(lobbyID: String) {
            Task { @MainActor [weak session] in
                session?.membershipDidChange(lobbyID: lobbyID)
            }
        }
    }

    private let runtime: EOSSDKRuntime
    private var activeLobby: ActiveLobby?
    private var notificationRegistration: NotificationRegistration?

    init(runtime: EOSSDKRuntime) {
        self.runtime = runtime
    }

    deinit {
        let registration = notificationRegistration
        let activeLobby = activeLobby
        guard registration != nil || activeLobby != nil else { return }

        do {
            try runtime.schedule { context in
                if let activeLobby {
                    activeLobby.lobbyID.withCString { lobbyID in
                        var options = EOS_Lobby_LeaveLobbyOptions()
                        options.ApiVersion = EOS_LOBBY_LEAVELOBBY_API_LATEST
                        options.LocalUserId = activeLobby.localUserID
                        options.LobbyId = lobbyID
                        EOS_Lobby_LeaveLobby(context.lobby, &options, nil, nil)
                    }
                }
                if let registration {
                    EOS_Lobby_RemoveNotifyLobbyMemberStatusReceived(
                        context.lobby,
                        registration.identifier
                    )
                    Unmanaged<MembershipNotificationBox>
                        .fromOpaque(registration.clientData)
                        .release()
                }
            }
        } catch {
            if let registration {
                Unmanaged<MembershipNotificationBox>
                    .fromOpaque(registration.clientData)
                    .release()
            }
        }
    }

    /// Finds and joins an existing lobby, or creates it when explicitly
    /// authorized by `createsIfMissing`.
    func start(
        sessionLocator: String,
        localUserID: EOS_ProductUserId,
        createsIfMissing: Bool
    ) async throws -> Snapshot {
        try Self.validate(sessionLocator: sessionLocator)
        guard await runtime.isValid(localUserID) else {
            throw EOSPrivateIslandRuntimeError.invalidProductUserID
        }

        if let activeLobby {
            guard activeLobby.sessionLocator == sessionLocator,
                  activeLobby.localUserID == localUserID
            else {
                throw EOSPrivateIslandRuntimeError.lobbyIdentityChanged
            }
            return try await refresh(localUserID: localUserID)
        }

        try await ensureMembershipNotification()
        do {
            if let match = try await search(
                sessionLocator: sessionLocator,
                localUserID: localUserID
            ) {
                do {
                    try await joinLobby(
                        lobbyID: match.lobbyID,
                        detailsHandle: match.detailsHandle,
                        localUserID: localUserID
                    )
                } catch {
                    await release(detailsHandle: match.detailsHandle)
                    throw error
                }
                await release(detailsHandle: match.detailsHandle)
                activeLobby = ActiveLobby(
                    sessionLocator: sessionLocator,
                    lobbyID: match.lobbyID,
                    localUserID: localUserID
                )
            } else {
                guard createsIfMissing else {
                    throw EOSPrivateIslandRuntimeError.lobbyNotFound
                }
                let lobbyID = try await createLobby(localUserID: localUserID)
                activeLobby = ActiveLobby(
                    sessionLocator: sessionLocator,
                    lobbyID: lobbyID,
                    localUserID: localUserID
                )
                do {
                    try await publish(
                        sessionLocator: sessionLocator,
                        lobbyID: lobbyID,
                        localUserID: localUserID
                    )
                } catch {
                    await leave(localUserID: localUserID)
                    throw error
                }
            }

            do {
                return try await refresh(localUserID: localUserID)
            } catch {
                await leave(localUserID: localUserID)
                throw error
            }
        } catch {
            if activeLobby == nil {
                await removeMembershipNotification()
            }
            throw error
        }
    }

    /// Re-reads owner and member Product User IDs from the active lobby.
    func refresh(localUserID: EOS_ProductUserId) async throws -> Snapshot {
        guard let activeLobby else {
            throw EOSPrivateIslandRuntimeError.transportNotReady
        }
        guard activeLobby.localUserID == localUserID else {
            throw EOSPrivateIslandRuntimeError.lobbyIdentityChanged
        }
        guard await runtime.isValid(localUserID) else {
            throw EOSPrivateIslandRuntimeError.invalidProductUserID
        }

        return try await runtime.run { context in
            try activeLobby.lobbyID.withCString { lobbyID in
                var options = EOS_Lobby_CopyLobbyDetailsHandleOptions()
                options.ApiVersion = EOS_LOBBY_COPYLOBBYDETAILSHANDLE_API_LATEST
                options.LobbyId = lobbyID
                options.LocalUserId = localUserID

                var detailsHandle: EOS_HLobbyDetails?
                let result = EOS_Lobby_CopyLobbyDetailsHandle(
                    context.lobby,
                    &options,
                    &detailsHandle
                )
                guard result == EOS_Success, let detailsHandle else {
                    if result == EOS_NotFound {
                        throw EOSPrivateIslandRuntimeError.lobbyNotFound
                    }
                    throw EOSSDKRuntime.operationError(
                        "Lobby_CopyLobbyDetailsHandle",
                        result: result
                    )
                }
                defer { EOS_LobbyDetails_Release(detailsHandle) }

                return try Self.snapshot(
                    detailsHandle: detailsHandle,
                    expectedLobbyID: activeLobby.lobbyID,
                    expectedSessionLocator: activeLobby.sessionLocator,
                    localUserID: localUserID
                )
            }
        }
    }

    /// Leaves membership but never destroys the lobby. Automatic host
    /// migration stays disabled until the protocol has an epoch/state-transfer
    /// handshake; an owner-related notification must be treated as fail-closed
    /// by the adapter.
    func leave(localUserID: EOS_ProductUserId) async {
        guard let activeLobby,
              activeLobby.localUserID == localUserID
        else {
            await removeMembershipNotification()
            return
        }

        _ = try? await leaveLobby(
            lobbyID: activeLobby.lobbyID,
            localUserID: localUserID
        )
        self.activeLobby = nil
        await removeMembershipNotification()
    }

    private func createLobby(localUserID: EOS_ProductUserId) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let box = StringCallbackBox(
                operation: "Lobby_CreateLobby",
                continuation: continuation
            )
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try runtime.schedule { context in
                    Self.bucketID.withCString { bucketID in
                        var options = EOS_Lobby_CreateLobbyOptions()
                        options.ApiVersion = EOS_LOBBY_CREATELOBBY_API_LATEST
                        options.LocalUserId = localUserID
                        options.MaxLobbyMembers = Self.maximumMembers
                        options.PermissionLevel = EOS_LPL_INVITEONLY
                        options.bPresenceEnabled = EOS_FALSE
                        options.bAllowInvites = EOS_TRUE
                        options.BucketId = bucketID
                        options.bDisableHostMigration = EOS_TRUE
                        options.bEnableRTCRoom = EOS_FALSE
                        options.LocalRTCOptions = nil
                        options.LobbyId = nil
                        options.bEnableJoinById = EOS_FALSE
                        options.bRejoinAfterKickRequiresInvite = EOS_TRUE
                        options.AllowedPlatformIds = nil
                        options.AllowedPlatformIdsCount = 0
                        options.bCrossplayOptOut = EOS_FALSE
                        options.RTCRoomJoinActionType = EOS_LRRJAT_ManualJoin

                        EOS_Lobby_CreateLobby(
                            context.lobby,
                            &options,
                            clientData
                        ) { callbackInfo in
                            guard let callbackInfo,
                                  let callbackData = callbackInfo.pointee.ClientData
                            else { return }
                            let result = callbackInfo.pointee.ResultCode
                            guard EOS_EResult_IsOperationComplete(result) == EOS_TRUE else {
                                return
                            }
                            let box = Unmanaged<StringCallbackBox>
                                .fromOpaque(callbackData)
                                .takeRetainedValue()
                            guard result == EOS_Success else {
                                box.continuation.resume(
                                    throwing: EOSSDKRuntime.operationError(
                                        box.operation,
                                        result: result
                                    )
                                )
                                return
                            }
                            guard let rawLobbyID = callbackInfo.pointee.LobbyId else {
                                box.continuation.resume(
                                    throwing: EOSPrivateIslandRuntimeError
                                        .lobbyConfigurationInvalid
                                )
                                return
                            }
                            let lobbyID = String(cString: rawLobbyID)
                            guard !lobbyID.isEmpty else {
                                box.continuation.resume(
                                    throwing: EOSPrivateIslandRuntimeError
                                        .lobbyConfigurationInvalid
                                )
                                return
                            }
                            box.continuation.resume(returning: lobbyID)
                        }
                    }
                }
            } catch {
                Unmanaged<StringCallbackBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }
    }

    private func publish(
        sessionLocator: String,
        lobbyID: String,
        localUserID: EOS_ProductUserId
    ) async throws {
        let modificationHandle = try await runtime.run { context in
            try lobbyID.withCString { lobbyIDPointer in
                var options = EOS_Lobby_UpdateLobbyModificationOptions()
                options.ApiVersion = EOS_LOBBY_UPDATELOBBYMODIFICATION_API_LATEST
                options.LocalUserId = localUserID
                options.LobbyId = lobbyIDPointer

                var modificationHandle: EOS_HLobbyModification?
                let result = EOS_Lobby_UpdateLobbyModification(
                    context.lobby,
                    &options,
                    &modificationHandle
                )
                guard result == EOS_Success, let modificationHandle else {
                    throw EOSSDKRuntime.operationError(
                        "Lobby_UpdateLobbyModification",
                        result: result
                    )
                }
                return modificationHandle
            }
        }

        do {
            try await runtime.run { _ in
                try Self.locatorAttributeKey.withCString { key in
                    try sessionLocator.withCString { locator in
                        var attribute = EOS_Lobby_AttributeData()
                        attribute.ApiVersion = EOS_LOBBY_ATTRIBUTEDATA_API_LATEST
                        attribute.Key = key
                        attribute.Value.AsUtf8 = locator
                        attribute.ValueType = EOS_AT_STRING

                        var addOptions = EOS_LobbyModification_AddAttributeOptions()
                        addOptions.ApiVersion = EOS_LOBBYMODIFICATION_ADDATTRIBUTE_API_LATEST
                        addOptions.Visibility = EOS_LAT_PUBLIC
                        let addResult = withUnsafePointer(to: &attribute) { pointer in
                            addOptions.Attribute = pointer
                            return EOS_LobbyModification_AddAttribute(
                                modificationHandle,
                                &addOptions
                            )
                        }
                        guard addResult == EOS_Success else {
                            throw EOSSDKRuntime.operationError(
                                "LobbyModification_AddAttribute",
                                result: addResult
                            )
                        }

                        var permissionOptions =
                            EOS_LobbyModification_SetPermissionLevelOptions()
                        permissionOptions.ApiVersion =
                            EOS_LOBBYMODIFICATION_SETPERMISSIONLEVEL_API_LATEST
                        permissionOptions.PermissionLevel = EOS_LPL_PUBLICADVERTISED
                        let permissionResult =
                            EOS_LobbyModification_SetPermissionLevel(
                                modificationHandle,
                                &permissionOptions
                            )
                        guard permissionResult == EOS_Success else {
                            throw EOSSDKRuntime.operationError(
                                "LobbyModification_SetPermissionLevel",
                                result: permissionResult
                            )
                        }
                    }
                }
            }
            try await updateLobby(
                lobbyID: lobbyID,
                modificationHandle: modificationHandle
            )
        } catch {
            await release(modificationHandle: modificationHandle)
            throw error
        }
        await release(modificationHandle: modificationHandle)
    }

    private func search(
        sessionLocator: String,
        localUserID: EOS_ProductUserId
    ) async throws -> SearchMatch? {
        let searchHandle = try await runtime.run { context in
            var options = EOS_Lobby_CreateLobbySearchOptions()
            options.ApiVersion = EOS_LOBBY_CREATELOBBYSEARCH_API_LATEST
            options.MaxResults = Self.maximumSearchResults

            var searchHandle: EOS_HLobbySearch?
            let createResult = EOS_Lobby_CreateLobbySearch(
                context.lobby,
                &options,
                &searchHandle
            )
            guard createResult == EOS_Success, let searchHandle else {
                throw EOSSDKRuntime.operationError(
                    "Lobby_CreateLobbySearch",
                    result: createResult
                )
            }

            do {
                try Self.locatorAttributeKey.withCString { key in
                    try sessionLocator.withCString { locator in
                        var parameter = EOS_Lobby_AttributeData()
                        parameter.ApiVersion = EOS_LOBBY_ATTRIBUTEDATA_API_LATEST
                        parameter.Key = key
                        parameter.Value.AsUtf8 = locator
                        parameter.ValueType = EOS_AT_STRING

                        var parameterOptions = EOS_LobbySearch_SetParameterOptions()
                        parameterOptions.ApiVersion =
                            EOS_LOBBYSEARCH_SETPARAMETER_API_LATEST
                        parameterOptions.ComparisonOp = EOS_CO_EQUAL
                        let parameterResult = withUnsafePointer(to: &parameter) { pointer in
                            parameterOptions.Parameter = pointer
                            return EOS_LobbySearch_SetParameter(
                                searchHandle,
                                &parameterOptions
                            )
                        }
                        guard parameterResult == EOS_Success else {
                            throw EOSSDKRuntime.operationError(
                                "LobbySearch_SetParameter",
                                result: parameterResult
                            )
                        }
                    }
                }
            } catch {
                EOS_LobbySearch_Release(searchHandle)
                throw error
            }
            return searchHandle
        }

        do {
            try await find(searchHandle: searchHandle, localUserID: localUserID)
            let result = try await copySearchMatch(
                searchHandle: searchHandle,
                sessionLocator: sessionLocator
            )
            await release(searchHandle: searchHandle)
            return result
        } catch {
            await release(searchHandle: searchHandle)
            throw error
        }
    }

    private func find(
        searchHandle: EOS_HLobbySearch,
        localUserID: EOS_ProductUserId
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ResultCallbackBox(
                operation: "LobbySearch_Find",
                continuation: continuation
            )
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try runtime.schedule { _ in
                    var options = EOS_LobbySearch_FindOptions()
                    options.ApiVersion = EOS_LOBBYSEARCH_FIND_API_LATEST
                    options.LocalUserId = localUserID
                    EOS_LobbySearch_Find(
                        searchHandle,
                        &options,
                        clientData
                    ) { callbackInfo in
                        guard let callbackInfo,
                              let callbackData = callbackInfo.pointee.ClientData
                        else { return }
                        let result = callbackInfo.pointee.ResultCode
                        guard EOS_EResult_IsOperationComplete(result) == EOS_TRUE else {
                            return
                        }
                        let box = Unmanaged<ResultCallbackBox>
                            .fromOpaque(callbackData)
                            .takeRetainedValue()
                        guard result == EOS_Success else {
                            box.continuation.resume(
                                throwing: EOSSDKRuntime.operationError(
                                    box.operation,
                                    result: result
                                )
                            )
                            return
                        }
                        box.continuation.resume()
                    }
                }
            } catch {
                Unmanaged<ResultCallbackBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }
    }

    private func copySearchMatch(
        searchHandle: EOS_HLobbySearch,
        sessionLocator: String
    ) async throws -> SearchMatch? {
        try await runtime.run { _ in
            var countOptions = EOS_LobbySearch_GetSearchResultCountOptions()
            countOptions.ApiVersion = EOS_LOBBYSEARCH_GETSEARCHRESULTCOUNT_API_LATEST
            let count = EOS_LobbySearch_GetSearchResultCount(
                searchHandle,
                &countOptions
            )

            var matches: [SearchMatch] = []
            var foundInvalidConfiguration = false
            for index in 0..<count {
                var copyOptions = EOS_LobbySearch_CopySearchResultByIndexOptions()
                copyOptions.ApiVersion =
                    EOS_LOBBYSEARCH_COPYSEARCHRESULTBYINDEX_API_LATEST
                copyOptions.LobbyIndex = index

                var detailsHandle: EOS_HLobbyDetails?
                let copyResult = EOS_LobbySearch_CopySearchResultByIndex(
                    searchHandle,
                    &copyOptions,
                    &detailsHandle
                )
                guard copyResult == EOS_Success, let detailsHandle else {
                    for match in matches {
                        EOS_LobbyDetails_Release(match.detailsHandle)
                    }
                    throw EOSSDKRuntime.operationError(
                        "LobbySearch_CopySearchResultByIndex",
                        result: copyResult
                    )
                }

                do {
                    let lobbyID = try Self.validate(
                        detailsHandle: detailsHandle,
                        expectedLobbyID: nil,
                        expectedSessionLocator: sessionLocator
                    )
                    matches.append(
                        SearchMatch(
                            lobbyID: lobbyID,
                            detailsHandle: detailsHandle
                        )
                    )
                } catch EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid {
                    foundInvalidConfiguration = true
                    EOS_LobbyDetails_Release(detailsHandle)
                } catch {
                    EOS_LobbyDetails_Release(detailsHandle)
                    for match in matches {
                        EOS_LobbyDetails_Release(match.detailsHandle)
                    }
                    throw error
                }
            }

            guard !foundInvalidConfiguration else {
                for match in matches {
                    EOS_LobbyDetails_Release(match.detailsHandle)
                }
                throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
            }
            guard matches.count <= 1 else {
                for match in matches {
                    EOS_LobbyDetails_Release(match.detailsHandle)
                }
                throw EOSPrivateIslandLobbySessionError.ambiguousSessionLocator
            }
            return matches.first
        }
    }

    private func joinLobby(
        lobbyID: String,
        detailsHandle: EOS_HLobbyDetails,
        localUserID: EOS_ProductUserId
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ResultCallbackBox(
                operation: "Lobby_JoinLobby",
                expectedLobbyID: lobbyID,
                continuation: continuation
            )
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try runtime.schedule { context in
                    var options = EOS_Lobby_JoinLobbyOptions()
                    options.ApiVersion = EOS_LOBBY_JOINLOBBY_API_LATEST
                    options.LobbyDetailsHandle = detailsHandle
                    options.LocalUserId = localUserID
                    options.bPresenceEnabled = EOS_FALSE
                    options.LocalRTCOptions = nil
                    options.bCrossplayOptOut = EOS_FALSE
                    options.RTCRoomJoinActionType = EOS_LRRJAT_ManualJoin

                    EOS_Lobby_JoinLobby(
                        context.lobby,
                        &options,
                        clientData
                    ) { callbackInfo in
                        guard let callbackInfo,
                              let callbackData = callbackInfo.pointee.ClientData
                        else { return }
                        let result = callbackInfo.pointee.ResultCode
                        guard EOS_EResult_IsOperationComplete(result) == EOS_TRUE else {
                            return
                        }
                        let box = Unmanaged<ResultCallbackBox>
                            .fromOpaque(callbackData)
                            .takeRetainedValue()
                        guard result == EOS_Success else {
                            box.continuation.resume(
                                throwing: EOSSDKRuntime.operationError(
                                    box.operation,
                                    result: result
                                )
                            )
                            return
                        }
                        guard EOSPrivateIslandLobbySession.callbackLobbyID(
                            callbackInfo.pointee.LobbyId
                        )
                                == box.expectedLobbyID
                        else {
                            box.continuation.resume(
                                throwing: EOSPrivateIslandRuntimeError
                                    .lobbyIdentityChanged
                            )
                            return
                        }
                        box.continuation.resume()
                    }
                }
            } catch {
                Unmanaged<ResultCallbackBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }
    }

    private func updateLobby(
        lobbyID: String,
        modificationHandle: EOS_HLobbyModification
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ResultCallbackBox(
                operation: "Lobby_UpdateLobby",
                expectedLobbyID: lobbyID,
                continuation: continuation
            )
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try runtime.schedule { context in
                    var options = EOS_Lobby_UpdateLobbyOptions()
                    options.ApiVersion = EOS_LOBBY_UPDATELOBBY_API_LATEST
                    options.LobbyModificationHandle = modificationHandle
                    EOS_Lobby_UpdateLobby(
                        context.lobby,
                        &options,
                        clientData
                    ) { callbackInfo in
                        guard let callbackInfo,
                              let callbackData = callbackInfo.pointee.ClientData
                        else { return }
                        let result = callbackInfo.pointee.ResultCode
                        guard EOS_EResult_IsOperationComplete(result) == EOS_TRUE else {
                            return
                        }
                        let box = Unmanaged<ResultCallbackBox>
                            .fromOpaque(callbackData)
                            .takeRetainedValue()
                        guard result == EOS_Success else {
                            box.continuation.resume(
                                throwing: EOSSDKRuntime.operationError(
                                    box.operation,
                                    result: result
                                )
                            )
                            return
                        }
                        guard EOSPrivateIslandLobbySession.callbackLobbyID(
                            callbackInfo.pointee.LobbyId
                        )
                                == box.expectedLobbyID
                        else {
                            box.continuation.resume(
                                throwing: EOSPrivateIslandRuntimeError
                                    .lobbyIdentityChanged
                            )
                            return
                        }
                        box.continuation.resume()
                    }
                }
            } catch {
                Unmanaged<ResultCallbackBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }
    }

    private func leaveLobby(
        lobbyID: String,
        localUserID: EOS_ProductUserId
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ResultCallbackBox(
                operation: "Lobby_LeaveLobby",
                expectedLobbyID: lobbyID,
                continuation: continuation
            )
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try runtime.schedule { context in
                    lobbyID.withCString { lobbyIDPointer in
                        var options = EOS_Lobby_LeaveLobbyOptions()
                        options.ApiVersion = EOS_LOBBY_LEAVELOBBY_API_LATEST
                        options.LocalUserId = localUserID
                        options.LobbyId = lobbyIDPointer
                        EOS_Lobby_LeaveLobby(
                            context.lobby,
                            &options,
                            clientData
                        ) { callbackInfo in
                            guard let callbackInfo,
                                  let callbackData = callbackInfo.pointee.ClientData
                            else { return }
                            let result = callbackInfo.pointee.ResultCode
                            guard EOS_EResult_IsOperationComplete(result) == EOS_TRUE else {
                                return
                            }
                            let box = Unmanaged<ResultCallbackBox>
                                .fromOpaque(callbackData)
                                .takeRetainedValue()
                            guard result == EOS_Success else {
                                box.continuation.resume(
                                    throwing: EOSSDKRuntime.operationError(
                                        box.operation,
                                        result: result
                                    )
                                )
                                return
                            }
                            guard EOSPrivateIslandLobbySession.callbackLobbyID(
                                callbackInfo.pointee.LobbyId
                            )
                                    == box.expectedLobbyID
                            else {
                                box.continuation.resume(
                                    throwing: EOSPrivateIslandRuntimeError
                                        .lobbyIdentityChanged
                                )
                                return
                            }
                            box.continuation.resume()
                        }
                    }
                }
            } catch {
                Unmanaged<ResultCallbackBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }
    }

    private func ensureMembershipNotification() async throws {
        guard notificationRegistration == nil else { return }

        let notificationBox = MembershipNotificationBox(session: self)
        let clientData = Unmanaged.passRetained(notificationBox).toOpaque()
        do {
            let identifier = try await runtime.run { context in
                var options = EOS_Lobby_AddNotifyLobbyMemberStatusReceivedOptions()
                options.ApiVersion =
                    EOS_LOBBY_ADDNOTIFYLOBBYMEMBERSTATUSRECEIVED_API_LATEST
                let identifier = EOS_Lobby_AddNotifyLobbyMemberStatusReceived(
                    context.lobby,
                    &options,
                    clientData
                ) { callbackInfo in
                    guard let callbackInfo,
                          let callbackData = callbackInfo.pointee.ClientData,
                          let rawLobbyID = callbackInfo.pointee.LobbyId
                    else { return }
                    let box = Unmanaged<MembershipNotificationBox>
                        .fromOpaque(callbackData)
                        .takeUnretainedValue()
                    box.signal(lobbyID: String(cString: rawLobbyID))
                }
                guard identifier != EOS_INVALID_NOTIFICATIONID else {
                    throw EOSSDKRuntime.operationError(
                        "Lobby_AddNotifyLobbyMemberStatusReceived",
                        result: EOS_UnexpectedError
                    )
                }
                return identifier
            }
            notificationRegistration = NotificationRegistration(
                identifier: identifier,
                clientData: clientData
            )
        } catch {
            Unmanaged<MembershipNotificationBox>.fromOpaque(clientData).release()
            throw error
        }
    }

    private func removeMembershipNotification() async {
        guard let registration = notificationRegistration else { return }
        notificationRegistration = nil
        _ = try? await runtime.run { context in
            EOS_Lobby_RemoveNotifyLobbyMemberStatusReceived(
                context.lobby,
                registration.identifier
            )
        }
        Unmanaged<MembershipNotificationBox>
            .fromOpaque(registration.clientData)
            .release()
    }

    private func membershipDidChange(lobbyID: String) {
        guard activeLobby?.lobbyID == lobbyID else { return }
        onMembershipChanged?()
    }

    private func release(detailsHandle: EOS_HLobbyDetails) async {
        _ = try? await runtime.run { _ in
            EOS_LobbyDetails_Release(detailsHandle)
        }
    }

    private func release(searchHandle: EOS_HLobbySearch) async {
        _ = try? await runtime.run { _ in
            EOS_LobbySearch_Release(searchHandle)
        }
    }

    private func release(modificationHandle: EOS_HLobbyModification) async {
        _ = try? await runtime.run { _ in
            EOS_LobbyModification_Release(modificationHandle)
        }
    }

    private static func validate(sessionLocator: String) throws {
        guard !sessionLocator.isEmpty else {
            throw EOSPrivateIslandLobbySessionError.missingSessionLocator
        }
        let bytes = Array(sessionLocator.utf8)
        guard bytes.count >= minimumLocatorBytes,
              bytes.count <= maximumLocatorBytes,
              bytes.allSatisfy({ (0x21...0x7E).contains($0) })
        else {
            throw EOSPrivateIslandLobbySessionError.invalidSessionLocator(
                actualBytes: bytes.count,
                minimumBytes: minimumLocatorBytes,
                maximumBytes: maximumLocatorBytes
            )
        }
    }

    private static func snapshot(
        detailsHandle: EOS_HLobbyDetails,
        expectedLobbyID: String,
        expectedSessionLocator: String,
        localUserID: EOS_ProductUserId
    ) throws -> Snapshot {
        let lobbyID = try validate(
            detailsHandle: detailsHandle,
            expectedLobbyID: expectedLobbyID,
            expectedSessionLocator: expectedSessionLocator
        )

        var ownerOptions = EOS_LobbyDetails_GetLobbyOwnerOptions()
        ownerOptions.ApiVersion = EOS_LOBBYDETAILS_GETLOBBYOWNER_API_LATEST
        guard let ownerProductUserID = EOS_LobbyDetails_GetLobbyOwner(
            detailsHandle,
            &ownerOptions
        ), EOSSDKRuntime.isValidOnSDKThread(ownerProductUserID) else {
            throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
        }

        var countOptions = EOS_LobbyDetails_GetMemberCountOptions()
        countOptions.ApiVersion = EOS_LOBBYDETAILS_GETMEMBERCOUNT_API_LATEST
        let memberCount = EOS_LobbyDetails_GetMemberCount(
            detailsHandle,
            &countOptions
        )
        guard memberCount > 0, memberCount <= maximumMembers else {
            throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
        }

        var members: [EOS_ProductUserId] = []
        members.reserveCapacity(Int(memberCount))
        for index in 0..<memberCount {
            var memberOptions = EOS_LobbyDetails_GetMemberByIndexOptions()
            memberOptions.ApiVersion = EOS_LOBBYDETAILS_GETMEMBERBYINDEX_API_LATEST
            memberOptions.MemberIndex = index
            guard let member = EOS_LobbyDetails_GetMemberByIndex(
                detailsHandle,
                &memberOptions
            ), EOSSDKRuntime.isValidOnSDKThread(member),
               !members.contains(where: { $0 == member })
            else {
                throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
            }
            members.append(member)
        }

        guard members.contains(where: { $0 == localUserID }) else {
            throw EOSPrivateIslandRuntimeError.localUserIsNotRoomMember
        }
        guard members.contains(where: { $0 == ownerProductUserID }) else {
            throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
        }
        return Snapshot(
            lobbyID: lobbyID,
            ownerProductUserID: ownerProductUserID,
            memberProductUserIDs: members
        )
    }

    @discardableResult
    private static func validate(
        detailsHandle: EOS_HLobbyDetails,
        expectedLobbyID: String?,
        expectedSessionLocator: String
    ) throws -> String {
        var infoOptions = EOS_LobbyDetails_CopyInfoOptions()
        infoOptions.ApiVersion = EOS_LOBBYDETAILS_COPYINFO_API_LATEST
        var infoPointer: UnsafeMutablePointer<EOS_LobbyDetails_Info>?
        let infoResult = EOS_LobbyDetails_CopyInfo(
            detailsHandle,
            &infoOptions,
            &infoPointer
        )
        guard infoResult == EOS_Success, let infoPointer else {
            throw EOSSDKRuntime.operationError(
                "LobbyDetails_CopyInfo",
                result: infoResult
            )
        }
        defer { EOS_LobbyDetails_Info_Release(infoPointer) }

        let info = infoPointer.pointee
        guard let rawLobbyID = info.LobbyId,
              let rawBucketID = info.BucketId,
              let ownerProductUserID = info.LobbyOwnerUserId,
              EOSSDKRuntime.isValidOnSDKThread(ownerProductUserID),
              info.MaxMembers == maximumMembers,
              info.PermissionLevel == EOS_LPL_PUBLICADVERTISED,
              info.bAllowInvites == EOS_TRUE,
              info.bAllowHostMigration == EOS_FALSE,
              info.bRTCRoomEnabled == EOS_FALSE,
              info.bAllowJoinById == EOS_FALSE,
              info.bRejoinAfterKickRequiresInvite == EOS_TRUE,
              info.bPresenceEnabled == EOS_FALSE,
              String(cString: rawBucketID) == bucketID
        else {
            throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
        }

        let lobbyID = String(cString: rawLobbyID)
        guard !lobbyID.isEmpty,
              expectedLobbyID == nil || expectedLobbyID == lobbyID
        else {
            throw EOSPrivateIslandRuntimeError.lobbyIdentityChanged
        }

        let locatorMatches = try locatorAttributeMatches(
            detailsHandle: detailsHandle,
            expectedSessionLocator: expectedSessionLocator
        )
        guard locatorMatches else {
            throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
        }
        return lobbyID
    }

    private static func locatorAttributeMatches(
        detailsHandle: EOS_HLobbyDetails,
        expectedSessionLocator: String
    ) throws -> Bool {
        try locatorAttributeKey.withCString { key in
            var options = EOS_LobbyDetails_CopyAttributeByKeyOptions()
            options.ApiVersion = EOS_LOBBYDETAILS_COPYATTRIBUTEBYKEY_API_LATEST
            options.AttrKey = key

            var attributePointer: UnsafeMutablePointer<EOS_Lobby_Attribute>?
            let result = EOS_LobbyDetails_CopyAttributeByKey(
                detailsHandle,
                &options,
                &attributePointer
            )
            guard result == EOS_Success, let attributePointer else {
                if result == EOS_NotFound {
                    return false
                }
                throw EOSSDKRuntime.operationError(
                    "LobbyDetails_CopyAttributeByKey",
                    result: result
                )
            }
            defer { EOS_Lobby_Attribute_Release(attributePointer) }

            let attribute = attributePointer.pointee
            guard attribute.Visibility == EOS_LAT_PUBLIC,
                  let dataPointer = attribute.Data,
                  dataPointer.pointee.ValueType == EOS_AT_STRING,
                  let value = dataPointer.pointee.Value.AsUtf8
            else {
                return false
            }
            return String(cString: value) == expectedSessionLocator
        }
    }

    private static func callbackLobbyID(_ value: EOS_LobbyId?) -> String? {
        value.map(String.init(cString:))
    }
}
#endif
