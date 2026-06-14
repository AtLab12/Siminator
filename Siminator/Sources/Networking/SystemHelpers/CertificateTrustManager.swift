import Foundation
import Security

struct AuthorizedCertificateTrustConfigurator: Sendable {
    private enum Constants {
        nonisolated static let systemKeychainPath = "/Library/Keychains/System.keychain"
        nonisolated static let securityToolPath = "/usr/bin/security"
        nonisolated static let maximumDeletePasses = 16
        nonisolated static let defaultCertificateLabel = "Siminator Root CA"
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

    // MARK: - Revert trust and delete certificate
    nonisolated func deleteCertificateFromKeychain(
        _ label: String = Constants.defaultCertificateLabel
    ) throws {
        let certificates = try certificates(matchingLabel: label)
        
        for cert in certificates {
            try removeTrustSettings(for: cert)
            try deleteCertificate(cert)
        }
                
    }

    nonisolated private func certificates(matchingLabel label: String) throws -> [SecCertificate] {
        let findQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let findStatus = SecItemCopyMatching(findQuery as CFDictionary, &result)

        guard findStatus == errSecSuccess || findStatus == errSecItemNotFound else {
            throw AuthorizedCertificateTrustError.failedToDeleteRootCert
        }

        guard findStatus != errSecItemNotFound else {
            return []
        }

        if let array = result as? [SecCertificate] {
            return array
        } else if let result,
                  CFGetTypeID(result) == SecCertificateGetTypeID()
        {
            return [result as! SecCertificate]
        } else {
            throw AuthorizedCertificateTrustError.failedToDeleteRootCert
        }
    }

    nonisolated private func allCertificates() throws -> [SecCertificate] {
        let findQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let findStatus = SecItemCopyMatching(findQuery as CFDictionary, &result)

        guard findStatus == errSecSuccess || findStatus == errSecItemNotFound else {
            throw AuthorizedCertificateTrustError.failedToDeleteRootCert
        }

        guard findStatus != errSecItemNotFound else {
            return []
        }

        if let array = result as? [SecCertificate] {
            return array
        } else if let result,
                  CFGetTypeID(result) == SecCertificateGetTypeID()
        {
            return [result as! SecCertificate]
        } else {
            throw AuthorizedCertificateTrustError.failedToDeleteRootCert
        }
    }

    nonisolated private func removeTrustSettings(for certificate: SecCertificate) throws {
        let trustStatus = SecTrustSettingsSetTrustSettings(certificate, .user, nil)

        guard trustStatus == errSecSuccess || trustStatus == errSecItemNotFound else {
            throw AuthorizedCertificateTrustError.failedToRevertTrustSettings
        }
    }

    nonisolated private func deleteCertificate(_ certificate: SecCertificate) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate
        ]

        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)

        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw AuthorizedCertificateTrustError.failedToDeleteRootCert
        }
    }

    nonisolated private func deleteCertificates(matchingLabel label: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
        ]

        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)

        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw AuthorizedCertificateTrustError.failedToDeleteRootCert
        }
    }

    nonisolated private func uniqueLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.filter { label in
            seen.insert(label).inserted
        }
    }

    nonisolated private func uniqueCertificates(_ certificates: [SecCertificate]) -> [SecCertificate] {
        var seenData = Set<Data>()
        var uniqueCertificates: [SecCertificate] = []

        for certificate in certificates {
            let data = SecCertificateCopyData(certificate) as Data
            guard seenData.insert(data).inserted else {
                continue
            }
            uniqueCertificates.append(certificate)
        }

        return uniqueCertificates
    }

    // MARK: - Save and trust certificate
    nonisolated func saveCertificateToKeyChain(
        certUrl: URL,
        certificateLabel: String = Constants.defaultCertificateLabel
    ) throws {
        try? deleteCertificateFromKeychain(certificateLabel)

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

        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw AuthorizedCertificateTrustError.certificateMissing
        }

        let trustSettings: [[String: Any]] = [
            [
                kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue
            ]
        ]

        let trustStatus = SecTrustSettingsSetTrustSettings(
            certificate,
            .user,
            trustSettings as CFTypeRef
        )
        guard trustStatus == errSecSuccess else {
            throw AuthorizedCertificateTrustError.failedToTrustCertificate
        }
    }
}

private enum AuthorizedCertificateTrustError: LocalizedError {
    case certificateMissing
    case failedToTrustCertificate
    case failedToDeleteRootCert
    case failedToRevertTrustSettings

    var errorDescription: String? {
        switch self {
        case .certificateMissing:
            "The certificate file could not be found."
        case .failedToTrustCertificate:
            "Failed to trust the certificate"
        case .failedToDeleteRootCert:
            "Failed to delete root cert"
        case .failedToRevertTrustSettings:
            "Failed to revert trust settings"
        }
    }
}
