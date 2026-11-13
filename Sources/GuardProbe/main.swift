import Foundation
import Network
import Darwin
import GuardCore

let usage = """
guard-probe [--host NUMERIC_IP] [--port 54321] [--transport tcp|udp]
            [--duration 10] [--interval 0.25] [--require-echo]
Defaults to loopback. Emits JSONL. A send callback is NOT proof of delivery.
Only an exact echoed probe frame counts as received. No echo is NOT proof of blocking.
"""

if CommandLine.arguments.contains("--help") {
    print(usage)
    exit(0)
}

final class Probe {
    private let options: ProbeOptions
    private let queue = DispatchQueue(label: "org.vpnguard.probe")
    private let connection: NWConnection
    private let runID = UUID().uuidString
    private var timer: DispatchSourceTimer?
    private var sequence = 0
    private var received = 0
    private var outstanding: Set<String> = []
    private var buffer = Data()
    private var started = false
    private var finished = false

    init(options: ProbeOptions) {
        self.options = options
        let parameters: NWParameters = options.transport == "tcp" ? .tcp : .udp
        connection = NWConnection(host: NWEndpoint.Host(options.host),
                                  port: NWEndpoint.Port(rawValue: options.port)!, using: parameters)
    }

    private func emit(_ event: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["event"] = event
        object["run"] = runID
        object["time"] = Date().timeIntervalSince1970
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data + Data([10]))
        }
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            guard !finished else { return }
            switch state {
            case .ready:
                emit("ready")
                guard !started else { return }
                started = true
                receive()
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now(), repeating: options.interval)
                timer.setEventHandler { [self] in send() }
                self.timer = timer
                timer.resume()
            case .failed(let error):
                emit("connection_failed", ["error": String(describing: error)])
                finish(code: 2)
            case .waiting(let error): emit("waiting", ["error": String(describing: error)])
            default: break
            }
        }
        queue.async { [self] in
            emit("start", ["host": options.host, "port": options.port, "transport": options.transport])
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + options.duration) { [self] in
            finish(code: options.requireEcho && received == 0 ? 2 : 0)
        }
    }

    private func send() {
        guard !finished else { return }
        sequence += 1
        let frame = "VPNGUARD/1 \(runID) \(sequence)"
        outstanding.insert(frame)
        let number = sequence
        connection.send(content: Data((frame + "\n").utf8), completion: .contentProcessed { [self] error in
            guard !finished else { return }
            if let error { emit("send_failed", ["sequence": number, "error": String(describing: error)]) }
            else { emit("send_queued", ["sequence": number]) }
        })
    }

    private func accept(_ data: Data) {
        buffer.append(data)
        // The endpoint is untrusted. Bound buffering even if it never returns a newline.
        if buffer.count > 65536 {
            emit("invalid_echo", ["reason": "frame too large"])
            finish(code: 2)
            return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self)
            buffer.removeSubrange(...newline)
            if outstanding.remove(line) != nil {
                received += 1
                emit("echo_received", ["count": received])
            } else { emit("invalid_echo", ["reason": "unexpected frame"]) }
        }
    }

    private func receive() {
        let handler: (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = { [self] data, _, complete, error in
            guard !finished else { return }
            if let data { accept(data) }
            if let error {
                emit("receive_failed", ["error": String(describing: error)])
                finish(code: 2)
            } else if complete && options.transport == "tcp" {
                emit("peer_closed")
                finish(code: 2)
            } else if !finished { receive() }
        }
        if options.transport == "udp" { connection.receiveMessage(completion: handler) }
        else { connection.receive(minimumIncompleteLength: 1, maximumLength: 4096, completion: handler) }
    }

    private func finish(code: Int32) {
        guard !finished else { return }
        finished = true
        timer?.cancel()
        connection.cancel()
        emit("summary", ["sent": sequence, "echoes": received, "exit_code": code,
                         "protection_verified": false])
        exit(code)
    }
}

do {
    let options = try ProbeOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    let probe = Probe(options: options)
    probe.start()
    dispatchMain()
} catch {
    FileHandle.standardError.write(Data("\(error)\n\(usage)\n".utf8))
    exit(64)
}

