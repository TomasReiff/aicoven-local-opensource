import Foundation
import FirebaseAuth

/// Centralized helper for scoping local data stores (UserDefaults keys,
/// Keychain service names, file paths) to the current Firebase user.
///
/// Every service that persists user-specific data should use these helpers
/// so that signing in as a different user produces a completely isolated
/// data space.
enum UserScope {

    // MARK: - Current User

    /// The Firebase UID of the currently signed-in user, or `nil` if
    /// nobody is signed in.
    static var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Key Scoping

    /// Returns a UserDefaults key scoped to the current user.
    ///
    /// Example: `scopedKey("provider_accounts.v1")` → `"abc123.provider_accounts.v1"`
    ///
    /// Falls back to the unscoped `base` if no user is signed in, so the
    /// app doesn't crash when accessed before authentication.
    static func scopedKey(_ base: String) -> String {
        guard let uid = currentUserID else { return base }
        return "\(uid).\(base)"
    }

    /// Returns a Keychain service identifier scoped to the current user.
    static func scopedKeychainService(_ base: String) -> String {
        guard let uid = currentUserID else { return base }
        return "\(base).\(uid)"
    }

    /// Returns a filename scoped to the current user.
    ///
    /// Example: `scopedFilename("personal_threads", extension: "json")` →
    /// `"personal_threads_abc123.json"`
    static func scopedFilename(_ base: String, extension ext: String) -> String {
        guard let uid = currentUserID else { return "\(base).\(ext)" }
        return "\(base)_\(uid).\(ext)"
    }
}
