import XCTest
@testable import AICoven

final class MessageAdapterTests: XCTestCase {

    func testSanitizeContent_removesSquareBracketToolCallMarkup() {
        let input = """
        Before text.

        [TOOL_CALL: name=github.createBranch]
        {"repo": "owner/repo", "base_branch": "dev"}
        [/TOOL_CALL]

        After text.
        """

        let output = MessageAdapter.sanitizeContent(input)

        XCTAssertFalse(output.contains("[TOOL_CALL:"))
        XCTAssertFalse(output.contains("[/TOOL_CALL]"))
        XCTAssertTrue(output.contains("Before text."))
        XCTAssertTrue(output.contains("After text."))
    }

    func testSanitizeContent_removesAngleBracketToolCallMarkup() {
        let input = """
        Intro.

        <TOOL_CALL>
        github.listFiles
        {"repo": "owner/repo", "path": ""}
        </TOOL_CALL>

        Outro.
        """

        let output = MessageAdapter.sanitizeContent(input)

        XCTAssertFalse(output.contains("<TOOL_CALL>"))
        XCTAssertFalse(output.contains("</TOOL_CALL>"))
        XCTAssertTrue(output.contains("Intro."))
        XCTAssertTrue(output.contains("Outro."))
    }

    func testSanitizeContent_removesThoughtBlocks() {
        let input = """
        <thought>Planning step 1</thought>
        <thought>Planning step 2</thought>
        Final answer.
        """

        let output = MessageAdapter.sanitizeContent(input)

        XCTAssertFalse(output.contains("<thought>"))
        XCTAssertFalse(output.contains("</thought>"))
        XCTAssertTrue(output.contains("Final answer."))
    }
}
