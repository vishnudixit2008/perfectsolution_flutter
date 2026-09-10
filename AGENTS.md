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
   - Primary Backend URL: `https://api.perfectsolutionnoida.in` (Official Cloudflare Zero Trust Tunnel).
   - Backup Public Tunnel: `https://gb4ccxrgywpd.shares.zrok.io` (Zrok v2).
   - Admin / Studio Dashboard: `http://100.123.9.102:3000` (Protected inside private Tailscale mesh).
   - Local Network LAN: `http://192.168.1.7:8000` (or `http://192.168.1.19:8000`).
   - **DO NOT** change the default URL without explicit user approval.

---

## 5. ACCESSING SUPABASE & LINUX SERVER IN ANY CHAT (MCP & SSH)

When the user asks to query or modify data in Supabase, or execute tasks on the dedicated Linux backend server:

### A. Supabase Database Operations (via Configured MCP Tools)
All chats have lazy-loaded MCP tools registered via `mcp_config.json`:
- **`supabase-server` (REST API via Cloudflare Tunnel - Always accessible from anywhere):**
  - `call_mcp_tool` with `ServerName: "supabase-server"`:
    - `supabase_select`: Query any table (`table`, `select`, `query_params`, `limit`).
    - `supabase_insert`: Insert rows (`table`, `rows`, `upsert`).
    - `supabase_update`: Update rows (`table`, `match_column`, `match_value`, `values`).
    - `supabase_delete`: Delete rows (`table`, `match_column`, `match_value`).
    - `supabase_storage_list`: List files in storage buckets (`bucket`, `path`, `limit`).
- **`supabase-postgres` (Direct Postgres SQL via Tailscale & Pooler):**
  - `call_mcp_tool` with `ServerName: "supabase-postgres"`, `ToolName: "query"`:
    - Runs direct SQL queries over `postgresql://postgres.your-tenant-id:...@100.123.9.102:5432/postgres`.

### B. Linux Server Shell Execution (via SSH)
Direct, key-authenticated SSH access is configured on this PC with instant keypair authentication (no passwords or browser checks):
- **Quick Command:**
  - `ssh shop-server "<command>"`
  - Or directly: `ssh 100.123.9.102 "<command>"` (Tailscale)
  - Or on Shop Wi-Fi: `ssh 192.168.1.7 "<command>"` (LAN)
- **Supabase Host Directory:** `/opt/supabase`
- **Example Maintenance Commands:**
  - Check container status: `ssh shop-server "docker ps"`
  - Resource usage: `ssh shop-server "docker stats --no-stream"`
  - Inspect storage & drives: `ssh shop-server "lsblk"` or `ssh shop-server "df -h"`
  - Supabase container logs: `ssh shop-server "cd /opt/supabase && docker compose logs --tail=50"`
  - Run direct SQL via docker: `ssh shop-server "docker exec supabase-db psql -U postgres -c '<SQL>'"`
