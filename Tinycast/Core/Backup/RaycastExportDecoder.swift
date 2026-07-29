import CommonCrypto
import CryptoKit
import Foundation

enum RaycastImportError: LocalizedError {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notRaycastFile: return "This doesn't look like a Raycast export (.rayconfig)."
        case .incorrectPassphrase: return "Incorrect passphrase, or the file is corrupted."
        case .corrupt: return "The Raycast export could not be read."
        }
    }
}

/// Decrypts both Raycast X exports and classic macOS exports into their settings JSON.
enum RaycastExportDecoder {
    static func decrypt(_ raw: Data, passphrase: String) throws -> Data {
        if let envelopeData = try? Gunzip.decompress(raw) {
            return try decryptEnvelope(envelopeData, passphrase: passphrase)
        }
        return try decryptClassic(raw, passphrase: passphrase)
    }

    private static func decryptEnvelope(_ envelopeData: Data, passphrase: String) throws -> Data {
        guard let env = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
            let dataHex = env["data"] as? String,
            let enc = env["encryption"] as? [String: String],
            let iv = enc["iv"].flatMap(Data.init(hex:)),
            let salt = enc["salt"].flatMap(Data.init(hex:)),
            let tag = enc["authTag"].flatMap(Data.init(hex:)),
            let ciphertext = Data(hex: dataHex)
        else { throw RaycastImportError.notRaycastFile }

        let key = Scrypt.derive(
            passphrase: Array(passphrase.utf8), salt: [UInt8](salt), n: 16384, r: 8, p: 1,
            dkLen: 32)

        let plaintextGz: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
            plaintextGz = try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw RaycastImportError.incorrectPassphrase
        }
        guard let plaintext = try? Gunzip.decompress(plaintextGz) else {
            throw RaycastImportError.corrupt
        }
        return plaintext
    }

    /// Classic Raycast stores a 16-byte header followed by AES-256-CBC ciphertext keyed by SHA-256(password).
    private static func decryptClassic(_ raw: Data, passphrase: String) throws -> Data {
        let blockSize = kCCBlockSizeAES128
        guard raw.count > blockSize, (raw.count - blockSize).isMultiple(of: blockSize) else {
            throw RaycastImportError.notRaycastFile
        }

        let ciphertext = raw.dropFirst(blockSize)
        let password = Data(passphrase.utf8)
        let key = Data(SHA256.hash(data: password))
        let derivedIV = Data(SHA256.hash(data: key + password)).prefix(blockSize)
        // Raycast releases have treated the leading block as either the IV or an ignored header.
        for iv in [raw.prefix(blockSize), derivedIV] {
            guard let plaintext = decryptCBC(ciphertext, key: key, iv: iv),
                plaintext.starts(with: [0x1f, 0x8b])
            else { continue }
            guard let json = try? Gunzip.decompress(plaintext),
                (try? JSONSerialization.jsonObject(with: json)) != nil
            else { throw RaycastImportError.corrupt }
            return json
        }
        throw RaycastImportError.incorrectPassphrase
    }

    private static func decryptCBC(_ ciphertext: Data.SubSequence, key: Data, iv: Data.SubSequence)
        -> Data?
    {
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var plaintextLength = 0
        let status = plaintext.withUnsafeMutableBytes { output in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    ciphertext.withUnsafeBytes { cipherBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress, cipherBytes.baseAddress, ciphertext.count,
                            output.baseAddress, output.count, &plaintextLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        plaintext.count = plaintextLength
        return plaintext
    }
}

extension Data {
    /// Parses an even-length hex string; returns nil on any non-hex character.
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x61...0x66: return c - 0x61 + 10
            case 0x41...0x46: return c - 0x41 + 10
            default: return nil
            }
        }
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            bytes.append(hi << 4 | lo)
            i += 2
        }
        self = Data(bytes)
    }
}
