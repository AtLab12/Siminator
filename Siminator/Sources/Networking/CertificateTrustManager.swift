import Foundation

actor CertificateTrustManager {
    private enum Constants {
        static let certificateCommonName = "Siminator Root CA"
        static let privateKeyLabel = "Siminator Root CA Private Key"
        static let certificateFilename = "siminator-root-ca.pem"
        static let privateKeyFilename = "siminator-root-ca-key.pem"
        static let trustedMarkerFilename = "siminator-root-ca.trusted"
    }

    func trustState() throws -> CertificateTrustState {
        let directoryURL = try certificateDirectoryURL()
        let certificateURL = directoryURL.appendingPathComponent(Constants.certificateFilename)
        let privateKeyURL = directoryURL.appendingPathComponent(Constants.privateKeyFilename)
        let trustedMarkerURL = directoryURL.appendingPathComponent(Constants.trustedMarkerFilename)

        let hasCertificate = FileManager.default.fileExists(atPath: certificateURL.path)
        let hasUserTrustedMarker = FileManager.default.fileExists(atPath: trustedMarkerURL.path)
        let isTrusted = hasCertificate
            && (hasUserTrustedMarker || isCertificatePresentInLoginKeychain(certificateURL))

        try removePrivateKeyFileIfPresent(at: privateKeyURL)

        return CertificateTrustState(
            certificateURL: hasCertificate ? certificateURL : nil,
            isTrusted: isTrusted
        )
    }

    func installTrustedRootCertificate() throws -> URL {
        let certificateURL = try ensureRootCertificateExists()
        let keychainPath = loginKeychainPath

        if isCertificatePresentInLoginKeychain(certificateURL) {
            try writeTrustedMarker()
            return certificateURL
        }

        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/security",
            arguments: [
                "add-trusted-cert",
                "-r", "trustRoot",
                "-p", "ssl",
                "-p", "basic",
                "-k", keychainPath,
                certificateURL.path
            ]
        )

        try writeTrustedMarker()

        return certificateURL
    }

    func ensureRootCertificateExists() throws -> URL {
        let directoryURL = try certificateDirectoryURL()
        let certificateURL = directoryURL.appendingPathComponent(Constants.certificateFilename)
        let privateKeyURL = directoryURL.appendingPathComponent(Constants.privateKeyFilename)

        if FileManager.default.fileExists(atPath: certificateURL.path) {
            try removePrivateKeyFileIfPresent(at: privateKeyURL)
            return certificateURL
        }

        try? FileManager.default.removeItem(at: certificateURL)
        try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(Constants.trustedMarkerFilename))
        
        defer {
            // Extra cleanup step to be sure
            try? removePrivateKeyFileIfPresent(at: privateKeyURL)
        }

        try generateRootCA(certificateURL: certificateURL, privateKeyURL: privateKeyURL)
        try importPrivateKeyIntoKeychain(privateKeyURL: privateKeyURL)
        try removePrivateKeyFileIfPresent(at: privateKeyURL)

        return certificateURL
    }

    private func generateRootCA(
        certificateURL: URL,
        privateKeyURL: URL
    ) throws {
        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/openssl",
            arguments: [
                "genrsa",
                "-out", privateKeyURL.path,
                "3072"
            ]
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: privateKeyURL.path
        )

        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/openssl",
            arguments: [
                "req",
                "-x509",
                "-new",
                "-key", privateKeyURL.path,
                "-sha256",
                "-days", "3650",
                "-out", certificateURL.path,
                "-subj", "/CN=\(Constants.certificateCommonName)/O=Siminator/OU=HTTPS Inspection",
                "-addext", "basicConstraints=critical,CA:TRUE",
                "-addext", "keyUsage=critical,keyCertSign",
                "-addext", "subjectKeyIdentifier=hash"
            ]
        )
    }

    private func importPrivateKeyIntoKeychain(privateKeyURL: URL) throws {
        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/security",
            arguments: [
                "import",
                privateKeyURL.path,
                "-k", loginKeychainPath,
                "-t", "priv",
                "-f", "openssl",
                "-x",
                "-a", "label", Constants.privateKeyLabel
            ]
        )
    }

    private func writeTrustedMarker() throws {
        let trustedMarkerURL = try certificateDirectoryURL()
            .appendingPathComponent(Constants.trustedMarkerFilename)

        try "trusted\n".write(
            to: trustedMarkerURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private func isCertificatePresentInLoginKeychain(_ certificateURL: URL) -> Bool {
        guard let fingerprint = try? certificateFingerprint(certificateURL) else {
            return false
        }

        guard let output = try? ExecutableHelper().runExecutable(
            "/usr/bin/security",
            arguments: [
                "find-certificate",
                "-a",
                "-Z",
                loginKeychainPath
            ]
        ) else {
            return false
        }

        return normalizedFingerprint(output).contains(fingerprint)
    }

    private func certificateFingerprint(_ certificateURL: URL) throws -> String {
        let output = try ExecutableHelper().runExecutable(
            "/usr/bin/openssl",
            arguments: [
                "x509",
                "-in", certificateURL.path,
                "-noout",
                "-fingerprint",
                "-sha256"
            ]
        )

        guard let fingerprint = output
            .split(separator: "\n")
            .first(where: { $0.contains("Fingerprint=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init) else {
            return ""
        }

        return normalizedFingerprint(fingerprint)
    }

    private func normalizedFingerprint(_ value: String) -> String {
        value
            .uppercased()
            .filter { $0.isHexDigit }
    }

    private var loginKeychainPath: String {
        "\(NSHomeDirectory())/Library/Keychains/login.keychain-db"
    }

    private func certificateDirectoryURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CertificateTrustError.applicationSupportUnavailable
        }

        let directoryURL = applicationSupportURL
            .appendingPathComponent("Siminator", isDirectory: true)
            .appendingPathComponent("Certificates", isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL
    }

    private func removePrivateKeyFileIfPresent(at privateKeyURL: URL) throws {
        if FileManager.default.fileExists(atPath: privateKeyURL.path) {
            try FileManager.default.removeItem(at: privateKeyURL)
        }
    }
}

struct CertificateTrustState: Sendable {
    let certificateURL: URL?
    let isTrusted: Bool
}

enum CertificateTrustError: LocalizedError {
    case applicationSupportUnavailable
    case commandFailed(executable: String, output: String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Could not locate the Application Support directory."
        case let .commandFailed(executable, output):
            if output.isEmpty {
                "\(executable) failed without output."
            } else {
                "\(executable) failed: \(output)"
            }
        }
    }
}
