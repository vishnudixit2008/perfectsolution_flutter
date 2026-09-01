# Workspace Rules

Whenever running static analysis commands (`dart analyze` or `flutter analyze`):
- ALWAYS execute with `BypassSandbox: true` to avoid sandboxed process isolation and SDK cache locking issues.

## Codebase Research & Subagent Delegation
- Whenever surveying, scraping, or investigating a large amount of codebase files (e.g. broad pattern searches across many files, reading multiple view/service files, or conducting deep architectural audits):
  - **ALWAYS delegate the investigation to a `research` subagent** via `invoke_subagent` instead of doing extensive multi-file reads in the main conversation.
  - The subagent will run in its own clean context, synthesize the findings, and return a clear and concise summary to the main agent.

## CRITICAL: Syncing, Database & Backend Architecture Rules
> ⚠️ **MANDATORY FOR ALL AI AGENTS & DEVELOPERS**

1. **PROHIBITED FROM MODIFYING SYNC LOGIC WITHOUT EXPLICIT PERMISSION:**
   - **NEVER** alter, refactor, or rewrite the core syncing logic in `lib/data/services/supabase_sync_service.dart`, `lib/data/services/user_permission_service.dart`, or `lib/data/services/local_database_service.dart` unless the user **EXPLICITLY** commands you to do so.
   - If an edit touches sync paths, you **MUST STOP AND ASK THE USER FIRST** with full technical justification.

2. **PROTECT DATA INTEGRITY & ZERO LOCAL DATA LOSS:**
   - **NEVER** wipe, clear, or overwrite local Hive tables with remote data without explicit merge keys.
   - All remote syncs MUST use **Merge-in-Place** (`clearOthers: false`).
   - Deleted records MUST use tombstone tracking (`deleted_records` table) and NEVER blind deletions.

3. **CONCURRENCY & BATCHED PIPELINE INTEGRITY:**
   - In `SupabaseSyncService.syncAllTablesFromCloud()`, queries MUST remain in **batched groups (maximum 4 concurrent connections)**.
   - **DO NOT** convert table synchronization back into an unbounded 12-table `Future.wait` blast, which causes socket exhaustion on mobile connections.
   - Delta syncs MUST strictly filter using `updated_at >= lastSyncIso` on all tables.

4. **BACKEND ENDPOINT & NETWORK TOPOLOGY:**
   - Primary Backend URL: `http://psflutter.duckdns.org:8000` (Self-Hosted Supabase on Linux over Direct Native IPv6 with DuckDNS).
   - Admin / Studio Dashboard: `http://100.123.9.102:3000` (Protected inside private Tailscale mesh).
   - Local Network LAN: `http://192.168.1.19:8000`.
   - **DO NOT** change the default URL to temporary tunnels or unapproved domains without explicit user approval.

