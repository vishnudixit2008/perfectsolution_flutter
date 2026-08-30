# Workspace Rules

Whenever running static analysis commands (`dart analyze` or `flutter analyze`):
- ALWAYS execute with `BypassSandbox: true` to avoid sandboxed process isolation and SDK cache locking issues.

## Codebase Research & Subagent Delegation
- Whenever surveying, scraping, or investigating a large amount of codebase files (e.g. broad pattern searches across many files, reading multiple view/service files, or conducting deep architectural audits):
  - **ALWAYS delegate the investigation to a `research` subagent** via `invoke_subagent` instead of doing extensive multi-file reads in the main conversation.
  - The subagent will run in its own clean context, synthesize the findings, and return a clear and concise summary to the main agent.
