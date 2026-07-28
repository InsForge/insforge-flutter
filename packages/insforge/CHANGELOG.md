## 0.2.0

Sync with InsForge-sdk-js v1.5.1.

- Auth: passwordless email OTP sign-in — `signInWithOtp` (send a 6-digit code,
  enumeration-safe) and `verifyOtp` (verify the code and establish a session).
- Storage: `deleteAll` now uses the batch-delete endpoint (one request, max
  1000 keys) and returns a `List<DeleteObjectResult>` with a per-key
  `deleted | notFound | failed` status. New `DeleteObjectResult` model.

## 0.1.0

Initial release.
