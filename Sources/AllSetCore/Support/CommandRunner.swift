import Darwin
import Foundation

/// Runs a command and says why it failed (nil when it succeeded). A timeout is an
/// upper bound: on expiry the command is asked to stop (SIGTERM), then killed
/// (SIGKILL) a second later, and the result says if even that didn't stop it.
/// Error output is drained as it comes, capped, and never waited on past a short
/// grace (a background child can keep the pipe open long after the command
/// ended). Cancelling the calling task stops the command too.
public enum CommandRunner {
    /// Error output kept for the message; the rest is read and dropped.
    public static let outputLimit = 64 * 1024
    static let killGrace: TimeInterval = 1
    static let drainGrace: TimeInterval = 0.5

    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval?) async -> String? {
        let handle = RunningProcess()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: runAndWait(path, arguments, timeout: timeout, handle: handle))
                }
            }
        } onCancel: {
            handle.stop()
        }
    }

    private static func runAndWait(_ path: String, _ arguments: [String], timeout: TimeInterval?, handle: RunningProcess) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        // Set before launching: a quick command could finish before a
        // handler set afterwards, and its end would never be seen.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return "Couldn't start \(name): \(error.localizedDescription)"
        }
        handle.set(process)
        // Drained as it runs: a command that fills the pipe would otherwise stall.
        let output = ErrorOutput()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let reader = errors.fileHandleForReading
            while case let chunk = reader.availableData, !chunk.isEmpty { output.append(chunk) }
            drained.signal()
        }
        if let timeout, exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                if exited.wait(timeout: .now() + killGrace) == .timedOut {
                    return "\(name) took too long and couldn't be stopped"
                }
            }
            return "\(name) took too long and was stopped"
        } else if timeout == nil {
            exited.wait()
        }
        // A child left running in the background may hold the pipe open: don't wait for it.
        _ = drained.wait(timeout: .now() + drainGrace)
        if handle.wasCancelled { return "\(name) was cancelled" }
        guard process.terminationStatus != 0 else { return nil }
        let message = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "\(name) failed (\(process.terminationStatus))" : message
    }

    /// The process, for cancellation from another thread.
    private final class RunningProcess: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func set(_ process: Process) {
            let stopNow = lock.withLock { () -> Bool in
                self.process = process
                return cancelled
            }
            if stopNow { process.terminate() }
        }

        func stop() {
            let running = lock.withLock { () -> Process? in
                cancelled = true
                return process
            }
            running?.terminate()
        }

        var wasCancelled: Bool { lock.withLock { cancelled } }
    }

    private final class ErrorOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Data()

        func append(_ chunk: Data) {
            lock.withLock {
                let room = CommandRunner.outputLimit - stored.count
                if room > 0 { stored.append(chunk.prefix(room)) }
            }
        }

        var data: Data { lock.withLock { stored } }
    }
}
