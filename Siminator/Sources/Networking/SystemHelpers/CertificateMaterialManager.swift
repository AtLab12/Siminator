import Foundation

actor CertificateMaterialManager {
    private enum Constants {
        static let certificateCommonName = "Siminator Root CA"
        static let certificateFilename = "siminator-root-ca.pem"
        static let privateKeyFilename = "siminator-root-ca-key.pem"
    }

    func certificateState() throws -> CertificateMaterialState {
        let material = try certificateMaterialURLs()
        let certificateURL = material.certificateURL
        let privateKeyURL = material.privateKeyURL
        let hasCertificate = FileManager.default.fileExists(atPath: certificateURL.path)
        let hasPrivateKey = FileManager.default.fileExists(atPath: privateKeyURL.path)
        let isGenerated = hasCertificate && hasPrivateKey

        return CertificateMaterialState(
            certificateURL: isGenerated ? certificateURL : nil,
            privateKeyURL: isGenerated ? privateKeyURL : nil,
            isGenerated: isGenerated
        )
    }

    func ensureCertificateMaterialExists() throws -> CertificateMaterial {
        let material = try certificateMaterialURLs()
        let certificateURL = material.certificateURL
        let privateKeyURL = material.privateKeyURL

        if FileManager.default.fileExists(atPath: certificateURL.path),
           FileManager.default.fileExists(atPath: privateKeyURL.path)
        {
            return material
        }

        try? FileManager.default.removeItem(at: certificateURL)
        try? FileManager.default.removeItem(at: privateKeyURL)

        do {
            try generateRootCA(certificateURL: certificateURL, privateKeyURL: privateKeyURL)
        } catch {
            try? FileManager.default.removeItem(at: certificateURL)
            try? FileManager.default.removeItem(at: privateKeyURL)
            throw error
        }

        return material
    }

    func deleteCertificateMaterial() throws {
        let material = try certificateMaterialURLs()

        try? FileManager.default.removeItem(at: material.certificateURL)
        try? FileManager.default.removeItem(at: material.privateKeyURL)
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
                "3072",
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
                "-addext", "subjectKeyIdentifier=hash",
            ]
        )
    }

    private func certificateDirectoryURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CertificateMaterialError.applicationSupportUnavailable
        }

        let directoryURL = applicationSupportURL
            .appendingPathComponent("Siminator", isDirectory: true)
            .appendingPathComponent("Certificates", isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL
    }

    private func certificateMaterialURLs() throws -> CertificateMaterial {
        let directoryURL = try certificateDirectoryURL()

        return CertificateMaterial(
            certificateURL: directoryURL.appendingPathComponent(Constants.certificateFilename),
            privateKeyURL: directoryURL.appendingPathComponent(Constants.privateKeyFilename)
        )
    }
}

struct CertificateMaterial: Sendable {
    let certificateURL: URL
    let privateKeyURL: URL
}

struct CertificateMaterialState: Sendable {
    let certificateURL: URL?
    let privateKeyURL: URL?
    let isGenerated: Bool
}

enum CertificateMaterialError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Could not locate the Application Support directory."
        }
    }
}
