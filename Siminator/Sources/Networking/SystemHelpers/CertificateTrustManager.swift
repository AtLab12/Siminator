import Foundation
import Security

struct AuthorizedCertificateTrustConfigurator: Sendable {
    private enum Constants {
        nonisolated static let defaultCertificateLabel = "Siminator Root CA"
    }

    nonisolated func deleteCertificateFromKeychain(
        _ label: String = Constants.defaultCertificateLabel
    ) throws {
        let certificates = try certificates(matchingLabel: label)

        for cert in certificates {
            try removeTrustSettings(for: cert)
            try deleteCertificate(cert)
        }
    }

    private nonisolated func certificates(matchingLabel label: String) throws -> [SecCertificate] {
        let findQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
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

    private nonisolated func removeTrustSettings(for certificate: SecCertificate) throws {
        let trustStatus = SecTrustSettingsSetTrustSettings(certificate, .user, nil)

        guard trustStatus == errSecSuccess || trustStatus == errSecItemNotFound else {
            throw AuthorizedCertificateTrustError.failedToRevertTrustSettings
        }
    }

    private nonisolated func deleteCertificate(_ certificate: SecCertificate) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
        ]

        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)

        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw AuthorizedCertificateTrustError.failedToDeleteRootCert
        }
    }

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
                kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue,
            ],
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
