import CryptoKit
import Foundation

struct LicenseValidationResult {
    let isValid: Bool
    let message: String
    let licenseID: String?
}

enum LicenseService {
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let productCode: UInt8 = 2
    private static let editionCode: UInt8 = 1
    private static let signingSecret = "justquit-pro-license-secret"
    private static let activationURL = URL(string: "https://license-key-generator-api.onrender.com/v1/activate")!
    private static let deviceIDKey = "justQuit.licenseDeviceID"
    private static let epoch = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 1, day: 1))!

    static func activate(_ licenseKey: String) async -> LicenseValidationResult {
        let localResult = validate(licenseKey)
        guard localResult.isValid else { return localResult }

        do {
            var request = URLRequest(url: activationURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                ActivationRequest(
                    licenseKey: normalizedKey(from: licenseKey),
                    deviceID: deviceID(),
                    deviceName: Host.current().localizedName ?? "Mac",
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                )
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return LicenseValidationResult(isValid: false, message: "The license server returned an invalid response.", licenseID: nil)
            }

            if httpResponse.statusCode == 404 {
                return localResult
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return LicenseValidationResult(isValid: false, message: serverErrorMessage(from: data), licenseID: nil)
            }

            let activation = try JSONDecoder().decode(ActivationResponse.self, from: data)
            return LicenseValidationResult(
                isValid: true,
                message: "justQuit Pro is active.",
                licenseID: activation.licenseID.isEmpty ? localResult.licenseID : activation.licenseID
            )
        } catch {
            return LicenseValidationResult(
                isValid: false,
                message: "Could not contact the license server. \(error.localizedDescription)",
                licenseID: nil
            )
        }
    }

    static func validate(_ licenseKey: String) -> LicenseValidationResult {
        guard !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return LicenseValidationResult(
                isValid: false,
                message: "Activate justQuit Pro to unlock countdowns, confirmation, custom menu bar icons, and profiles.",
                licenseID: nil
            )
        }

        let normalized = normalizedKey(from: licenseKey)

        guard let decoded = decodeBase32(normalized), decoded.count == 22 else {
            return LicenseValidationResult(isValid: false, message: "Enter a valid justQuit Pro license key.", licenseID: nil)
        }

        let payload = decoded.prefix(10)
        let signature = decoded.suffix(12)

        guard payload[0] == productCode, payload[1] == editionCode else {
            return LicenseValidationResult(isValid: false, message: "This license is not for justQuit Pro.", licenseID: nil)
        }

        let expectedSignature = HMAC<SHA256>.authenticationCode(
            for: payload,
            using: SymmetricKey(data: Data(signingSecret.utf8))
        ).prefix(12)

        guard Data(signature) == Data(expectedSignature) else {
            return LicenseValidationResult(isValid: false, message: "The license signature could not be verified.", licenseID: nil)
        }

        let daysSinceEpoch = (Int(payload[2]) << 8) | Int(payload[3])
        guard let issuedDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: daysSinceEpoch, to: epoch),
              issuedDate <= Date().addingTimeInterval(24 * 60 * 60) else {
            return LicenseValidationResult(isValid: false, message: "This license has an invalid issue date.", licenseID: nil)
        }

        let licenseID = "JQPRO-\(encodeBase32(Array(payload.suffix(6))))"
        return LicenseValidationResult(isValid: true, message: "justQuit Pro is active.", licenseID: licenseID)
    }

    private static func normalizedKey(from licenseKey: String) -> String {
        licenseKey
            .uppercased()
            .filter { alphabet.contains($0) }
    }

    private static func deviceID() -> String {
        let defaults = UserDefaults.standard
        if let storedID = defaults.string(forKey: deviceIDKey), !storedID.isEmpty {
            return storedID
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: deviceIDKey)
        return newID
    }

    private static func serverErrorMessage(from data: Data) -> String {
        if let error = try? JSONDecoder().decode(ActivationError.self, from: data) {
            switch error.detail {
            case "license_not_issued":
                return "This key was not found in the issued-license ledger."
            case let detail where detail.hasPrefix("device_limit_reached"):
                return "This license key has already been activated on its allowed device limit."
            default:
                return error.detail
            }
        }
        return "The license server rejected this activation."
    }

    private static func decodeBase32(_ value: String) -> [UInt8]? {
        var buffer = 0
        var bitsInBuffer = 0
        var output: [UInt8] = []

        for character in value {
            guard let index = alphabet.firstIndex(of: character) else {
                return nil
            }

            buffer = (buffer << 5) | index
            bitsInBuffer += 5

            while bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                output.append(UInt8((buffer >> bitsInBuffer) & 0xFF))
            }
        }

        return output
    }

    private static func encodeBase32(_ data: [UInt8]) -> String {
        var buffer = 0
        var bitsInBuffer = 0
        var output = ""

        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsInBuffer += 8

            while bitsInBuffer >= 5 {
                bitsInBuffer -= 5
                output.append(alphabet[(buffer >> bitsInBuffer) & 0b11111])
            }
        }

        if bitsInBuffer > 0 {
            output.append(alphabet[(buffer << (5 - bitsInBuffer)) & 0b11111])
        }

        return output
    }
}

private struct ActivationRequest: Encodable {
    let licenseKey: String
    let deviceID: String
    let deviceName: String
    let appVersion: String

    private enum CodingKeys: String, CodingKey {
        case licenseKey = "license_key"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
    }
}

private struct ActivationResponse: Decodable {
    let licenseID: String

    private enum CodingKeys: String, CodingKey {
        case licenseID = "license_id"
    }
}

private struct ActivationError: Decodable {
    let detail: String
}
