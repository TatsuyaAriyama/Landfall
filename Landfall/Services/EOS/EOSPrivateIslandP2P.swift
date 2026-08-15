#if EOS_SDK_AVAILABLE && !targetEnvironment(simulator)
import EOSSDK
import Foundation

/// Thin, thread-confined wrapper around a session-scoped EOS P2P socket.
/// Authorization remains the adapter's responsibility; this class never
/// accepts a peer implicitly and never infers identity from packet bytes.
final class EOSPrivateIslandP2P {
    struct ReceivedPacket {
        let remoteProductUserID: EOS_ProductUserId
        let remoteProductUserIDString: String
        let channel: UInt8
        let data: Data
    }

    typealias ConnectionRequestHandler = (EOS_ProductUserId, String) -> Void
    typealias PacketHandler = (ReceivedPacket) -> Void
    typealias ErrorHandler = (Error) -> Void

    static let maximumPacketsPerTick = 64
    static let maximumPumpDuration: TimeInterval = 0.004

    var onConnectionRequest: ConnectionRequestHandler?
    var onPacket: PacketHandler?
    var onError: ErrorHandler?
    var onConnectionEstablished: ConnectionRequestHandler?
    var onConnectionClosed: ConnectionRequestHandler?

    private let runtime: EOSSDKRuntime
    private let socketName: String
    private var localUserID: EOS_ProductUserId?
    private var requestNotificationID: EOS_NotificationId?
    private var requestClientData: UnsafeMutableRawPointer?
    private var establishedNotificationID: EOS_NotificationId?
    private var establishedClientData: UnsafeMutableRawPointer?
    private var closedNotificationID: EOS_NotificationId?
    private var closedClientData: UnsafeMutableRawPointer?
    private var tickHandlerID: UUID?

    init(runtime: EOSSDKRuntime, socketName: String) throws {
        guard !socketName.isEmpty,
              socketName.utf8.count <= 32,
              socketName.utf8.allSatisfy({ byte in
                  (48...57).contains(byte)
                      || (65...90).contains(byte)
                      || (97...122).contains(byte)
                      || byte == 45 || byte == 95 || byte == 32
                      || byte == 43 || byte == 61 || byte == 46
              })
        else {
            throw EOSPrivateIslandRuntimeError.invalidSocketSecret
        }
        self.runtime = runtime
        self.socketName = socketName
    }

    func start(localUserID: EOS_ProductUserId) async throws {
        guard self.localUserID == nil else { return }
        let requestBox = ConnectionRequestBox { [weak self] remoteUserID in
            guard let self else { return }
            do {
                let remoteID = try Self.productUserIDString(remoteUserID)
                self.onConnectionRequest?(remoteUserID, remoteID)
            } catch {
                self.onError?(error)
            }
        }
        let clientData = Unmanaged.passRetained(requestBox).toOpaque()

        do {
            let notificationID: EOS_NotificationId = try await runtime.run { context in
                var socket = Self.makeSocketID(name: self.socketName)
                var options = EOS_P2P_AddNotifyPeerConnectionRequestOptions()
                options.ApiVersion = EOS_P2P_ADDNOTIFYPEERCONNECTIONREQUEST_API_LATEST
                options.LocalUserId = localUserID
                return withUnsafePointer(to: &socket) { socketPointer in
                    options.SocketId = socketPointer
                    return EOS_P2P_AddNotifyPeerConnectionRequest(
                        context.p2p,
                        &options,
                        clientData
                    ) { callbackInfo in
                        guard let callbackInfo,
                              let callbackData = callbackInfo.pointee.ClientData
                        else { return }
                        let box = Unmanaged<ConnectionRequestBox>
                            .fromOpaque(callbackData)
                            .takeUnretainedValue()
                        box.handler(callbackInfo.pointee.RemoteUserId)
                    }
                }
            }
            guard notificationID != EOS_INVALID_NOTIFICATIONID else {
                throw EOSPrivateIslandRuntimeError.sdkOperationFailed(
                    operation: "P2P_AddNotifyPeerConnectionRequest",
                    result: "invalid notification identifier"
                )
            }
            requestNotificationID = notificationID
            requestClientData = clientData
            self.localUserID = localUserID
            try await registerConnectionLifecycleNotifications(localUserID: localUserID)
            tickHandlerID = try await runtime.addTickHandler { [weak self] context in
                self?.receivePump(context: context, localUserID: localUserID)
            }
        } catch {
            if requestClientData == nil {
                Unmanaged<ConnectionRequestBox>.fromOpaque(clientData).release()
            } else {
                await stop()
            }
            throw error
        }
    }

    /// Accepts only a peer that the caller has already resolved through EOS
    /// Connect and checked against Firebase room membership/topology.
    func accept(remoteUserID: EOS_ProductUserId) async throws {
        guard let localUserID else {
            throw EOSPrivateIslandRuntimeError.transportNotReady
        }
        try await runtime.run { context in
            var socket = Self.makeSocketID(name: self.socketName)
            var options = EOS_P2P_AcceptConnectionOptions()
            options.ApiVersion = EOS_P2P_ACCEPTCONNECTION_API_LATEST
            options.LocalUserId = localUserID
            options.RemoteUserId = remoteUserID
            let result = withUnsafePointer(to: &socket) { socketPointer in
                options.SocketId = socketPointer
                return EOS_P2P_AcceptConnection(context.p2p, &options)
            }
            guard result == EOS_Success else {
                throw EOSSDKRuntime.operationError(
                    "P2P_AcceptConnection",
                    result: result
                )
            }
        }
    }

    func close(remoteUserID: EOS_ProductUserId) async {
        guard let localUserID else { return }
        _ = try? await runtime.run { context in
            var socket = Self.makeSocketID(name: self.socketName)
            var options = EOS_P2P_CloseConnectionOptions()
            options.ApiVersion = EOS_P2P_CLOSECONNECTION_API_LATEST
            options.LocalUserId = localUserID
            options.RemoteUserId = remoteUserID
            _ = withUnsafePointer(to: &socket) { socketPointer in
                options.SocketId = socketPointer
                return EOS_P2P_CloseConnection(context.p2p, &options)
            }
        }
    }

    func send(
        _ data: Data,
        to remoteUserID: EOS_ProductUserId,
        channel: UInt8,
        delivery: PrivateIslandTransportDelivery,
        allowDelayedDelivery: Bool = false
    ) async throws {
        guard let localUserID else {
            throw EOSPrivateIslandRuntimeError.transportNotReady
        }
        guard !data.isEmpty,
              data.count <= EOSIslandPacketCodec.maximumPacketByteCount,
              channel <= EOSIslandPacketCodec.maximumStream
        else {
            throw EOSPrivateIslandRuntimeError.packetTooLarge
        }
        try await runtime.run { context in
            var socket = Self.makeSocketID(name: self.socketName)
            let result = data.withUnsafeBytes { dataBytes in
                var options = EOS_P2P_SendPacketOptions()
                options.ApiVersion = EOS_P2P_SENDPACKET_API_LATEST
                options.LocalUserId = localUserID
                options.RemoteUserId = remoteUserID
                options.Channel = channel
                options.DataLengthBytes = UInt32(dataBytes.count)
                options.Data = dataBytes.baseAddress
                options.bAllowDelayedDelivery = allowDelayedDelivery
                    ? EOS_TRUE
                    : EOS_FALSE
                options.Reliability = delivery == .bestEffort
                    ? EOS_PR_UnreliableUnordered
                    : EOS_PR_ReliableOrdered
                options.bDisableAutoAcceptConnection = EOS_TRUE
                return withUnsafePointer(to: &socket) { socketPointer in
                    options.SocketId = socketPointer
                    return EOS_P2P_SendPacket(context.p2p, &options)
                }
            }
            guard result == EOS_Success else {
                throw EOSSDKRuntime.operationError("P2P_SendPacket", result: result)
            }
        }
    }

    func stop() async {
        if let tickHandlerID {
            await runtime.removeTickHandler(tickHandlerID)
            self.tickHandlerID = nil
        }
        guard let localUserID else { return }
        let notificationID = requestNotificationID
        let clientData = requestClientData
        let establishedNotificationID = establishedNotificationID
        let establishedClientData = establishedClientData
        let closedNotificationID = closedNotificationID
        let closedClientData = closedClientData
        _ = try? await runtime.run { context in
            if let notificationID {
                EOS_P2P_RemoveNotifyPeerConnectionRequest(
                    context.p2p,
                    notificationID
                )
            }
            if let establishedNotificationID {
                EOS_P2P_RemoveNotifyPeerConnectionEstablished(
                    context.p2p,
                    establishedNotificationID
                )
            }
            if let closedNotificationID {
                EOS_P2P_RemoveNotifyPeerConnectionClosed(
                    context.p2p,
                    closedNotificationID
                )
            }
            var socket = Self.makeSocketID(name: self.socketName)
            var options = EOS_P2P_CloseConnectionsOptions()
            options.ApiVersion = EOS_P2P_CLOSECONNECTIONS_API_LATEST
            options.LocalUserId = localUserID
            _ = withUnsafePointer(to: &socket) { socketPointer in
                options.SocketId = socketPointer
                return EOS_P2P_CloseConnections(context.p2p, &options)
            }
        }
        if let clientData {
            // Removal completed on the SDK thread before `run` returned. If
            // scheduling failed, the process-global worker is no longer able
            // to invoke the callback, so retaining the box would only leak it.
            Unmanaged<ConnectionRequestBox>.fromOpaque(clientData).release()
        }
        if let establishedClientData {
            Unmanaged<ConnectionRequestBox>.fromOpaque(establishedClientData).release()
        }
        if let closedClientData {
            Unmanaged<ConnectionRequestBox>.fromOpaque(closedClientData).release()
        }
        requestNotificationID = nil
        requestClientData = nil
        self.establishedNotificationID = nil
        self.establishedClientData = nil
        self.closedNotificationID = nil
        self.closedClientData = nil
        self.localUserID = nil
    }

    private func registerConnectionLifecycleNotifications(
        localUserID: EOS_ProductUserId
    ) async throws {
        let establishedBox = ConnectionRequestBox { [weak self] remoteUserID in
            guard let self else { return }
            do {
                self.onConnectionEstablished?(
                    remoteUserID,
                    try Self.productUserIDString(remoteUserID)
                )
            } catch {
                self.onError?(error)
            }
        }
        let establishedData = Unmanaged.passRetained(establishedBox).toOpaque()
        do {
            let identifier: EOS_NotificationId = try await runtime.run { context in
                var socket = Self.makeSocketID(name: self.socketName)
                var options = EOS_P2P_AddNotifyPeerConnectionEstablishedOptions()
                options.ApiVersion = EOS_P2P_ADDNOTIFYPEERCONNECTIONESTABLISHED_API_LATEST
                options.LocalUserId = localUserID
                return withUnsafePointer(to: &socket) { pointer in
                    options.SocketId = pointer
                    return EOS_P2P_AddNotifyPeerConnectionEstablished(
                        context.p2p,
                        &options,
                        establishedData
                    ) { info in
                        guard let info,
                              let data = info.pointee.ClientData
                        else { return }
                        Unmanaged<ConnectionRequestBox>
                            .fromOpaque(data)
                            .takeUnretainedValue()
                            .handler(info.pointee.RemoteUserId)
                    }
                }
            }
            guard identifier != EOS_INVALID_NOTIFICATIONID else {
                throw EOSPrivateIslandRuntimeError.sdkOperationFailed(
                    operation: "P2P_AddNotifyPeerConnectionEstablished",
                    result: "invalid notification identifier"
                )
            }
            establishedNotificationID = identifier
            establishedClientData = establishedData
        } catch {
            Unmanaged<ConnectionRequestBox>.fromOpaque(establishedData).release()
            throw error
        }

        let closedBox = ConnectionRequestBox { [weak self] remoteUserID in
            guard let self else { return }
            do {
                self.onConnectionClosed?(
                    remoteUserID,
                    try Self.productUserIDString(remoteUserID)
                )
            } catch {
                self.onError?(error)
            }
        }
        let closedData = Unmanaged.passRetained(closedBox).toOpaque()
        do {
            let identifier: EOS_NotificationId = try await runtime.run { context in
                var socket = Self.makeSocketID(name: self.socketName)
                var options = EOS_P2P_AddNotifyPeerConnectionClosedOptions()
                options.ApiVersion = EOS_P2P_ADDNOTIFYPEERCONNECTIONCLOSED_API_LATEST
                options.LocalUserId = localUserID
                return withUnsafePointer(to: &socket) { pointer in
                    options.SocketId = pointer
                    return EOS_P2P_AddNotifyPeerConnectionClosed(
                        context.p2p,
                        &options,
                        closedData
                    ) { info in
                        guard let info,
                              let data = info.pointee.ClientData
                        else { return }
                        Unmanaged<ConnectionRequestBox>
                            .fromOpaque(data)
                            .takeUnretainedValue()
                            .handler(info.pointee.RemoteUserId)
                    }
                }
            }
            guard identifier != EOS_INVALID_NOTIFICATIONID else {
                throw EOSPrivateIslandRuntimeError.sdkOperationFailed(
                    operation: "P2P_AddNotifyPeerConnectionClosed",
                    result: "invalid notification identifier"
                )
            }
            closedNotificationID = identifier
            closedClientData = closedData
        } catch {
            Unmanaged<ConnectionRequestBox>.fromOpaque(closedData).release()
            throw error
        }
    }

    private func receivePump(
        context: EOSSDKRuntime.Context,
        localUserID: EOS_ProductUserId
    ) {
        let deadline = CFAbsoluteTimeGetCurrent() + Self.maximumPumpDuration
        for _ in 0..<Self.maximumPacketsPerTick {
            guard CFAbsoluteTimeGetCurrent() < deadline else { break }
            var sizeOptions = EOS_P2P_GetNextReceivedPacketSizeOptions()
            sizeOptions.ApiVersion = EOS_P2P_GETNEXTRECEIVEDPACKETSIZE_API_LATEST
            sizeOptions.LocalUserId = localUserID
            var packetSize: UInt32 = 0
            let sizeResult = EOS_P2P_GetNextReceivedPacketSize(
                context.p2p,
                &sizeOptions,
                &packetSize
            )
            if sizeResult == EOS_NotFound { break }
            guard sizeResult == EOS_Success else {
                onError?(
                    EOSSDKRuntime.operationError(
                        "P2P_GetNextReceivedPacketSize",
                        result: sizeResult
                    )
                )
                break
            }

            // EOS currently caps packets at 1170 bytes. Drain the SDK packet
            // even when it exceeds Landfall's stricter 1024-byte protocol cap.
            guard packetSize > 0, packetSize <= 1_170 else {
                onError?(EOSPrivateIslandRuntimeError.packetTooLarge)
                break
            }
            var buffer = Data(count: Int(packetSize))
            var remoteUserID: EOS_ProductUserId?
            var receivedSocket = EOS_P2P_SocketId()
            var channel: UInt8 = 0
            var bytesWritten: UInt32 = 0
            let receiveResult = buffer.withUnsafeMutableBytes { bytes in
                var options = EOS_P2P_ReceivePacketOptions()
                options.ApiVersion = EOS_P2P_RECEIVEPACKET_API_LATEST
                options.LocalUserId = localUserID
                options.MaxDataSizeBytes = UInt32(bytes.count)
                return EOS_P2P_ReceivePacket(
                    context.p2p,
                    &options,
                    &remoteUserID,
                    &receivedSocket,
                    &channel,
                    bytes.baseAddress,
                    &bytesWritten
                )
            }
            guard receiveResult == EOS_Success else {
                onError?(
                    EOSSDKRuntime.operationError(
                        "P2P_ReceivePacket",
                        result: receiveResult
                    )
                )
                continue
            }
            guard bytesWritten <= packetSize else {
                onError?(EOSPrivateIslandRuntimeError.packetRejected)
                continue
            }
            buffer.count = Int(bytesWritten)
            guard buffer.count <= EOSIslandPacketCodec.maximumPacketByteCount else {
                onError?(EOSPrivateIslandRuntimeError.packetTooLarge)
                continue
            }
            guard Self.socketName(from: receivedSocket) == socketName,
                  let remoteUserID
            else {
                continue
            }
            do {
                let remoteID = try Self.productUserIDString(remoteUserID)
                onPacket?(
                    ReceivedPacket(
                        remoteProductUserID: remoteUserID,
                        remoteProductUserIDString: remoteID,
                        channel: channel,
                        data: buffer
                    )
                )
            } catch {
                onError?(error)
            }
        }
    }

    private static func makeSocketID(name: String) -> EOS_P2P_SocketId {
        var socket = EOS_P2P_SocketId()
        socket.ApiVersion = EOS_P2P_SOCKETID_API_LATEST
        withUnsafeMutableBytes(of: &socket.SocketName) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in name.utf8.enumerated() {
                bytes[index] = byte
            }
        }
        return socket
    }

    private static func socketName(from socket: EOS_P2P_SocketId) -> String {
        var socket = socket
        return withUnsafePointer(to: &socket.SocketName) { tuplePointer in
            tuplePointer.withMemoryRebound(
                to: CChar.self,
                capacity: Int(EOS_P2P_SOCKETID_SOCKETNAME_SIZE)
            ) { String(cString: $0) }
        }
    }

    private static func productUserIDString(
        _ productUserID: EOS_ProductUserId
    ) throws -> String {
        guard EOSSDKRuntime.isValidOnSDKThread(productUserID) else {
            throw EOSPrivateIslandRuntimeError.invalidProductUserID
        }
        var buffer = [CChar](
            repeating: 0,
            count: Int(EOS_PRODUCTUSERID_MAX_LENGTH) + 1
        )
        var length = Int32(buffer.count)
        let result = EOS_ProductUserId_ToString(productUserID, &buffer, &length)
        guard result == EOS_Success else {
            throw EOSSDKRuntime.operationError(
                "ProductUserId_ToString",
                result: result
            )
        }
        return String(cString: buffer)
    }

    private final class ConnectionRequestBox {
        let handler: (EOS_ProductUserId) -> Void

        init(handler: @escaping (EOS_ProductUserId) -> Void) {
            self.handler = handler
        }
    }
}
#endif
