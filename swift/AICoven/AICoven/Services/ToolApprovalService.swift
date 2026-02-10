import Foundation

/// Local-only tool approval logging stub.
///
/// In the open-source client we do not resume backend tool calls; this actor
/// simply logs approvals/rejections so the UI has a single place to send
/// intent, and can be wired to richer local behavior in the future.
actor ToolApprovalService {
    static let shared = ToolApprovalService()

    func approve(toolCallId: String, threadId: String) async {
        AppErrorReporter.log(
            message: "Approve tool call: \(toolCallId) on thread: \(threadId)",
            context: "ToolApprovalService.approve"
        )
    }

    func reject(toolCallId: String, threadId: String, reason: String? = nil) async {
        AppErrorReporter.log(
            message: "Reject tool call: \(toolCallId) on thread: \(threadId) reason: \(reason ?? "-")",
            context: "ToolApprovalService.reject"
        )
    }
}
