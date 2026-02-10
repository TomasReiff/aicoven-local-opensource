# Analytics Privacy Implementation

## Overview

The `AnalyticsService` has been updated to respect the privacy guarantees of the local-first AICoven architecture. All analytics are now privacy-preserving and require explicit user consent.

## Key Changes

### 1. User Consent Requirement

Analytics collection is now **opt-in only**. No events are sent to Firebase Analytics unless the user explicitly consents.

- New property: `analyticsConsent: Bool` (persisted to UserDefaults)
- New method: `setAnalyticsConsent(_ consent: Bool)` to enable/disable analytics
- All events check consent before sending via `logEventIfEnabled()`

### 2. ID Anonymization

All identifiable data is now hashed using SHA-256 before being sent to Firebase Analytics:

- **Thread IDs** → `thread_id_hash`
- **Memory IDs** → `memory_id_hash`
- **Proposal IDs** → `proposal_id_hash`
- **Coven IDs** → `coven_id_hash`
- **Agent IDs** → `agent_id_hash`

This prevents Firebase from correlating analytics events with specific user content while still allowing aggregate analysis of user behavior patterns.

### 3. Removed Privacy-Violating Methods

The following methods have been **completely removed** as they violated the local-first privacy model:

- `setUserId(_ userId: String?)` - Removed
- `setUserProperty(_ value: String?, forName name: String)` - Removed

These methods sent raw user identifiers to Firebase, which is incompatible with the promise that "all user data stays on-device."

### 4. Removed Authentication Events

All authentication tracking methods were removed since the local-first client has no actual login/signup flow:

- `trackLoginStarted()`, `trackLoginSuccess()`, `trackLoginFailed()`
- `trackSignupStarted()`, `trackSignupSuccess()`, `trackSignupFailed()`
- `trackForgotPasswordTapped()`, `trackPasswordResetRequested()`

These were dead code that would never be called in the current architecture.

## Implementation Details

### Hash Function

```swift
private func hashIdentifier(_ identifier: String?) -> String? {
    guard let identifier = identifier else { return nil }
    
    let data = Data(identifier.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

SHA-256 provides:
- **Consistency**: Same ID always produces same hash (enables session tracking without revealing ID)
- **One-way**: Cannot reverse hash to discover original ID
- **Collision resistance**: Different IDs produce different hashes

### Consent Checking

```swift
private func logEventIfEnabled(_ name: String, parameters: [String: Any]?) {
    guard analyticsConsent else { return }
    Analytics.logEvent(name, parameters: parameters)
}
```

All event tracking methods now call `logEventIfEnabled()` instead of `Analytics.logEvent()` directly.

## Usage

### Setting Analytics Consent

During onboarding or in settings:

```swift
// Enable analytics
AnalyticsService.shared.setAnalyticsConsent(true)

// Disable analytics
AnalyticsService.shared.setAnalyticsConsent(false)
```

### Tracking Events

No changes required for existing tracking calls. All methods automatically:
1. Check consent
2. Hash any identifiable IDs
3. Only send if user has opted in

Example:
```swift
// Thread ID is automatically hashed before sending
AnalyticsService.shared.trackThreadOpened(
    threadId: thread.id,
    threadAgeDays: threadAge
)
```

## Compliance

These changes ensure compliance with the local-first architecture principles:

✅ **No identifiable data leaves the device** (all IDs are hashed)  
✅ **Analytics require explicit consent** (opt-in only)  
✅ **No user tracking** (no userId or user properties)  
✅ **Aggregate metrics only** (hashes prevent correlation with real users)

## Future Considerations

For even stronger privacy guarantees, consider:

1. **Local-only analytics**: Store analytics entirely on-device
2. **Differential privacy**: Add noise to aggregate metrics
3. **Session IDs**: Use temporary session hashes instead of persistent ID hashes
4. **Opt-out UI**: Prominent settings toggle for analytics consent

## Migration Notes

**Breaking Changes:**
- Any code calling `setUserId()` or `setUserProperty()` must be removed
- Analytics parameter names have changed (e.g., `thread_id` → `thread_id_hash`)
- Analytics will not fire until user grants consent

**Dashboard Impact:**
- Thread/memory IDs in Firebase Analytics are now SHA-256 hashes
- User identification is no longer possible
- Only aggregate behavior patterns can be analyzed
