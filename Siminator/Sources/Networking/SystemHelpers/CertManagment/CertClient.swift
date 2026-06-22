//
//  CertClient.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 21/06/2026.
//

import Foundation
import Dependencies

struct CertClient: Sendable{
    var deleteAllCertificates: @Sendable () async throws -> Void
    var resetCertificates: @Sendable () async throws -> Void
}

extension CertClient: DependencyKey {
    static var liveValue: Self {
        let certificateManager: CertificateMangement = CertificateMaterialManager()
        return Self {
            try await certificateManager.deleteCertificateMaterial()
        } resetCertificates: {
            // Delete all certificates
            // Generate new once
        }
    }
}

extension DependencyValues {
    var certClient: CertClient {
        get { self[CertClient.self] }
        set { self[CertClient.self] = newValue }
    }
}
