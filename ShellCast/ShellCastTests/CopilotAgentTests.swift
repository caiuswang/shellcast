import XCTest
@testable import ShellCast

/// Tests for `CopilotAgent` — covers pure helpers, the running-process detection
/// regex, and the `parseSessionListOutput` parser. Integration paths that require
/// a live SSH session are deferred (no `MockSSHSession` infrastructure yet).
final class CopilotAgentTests: XCTestCase {

    // MARK: - Group A1: resumeCommand

    func testResumeCommand_PlainUUID() {
        let cmd = CopilotAgent.resumeCommand(
            sessionId: "5243facb-f629-44e5-b939-60fe2d1ba02b",
            binaryPath: "/opt/homebrew/bin/copilot"
        )
        XCTAssertEqual(cmd, "/opt/homebrew/bin/copilot --resume='5243facb-f629-44e5-b939-60fe2d1ba02b'")
    }

    func testResumeCommand_EscapesSingleQuote() {
        let cmd = CopilotAgent.resumeCommand(
            sessionId: "weird'id",
            binaryPath: "copilot"
        )
        XCTAssertEqual(cmd, "copilot --resume='weird'\\''id'")
    }

    func testResumeCommand_EmptyId() {
        let cmd = CopilotAgent.resumeCommand(sessionId: "", binaryPath: "copilot")
        XCTAssertEqual(cmd, "copilot --resume=''")
    }

    // MARK: - Group A2: newCommand

    func testNewCommand_WithProjectPath() {
        let cmd = CopilotAgent.newCommand(projectPath: "/home/user/proj", binaryPath: "copilot")
        XCTAssertEqual(cmd, "cd '/home/user/proj' && copilot")
    }

    func testNewCommand_WithNilProjectPath() {
        let cmd = CopilotAgent.newCommand(projectPath: nil, binaryPath: "copilot")
        XCTAssertEqual(cmd, "copilot")
    }

    func testNewCommand_WithEmptyProjectPath() {
        let cmd = CopilotAgent.newCommand(projectPath: "", binaryPath: "copilot")
        XCTAssertEqual(cmd, "copilot")
    }

    func testNewCommand_PathWithSingleQuote() {
        let cmd = CopilotAgent.newCommand(projectPath: "/foo's/bar", binaryPath: "copilot")
        XCTAssertEqual(cmd, "cd '/foo'\\''s/bar' && copilot")
    }

    // MARK: - Group A3: cleanSummary

    func testCleanSummary_Nil() {
        XCTAssertNil(CopilotAgent.cleanSummary(nil))
    }

    func testCleanSummary_Empty() {
        XCTAssertNil(CopilotAgent.cleanSummary(""))
    }

    func testCleanSummary_WhitespaceOnly() {
        XCTAssertNil(CopilotAgent.cleanSummary("   \t  "))
    }

    func testCleanSummary_StripsSurroundingDoubleQuotes() {
        XCTAssertEqual(CopilotAgent.cleanSummary("\"Fix bug\""), "Fix bug")
    }

    func testCleanSummary_StripsSurroundingSingleQuotes() {
        XCTAssertEqual(CopilotAgent.cleanSummary("'Fix bug'"), "Fix bug")
    }

    func testCleanSummary_PreservesEmbeddedQuotes() {
        XCTAssertEqual(CopilotAgent.cleanSummary("He said \"hi\""), "He said \"hi\"")
    }

    func testCleanSummary_TrimsSurroundingWhitespace() {
        XCTAssertEqual(CopilotAgent.cleanSummary("   Fix bug  "), "Fix bug")
    }

    // MARK: - Group B: detectionPattern regex

    private func matchesCopilot(_ argv: String) -> Bool {
        let regex = try! NSRegularExpression(
            pattern: CopilotAgent.detectionPattern,
            options: [.caseInsensitive]
        )
        let range = NSRange(argv.startIndex..., in: argv)
        return regex.firstMatch(in: argv, options: [], range: range) != nil
    }

    func testDetection_MatchesAbsolutePath() {
        XCTAssertTrue(matchesCopilot("/usr/local/bin/copilot"))
    }

    func testDetection_MatchesBareCopilot() {
        XCTAssertTrue(matchesCopilot("copilot"))
    }

    func testDetection_MatchesCopilotChat() {
        XCTAssertTrue(matchesCopilot("copilot chat"))
    }

    func testDetection_MatchesCopilotResumeFlag() {
        XCTAssertTrue(matchesCopilot("copilot --resume=foo"))
        XCTAssertTrue(matchesCopilot("/opt/homebrew/bin/copilot --version"))
        XCTAssertTrue(matchesCopilot("copilot --continue"))
    }

    func testDetection_MatchesEachGitHubVerb() {
        for verb in ["auth", "login", "logout", "version", "help"] {
            XCTAssertTrue(matchesCopilot("copilot \(verb)"), "should match: copilot \(verb)")
        }
    }

    func testDetection_CaseInsensitive() {
        // The remote pipeline already lowercases via tolower(args), but the regex
        // itself must also be case-insensitive when compiled with .caseInsensitive.
        XCTAssertTrue(matchesCopilot("COPILOT"))
        XCTAssertTrue(matchesCopilot("Copilot --version"))
        XCTAssertTrue(matchesCopilot("/Usr/Local/Bin/Copilot"))
    }

    func testDetection_RejectsAWSCopilotSubcommands() {
        // AWS Copilot CLI uses subcommands first — must not match.
        for sub in ["app", "svc", "env", "deploy", "init", "pipeline", "task", "job", "ls", "run"] {
            let argv = "copilot \(sub)"
            XCTAssertFalse(matchesCopilot(argv), "should reject: \(argv)")
            XCTAssertFalse(matchesCopilot("copilot \(sub) deploy"), "should reject: copilot \(sub) deploy")
        }
    }

    func testDetection_RejectsAWSCopilotWithPathPrefix() {
        XCTAssertFalse(matchesCopilot("/usr/local/bin/copilot app deploy"))
        XCTAssertFalse(matchesCopilot("aws/copilot init"))
    }

    func testDetection_RejectsSubstringMatches() {
        // Other processes that happen to contain "copilot" as a substring.
        XCTAssertFalse(matchesCopilot("fish copilotbar"))
        XCTAssertFalse(matchesCopilot("vim copilot.md"))
        XCTAssertFalse(matchesCopilot("grep copilot /etc/hosts"))
    }

    // MARK: - Group C: parseSessionListOutput

    func testParse_EmptyInput() {
        XCTAssertEqual(CopilotAgent.parseSessionListOutput("").count, 0)
    }

    func testParse_WhitespaceOnlyInput() {
        XCTAssertEqual(CopilotAgent.parseSessionListOutput("\n  \t\n").count, 0)
    }

    func testParse_SingleFullLine() {
        let raw = "1777392636|||5243facb-f629-44e5-b939-60fe2d1ba02b|||/Users/me/proj|||Fix bug"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        let s = sessions[0]
        XCTAssertEqual(s.sessionId, "5243facb-f629-44e5-b939-60fe2d1ba02b")
        XCTAssertEqual(s.projectPath, "/Users/me/proj")
        XCTAssertEqual(s.summary, "Fix bug")
        XCTAssertNotNil(s.lastModified)
        XCTAssertEqual(s.lastModified!.timeIntervalSince1970, 1777392636, accuracy: 1.0)
    }

    func testParse_AIAgentSessionIdentifier() {
        let raw = "1777000000|||abc123|||/p|||t"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "copilot:abc123")
    }

    func testParse_PreservesInputOrder() {
        let raw = """
        1777392636|||uuid-newest|||/p1|||A
        1777300000|||uuid-mid|||/p2|||B
        1777200000|||uuid-oldest|||/p3|||C
        """
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.map(\.sessionId), ["uuid-newest", "uuid-mid", "uuid-oldest"])
    }

    func testParse_EmptySummarySlot() {
        // Real-world: a freshly-created session has no `summary:` or `name:` in its
        // workspace.yaml, so the shell command emits a trailing empty field.
        let raw = "1777356686|||uuid|||/Users/me/note|||"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].summary)
    }

    func testParse_QuotedSummaryStripped() {
        let raw = "1777000000|||uuid|||/p|||\"Has: a colon\""
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.first?.summary, "Has: a colon")
    }

    func testParse_SingleQuotedSummaryStripped() {
        let raw = "1777000000|||uuid|||/p|||'wrapped'"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.first?.summary, "wrapped")
    }

    func testParse_NonNumericTimestamp() {
        let raw = "not-a-number|||uuid|||/p|||summary"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].lastModified)
        XCTAssertEqual(sessions[0].sessionId, "uuid")
    }

    func testParse_ValidEpochTimestamp() {
        let raw = "1700000000|||uuid|||/p|||s"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        guard let date = sessions.first?.lastModified else {
            return XCTFail("expected non-nil date")
        }
        XCTAssertEqual(date.timeIntervalSince1970, 1700000000, accuracy: 1.0)
    }

    func testParse_LineWithTooFewFieldsIsSkipped() {
        let raw = """
        1777000000|||uuid|||/p|||valid
        only-one-field
        """
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "uuid")
    }

    func testParse_LineWithEmptySessionIdIsSkipped() {
        let raw = """
        1777000000|||uuid|||/p|||valid
        1777000001||||||/p|||has-empty-id
        """
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "uuid")
    }

    func testParse_EmptyCwdMapsToUnknown() {
        let raw = "1777000000|||uuid||||||some summary"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.first?.projectPath, "Unknown")
    }

    func testParse_TrimsWhitespaceInFields() {
        let raw = "  1777000000  |||  uuid  |||  /p  |||  Summary text  "
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "uuid")
        XCTAssertEqual(sessions[0].projectPath, "/p")
        XCTAssertEqual(sessions[0].summary, "Summary text")
        XCTAssertNotNil(sessions[0].lastModified)
    }

    func testParse_MixedValidAndInvalidLines() {
        let raw = """

        1777000000|||valid1|||/p|||A
        garbage-line
        1777000001|||valid2|||/q|||B

        """
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.map(\.sessionId), ["valid1", "valid2"])
    }

    func testParse_TrailingNewlineDoesNotEmitEmptySession() {
        let raw = "1777000000|||uuid|||/p|||s\n"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
    }

    func testParse_TripleBarInsideValueFragments() {
        // Locked behavior: a value containing literal `|||` fragments the line.
        // Extras beyond field 4 are dropped. Intentional simplicity — a session
        // name with `|||` is wildly unlikely.
        let raw = "1777000000|||uuid|||/p|||summary|||extra-fragment"
        let sessions = CopilotAgent.parseSessionListOutput(raw)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].summary, "summary")
    }

    // MARK: - Static metadata sanity

    func testStaticMetadata() {
        XCTAssertEqual(CopilotAgent.agentID, "copilot")
        XCTAssertEqual(CopilotAgent.displayName, "GitHub Copilot")
        XCTAssertEqual(CopilotAgent.binaryNames, ["copilot"])
    }
}
