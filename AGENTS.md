# Workspace Rules

Whenever running static analysis commands (`dart analyze` or `flutter analyze`):
- ALWAYS execute with `BypassSandbox: true` to avoid sandboxed process isolation and SDK cache locking issues.
