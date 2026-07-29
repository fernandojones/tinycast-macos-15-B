// Standalone regression test for both encrypted Raycast export formats.
// swiftc -swift-version 6 Tinycast/Core/Backup/{Gunzip,RaycastExportDecoder,Scrypt}.swift Tools/raycast-import-test.swift -o /tmp/raycast-import-test && /tmp/raycast-import-test

import Foundation

@main
@MainActor
struct RaycastImportTests {
    private static let password = "orange-blue-42"
    private static var failures = 0

    static func main() throws {
        try classicExportDecrypts()
        try classicDerivedIVExportDecrypts()
        try raycastXExportStillDecrypts()
        classicWrongPasswordFails()

        if CommandLine.arguments.count > 1 {
            try suppliedFileHasClassicEnvelope(URL(fileURLWithPath: CommandLine.arguments[1]))
        }

        print(failures == 0 ? "All Raycast import checks passed" : "\(failures) checks failed")
        if failures > 0 { exit(1) }
    }

    private static func classicExportDecrypts() throws {
        let decrypted = try RaycastExportDecoder.decrypt(classicEncrypted, passphrase: password)
        let json = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any]
        expect(json?["raycast_version"] as? String == "1.99.0", "classic export decrypts")
    }

    private static func raycastXExportStillDecrypts() throws {
        let decrypted = try RaycastExportDecoder.decrypt(raycastXEncrypted, passphrase: password)
        let json = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any]
        expect(json?["settings"] != nil, "Raycast X export still decrypts")
    }

    private static func classicDerivedIVExportDecrypts() throws {
        let decrypted = try RaycastExportDecoder.decrypt(classicDerivedIV, passphrase: password)
        let json = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any]
        expect(json?["raycast_version"] as? String == "1.99.0", "classic derived-IV export decrypts")
    }

    private static func classicWrongPasswordFails() {
        do {
            _ = try RaycastExportDecoder.decrypt(classicEncrypted, passphrase: "wrong")
            expect(false, "classic wrong password is rejected")
        } catch RaycastImportError.incorrectPassphrase {
            expect(true, "classic wrong password is rejected")
        } catch {
            expect(false, "classic wrong password reports the right error")
        }
    }

    private static func suppliedFileHasClassicEnvelope(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        expect(
            data.count > 16 && (data.count - 16).isMultiple(of: 16)
                && !data.starts(with: [0x1f, 0x8b]),
            "supplied export is recognized as classic encrypted Raycast data")
    }

    private static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS: \(label)")
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    private static var classicEncrypted: Data {
        decode(
            """
            AAECAwQFBgcICQoLDA0ODwn6XH6dI1j0GICCvCzAYUsMYEJbIpsucCoZ37msWE8Y0ejHD1HzNjQ2emWcvZe5vw2dVk2ow2i/gWwNKbZwphZlmiyyZiuGVFtm0SKo7jvSAoxbqpD8bU/KZXb2UiKaKmYQKYExbnXO8tdCk5o7bYX3skt/D/PrfHwbkIdOpA1RhNMC1k1e/wbn3gWmbmQT4Bys92kXyubPd4+Nn9ZXuH01lQ6IZGFMEZCB1j2ug06cOTR/XpZAIvkw/OF7slKxwPBwGFMVNcy1f4uZeceG/D5oM7mjUQJl/XN28aTG14xLLGej/ktFoXBalg7Fp3/o/DFLSFn/hmixVgCQfkTQu15KODbu/4EJCy0H7tHizYVvfMICtsWV84xa04wg57EF5Q==
            """)
    }

    private static var raycastXEncrypted: Data {
        decode(
            """
            H4sIAAAAAAAAE0VVzY6dNQx9l1mXkRPbsd1dX4BVxYKd4zgUiXaq6YBAiHfn3C5gd5XrxD4/Pt/fT/3n15fXtz4f3p7eP02a6weyH4g/kr3n+X7O55D189O7p/z69ad+/fbryxfU0fOyZ3omnL98+zE/N84+5qeX/n7wf91cz/o8vx9+eK1POMnXz0tw8K0+9ef8r3K+ezr5ligYccbKEjXM4peuLRokw1X8sC630kHVKpbpew2+JUWki9gq2lkil2zU5fKxp41y9TOpTmTe1OOc80yxO+5WtUNnRUWNJJ7qO+sM3Nma1rSzW1zMyKTzilGr+lysNURiaEfQPGyJ63rpUInHROO894ZeaRFdV4SGU00X74mLqCfg1BVsq4mqKn3NNa+SxNrLvDuS/di02pfLJNs8l8XxBGKQcmL4PnVBw2q8cPeRUQMPzmbVnm4gTcbuYMZUx+tQXFoVKjk3kCtlhG9xU4sZmEx0rrtjk9M+J3vZvDRuctTSezpT2VzYKfIevCUWEeh4K0hjzFYXacOpQrWc4osLqsbZVrxvgBqWuYhMH0yUAeDB27Q47IYz0R02hO8mTmPohJaoLZ0sNEePdo3dYLnq2Fk2oMCxahMIxqVyrSXXHsAcU9urHCfcLO4OSm1MHasvbTm9dG1Mw3lGbeh4qzHlcBRsiEg1lk4AAJYiEaij7rF3DhB+99TyU77OyO1axFfuLBAYYGvOi44N6yrTmbwYVoDYt3nWPQ9uJzyXe26KpnO9rOPk2XzjAs4wOJGyxwoKYLGDx/0kBtXLevoOFR2Qz0Y2FqI58UzgpwkdC4h0b3vAwpo6ahKg8cnJd+4GUxt9fClLwSXzjlhT7lFud5572zyYQo8tU1rn6IVvD/5dM4EfNlsBF5rCZAZuZRbf3MJcPrpNsWXFq7kD3fBkQtBW+KHXYc+UcyUdPgRirNpJy/ZkQeOGXRcGBb2xImSO7dglix6yBPsIBsgLIsRNXL48L7al1s1DLdi/uA7DAlSvPv4wNjSmxgQ+wkfBmwzzyUIsUMyhS7D2uhiirRmFh6O6N6SFyJEn1yqFfRIqermQwfMyFIZ4WEMl+GD/gQn7EqCdOZ0BtTYCiQldz5hzYPdwBaAIWgnxQCYQQq0ZjparG0sVdbsYPR6gqxOLS9v4wDxevXIdQ1QdMBcMzx60gzYF/ULSNkKq4SDOCoHBJePCHYbNxruKRFrLTxjsMEmRtHHV2h82Ni2ADTngC0Y/yIQzEUQXKRPSj3hEUCCbdI+zxtpQ0GD8xNrCY4DMSzA0xTZBfyR+f6nXv76+fY/7v59+/QNZL4gKQp5DK+YNcof5hL2czm7E8+M7kb89Pky1HdFBF56bexCMCWBq2AOocr5X5u9vnz7mL49PCD4T8DzyUbBGPdJbDZuHcLclYz7988+/pU1xpvgGAAA=
            """)
    }

    private static var classicDerivedIV: Data {
        decode(
            """
            AAECAwQFBgcICQoLDA0OD6RhoXbsTCaf951SPMXcH0P1P+iAFS+NuQU5U0yTvGE+HLLZRolI6774NN2C5/rh8uivsgPLJp2OMQW7x9tU5BNSukLVhDVFhM2qKK6USygl+360+gf5dylIENyRKAHXht+D+ET7f9UVHvi2O+uECnSVxiyvj0UXHX/KhrtoA4towH+sNOCNJnVPDfV0F4PJpUgtE83DAOkZqSKjtkmW9unv2HwGIvtjbKaa5jz/5zSeuWNEjPOFUyh47tdywrrDL2U2Is1Z55t/lsVMyhqx9G2bIOCDIfeO0vvsvZNXSW/5DvhevpdnTOTPTAkHcQUMq3+nyGwumcmDCv4mGtSe8MQmL2FIv6LSvvKlFdvTa1Ak3GSRRBbXl6fVazhqYZjMOw==
            """)
    }

    private static func decode(_ base64: String) -> Data {
        Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
    }
}
