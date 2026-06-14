import Foundation
import Security

actor CertificateTrustManager {
    private let trustConfigurator = AuthorizedCertificateTrustConfigurator()

    func trustCertificate(atPath path: String) async throws {
        try await trustConfigurator.trustCertificate(atPath: path)
    }

    func removeTrustedCertificate(atPath path: String, commonName: String) async throws {
        try await trustConfigurator.removeTrustedCertificate(atPath: path, commonName: commonName)
    }
}

struct AuthorizedCertificateTrustConfigurator: Sendable {
    private enum Constants {
        nonisolated static let systemKeychainPath = "/Library/Keychains/System.keychain"
        nonisolated static let securityToolPath = "/usr/bin/security"
        nonisolated static let maximumDeletePasses = 16
    }

    nonisolated func trustCertificate(atPath path: String) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AuthorizedCertificateTrustError.certificateMissing
        }

        try await runPrivilegedShell([
            Constants.securityToolPath,
            "add-trusted-cert",
            "-d",
            "-r", "trustRoot",
            "-k", shellQuoted(Constants.systemKeychainPath),
            shellQuoted(path),
        ].joined(separator: " "), requiresWindow: true)
    }

    nonisolated func removeTrustedCertificate(atPath path: String, commonName: String) async throws {
        var commands: [String] = []

        if FileManager.default.fileExists(atPath: path) {
            commands.append([
                Constants.securityToolPath,
                "remove-trusted-cert",
                "-d",
                shellQuoted(path),
                ">/dev/null 2>&1 || true",
            ].joined(separator: " "))
        }

        commands.append(
            """
            i=0; while [ $i -lt \(Constants.maximumDeletePasses) ]; do \
            i=$((i + 1)); \
            \(Constants.securityToolPath) delete-certificate -c \(shellQuoted(commonName)) -t \(shellQuoted(Constants.systemKeychainPath)) >/dev/null 2>&1 || break; \
            done
            """
        )

        try await runPrivilegedShell(commands.joined(separator: "; "))
    }

    private func runPrivilegedShell(_ command: String, requiresWindow: Bool = false) throws {
        let appleScript = """
        do shell script \(appleScriptQuoted(command)) with administrator privileges
        """

        if requiresWindow {
            try runGUIScript(appleScript)
        } else {
            _ = try ExecutableHelper().runExecutable(
                "/usr/bin/osascript",
                arguments: ["-e", appleScript]
            )
        }
    }

    @MainActor
    private func runGUIScript(_ appleScript: String) throws {
        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/osascript",
            arguments: ["-e", appleScript]
        )
    }

    nonisolated private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    nonisolated private func appleScriptQuoted(_ value: String) -> String {
        let escapedBackslashes = value.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedQuotes = escapedBackslashes.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedQuotes)\""
    }
//
//    private func deleteCertificateFromKeyChain(_ certificateLabel: String) -> Bool {
//        let delQuery: [NSString: Any] = [
//            kSecClass: kSecClassCertificate,
//            kSecAttrLabel: certificateLabel,
//        ]
//        let delStatus: OSStatus = SecItemDelete(delQuery as CFDictionary)
//
//        return delStatus == errSecSuccess
//    }
//
    nonisolated func saveCertificateToKeyChain(certUrl: URL, certificateLabel: String = "Siminator") throws {
//        SecKeychainSetPreferenceDomain(SecPreferencesDomain.system)
//        deleteCertificateFromKeyChain(certificateLabel)

        let certData = try Data(contentsOf: certUrl)
        let certificate = SecCertificateCreateWithData(nil, certData as CFData)

        guard let certificate else {
            throw AuthorizedCertificateTrustError.certificateMissing
        }

        let setQuery: [NSString: AnyObject] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: certificateLabel as AnyObject,
        ]

        let addStatus: OSStatus = SecItemAdd(setQuery as CFDictionary, nil)

        guard addStatus == errSecSuccess && addStatus != errSecDuplicateItem else {
            throw AuthorizedCertificateTrustError.certificateMissing
        }

        let trustStatus = SecTrustSettingsSetTrustSettings(certificate, .admin, nil)

        guard trustStatus == errSecSuccess else {
            throw AuthorizedCertificateTrustError.failedToTrustCertificate
        }
    }
}

private enum AuthorizedCertificateTrustError: LocalizedError {
    case certificateMissing
    case failedToTrustCertificate

    var errorDescription: String? {
        switch self {
        case .certificateMissing:
            "The certificate file could not be found."
        case .failedToTrustCertificate:
            "Failed to trust the certificate"
        }
    }
}
