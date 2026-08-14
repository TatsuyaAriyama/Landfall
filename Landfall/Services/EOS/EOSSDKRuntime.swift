#if EOS_SDK_AVAILABLE && !targetEnvironment(simulator)
import CoreFoundation
import EOSSDK
import FirebaseAuth
import Foundation

/// The SDK objects are deliberately confined to one long-lived thread. EOS
/// callbacks are delivered by `EOS_Platform_Tick`, so running Tick on the main
/// actor would compete with SceneKit rendering and could introduce visible
/// frame pacing stalls.
final class EOSSDKRuntime {
    struct AuthenticatedUser {
        let firebaseUID: String
        let productUserID: EOS_ProductUserId
        let productUserIDString: String
    }

    struct Context {
        let platform: EOS_HPlatform
        let connect: EOS_HConnect
        let lobby: EOS_HLobby
        let p2p: EOS_HP2P
    }

    private static let sharedLock = NSLock()
    private static var sharedRuntime: EOSSDKRuntime?

    private let configuration: EOSPrivateIslandConfiguration
    private let worker: EOSSDKThreadWorker

    /// The process-wide Platform instance. Loading configuration is kept
    /// outside this method so a factory can fall back to Firestore without
    /// ever initializing EOS when Portal values are absent.
    static func shared(
        configuration: EOSPrivateIslandConfiguration
    ) throws -> EOSSDKRuntime {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if let sharedRuntime {
            guard sharedRuntime.configuration == configuration else {
                throw EOSPrivateIslandRuntimeError.runtimeConfigurationMismatch
            }
            return sharedRuntime
        }
        let runtime = try EOSSDKRuntime(configuration: configuration)
        sharedRuntime = runtime
        return runtime
    }

    private init(configuration: EOSPrivateIslandConfiguration) throws {
        self.configuration = configuration
        worker = EOSSDKThreadWorker(configuration: configuration)
        try worker.start()
    }

    /// Runs a synchronous EOS operation on the owning SDK thread.
    func run<T>(
        _ operation: @escaping (Context) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try worker.schedule { context in
                    continuation.resume(with: Result { try operation(context) })
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Starts an asynchronous EOS operation on the owning SDK thread. The
    /// operation's SDK callback will run on this thread during a later Tick.
    func schedule(_ operation: @escaping (Context) -> Void) throws {
        try worker.schedule(operation)
    }

    func addTickHandler(
        _ handler: @escaping (Context) -> Void
    ) async throws -> UUID {
        try await run { _ in
            self.worker.addTickHandler(handler)
        }
    }

    func removeTickHandler(_ identifier: UUID) async {
        _ = try? await run { _ in
            self.worker.removeTickHandler(identifier)
        }
    }

    @MainActor
    func authenticateWithFirebase() async throws -> AuthenticatedUser {
        guard let firebaseUser = Auth.auth().currentUser, !firebaseUser.uid.isEmpty else {
            throw EOSPrivateIslandRuntimeError.notSignedIn
        }

        let token: String
        do {
            token = try await firebaseUser.getIDToken(forcingRefresh: true)
        } catch {
            throw EOSPrivateIslandRuntimeError.firebaseTokenUnavailable(
                error.localizedDescription
            )
        }
        guard !token.isEmpty else {
            throw EOSPrivateIslandRuntimeError.firebaseTokenUnavailable("empty token")
        }

        let productUserID = try await connectLogin(openIDToken: token)
        let productUserIDString = try await string(for: productUserID)
        let mappedFirebaseUID = try await firebaseUID(
            for: productUserID,
            localUserID: productUserID
        )
        guard mappedFirebaseUID == firebaseUser.uid else {
            throw EOSPrivateIslandRuntimeError.productUserMappingMismatch
        }
        return AuthenticatedUser(
            firebaseUID: firebaseUser.uid,
            productUserID: productUserID,
            productUserIDString: productUserIDString
        )
    }

    /// Resolves the OpenID `sub` cached by EOS for a Product User ID. Callers
    /// still must compare the result with the Firebase-owned room membership.
    func firebaseUID(
        for targetProductUserID: EOS_ProductUserId,
        localUserID: EOS_ProductUserId
    ) async throws -> String {
        guard await isValid(targetProductUserID), await isValid(localUserID) else {
            throw EOSPrivateIslandRuntimeError.invalidProductUserID
        }
        try await queryMappings(
            targetProductUserID: targetProductUserID,
            localUserID: localUserID
        )

        return try await run { context in
            var options = EOS_Connect_GetProductUserIdMappingOptions()
            options.ApiVersion = EOS_CONNECT_GETPRODUCTUSERIDMAPPING_API_LATEST
            options.LocalUserId = localUserID
            options.AccountIdType = EOS_EAT_OPENID
            options.TargetProductUserId = targetProductUserID

            var buffer = [CChar](
                repeating: 0,
                count: Int(EOS_CONNECT_EXTERNAL_ACCOUNT_ID_MAX_LENGTH) + 1
            )
            var length = Int32(buffer.count)
            let result = buffer.withUnsafeMutableBufferPointer { storage in
                EOS_Connect_GetProductUserIdMapping(
                    context.connect,
                    &options,
                    storage.baseAddress,
                    &length
                )
            }
            guard result == EOS_Success else {
                if result == EOS_NotFound {
                    throw EOSPrivateIslandRuntimeError.productUserMappingMissing
                }
                throw Self.operationError("GetProductUserIdMapping", result: result)
            }
            guard length > 0, buffer.first != 0 else {
                throw EOSPrivateIslandRuntimeError.productUserMappingMissing
            }
            return String(cString: buffer)
        }
    }

    func string(for productUserID: EOS_ProductUserId) async throws -> String {
        try await run { _ in
            guard Self.isValidOnSDKThread(productUserID) else {
                throw EOSPrivateIslandRuntimeError.invalidProductUserID
            }
            var buffer = [CChar](
                repeating: 0,
                count: Int(EOS_PRODUCTUSERID_MAX_LENGTH) + 1
            )
            var length = Int32(buffer.count)
            let result = EOS_ProductUserId_ToString(productUserID, &buffer, &length)
            guard result == EOS_Success else {
                throw Self.operationError("ProductUserId_ToString", result: result)
            }
            return String(cString: buffer)
        }
    }

    func isValid(_ productUserID: EOS_ProductUserId) async -> Bool {
        (try? await run { _ in Self.isValidOnSDKThread(productUserID) }) ?? false
    }

    static func isValidOnSDKThread(_ productUserID: EOS_ProductUserId) -> Bool {
        return EOS_ProductUserId_IsValid(productUserID) == EOS_TRUE
    }

    static func operationError(
        _ operation: String,
        result: EOS_EResult
    ) -> EOSPrivateIslandRuntimeError {
        let resultName = EOS_EResult_ToString(result).map(String.init(cString:))
            ?? "EOS result \(result.rawValue)"
        return .sdkOperationFailed(operation: operation, result: resultName)
    }

    private enum LoginOutcome {
        case authenticated(EOS_ProductUserId)
        case requiresUserCreation(EOS_ContinuanceToken)
    }

    private final class LoginBox {
        let continuation: CheckedContinuation<LoginOutcome, Error>

        init(_ continuation: CheckedContinuation<LoginOutcome, Error>) {
            self.continuation = continuation
        }
    }

    private final class ProductUserBox {
        let continuation: CheckedContinuation<EOS_ProductUserId, Error>

        init(_ continuation: CheckedContinuation<EOS_ProductUserId, Error>) {
            self.continuation = continuation
        }
    }

    private final class ResultBox {
        let operation: String
        let continuation: CheckedContinuation<Void, Error>

        init(
            operation: String,
            continuation: CheckedContinuation<Void, Error>
        ) {
            self.operation = operation
            self.continuation = continuation
        }
    }

    private func connectLogin(openIDToken: String) async throws -> EOS_ProductUserId {
        let outcome: LoginOutcome = try await withCheckedThrowingContinuation { continuation in
            let box = LoginBox(continuation)
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try schedule { context in
                    openIDToken.withCString { token in
                        var credentials = EOS_Connect_Credentials()
                        credentials.ApiVersion = EOS_CONNECT_CREDENTIALS_API_LATEST
                        credentials.Token = token
                        credentials.Type = EOS_ECT_OPENID_ACCESS_TOKEN

                        var options = EOS_Connect_LoginOptions()
                        options.ApiVersion = EOS_CONNECT_LOGIN_API_LATEST
                        withUnsafePointer(to: &credentials) { credentialsPointer in
                            options.Credentials = credentialsPointer
                            EOS_Connect_Login(
                                context.connect,
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
                                let box = Unmanaged<LoginBox>
                                    .fromOpaque(callbackData)
                                    .takeRetainedValue()
                                switch result {
                                case EOS_Success:
                                    guard EOSSDKRuntime.isValidOnSDKThread(
                                        callbackInfo.pointee.LocalUserId
                                    ) else {
                                        box.continuation.resume(
                                            throwing: EOSPrivateIslandRuntimeError
                                                .invalidProductUserID
                                        )
                                        return
                                    }
                                    box.continuation.resume(
                                        returning: .authenticated(
                                            callbackInfo.pointee.LocalUserId
                                        )
                                    )
                                case EOS_InvalidUser:
                                    guard callbackInfo.pointee.ContinuanceToken != nil else {
                                        box.continuation.resume(
                                            throwing: EOSPrivateIslandRuntimeError
                                                .invalidProductUserID
                                        )
                                        return
                                    }
                                    box.continuation.resume(
                                        returning: .requiresUserCreation(
                                            callbackInfo.pointee.ContinuanceToken
                                        )
                                    )
                                default:
                                    box.continuation.resume(
                                        throwing: EOSSDKRuntime.operationError(
                                            "Connect_Login",
                                            result: result
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            } catch {
                Unmanaged<LoginBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }

        switch outcome {
        case let .authenticated(productUserID):
            return productUserID
        case let .requiresUserCreation(continuanceToken):
            return try await createUser(continuanceToken: continuanceToken)
        }
    }

    private func createUser(
        continuanceToken: EOS_ContinuanceToken
    ) async throws -> EOS_ProductUserId {
        try await withCheckedThrowingContinuation { continuation in
            let box = ProductUserBox(continuation)
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try schedule { context in
                    var options = EOS_Connect_CreateUserOptions()
                    options.ApiVersion = EOS_CONNECT_CREATEUSER_API_LATEST
                    options.ContinuanceToken = continuanceToken
                    EOS_Connect_CreateUser(
                        context.connect,
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
                        let box = Unmanaged<ProductUserBox>
                            .fromOpaque(callbackData)
                            .takeRetainedValue()
                        guard result == EOS_Success else {
                            box.continuation.resume(
                                throwing: EOSSDKRuntime.operationError(
                                    "Connect_CreateUser",
                                    result: result
                                )
                            )
                            return
                        }
                        guard EOSSDKRuntime.isValidOnSDKThread(
                            callbackInfo.pointee.LocalUserId
                        ) else {
                            box.continuation.resume(
                                throwing: EOSPrivateIslandRuntimeError.invalidProductUserID
                            )
                            return
                        }
                        box.continuation.resume(
                            returning: callbackInfo.pointee.LocalUserId
                        )
                    }
                }
            } catch {
                Unmanaged<ProductUserBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }
    }

    private func queryMappings(
        targetProductUserID: EOS_ProductUserId,
        localUserID: EOS_ProductUserId
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ResultBox(
                operation: "QueryProductUserIdMappings",
                continuation: continuation
            )
            let clientData = Unmanaged.passRetained(box).toOpaque()
            do {
                try schedule { context in
                    var target: EOS_ProductUserId? = targetProductUserID
                    var options = EOS_Connect_QueryProductUserIdMappingsOptions()
                    options.ApiVersion = EOS_CONNECT_QUERYPRODUCTUSERIDMAPPINGS_API_LATEST
                    options.LocalUserId = localUserID
                    options.AccountIdType_DEPRECATED = EOS_EAT_OPENID
                    options.ProductUserIdCount = 1
                    withUnsafeMutablePointer(to: &target) { targetPointer in
                        options.ProductUserIds = targetPointer
                        EOS_Connect_QueryProductUserIdMappings(
                            context.connect,
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
                            let box = Unmanaged<ResultBox>
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
                }
            } catch {
                Unmanaged<ResultBox>.fromOpaque(clientData).release()
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class EOSSDKThreadWorker {
    private let configuration: EOSPrivateIslandConfiguration
    private let stateCondition = NSCondition()
    private var startupResult: Result<Void, Error>?
    private var didStop = false
    private var runLoop: CFRunLoop?
    private var context: EOSSDKRuntime.Context?
    private var tickTimer: Timer?
    private var tickHandlers: [UUID: (EOSSDKRuntime.Context) -> Void] = [:]
    private lazy var thread: Thread = {
        let thread = Thread { [weak self] in
            self?.threadMain()
        }
        thread.name = "com.landfall.eos-sdk"
        thread.qualityOfService = .userInitiated
        return thread
    }()

    init(configuration: EOSPrivateIslandConfiguration) {
        self.configuration = configuration
    }

    func start() throws {
        thread.start()
        stateCondition.lock()
        while startupResult == nil {
            stateCondition.wait()
        }
        let result = startupResult!
        stateCondition.unlock()
        try result.get()
    }

    func schedule(
        _ operation: @escaping (EOSSDKRuntime.Context) -> Void
    ) throws {
        stateCondition.lock()
        guard !didStop, let runLoop, let context else {
            stateCondition.unlock()
            throw EOSPrivateIslandRuntimeError.transportNotReady
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            operation(context)
        }
        CFRunLoopWakeUp(runLoop)
        stateCondition.unlock()
    }

    /// Must only be called from a closure submitted with `schedule`.
    func addTickHandler(
        _ handler: @escaping (EOSSDKRuntime.Context) -> Void
    ) -> UUID {
        let identifier = UUID()
        tickHandlers[identifier] = handler
        return identifier
    }

    /// Must only be called from a closure submitted with `schedule`.
    func removeTickHandler(_ identifier: UUID) {
        tickHandlers.removeValue(forKey: identifier)
    }

    private func threadMain() {
        autoreleasepool {
            do {
                let context = try makeContext()
                stateCondition.lock()
                self.context = context
                runLoop = CFRunLoopGetCurrent()
                startupResult = .success(())
                stateCondition.broadcast()
                stateCondition.unlock()

                let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) {
                    [weak self] _ in
                    guard let self, let context = self.context else { return }
                    EOS_Platform_Tick(context.platform)
                    let handlers = Array(self.tickHandlers.values)
                    for handler in handlers {
                        handler(context)
                    }
                }
                RunLoop.current.add(timer, forMode: .default)
                tickTimer = timer
                timer.fire()

                while true {
                    stateCondition.lock()
                    let shouldStop = didStop
                    stateCondition.unlock()
                    guard !shouldStop else { break }
                    autoreleasepool {
                        _ = RunLoop.current.run(
                            mode: .default,
                            before: Date(timeIntervalSinceNow: 1)
                        )
                    }
                }

                timer.invalidate()
                tickHandlers.removeAll()
                EOS_Platform_Release(context.platform)
                self.context = nil
                _ = EOS_Shutdown()
            } catch {
                stateCondition.lock()
                startupResult = .failure(error)
                didStop = true
                stateCondition.broadcast()
                stateCondition.unlock()
            }
        }
    }

    private func makeContext() throws -> EOSSDKRuntime.Context {
        let initializeResult = configuration.productName.withCString { productName in
            configuration.productVersion.withCString { productVersion in
                var options = EOS_InitializeOptions()
                options.ApiVersion = EOS_INITIALIZE_API_LATEST
                options.ProductName = productName
                options.ProductVersion = productVersion
                return EOS_Initialize(&options)
            }
        }
        guard initializeResult == EOS_Success
                || initializeResult == EOS_AlreadyConfigured
        else {
            throw EOSPrivateIslandRuntimeError.sdkInitializationFailed(
                EOSSDKRuntime.operationError(
                    "Initialize",
                    result: initializeResult
                ).localizedDescription
            )
        }

        let platform = configuration.productID.withCString { productID in
            configuration.sandboxID.withCString { sandboxID in
                configuration.deploymentID.withCString { deploymentID in
                    configuration.clientID.withCString { clientID in
                        configuration.clientSecret.withCString { clientSecret in
                            var credentials = EOS_Platform_ClientCredentials()
                            credentials.ClientId = clientID
                            credentials.ClientSecret = clientSecret

                            var options = EOS_Platform_Options()
                            options.ApiVersion = EOS_PLATFORM_OPTIONS_API_LATEST
                            options.ProductId = productID
                            options.SandboxId = sandboxID
                            options.ClientCredentials = credentials
                            options.bIsServer = EOS_FALSE
                            options.DeploymentId = deploymentID
                            options.Flags = UInt64(EOS_PF_DISABLE_OVERLAY)
                            options.TickBudgetInMilliseconds = 1
                            return EOS_Platform_Create(&options)
                        }
                    }
                }
            }
        }
        guard let platform else {
            _ = EOS_Shutdown()
            throw EOSPrivateIslandRuntimeError.platformCreationFailed
        }
        guard let connect = EOS_Platform_GetConnectInterface(platform) else {
            EOS_Platform_Release(platform)
            _ = EOS_Shutdown()
            throw EOSPrivateIslandRuntimeError.sdkInterfaceUnavailable("Connect")
        }
        guard let lobby = EOS_Platform_GetLobbyInterface(platform) else {
            EOS_Platform_Release(platform)
            _ = EOS_Shutdown()
            throw EOSPrivateIslandRuntimeError.sdkInterfaceUnavailable("Lobby")
        }
        guard let p2p = EOS_Platform_GetP2PInterface(platform) else {
            EOS_Platform_Release(platform)
            _ = EOS_Shutdown()
            throw EOSPrivateIslandRuntimeError.sdkInterfaceUnavailable("P2P")
        }
        return EOSSDKRuntime.Context(
            platform: platform,
            connect: connect,
            lobby: lobby,
            p2p: p2p
        )
    }
}
#endif
