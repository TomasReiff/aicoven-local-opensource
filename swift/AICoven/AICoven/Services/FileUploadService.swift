import Foundation

/// Legacy helper for backend file upload and metadata APIs.
///
/// The local-first client does not upload files to a custom backend; files
/// are kept on-device and analyzed directly via provider tools. This type is
/// retained only for historical reference and is not used in the local build.
@available(*, unavailable, message: "Backend file uploads are not supported in the local-only client; use local file URLs instead.")
actor FileUploadService {
    static let shared = FileUploadService()

    /// These APIs are intentionally unavailable in the local client. If you
    /// need upload behavior, prefer local file URLs and ToolService helpers
    /// instead of calling a backend.
    func uploadFile(data: Data, filename: String, contentType: String) async throws -> String {
        fatalError("FileUploadService.uploadFile is unavailable in the local-only client.")
    }

    func getFileDetails(fileId: String) async throws -> FileAttachmentDetail {
        fatalError("FileUploadService.getFileDetails is unavailable in the local-only client.")
    }

    func getFileDetails(ids: [String]) async throws -> [FileAttachmentDetail] {
        fatalError("FileUploadService.getFileDetails(ids:) is unavailable in the local-only client.")
    }
}
