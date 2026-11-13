import XCTest
@testable import GuardCore

final class GuardCoreTests: XCTestCase {
    func testBlocksResponsibleProbeEvenWhenSocketOwnerIsSystemService() {
        XCTAssertEqual(ProbePolicy.evaluate(appID: ProbePolicy.signingIdentifier,
                                           processID: "com.apple.some-service"), .blockProbe)
    }

    func testBlocksProbeOwnerEvenWithoutResponsibleApplication() {
        XCTAssertEqual(ProbePolicy.evaluate(appID: nil,
                                           processID: ProbePolicy.signingIdentifier), .blockProbe)
    }

    func testDoesNotMatchDisplayNamesOrIdentifierPrefixes() {
        for id in ["guard-probe", "node", ProbePolicy.signingIdentifier + ".other"] {
            XCTAssertEqual(ProbePolicy.evaluate(appID: id, processID: id), .allowUnrelated)
        }
    }

    func testMissingIdentityIsNotAConfirmedUnrelatedApplication() {
        XCTAssertEqual(ProbePolicy.evaluate(appID: nil, processID: nil), .unresolvedIdentity)
        XCTAssertEqual(ProbePolicy.evaluate(appID: "", processID: "other"), .unresolvedIdentity)
        XCTAssertEqual(ProbePolicy.evaluate(appID: "other", processID: nil), .unresolvedIdentity)
    }

    func testDefaultsOnlyContactLoopback() throws {
        let options = try ProbeOptions(arguments: [])
        XCTAssertEqual(options.host, "127.0.0.1")
        XCTAssertEqual(options.transport, "tcp")
    }

    func testIPv6AndUDPOptions() throws {
        let options = try ProbeOptions(arguments: ["--host", "::1", "--transport", "udp", "--require-echo"])
        XCTAssertEqual(options.host, "::1")
        XCTAssertEqual(options.transport, "udp")
        XCTAssertTrue(options.requireEcho)
    }

    func testRejectsInvalidArgumentsBeforeOpeningSockets() {
        let invalid = [
            ["--host", "example.com"], ["--port", "0"], ["--port", "65536"],
            ["--duration", "nan"], ["--duration", "inf"], ["--duration", "-1"],
            ["--interval", "0"], ["--interval", "11"], ["--transport", "quic"],
            ["--host"], ["--typo", "1"], ["--port", "1", "--port", "2"],
            ["--require-echo", "--require-echo"],
        ]
        for args in invalid { XCTAssertThrowsError(try ProbeOptions(arguments: args), "\(args)") }
    }
}

