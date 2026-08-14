import Foundation

/// Payload-only schemas carried inside `EOSIslandPacketCodec`'s 48-byte
/// envelope. Identity is intentionally absent: the adapter derives it from the
/// EOS receive metadata and its verified lobby PUID-to-Firebase-UID roster.
enum EOSPrivateIslandPayloadCodec {
    enum PayloadError: Error, Equatable {
        case invalidValue
        case truncated
        case trailingBytes
        case invalidUTF8
        case payloadTooLarge
    }

    static func encodePresence(
        _ presence: PrivateIslandTransportPresence
    ) throws -> Data {
        try PrivateIslandTransportCodec.validate(presence)
        var writer = Writer()
        writer.append(presence.x.bitPattern)
        writer.append(presence.z.bitPattern)
        writer.append(presence.yaw.bitPattern)
        writer.append(UInt64(bitPattern: presence.updatedAtMilliseconds))
        writer.append(UInt8(presence.isVisible ? 1 : 0))
        try writer.append(presence.pose, maximumBytes: 40)
        try writer.append(presence.scene, maximumBytes: 40)
        try writer.append(presence.phase, maximumBytes: 40)
        try writer.appendOptional(presence.seatPlacementID, maximumBytes: 64)
        try writer.appendOptional(presence.seatSlotID, maximumBytes: 40)
        try writer.appendOptional(presence.arrivalNonce, maximumBytes: 64)
        guard writer.data.count <= EOSIslandPacketCodec.maximumPayloadByteCount else {
            throw PayloadError.payloadTooLarge
        }
        return writer.data
    }

    static func decodePresence(
        _ payload: Data,
        verifiedParticipantID: String
    ) throws -> PrivateIslandTransportPresence {
        var reader = Reader(data: payload)
        let x = Float(bitPattern: try reader.readUInt32())
        let z = Float(bitPattern: try reader.readUInt32())
        let yaw = Float(bitPattern: try reader.readUInt32())
        let updatedAt = Int64(bitPattern: try reader.readUInt64())
        let visibility = try reader.readUInt8()
        guard visibility <= 1 else { throw PayloadError.invalidValue }
        let presence = PrivateIslandTransportPresence(
            participantID: verifiedParticipantID,
            x: x,
            z: z,
            yaw: yaw,
            pose: try reader.readString(maximumBytes: 40),
            scene: try reader.readString(maximumBytes: 40),
            phase: try reader.readString(maximumBytes: 40),
            seatPlacementID: try reader.readOptionalString(maximumBytes: 64),
            seatSlotID: try reader.readOptionalString(maximumBytes: 40),
            arrivalNonce: try reader.readOptionalString(maximumBytes: 64),
            isVisible: visibility == 1,
            updatedAtMilliseconds: updatedAt
        )
        guard reader.isAtEnd else { throw PayloadError.trailingBytes }
        do {
            try PrivateIslandTransportCodec.validate(presence)
        } catch {
            throw PayloadError.invalidValue
        }
        return presence
    }

    static func encodeChat(text: String, createdAtMilliseconds: Int64) throws -> Data {
        guard !text.isEmpty, text.count <= 500 else {
            throw PayloadError.invalidValue
        }
        var writer = Writer()
        writer.append(UInt64(bitPattern: createdAtMilliseconds))
        try writer.append(text, maximumBytes: 960)
        guard writer.data.count <= EOSIslandPacketCodec.maximumPayloadByteCount else {
            throw PayloadError.payloadTooLarge
        }
        return writer.data
    }

    static func decodeChat(
        _ payload: Data,
        verifiedSenderID: String,
        verifiedSenderName: String,
        messageID: UInt64
    ) throws -> PrivateIslandTransportChatMessage {
        guard messageID != 0 else { throw PayloadError.invalidValue }
        var reader = Reader(data: payload)
        let createdAt = Int64(bitPattern: try reader.readUInt64())
        let text = try reader.readString(maximumBytes: 960)
        guard !text.isEmpty, text.count <= 500, reader.isAtEnd else {
            throw reader.isAtEnd ? PayloadError.invalidValue : PayloadError.trailingBytes
        }
        let message = PrivateIslandTransportChatMessage(
            id: String(format: "%016llx", messageID),
            senderID: verifiedSenderID,
            senderName: verifiedSenderName,
            text: text,
            createdAtMilliseconds: createdAt
        )
        do {
            try PrivateIslandTransportCodec.validate(message)
        } catch {
            throw PayloadError.invalidValue
        }
        return message
    }

    private struct Writer {
        var data = Data()

        mutating func append(_ value: UInt8) {
            data.append(value)
        }

        mutating func append(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value >> 8))
            data.append(UInt8(truncatingIfNeeded: value))
        }

        mutating func append(_ value: UInt32) {
            data.append(UInt8(truncatingIfNeeded: value >> 24))
            data.append(UInt8(truncatingIfNeeded: value >> 16))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
            data.append(UInt8(truncatingIfNeeded: value))
        }

        mutating func append(_ value: UInt64) {
            data.append(UInt8(truncatingIfNeeded: value >> 56))
            data.append(UInt8(truncatingIfNeeded: value >> 48))
            data.append(UInt8(truncatingIfNeeded: value >> 40))
            data.append(UInt8(truncatingIfNeeded: value >> 32))
            data.append(UInt8(truncatingIfNeeded: value >> 24))
            data.append(UInt8(truncatingIfNeeded: value >> 16))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
            data.append(UInt8(truncatingIfNeeded: value))
        }

        mutating func append(_ value: String, maximumBytes: Int) throws {
            let bytes = Array(value.utf8)
            guard !bytes.isEmpty,
                  bytes.count <= maximumBytes,
                  bytes.count < Int(UInt16.max)
            else { throw PayloadError.invalidValue }
            append(UInt16(bytes.count))
            data.append(contentsOf: bytes)
        }

        mutating func appendOptional(
            _ value: String?,
            maximumBytes: Int
        ) throws {
            guard let value else {
                append(UInt16.max)
                return
            }
            let bytes = Array(value.utf8)
            guard bytes.count <= maximumBytes,
                  bytes.count < Int(UInt16.max)
            else { throw PayloadError.invalidValue }
            append(UInt16(bytes.count))
            data.append(contentsOf: bytes)
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        init(data: Data) {
            bytes = Array(data)
        }

        var isAtEnd: Bool { offset == bytes.count }

        mutating func readUInt8() throws -> UInt8 {
            guard offset < bytes.count else { throw PayloadError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readUInt16() throws -> UInt16 {
            guard bytes.count - offset >= 2 else { throw PayloadError.truncated }
            defer { offset += 2 }
            return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        }

        mutating func readUInt32() throws -> UInt32 {
            guard bytes.count - offset >= 4 else { throw PayloadError.truncated }
            defer { offset += 4 }
            return (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
        }

        mutating func readUInt64() throws -> UInt64 {
            guard bytes.count - offset >= 8 else { throw PayloadError.truncated }
            defer { offset += 8 }
            return (UInt64(bytes[offset]) << 56)
                | (UInt64(bytes[offset + 1]) << 48)
                | (UInt64(bytes[offset + 2]) << 40)
                | (UInt64(bytes[offset + 3]) << 32)
                | (UInt64(bytes[offset + 4]) << 24)
                | (UInt64(bytes[offset + 5]) << 16)
                | (UInt64(bytes[offset + 6]) << 8)
                | UInt64(bytes[offset + 7])
        }

        mutating func readString(maximumBytes: Int) throws -> String {
            let length = Int(try readUInt16())
            guard length > 0, length <= maximumBytes else {
                throw PayloadError.invalidValue
            }
            return try readStringBytes(count: length)
        }

        mutating func readOptionalString(
            maximumBytes: Int
        ) throws -> String? {
            let rawLength = try readUInt16()
            guard rawLength != UInt16.max else { return nil }
            let length = Int(rawLength)
            guard length <= maximumBytes else { throw PayloadError.invalidValue }
            return try readStringBytes(count: length)
        }

        private mutating func readStringBytes(count: Int) throws -> String {
            guard count >= 0, bytes.count - offset >= count else {
                throw PayloadError.truncated
            }
            let valueBytes = bytes[offset..<(offset + count)]
            offset += count
            guard let value = String(bytes: valueBytes, encoding: .utf8) else {
                throw PayloadError.invalidUTF8
            }
            return value
        }
    }
}
