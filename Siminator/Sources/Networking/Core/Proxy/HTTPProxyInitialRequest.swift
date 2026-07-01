//
//  HTTPProxyInitialRequest.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 09/06/2026.
//

import Foundation
import NIOCore

nonisolated struct HTTPProxyInitialRequest: Sendable {
    let method: String
    let host: String
    let port: Int
    let isConnect: Bool
    let displayPath: String

    private let headerText: String
    private let bodyBytes: [UInt8]

    var forwardedByteCount: Int {
        headerText.utf8.count + bodyBytes.count
    }

    init?(buffer: ByteBuffer) {
        guard let requestBytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes),
              let headerEnd = requestBytes.firstRange(of: [13, 10, 13, 10])
        else {
            return nil
        }

        let headerBytes = Array(requestBytes[..<headerEnd.upperBound])
        let remainingBytes = Array(requestBytes[headerEnd.upperBound...])

        guard let headerText = String(bytes: headerBytes, encoding: .utf8) else {
            return nil
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let firstLine = headerLines.first else {
            return nil
        }

        let requestLineParts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard requestLineParts.count == 3 else {
            return nil
        }

        let method = String(requestLineParts[0])
        let uri = String(requestLineParts[1])
        let isConnect = method.uppercased() == "CONNECT"

        if isConnect {
            guard let destination = HTTPProxyDestination(connectURI: uri) else {
                return nil
            }

            self.method = method
            host = destination.host
            port = destination.port
            self.isConnect = true
            displayPath = uri
            self.headerText = headerText
            bodyBytes = remainingBytes
            return
        }

        guard let destination = HTTPProxyDestination(requestURI: uri, headerLines: headerLines) else {
            return nil
        }

        self.method = method
        host = destination.host
        port = destination.port
        self.isConnect = false
        displayPath = destination.path
        self.headerText = HTTPProxyInitialRequest.rewrittenHeaderText(
            originalHeaderText: headerText,
            originalFirstLine: firstLine,
            method: method,
            path: destination.path,
            version: String(requestLineParts[2])
        )
        bodyBytes = remainingBytes
    }

    func forwardedBuffer(allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: headerText.utf8.count + bodyBytes.count)
        buffer.writeString(headerText)
        buffer.writeBytes(bodyBytes)
        return buffer
    }

    func tunneledBodyBuffer(allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: bodyBytes.count)
        buffer.writeBytes(bodyBytes)
        return buffer
    }

    private static func rewrittenHeaderText(
        originalHeaderText: String,
        originalFirstLine: String,
        method: String,
        path: String,
        version: String
    ) -> String {
        let rewrittenFirstLine = "\(method) \(path) \(version)"

        guard let firstLineRange = originalHeaderText.range(of: originalFirstLine) else {
            return originalHeaderText
        }

        return originalHeaderText.replacingCharacters(in: firstLineRange, with: rewrittenFirstLine)
    }
}
