import Foundation
import Darwin

public struct ProbeOptions {
    public let host: String
    public let port: UInt16
    public let transport: String
    public let duration: Double
    public let interval: Double
    public let requireEcho: Bool

    public enum Invalid: Error, CustomStringConvertible {
        case argument(String)
        public var description: String {
            switch self { case .argument(let message): return message }
        }
    }

    public init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var requireEcho = false
        var index = 0
        let names: Set<String> = ["--host", "--port", "--transport", "--duration", "--interval"]
        while index < arguments.count {
            let name = arguments[index]
            if name == "--require-echo" {
                guard !requireEcho else { throw Invalid.argument("Duplicate --require-echo") }
                requireEcho = true
                index += 1
                continue
            }
            guard names.contains(name), index + 1 < arguments.count, values[name] == nil else {
                throw Invalid.argument("Unknown, duplicate or incomplete option: \(name)")
            }
            values[name] = arguments[index + 1]
            index += 2
        }
        let host = values["--host"] ?? "127.0.0.1"
        var v4 = in_addr()
        var v6 = in6_addr()
        guard inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1 else {
            throw Invalid.argument("--host must be a numeric IPv4 or IPv6 address; DNS is a separate test")
        }
        guard let port = UInt16(values["--port"] ?? "54321"), port > 0 else {
            throw Invalid.argument("--port must be 1...65535")
        }
        let transport = values["--transport"] ?? "tcp"
        guard ["tcp", "udp"].contains(transport) else {
            throw Invalid.argument("--transport must be tcp or udp")
        }
        guard let duration = Double(values["--duration"] ?? "10"), duration.isFinite,
              duration >= 1, duration <= 3600 else {
            throw Invalid.argument("--duration must be 1...3600 seconds")
        }
        guard let interval = Double(values["--interval"] ?? "0.25"), interval.isFinite,
              interval >= 0.1, interval <= duration else {
            throw Invalid.argument("--interval must be 0.1...duration seconds")
        }
        self.host = host
        self.port = port
        self.transport = transport
        self.duration = duration
        self.interval = interval
        self.requireEcho = requireEcho
    }
}

