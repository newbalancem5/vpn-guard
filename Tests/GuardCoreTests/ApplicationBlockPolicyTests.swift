import Security
import XCTest
@testable import GuardCore

final class ApplicationBlockPolicyTests: XCTestCase {
    func testExactIdentifiersRequireGoogleTeam() {
        for identifier in ApplicationBlockPolicy.identifiers {
            XCTAssertTrue(ApplicationBlockPolicy.matches(.init(identifier: identifier, team: ApplicationBlockPolicy.team), languageServerHash: nil))
            XCTAssertFalse(ApplicationBlockPolicy.matches(.init(identifier: identifier, team: "OTHERTEAM"), languageServerHash: nil))
        }
        XCTAssertFalse(ApplicationBlockPolicy.matches(.init(identifier: "com.google.antigravity.unrelated", team: ApplicationBlockPolicy.team), languageServerHash: nil))
    }
    func testGenericLanguageServerRequiresVerifiedCodeHash() {
        let process = SignedProcessIdentity(identifier: "language_server", team: ApplicationBlockPolicy.team, codeHash: "abc")
        XCTAssertFalse(ApplicationBlockPolicy.matches(process, languageServerHash: nil))
        XCTAssertFalse(ApplicationBlockPolicy.matches(process, languageServerHash: ""))
        XCTAssertFalse(ApplicationBlockPolicy.matches(process, languageServerHash: "different"))
        XCTAssertTrue(ApplicationBlockPolicy.matches(process, languageServerHash: "abc"))
    }
    func testTeamRequirementRejectsMalformedTeams() {
        XCTAssertEqual(SignedProcessIdentity.teamRequirement(ApplicationBlockPolicy.team),
                       "anchor apple generic and certificate leaf[subject.OU] = \"EQHXZ8M8AV\"")
        for team in ["", "eqhxz8m8av", "EQHXZ8M8A", "EQHXZ8M8AV1", "EQHXZ8M8A\"", "X\" or true"] {
            XCTAssertNil(SignedProcessIdentity.teamRequirement(team), team)
        }
    }
    func testResolvesRunningCodeWithGenericFieldsAndVerifiedTeamOnly() throws {
        var code: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        let identity = try XCTUnwrap(try SignedProcessIdentity.resolve(XCTUnwrap(code)))
        XCTAssertFalse(identity.identifier.isEmpty)
        XCTAssertNotNil(identity.codeHash)
        // A reported team must be the one the running code is anchored to.
        if let team = identity.team {
            XCTAssertNotNil(SignedProcessIdentity.teamRequirement(team))
        }
    }
    func testBothAuditIdentitiesAndExplicitMode() {
        let target = SignedProcessIdentity(identifier: "com.google.antigravity", team: ApplicationBlockPolicy.team)
        XCTAssertFalse(ApplicationBlockPolicy.shouldBlock(mode: nil, app: target, process: target, languageServerHash: nil))
        XCTAssertTrue(ApplicationBlockPolicy.shouldBlock(mode: ApplicationBlockPolicy.mode, app: nil, process: target, languageServerHash: nil))
        XCTAssertTrue(ApplicationBlockPolicy.shouldBlock(mode: ApplicationBlockPolicy.mode, app: target, process: nil, languageServerHash: nil))
        for identifier in ["com.openai.codex", "com.yourcompany.AmneziaVPN", "com.google.Chrome", "node"] {
            let unrelated = SignedProcessIdentity(identifier: identifier, team: ApplicationBlockPolicy.team)
            XCTAssertFalse(ApplicationBlockPolicy.shouldBlock(mode: ApplicationBlockPolicy.mode, app: unrelated, process: unrelated, languageServerHash: nil))
        }
    }
}
