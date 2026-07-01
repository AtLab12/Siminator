import Foundation
import NIOSSL

protocol CertificateMangement: Actor {
    func deleteCertificateMaterial () throws -> Void
}

actor CertificateMaterialManager: CertificateMangement {
    private enum Constants {
        static let certificateCommonName = "Siminator Root CA"
        static let certificateFilename = "siminator-root-ca.cer"
        static let privateKeyFilename = "siminator-root-ca-key.pem"
        static let hostsDirectoryName = "Hosts"
    }

    private var serverTLSContexts: [String: NIOSSLContext] = [:]
    private var trustManager: AuthorizedCertificateTrustConfigurator = .init()

    func certificateState() throws -> CertificateMaterialState {
        let material = try certificateMaterialURLs()
        let certificateURL = material.certificateURL
        let privateKeyURL = material.privateKeyURL
        let hasCertificate = FileManager.default.fileExists(atPath: certificateURL.path)
        let hasPrivateKey = FileManager.default.fileExists(atPath: privateKeyURL.path)
        let isGenerated = hasCertificate && hasPrivateKey

        return CertificateMaterialState(
            certificateURL: isGenerated ? certificateURL : nil,
            isGenerated: isGenerated
        )
    }

    func ensureCertificateMaterialExists() async throws -> CertificateMaterial {
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
            try trustManager.saveCertificateToKeyChain(certUrl: certificateURL)
        } catch {
            try? FileManager.default.removeItem(at: certificateURL)
            try? FileManager.default.removeItem(at: privateKeyURL)
            throw error
        }

        return material
    }

    func deleteCertificateMaterial() throws {
        try trustManager.deleteCertificateFromKeychain(Constants.certificateCommonName)

        // Delete from file storage, both leaf and root cert.
        let directoryURL = try certificateDirectoryURL()
        let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)

        for itemURL in contents {
            try? FileManager.default.removeItem(at: itemURL)
        }

        serverTLSContexts.removeAll(keepingCapacity: true)
    }

    func serverTLSContext(for host: String) async throws -> NIOSSLContext {
        let normalizedHost = host.lowercased()

        if let context = serverTLSContexts[normalizedHost] {
            return context
        }

        let leafMaterial = try await ensureLeafCertificateExists(for: normalizedHost)
        let certificateChain = try NIOSSLCertificate.fromPEMFile(leafMaterial.certificateURL.path)
        let privateKey = try NIOSSLPrivateKey(file: leafMaterial.privateKeyURL.path, format: .pem)

        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: certificateChain.map { .certificate($0) },
            privateKey: .privateKey(privateKey)
        )
        configuration.applicationProtocols = ["http/1.1"]

        let context = try NIOSSLContext(configuration: configuration)
        serverTLSContexts[normalizedHost] = context
        return context
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
                "-outform", "DER",
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

    private func ensureLeafCertificateExists(for host: String) async throws -> CertificateMaterial {
        let rootMaterial = try await ensureCertificateMaterialExists()
        let leafMaterial = try leafCertificateMaterialURLs(for: host)
        let certificateURL = leafMaterial.certificateURL
        let privateKeyURL = leafMaterial.privateKeyURL

        if FileManager.default.fileExists(atPath: certificateURL.path),
           FileManager.default.fileExists(atPath: privateKeyURL.path)
        {
            return leafMaterial
        }

        try? FileManager.default.removeItem(at: certificateURL)
        try? FileManager.default.removeItem(at: privateKeyURL)

        do {
            try generateLeafCertificate(
                host: host,
                rootMaterial: rootMaterial,
                certificateURL: certificateURL,
                privateKeyURL: privateKeyURL
            )
        } catch {
            try? FileManager.default.removeItem(at: certificateURL)
            try? FileManager.default.removeItem(at: privateKeyURL)
            throw error
        }

        return leafMaterial
    }

    private func generateLeafCertificate(
        host: String,
        rootMaterial: CertificateMaterial,
        certificateURL: URL,
        privateKeyURL: URL
    ) throws {
        let workingDirectoryURL = certificateURL.deletingLastPathComponent()
        let csrURL = workingDirectoryURL.appendingPathComponent("\(certificateURL.deletingPathExtension().lastPathComponent).csr")
        let extensionURL = workingDirectoryURL.appendingPathComponent("\(certificateURL.deletingPathExtension().lastPathComponent).ext")

        defer {
            try? FileManager.default.removeItem(at: csrURL)
            try? FileManager.default.removeItem(at: extensionURL)
        }

        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/openssl",
            arguments: [
                "genrsa",
                "-out", privateKeyURL.path,
                "2048",
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
                "-new",
                "-key", privateKeyURL.path,
                "-out", csrURL.path,
                "-subj", "/CN=\(host)/O=Siminator/OU=HTTPS Inspection",
            ]
        )

        try leafExtensionText(for: host).write(
            to: extensionURL,
            atomically: true,
            encoding: .utf8
        )

        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/openssl",
            arguments: [
                "x509",
                "-req",
                "-in", csrURL.path,
                "-CA", rootMaterial.certificateURL.path,
                "-CAform", "DER",
                "-CAkey", rootMaterial.privateKeyURL.path,
                "-CAcreateserial",
                "-out", certificateURL.path,
                "-days", "825",
                "-sha256",
                "-extfile", extensionURL.path,
            ]
        )
    }

    private func leafCertificateMaterialURLs(for host: String) throws -> CertificateMaterial {
        let directoryURL = try certificateDirectoryURL()
            .appendingPathComponent(Constants.hostsDirectoryName, isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let filename = sanitizedCertificateFilenameComponent(for: host)

        return CertificateMaterial(
            certificateURL: directoryURL.appendingPathComponent("\(filename).pem"),
            privateKeyURL: directoryURL.appendingPathComponent("\(filename)-key.pem")
        )
    }

    private func leafExtensionText(for host: String) -> String {
        let subjectAlternativeName = isIPAddress(host) ? "IP:\(host)" : "DNS:\(host)"

        return """
        basicConstraints=critical,CA:FALSE
        keyUsage=critical,digitalSignature,keyEncipherment
        extendedKeyUsage=serverAuth
        subjectAltName=\(subjectAlternativeName)

        """
    }

    private func sanitizedCertificateFilenameComponent(for host: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = host.unicodeScalars.map { scalar -> String in
            allowedCharacters.contains(scalar) ? String(scalar) : "_"
        }
        let sanitized = scalars.joined()
        return sanitized.isEmpty ? "unknown-host" : sanitized
    }

    private func isIPAddress(_ host: String) -> Bool {
        host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
            || host.contains(":")
    }

    func installRootCertToBootedSimulator() async throws {
        let certificateMaterial = try await ensureCertificateMaterialExists()

        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/xcrun",
            arguments: [
                "simctl",
                "keychain",
                "booted",
                "add-root-cert",
                certificateMaterial.certificateURL.path,
            ]
        )
    }

    func rebootBootedSimulators() throws {
        let bootedSimulators = try getBootedSimulators()

        guard !bootedSimulators.isEmpty else {
            throw CertificateMaterialError.noBootedSimulators
        }

        for simulator in bootedSimulators {
            _ = try ExecutableHelper().runExecutable(
                "/usr/bin/xcrun",
                arguments: [
                    "simctl",
                    "shutdown",
                    simulator.udid,
                ]
            )

            _ = try ExecutableHelper().runExecutable(
                "/usr/bin/xcrun",
                arguments: [
                    "simctl",
                    "boot",
                    simulator.udid,
                ]
            )
        }
    }
    
    func getBootedSimulators() throws -> [SimctlDevice] {
        let output = try ExecutableHelper().runExecutable(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "booted", "--json"]
        )

        guard let data = output.data(using: .utf8) else {
            throw CertificateMaterialError.invalidSimulatorList
        }

        let deviceList = try JSONDecoder().decode(SimctlDeviceList.self, from: data)
        
        return deviceList.bootedDevices
    }
}

struct CertificateMaterial: Sendable {
    let certificateURL: URL
    let privateKeyURL: URL
}

struct CertificateMaterialState: Sendable {
    let certificateURL: URL?
    let isGenerated: Bool
}

enum CertificateMaterialError: LocalizedError {
    case applicationSupportUnavailable
    case invalidSimulatorList
    case noBootedSimulators

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Could not locate the Application Support directory."
        case .invalidSimulatorList:
            "Could not read the booted simulator list."
        case .noBootedSimulators:
            "No booted simulators were found."
        }
    }
}
