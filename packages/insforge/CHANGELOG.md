## 0.2.0

Syncs with InsForge JS SDK v1.5.0 (storage: standard PUT create-or-replace
semantics). Requires an InsForge backend that includes the standard-PUT
storage change (InsForge/InsForge#1760).

- **Changed:** storage `upload(path, bytes)` — uploading to an existing key
  now replaces the object in place instead of the server auto-renaming the
  key. Signature unchanged.
- **Changed:** storage `uploadAutoKey(filename, bytes)` — now generates a
  unique, collision-free key client-side (sanitized base + timestamp +
  random suffix) and uploads through the standard `upload` path.
- **Deprecated:** the no-op `upsert` flag on `upload`, `uploadAutoKey`, and
  `FileOptions` (the `x-upsert` header is no longer sent).

## 0.1.0

Initial release.
