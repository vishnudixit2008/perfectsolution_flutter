# Sync Architecture & Backend Infrastructure Documentation

> ⚠️ **CRITICAL DEVELOPER & AI AGENT DIRECTIVE:**
> **DO NOT MODIFY ANY SYNC, AUTH, OR MERGE LOGIC IN THIS CODEBASE WITHOUT EXPLICIT PERMISSION FROM THE USER.**
> Any modifications to `lib/data/services/supabase_sync_service.dart`, `lib/data/services/user_permission_service.dart`, or `lib/data/services/local_database_service.dart` must be thoroughly justified and approved before execution.

---

## 1. Network & Backend Topology

The backend runs on a dedicated Linux host with the following network setup:

| Interface / Access | Endpoint | Purpose |
|---|---|---|
| **Public Flutter App Client** | `https://api.perfectsolutionnoida.in` | Official Cloudflare Zero Trust Tunnel. 256-bit TLS 1.3, DDoS protection, Anycast global routing (Noida/Delhi edge), unlimited bandwidth, 0 open router ports. |
| **Backup Public Tunnel** | `https://gb4ccxrgywpd.shares.zrok.io` | Zrok v2 public fallback tunnel running via systemd service. |
| **Local Shop LAN** | `http://192.168.1.19:8000` | Direct local network connection when on the same Wi-Fi. |
| **Admin & Supabase Studio** | `http://100.123.9.102:3000` | Encrypted private Tailscale mesh network for administrators to inspect tables and execute SQL securely. |
| **Database Server** | Dockerized Supabase (Postgres 17, PostgREST, Realtime, GoTrue Auth, Envoy Gateway) | Self-hosted backend in `/opt/supabase`. |

---

## 2. Syncing Architecture Principles

### A. Local-First & Cache-First (0ms UI Response)
* **Local Storage:** Hive database (`LocalDatabaseService`) stores all tables locally on each client device.
* **Reads & Writes:** UI operations read and write to local Hive immediately. The user experience is instantaneous (0ms) and works offline.
* **Authentication:** User authentication and permission checks verify local Hive credentials first so the login screen never freezes or buffers on network latency. Cloud synchronization happens non-blocking in the background (`unawaited`).

### B. Delta Sync with `updated_at` Filtering
* When syncing from cloud (`syncAllTablesFromCloud`), the app tracks `last_sync_timestamp`.
* Queries filter using `.gte('updated_at', lastSyncIso)` across all tables, including `shop_settings` and `pricelist`.
* This reduces payload size from large datasets to minimal delta payloads, saving bandwidth and memory.

### C. Batched Query Pipeline (Max 4 Concurrent Connections)
* Dart mobile HTTP clients enforce a pool limit (`maxConnectionsPerHost = 6`).
* Firing 12 table queries simultaneously in an unconstrained `Future.wait` saturates the socket pool and terminates long-lived Realtime WebSockets.
* `syncAllTablesFromCloud()` is strictly divided into **3 batched groups (max 4 tables per batch)**:
  * **Batch 1:** `deleted_records`, `inward_repairs`, `inward_estimate_items`, `calls`
  * **Batch 2:** `sales`, `sale_items`, `replacements`, `requests`
  * **Batch 3:** `purchases`, `purchase_order_items`, `pricelist`, `shop_settings`

### D. Zero Data Loss (Merge-in-Place & Tombstones)
* **No Table Overwrites:** Data from the cloud is merged with local records using primary keys (`clearOthers: false`). Local tables are NEVER cleared blindly during sync.
* **Tombstone Deletions:** Deletions are tracked via the `deleted_records` table on Supabase. When a record is deleted, its ID is recorded in `deleted_records` with a timestamp so all client devices purge only the intended record without accidental table wipes.
* **Offline Outbox Queue:** When offline, mutations are saved to local Hive pending queues (`pending_sync_queue`) and synced automatically upon reconnection.

### E. Realtime WebSockets
* Supabase Realtime listens for postgres change events (`INSERT`, `UPDATE`, `DELETE`) across all tables.
* Incoming realtime events trigger debounced table updates in local storage and notify UI providers via `ShopRepository.notifyTableChanged()`.

---

## 3. Database Indexes (Server-Side Postgres)

The Postgres database on the Linux host has B-Tree indexes on all foreign keys and timestamp columns:
* `inward_repairs(updated_at)`
* `inward_estimate_items(job_no, updated_at)`
* `sales(updated_at)`
* `sale_items(invoice_no, updated_at)`
* `purchases(updated_at)`
* `purchase_order_items(purchase_id, updated_at)`
* `calls(updated_at)`
* `replacements(updated_at)`
* `requests(updated_at)`
* `pricelist(updated_at)`
* `shop_settings(updated_at)`
* `deleted_records(deleted_at, table_name)`

---

## 4. Multi-Platform Google OAuth
* **Android & iOS:** Native `GoogleSignIn` SDK with `signInWithIdToken` (native account sheet, zero redirect URLs).
* **Windows & macOS:** Local Loopback Server (`WindowsOAuthService.startLocalServer()`) receiving auth tokens at `http://localhost:54321`.
* **Web:** Google Identity Services (GIS) popup.
