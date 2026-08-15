import Foundation
import CryptoKit

struct EOSPrivateIslandConfiguration: Equatable, Sendable {
    let productID: String
    let sandboxID: String
    let deploymentID: String
    let clientID: String
    let clientSecret: String
    let productName: String
    let productVersion: String

    static func load(from bundle: Bundle = .main) throws -> EOSPrivateIslandConfiguration {
        let requiredKeys = [
            "EOSProductID",
            "EOSSandboxID",
            "EOSDeploymentID",
            "EOSClientID",
            "EOSClientSecret",
        ]
        var values: [String: String] = [:]
        var missingKeys: [String] = []
        for key in requiredKeys {
            let value = (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                missingKeys.append(key)
            } else {
                values[key] = value
            }
        }
        guard missingKeys.isEmpty else {
            throw EOSPrivateIslandRuntimeError.missingConfiguration(missingKeys)
        }

        let rawName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "KeelMira"
        let rawVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "1"
        let productName = asciiValue(rawName, maximumBytes: 64, fallback: "KeelMira")
        let productVersion = asciiValue(rawVersion, maximumBytes: 64, fallback: "1")

        return EOSPrivateIslandConfiguration(
            productID: values["EOSProductID"]!,
            sandboxID: values["EOSSandboxID"]!,
            deploymentID: values["EOSDeploymentID"]!,
            clientID: values["EOSClientID"]!,
            clientSecret: values["EOSClientSecret"]!,
            productName: productName,
            productVersion: productVersion
        )
    }

    private static func asciiValue(
        _ rawValue: String,
        maximumBytes: Int,
        fallback: String
    ) -> String {
        let scalars = rawValue.unicodeScalars.filter { 32...126 ~= $0.value }
        let value = String(String.UnicodeScalarView(scalars)).prefix(maximumBytes)
        return value.isEmpty ? fallback : String(value)
    }
}

/// Ephemeral identifiers issued to authorized room members by the Firebase
/// control plane. Neither value may be derived from the six-character invite
/// code. Keeping the socket secret separate from the public lobby locator
/// prevents discovery of a lobby from also authorizing a P2P connection.
struct EOSPrivateIslandSessionConfiguration: Equatable, Sendable {
    let sessionLocator: String
    let socketName: String

    init(sessionLocator: String, socketSecret: String) throws {
        let locatorBytes = Array(sessionLocator.utf8)
        guard (32...64).contains(locatorBytes.count),
              locatorBytes.allSatisfy({ 0x21...0x7e ~= $0 })
        else {
            throw EOSPrivateIslandRuntimeError.invalidSessionLocator
        }
        let secretBytes = Array(socketSecret.utf8)
        guard secretBytes.count >= 32 else {
            throw EOSPrivateIslandRuntimeError.invalidSocketSecret
        }
        let digest = SHA256.hash(data: Data(secretBytes))
        let suffix = digest.prefix(15).map { String(format: "%02x", $0) }.joined()
        self.sessionLocator = sessionLocator
        socketName = "LF\(suffix)" // 32 EOS-safe characters.
    }
}

enum EOSPrivateIslandRuntimeError: LocalizedError, Equatable {
    case missingConfiguration([String])
    case notSignedIn
    case firebaseTokenUnavailable(String)
    case sdkInitializationFailed(String)
    case runtimeConfigurationMismatch
    case missingSessionLocator
    case invalidSessionLocator
    case missingSocketSecret
    case invalidSocketSecret
    case platformCreationFailed
    case sdkInterfaceUnavailable(String)
    case sdkOperationFailed(operation: String, result: String)
    case invalidProductUserID
    case productUserMappingMissing
    case productUserMappingMismatch
    case localUserIsNotRoomMember
    case remoteUserIsNotRoomMember
    case lobbyNotFound
    case lobbyConfigurationInvalid
    case lobbyIdentityChanged
    case packetRejected
    case packetTooLarge
    case transportNotReady

    var errorDescription: String? {
        switch self {
        case let .missingConfiguration(keys):
            return "Epic Online Services is not configured. Missing: \(keys.joined(separator: ", "))."
        case .notSignedIn:
            return "Sign in before starting Epic Online Services multiplayer."
        case let .firebaseTokenUnavailable(message):
            return "A Firebase identity token could not be obtained: \(message)"
        case let .sdkInitializationFailed(result):
            return "Epic Online Services could not initialize (\(result))."
        case .runtimeConfigurationMismatch:
            return "Epic Online Services was already started with different Portal settings."
        case .missingSessionLocator:
            return "This private island does not yet have a secure Epic session locator."
        case .invalidSessionLocator:
            return "The private-island Epic session locator was invalid."
        case .missingSocketSecret:
            return "This private island does not yet have a secure Epic socket secret."
        case .invalidSocketSecret:
            return "The private-island Epic socket secret was invalid."
        case .platformCreationFailed:
            return "Epic Online Services could not create its platform runtime."
        case let .sdkInterfaceUnavailable(name):
            return "The Epic Online Services \(name) interface is unavailable."
        case let .sdkOperationFailed(operation, result):
            return "Epic Online Services \(operation) failed (\(result))."
        case .invalidProductUserID:
            return "Epic Online Services returned an invalid Product User ID."
        case .productUserMappingMissing:
            return "The Epic Product User ID is not linked to a Firebase account."
        case .productUserMappingMismatch:
            return "The Epic Product User ID did not match the signed-in Firebase account."
        case .localUserIsNotRoomMember:
            return "The signed-in sailor is not a member of this private island."
        case .remoteUserIsNotRoomMember:
            return "A remote Epic user is not a verified member of this private island."
        case .lobbyNotFound:
            return "No Epic lobby was found for this private island."
        case .lobbyConfigurationInvalid:
            return "The Epic lobby did not match the private-island configuration."
        case .lobbyIdentityChanged:
            return "The Epic lobby identity changed while the session was active."
        case .packetRejected:
            return "A private-island real-time packet was rejected."
        case .packetTooLarge:
            return "A private-island real-time packet exceeded its size limit."
        case .transportNotReady:
            return "The Epic private-island transport is not ready."
        }
    }
}
