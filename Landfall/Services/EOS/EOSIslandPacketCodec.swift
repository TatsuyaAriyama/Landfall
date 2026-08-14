import Foundation

/// Bounded binary envelope codec for the private-island EOS protocol.
///
/// Payload schemas, connection state, reassembly limits, and replay windows are
/// intentionally owned by higher layers. This type validates every invariant
/// that can be decided from one packet and its EOS channel.
enum EOSIslandPacketCodec {
    static let protocolMajor: UInt8 = 1
    static let protocolMinor: UInt8 = 0
    static let headerByteCount = 48
    static let maximumPayloadByteCount = 976
    static let maximumPacketByteCount = 1_024
    static let maximumStream: UInt8 = 6

    struct Header: Equatable, Sendable {
        let protocolMajor: UInt8
        let protocolMinor: UInt8
        let kind: UInt8
        let flags: PacketFlags
        let hostEpoch: UInt32
        let sequence: UInt32
        let hostTickMilliseconds: UInt32
        let senderSlot: UInt8
        let stream: UInt8
        let fragmentIndex: UInt8
        let fragmentCount: UInt8
        let linkNonce: UInt64
        let messageID: UInt64

        var registeredKind: PacketKind? {
            PacketKind(rawValue: kind)
        }

        init(
            protocolMajor: UInt8 = EOSIslandPacketCodec.protocolMajor,
            protocolMinor: UInt8 = EOSIslandPacketCodec.protocolMinor,
            kind: UInt8,
            flags: PacketFlags = [.finalFragment],
            hostEpoch: UInt32,
            sequence: UInt32,
            hostTickMilliseconds: UInt32,
            senderSlot: UInt8,
            stream: UInt8,
            fragmentIndex: UInt8 = 0,
            fragmentCount: UInt8 = 1,
            linkNonce: UInt64,
            messageID: UInt64
        ) {
            self.protocolMajor = protocolMajor
            self.protocolMinor = protocolMinor
            self.kind = kind
            self.flags = flags
            self.hostEpoch = hostEpoch
            self.sequence = sequence
            self.hostTickMilliseconds = hostTickMilliseconds
            self.senderSlot = senderSlot
            self.stream = stream
            self.fragmentIndex = fragmentIndex
            self.fragmentCount = fragmentCount
            self.linkNonce = linkNonce
            self.messageID = messageID
        }

        init(
            protocolMajor: UInt8 = EOSIslandPacketCodec.protocolMajor,
            protocolMinor: UInt8 = EOSIslandPacketCodec.protocolMinor,
            kind: PacketKind,
            flags: PacketFlags = [.finalFragment],
            hostEpoch: UInt32,
            sequence: UInt32,
            hostTickMilliseconds: UInt32,
            senderSlot: UInt8,
            fragmentIndex: UInt8 = 0,
            fragmentCount: UInt8 = 1,
            linkNonce: UInt64,
            messageID: UInt64
        ) {
            self.init(
                protocolMajor: protocolMajor,
                protocolMinor: protocolMinor,
                kind: kind.rawValue,
                flags: flags,
                hostEpoch: hostEpoch,
                sequence: sequence,
                hostTickMilliseconds: hostTickMilliseconds,
                senderSlot: senderSlot,
                stream: kind.stream,
                fragmentIndex: fragmentIndex,
                fragmentCount: fragmentCount,
                linkNonce: linkNonce,
                messageID: messageID
            )
        }
    }

    struct Packet: Equatable, Sendable {
        let header: Header
        let payload: Data

        var registeredKind: PacketKind? {
            header.registeredKind
        }

        var payloadByteCount: Int {
            payload.count
        }
    }

    struct PacketFlags: OptionSet, Equatable, Sendable {
        let rawValue: UInt8

        static let acknowledgementRequired = PacketFlags(rawValue: 1 << 0)
        static let isAcknowledgement = PacketFlags(rawValue: 1 << 1)
        static let keyframe = PacketFlags(rawValue: 1 << 2)
        static let finalFragment = PacketFlags(rawValue: 1 << 3)
        static let compressed = PacketFlags(rawValue: 1 << 4)
        static let backendCommitted = PacketFlags(rawValue: 1 << 5)
    }

    enum PacketKind: UInt8, CaseIterable, Sendable {
        case hello = 0x01
        case welcome = 0x02
        case ready = 0x03
        case reject = 0x04
        case hostClaim = 0x05
        case roster = 0x06
        case resyncRequest = 0x07
        case resyncComplete = 0x08

        case playerSample = 0x10
        case worldFrame = 0x11

        case discreteSubmit = 0x20
        case discreteCommit = 0x21
        case worldKeyframe = 0x22

        case chatSubmit = 0x30
        case chatCommit = 0x31
        case chatReject = 0x32
        case chatBacklog = 0x33
        case chatTombstone = 0x34

        case snapshotManifest = 0x40
        case snapshotAcknowledgement = 0x41
        case snapshotNegativeAcknowledgement = 0x42
        case snapshotDelta = 0x43
        case snapshotFullRequest = 0x44
        case snapshotChunk = 0x45

        case ping = 0x50
        case pong = 0x51
        case metrics = 0x52

        var stream: UInt8 {
            switch self {
            case .hello, .welcome, .ready, .reject, .hostClaim, .roster,
                    .resyncRequest, .resyncComplete:
                return 0
            case .playerSample, .worldFrame:
                return 1
            case .discreteSubmit, .discreteCommit, .worldKeyframe:
                return 2
            case .chatSubmit, .chatCommit, .chatReject, .chatBacklog,
                    .chatTombstone:
                return 3
            case .snapshotManifest, .snapshotAcknowledgement,
                    .snapshotNegativeAcknowledgement, .snapshotDelta,
                    .snapshotFullRequest:
                return 4
            case .snapshotChunk:
                return 5
            case .ping, .pong, .metrics:
                return 6
            }
        }

        fileprivate var permitsZeroMessageID: Bool {
            switch self {
            case .playerSample, .worldFrame, .ping, .pong:
                return true
            default:
                return false
            }
        }
    }

    enum SerialComparison: Equatable, Sendable {
        case older
        case same
        case newer
        case ambiguousHalfRange
    }

    enum CodecError: Error, Equatable, Sendable {
        case packetTooShort(actual: Int)
        case packetTooLarge(actual: Int)
        case invalidMagic
        case invalidHeaderByteCount(actual: UInt16)
        case payloadTooLarge(actual: Int)
        case truncatedPacket(expected: Int, actual: Int)
        case trailingBytes(expected: Int, actual: Int)
        case unsupportedProtocolVersion(major: UInt8, minor: UInt8)
        case invalidFlags(rawValue: UInt8)
        case nonzeroReservedField(actual: UInt32)
        case invalidSenderSlot(actual: UInt8)
        case invalidStream(actual: UInt8)
        case channelMismatch(header: UInt8, eos: UInt8)
        case kindStreamMismatch(kind: UInt8, expected: UInt8, actual: UInt8)
        case unregisteredKindForEncoding(kind: UInt8)
        case invalidFragmentCount(actual: UInt8)
        case invalidFragmentIndex(index: UInt8, count: UInt8)
        case finalFragmentFlagMismatch(index: UInt8, count: UInt8, flag: Bool)
        case zeroLinkNonceNotAllowed
        case zeroHostEpochNotAllowed(kind: UInt8)
        case invalidInitialHelloTick(actual: UInt32)
        case invalidInitialHelloSenderSlot(actual: UInt8)
        case zeroMessageIDNotAllowed(kind: UInt8, fragmentCount: UInt8)
    }

    /// Encodes a packet for the stream declared in its header.
    static func encode(header: Header, payload: Data) throws -> Data {
        try encode(header: header, payload: payload, outgoingChannel: header.stream)
    }

    /// Encodes a packet and verifies that the caller will send it on the same
    /// EOS channel carried by the header.
    static func encode(
        header: Header,
        payload: Data,
        outgoingChannel: UInt8
    ) throws -> Data {
        guard payload.count <= maximumPayloadByteCount else {
            throw CodecError.payloadTooLarge(actual: payload.count)
        }
        try validateVersionOneHeader(
            header,
            eosChannel: outgoingChannel,
            allowsUnknownKind: false
        )

        var encoded = Data()
        encoded.reserveCapacity(headerByteCount + payload.count)
        encoded.append(contentsOf: magic)
        encoded.append(header.protocolMajor)
        encoded.append(header.protocolMinor)
        encoded.append(header.kind)
        encoded.append(header.flags.rawValue)
        append(UInt16(headerByteCount), to: &encoded)
        append(UInt16(payload.count), to: &encoded)
        append(header.hostEpoch, to: &encoded)
        append(header.sequence, to: &encoded)
        append(header.hostTickMilliseconds, to: &encoded)
        encoded.append(header.senderSlot)
        encoded.append(header.stream)
        encoded.append(header.fragmentIndex)
        encoded.append(header.fragmentCount)
        append(header.linkNonce, to: &encoded)
        append(header.messageID, to: &encoded)
        append(UInt32.zero, to: &encoded)
        assert(encoded.count == headerByteCount)
        encoded.append(payload)
        return encoded
    }

    /// Decodes one complete EOS packet. Unknown v1 kinds are returned with a
    /// nil `registeredKind` only after the complete envelope is validated.
    static func decode(_ packet: Data, receivedChannel: UInt8) throws -> Packet {
        guard packet.count >= headerByteCount else {
            throw CodecError.packetTooShort(actual: packet.count)
        }
        guard packet.count <= maximumPacketByteCount else {
            throw CodecError.packetTooLarge(actual: packet.count)
        }

        let bytes = [UInt8](packet)
        guard Array(bytes[0..<4]) == magic else {
            throw CodecError.invalidMagic
        }

        let decodedHeaderByteCount = readUInt16(bytes, at: 8)
        guard decodedHeaderByteCount == UInt16(headerByteCount) else {
            throw CodecError.invalidHeaderByteCount(actual: decodedHeaderByteCount)
        }

        let payloadByteCount = Int(readUInt16(bytes, at: 10))
        guard payloadByteCount <= maximumPayloadByteCount else {
            throw CodecError.payloadTooLarge(actual: payloadByteCount)
        }
        let expectedPacketByteCount = headerByteCount + payloadByteCount
        guard packet.count >= expectedPacketByteCount else {
            throw CodecError.truncatedPacket(
                expected: expectedPacketByteCount,
                actual: packet.count
            )
        }
        guard packet.count == expectedPacketByteCount else {
            throw CodecError.trailingBytes(
                expected: expectedPacketByteCount,
                actual: packet.count
            )
        }

        let decodedProtocolMajor = bytes[4]
        let decodedProtocolMinor = bytes[5]
        guard decodedProtocolMajor == protocolMajor,
              decodedProtocolMinor == protocolMinor
        else {
            throw CodecError.unsupportedProtocolVersion(
                major: decodedProtocolMajor,
                minor: decodedProtocolMinor
            )
        }

        let header = Header(
            protocolMajor: decodedProtocolMajor,
            protocolMinor: decodedProtocolMinor,
            kind: bytes[6],
            flags: PacketFlags(rawValue: bytes[7]),
            hostEpoch: readUInt32(bytes, at: 12),
            sequence: readUInt32(bytes, at: 16),
            hostTickMilliseconds: readUInt32(bytes, at: 20),
            senderSlot: bytes[24],
            stream: bytes[25],
            fragmentIndex: bytes[26],
            fragmentCount: bytes[27],
            linkNonce: readUInt64(bytes, at: 28),
            messageID: readUInt64(bytes, at: 36)
        )

        let reserved = readUInt32(bytes, at: 44)
        guard reserved == 0 else {
            throw CodecError.nonzeroReservedField(actual: reserved)
        }
        try validateVersionOneHeader(
            header,
            eosChannel: receivedChannel,
            allowsUnknownKind: true
        )

        return Packet(
            header: header,
            payload: Data(bytes[headerByteCount..<expectedPacketByteCount])
        )
    }

    /// RFC 1982-style UInt32 comparison used by host epochs and sequences.
    /// Values separated by exactly half the number space are intentionally
    /// reported as ambiguous and must not advance protocol state.
    static func compareSerial(
        _ candidate: UInt32,
        against reference: UInt32
    ) -> SerialComparison {
        let difference = candidate &- reference
        switch difference {
        case 0:
            return .same
        case 0x8000_0000:
            return .ambiguousHalfRange
        default:
            return Int32(bitPattern: difference) > 0 ? .newer : .older
        }
    }

    static func isSerialNewer(_ candidate: UInt32, than reference: UInt32) -> Bool {
        Int32(bitPattern: candidate &- reference) > 0
    }

    private static let magic: [UInt8] = [0x4C, 0x46, 0x45, 0x50]
    private static let allowedVersionOneFlags: UInt8 =
        PacketFlags.acknowledgementRequired.rawValue
        | PacketFlags.isAcknowledgement.rawValue
        | PacketFlags.keyframe.rawValue
        | PacketFlags.finalFragment.rawValue
        | PacketFlags.backendCommitted.rawValue

    private static func validateVersionOneHeader(
        _ header: Header,
        eosChannel: UInt8,
        allowsUnknownKind: Bool
    ) throws {
        guard header.protocolMajor == protocolMajor,
              header.protocolMinor == protocolMinor
        else {
            throw CodecError.unsupportedProtocolVersion(
                major: header.protocolMajor,
                minor: header.protocolMinor
            )
        }

        guard header.flags.rawValue & ~allowedVersionOneFlags == 0 else {
            throw CodecError.invalidFlags(rawValue: header.flags.rawValue)
        }
        guard header.senderSlot <= 7 || header.senderSlot == .max else {
            throw CodecError.invalidSenderSlot(actual: header.senderSlot)
        }
        guard header.stream <= maximumStream else {
            throw CodecError.invalidStream(actual: header.stream)
        }
        guard header.stream == eosChannel else {
            throw CodecError.channelMismatch(header: header.stream, eos: eosChannel)
        }

        let registeredKind = header.registeredKind
        if let registeredKind {
            guard registeredKind.stream == header.stream else {
                throw CodecError.kindStreamMismatch(
                    kind: header.kind,
                    expected: registeredKind.stream,
                    actual: header.stream
                )
            }
        } else if !allowsUnknownKind {
            throw CodecError.unregisteredKindForEncoding(kind: header.kind)
        }

        guard header.fragmentCount > 0 else {
            throw CodecError.invalidFragmentCount(actual: header.fragmentCount)
        }
        guard header.fragmentIndex < header.fragmentCount else {
            throw CodecError.invalidFragmentIndex(
                index: header.fragmentIndex,
                count: header.fragmentCount
            )
        }
        let isFinalFragment = header.fragmentIndex == header.fragmentCount - 1
        let hasFinalFragmentFlag = header.flags.contains(.finalFragment)
        guard isFinalFragment == hasFinalFragmentFlag else {
            throw CodecError.finalFragmentFlagMismatch(
                index: header.fragmentIndex,
                count: header.fragmentCount,
                flag: hasFinalFragmentFlag
            )
        }

        guard header.linkNonce != 0 else {
            throw CodecError.zeroLinkNonceNotAllowed
        }

        if header.hostEpoch == 0 {
            guard registeredKind == .hello else {
                throw CodecError.zeroHostEpochNotAllowed(kind: header.kind)
            }
            guard header.hostTickMilliseconds == 0 else {
                throw CodecError.invalidInitialHelloTick(
                    actual: header.hostTickMilliseconds
                )
            }
            guard header.senderSlot == .max else {
                throw CodecError.invalidInitialHelloSenderSlot(
                    actual: header.senderSlot
                )
            }
        }

        if header.messageID == 0 {
            guard header.fragmentCount == 1,
                  let registeredKind,
                  registeredKind.permitsZeroMessageID
            else {
                throw CodecError.zeroMessageIDNotAllowed(
                    kind: header.kind,
                    fragmentCount: header.fragmentCount
                )
            }
        }
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 56))
        data.append(UInt8(truncatingIfNeeded: value >> 48))
        data.append(UInt8(truncatingIfNeeded: value >> 40))
        data.append(UInt8(truncatingIfNeeded: value >> 32))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8)
            | UInt16(bytes[offset + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        (UInt64(bytes[offset]) << 56)
            | (UInt64(bytes[offset + 1]) << 48)
            | (UInt64(bytes[offset + 2]) << 40)
            | (UInt64(bytes[offset + 3]) << 32)
            | (UInt64(bytes[offset + 4]) << 24)
            | (UInt64(bytes[offset + 5]) << 16)
            | (UInt64(bytes[offset + 6]) << 8)
            | UInt64(bytes[offset + 7])
    }
}
