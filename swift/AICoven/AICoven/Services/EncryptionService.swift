import Foundation

/// Legacy cloud-only encryption service has been removed from the local-first
/// client. All at-rest encryption now goes through `DataEncryptionService`.
///
/// This stub remains so any lingering code references fail in a controlled
/// manner and to make the intent explicit.
@available(*, unavailable, message: "EncryptionService has been removed. Use DataEncryptionService instead; the local client does not talk to the multi-tenant backend.")
actor EncryptionService {}
