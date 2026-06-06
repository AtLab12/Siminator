//
//  ExecutableHelper.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 06/06/2026.
//

import Foundation

struct ExecutableHelper {
    
    nonisolated func runExecutable(_ executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw SystemProxySettingsError.commandFailed(
                executable: URL(fileURLWithPath: executablePath).lastPathComponent,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
    }
    
    enum SystemProxySettingsError: LocalizedError {
        case commandFailed(executable: String, output: String)

        var errorDescription: String? {
            switch self {
            case let .commandFailed(executable, output):
                if output.isEmpty {
                    "\(executable) failed without output."
                } else {
                    "\(executable) failed: \(output)"
                }
            }
        }
    }
}
