# ZenLog — Offline-First Spec (Final Feature)

Adds to the existing app: **persistent login, 24-hour on-device cache, backend connection indicator in Profile, and an offline write queue that auto-syncs.**
Builds on `ZENLOG_V2_UPGRADE.md` (backend), `ZENLOG_UI_GUIDE.md` (contracts), `ZENLOG_UI_UX_SPEC_V3.md` (visuals/popups). Where this file conflicts with them, **this file wins** (see §8.6 for the exact overrides).

---

## 0. Instructions to the builder

Make ZenLog behave like a normal app when the network or backend is down. The user must be able to open the app, see their data, and write entries without ever hitting an error wall.

Hard rules:
1. **A network failure is never a logout.** Only an actual HTTP `401` from the server ends the session (§4).
2. **Reads come from the local cache first**, then refresh from the server when possible (§5).
3. **Writes never wait for the server.** Save locally in the same step as the UI update, queue the request, sync later (§7).
4. **A server rejection (4xx validation) is not an offline problem.** Don't turn the connection dot red for it and don't retry it forever.
5. **No fake data.** The client never estimates protein, calories or scores for queued entries. They count only after the server reads them (§1.3).
6. Stack is unspecified. Use the app's existing storage, network-status and background-task libraries. Pseudo-code below is TypeScript-style but framework-neutral.

Deliverables in order: storage layer → auth persistence → cache layer → connection monitor → outbox + sync engine → UI changes → backend amendments → tests.

---

## 1. Scope, Decisions and Honest Limits

### 1.1 What you asked for → what it becomes

| Your request | Implementation |
|---|---|
| Stay logged in permanently until logout | Token in secure storage; cached user opens the app instantly; only a real `401` or user logout clears it (§4) |
| Motivation text cached | Cached with the day view; static fallback pool if nothing cached and offline (§5.5) |
| App statistics cached, refreshed after 24 h | Stats, progress, calendar, insights, profile and day views cached with a 24 h soft expiry (§5.2) |
| Green/red dot in Profile with a short reason | Connection card at the bottom of Me (§6, §8.4) |
| Offline writes saved as a queue with an indicator | Outbox table + "Queued" state on each entry (§7, §8.1) |
| Auto-push when connection returns, in the background | Sync engine with triggers, backoff and OS background tasks (§7.6–7.8) |

### 1.2 Decision: 24 hours is a *soft* expiry, not a delete timer
After 24 h a cache entry is **stale**: it is refetched as soon as the server is reachable. **It is not deleted while offline**; it is shown with an "Updated 2 days ago" label. Deleting at 24 h would leave a blank screen precisely when the user is offline. A hard purge happens at 7 days (§5.4). If you really want hard deletion at 24 h, set `HARD_EXPIRY_MS = 24h` in config; I don't recommend it.

### 1.3 Limit: queued entries don't change totals until synced
Protein, calories and hydration are extracted by Gemini on the server. A queued entry has no extracted values, so the pace card and totals don't include it, and the UI says so ("2 queued entries not counted yet"). Estimating locally would show invented numbers. Manual overrides and target edits are also applied only after sync.

### 1.4 Limit: sync when the app is fully closed is best-effort
Sync is guaranteed when the app is open or returns to the foreground. For a closed app, use Android WorkManager and iOS BGTaskScheduler. As far as I know, Android periodic work has a ~15 min minimum interval and iOS decides when background tasks run, so neither is guaranteed. Treat background sync as a bonus; the guarantee is "syncs the next time you open the app".

### 1.5 Non-goals
Conflict-resolution UI, multi-user data sharing, a batch sync endpoint, offline analytics, offline AI features (Analyze, Retry extraction, Insights generation).

---

## 2. Architecture

```
                       ┌────────────────────────────┐
   UI (screens) ◄──────│  Repository layer          │
                       │  read: cache → network     │
                       │  write: local → outbox     │
                       └──────┬───────────┬─────────┘
                              │           │
                  ┌───────────▼──┐   ┌────▼──────────────┐
                  │ Cache store  │   │ Outbox + local    │
                  │ (24h soft)   │   │ entries (durable) │
                  └───────────┬──┘   └────┬──────────────┘
                              │           │
                       ┌──────▼───────────▼──────┐        ┌────────────────────┐
                       │      Sync Engine        │◄──────►│ Connection Monitor │
                       │ (single-flight, backoff)│ events │ (state + reason)   │
                       └──────────────┬──────────┘        └────────────────────┘
                                      │ HTTP
                                 ZenLog backend
```

- The UI never calls the API directly. It talks to repositories.
- The connection monitor is the only thing that decides "connected / disconnected", and it classifies every failure (§6).
- The sync engine is the only thing that talks to the server for queued writes.

---

## 3. Local Storage

### 3.1 Tiers

| Tier | Holds | Notes |
|---|---|---|
| **Secure storage** (Keychain/Keystore) | `access_token`, `pending_revoke_token` (§4.4), `device_id` | Never in the database or logs |
| **Persistent database** (SQLite, or the framework's equivalent) | cache, local entries, outbox, kv | Survives app kill and phone restart. This is the "cache memory" you described: on disk, not RAM |
| **In-memory** | query client / UI state | Rebuilt from the database on launch |

Use one SQLite database with transactions for cache, local entries and outbox. It's required for write-ahead saves (§7.2). If you use TanStack Query, its persister can serve the read cache, but **the outbox and local entries must be your own tables**, because you need idempotency, coalescing and per-entry status.

### 3.2 Schema (SQLite)

```sql
CREATE TABLE cache (
  user_id TEXT NOT NULL,
  key TEXT NOT NULL,                 -- e.g. 'dayView:2026-10-01', 'calendar:2026-10', 'progressWeek:2026-09-28'
  json TEXT NOT NULL,
  fetched_at INTEGER NOT NULL,       -- epoch ms
  soft_expires_at INTEGER NOT NULL,  -- fetched_at + 24h
  schema_v INTEGER NOT NULL,
  PRIMARY KEY (user_id, key)
);

CREATE TABLE local_logs (            -- entries created or changed on this phone
  client_id TEXT PRIMARY KEY,        -- UUID, stable UI key, also sent to server as client_id
  user_id TEXT NOT NULL,
  server_id TEXT,                    -- null until the create syncs
  text TEXT NOT NULL,
  timestamp TEXT NOT NULL,           -- ISO with +05:30, the moment the user wrote it
  provisional_date TEXT NOT NULL,    -- computed locally with the 4 AM rule, replaced by server date after sync
  sync_state TEXT NOT NULL,          -- queued | syncing | synced | failed
  edit_pending INTEGER DEFAULT 0,    -- 1 when an edit is queued for a synced entry
  delete_pending INTEGER DEFAULT 0,
  fail_reason TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE outbox (
  op_id TEXT PRIMARY KEY,            -- UUID, also the idempotency key
  user_id TEXT NOT NULL,
  seq INTEGER NOT NULL,              -- strictly increasing per user, defines order
  type TEXT NOT NULL,                -- CREATE_LOG | UPDATE_LOG | DELETE_LOG | OVERRIDE_LOG | SET_WAKE | SET_SLEEP | UPDATE_PROFILE
  entity_key TEXT,                   -- local_logs.client_id, or 'wake:2026-10-01', 'profile'
  payload TEXT NOT NULL,             -- JSON
  status TEXT NOT NULL,              -- queued | sending | failed_permanent
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL DEFAULT 0,
  last_error_code TEXT,
  last_error_msg TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX outbox_user_seq ON outbox(user_id, seq);

CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- kv keys: schema_version, last_full_refresh_at, last_sync_ok_at, last_connection_state
```

### 3.3 Rules
- **Partition by `user_id`** everywhere. Two friends on one phone (or a re-login as someone else) never see each other's data.
- **Do not include the database in cloud backups** (Android `allowBackup="false"` or backup rules; iOS "exclude from backup"). It contains a personal health journal.
- Optional hardening: encrypt the database (SQLCipher or the platform's equivalent). The token must stay in secure storage regardless.
- **Schema versioning:** the cache may be wiped on a version change. The **outbox and local_logs must be migrated, never wiped**; otherwise an app update destroys unsynced entries.

---

## 4. Persistent Login

### 4.1 Rules
1. Login (`POST /api/auth/login`) stores `access_token` and `device_id` in secure storage, and the `user` profile in the cache.
2. App start: if a token exists, **render immediately from cache**; call `/api/auth/me` in the background. The app never waits on it.
3. The session ends only when:
   - the server returns **HTTP 401** on any authenticated request, **or**
   - the user taps **Log out**.
4. These **never** log the user out: no network, timeout, DNS failure, TLS error, 5xx, 429, `/health` failing, DB down, slow response, captive portal HTML responses.
5. Treat a `401` only if the response is a real HTTP 401 from the ZenLog API (check JSON shape/header). A captive-portal 401 page must be classified `UNREACHABLE`.
6. On a real `401`: pause the sync engine, keep the outbox and local entries (partitioned by user), go to Login with the username prefilled and the notice "Your session ended. Log in again." After re-login as the **same** user, the queue resumes automatically. A different user can't see or flush it.

### 4.2 Boot flow

```
App start
 ├─ read token from secure storage
 │    ├─ none → Welcome/Login
 │    └─ present → open DB → render Today from cache (skeleton only if cache is empty)
 │                    └─ background: GET /api/auth/me
 │                          ├─ 200 → refresh user, serverToday, start sync, start prefetch (§5.3)
 │                          ├─ 401 → session ended flow (§4.1.6)
 │                          └─ network/5xx/timeout → connection monitor marks DISCONNECTED(reason); app keeps working
```

### 4.3 Logout (user-initiated)
1. If the outbox has items for this user → show dialog **P40** (§8.5).
2. Move the token to secure storage slot `pending_revoke_token`, clear the active token, wipe the user's cache and (after confirmation) outbox + local entries, navigate to Login with username prefilled.
3. Try `POST /api/auth/logout` with the pending token now. If it fails, retry on the next connectivity event; on success or on a `401`, delete the slot. This works offline and still revokes the session on the server later.
4. Keep (not wiped): `device_id`, theme, `welcomeSeen`, last username.

---

## 5. Read Cache (24-hour policy)

### 5.1 Pattern: stale-while-revalidate
Every read returns cached data immediately (if any), then refreshes in the background when the server is reachable and the entry is stale or invalidated. The UI shows the refreshed data when it arrives. If the refresh fails, the cached data stays on screen and the connection monitor records the reason.

### 5.2 What is cached and how fresh it must be

| Resource (cache key) | Soft TTL | Extra refresh rules | Offline behavior |
|---|---|---|---|
| `me` (user + targets) | 24 h | Invalidate on profile update | Cached |
| `dayView:{date}` (today) | 24 h | Also refetch on screen focus if > 60 s old; poll every 2 s (max 30 s) only while `pending_count > 0` or `verdict_status = pending` | Cached + local overlay (§5.6) |
| `dayView:{date}` (past/future) | 24 h | Refetch if `verdict_status` or `pending_count` indicates work in progress | Cached; if never cached see §5.7 |
| `calendar:{YYYY-MM}` | 24 h | Invalidate on any log mutation in that month | Cached |
| `progressWeek:{anchor}`, `progressMonth:{anchor}` | 24 h | Invalidate on any log/target mutation | Cached |
| `stats:{period}:{anchor}` | 24 h | Same | Cached |
| `insights:{period}:{anchor}` | 24 h | Fetch only when the Insights tab is opened (never prefetch: the backend may spend a Gemini call generating it) | Cached; else §5.7 |
| Motivation | part of `dayView:{futureDate}` | Deterministic per (user, date), safe for 24 h | Cached; else static fallback (§5.5) |

"Invalidate" = mark stale and refetch when online; keep the old data on screen meanwhile.

### 5.3 Prefetch (so offline has something to show)
After a successful `/auth/me` and at most once per 24 h (`kv.last_full_refresh_at`), run silently at low priority, sequentially:
1. `me`
2. `dayView` for today and the previous 6 days
3. `dayView` for the next 3 days (motivation)
4. `calendar` for the current and previous month
5. `progressWeek` and `progressMonth` (current)
6. `stats` weekly and monthly (current)

Skip prefetch if the monitor says DISCONNECTED. Never prefetch insights.

### 5.4 Expiry and housekeeping
- **Soft expiry (24 h):** entry is stale. When online → refetch. When offline → keep showing it with the label "Updated {relative time}".
- **Hard purge:** at boot and once per day, delete cache rows older than **7 days** and cap `dayView` rows at the most recent 45 dates. Never touch `outbox` or `local_logs`.
- Day rollover (the 4 AM rule changes `serverToday`): treat all `dayView:today`-related entries and `progressWeek` as stale.

### 5.5 Motivation fallback (the "default code")
When a future day has no cached motivation and the device is offline, show a **static, number-free** fallback so the screen isn't empty:

```ts
const DEFAULT_MOTIVATION = [
  { headline: "A fresh page.", message: "Log what you actually do. Small, honest entries beat perfect ones.", tone: "steady" },
  { headline: "Show up tomorrow.", message: "Write your first meal and your first glass of water early.", tone: "steady" },
  { headline: "Keep it simple.", message: "Protein at every meal, water through the day, one workout when planned.", tone: "steady" },
  { headline: "Rhythm over intensity.", message: "A normal day, logged, is worth more than a perfect day skipped.", tone: "steady" },
];
// pick by hash(userId + date) % length so the same date always shows the same text
```
Label: a small caption "Offline · generic plan". Never show targets, week shortfalls or any number in the fallback; those require server data.

### 5.6 Local overlay (merging unsynced changes into a cached day)
The UI renders `applyOverlay(cachedDayView, localState)`:
- Entries in `local_logs` with `sync_state != synced` and `provisional_date == date` are inserted in timestamp order with queue states (§8.1).
- Entries with `delete_pending = 1` are hidden.
- Entries with `edit_pending = 1` show the **new text** and their old extracted chips marked "old values".
- **Totals, progress, score and verdict are not modified.** Show the footnote "N queued entries not counted yet. Totals update after sync."

### 5.7 Offline and nothing cached
| Screen | Fallback |
|---|---|
| Past day never opened | Empty state "This day isn't saved for offline use." + the entry list from `local_logs` if any |
| Future day | Static fallback (§5.5) |
| Calendar month not cached | Plain grid, no markers, note "Connect once to load this month." |
| Insights not cached | "Open this once while online to keep it for offline use." |
| Profile/targets | Cached `me` (always cached after first login) |

### 5.8 "Pace as of" label
The pace card's `expected_pct_now` is computed by the server at fetch time. When cached data is older than 5 minutes (or the monitor is DISCONNECTED), show "Pace as of {time}" on the card and dim the "now" tick. Otherwise the tick implies a time the data isn't true for.

### 5.9 Stale label rule
Show a small caption "Updated {relative time}" on a card only when its cache age is > 1 hour or the monitor is DISCONNECTED. Don't show it on fresh online data.

---

## 6. Connection Monitor

### 6.1 States

```
UNKNOWN (checking, grey)  ──success──►  CONNECTED (green)
CONNECTED ──classified failure ×2, or failure + failed /health probe──► DISCONNECTED(reason) (red)
DISCONNECTED ──any success or successful /health──► CONNECTED
Overlay: AUTH_REQUIRED (amber) when a real 401 happens; not "disconnected"
```

- **Truth source = real outcomes.** Device network status (NetInfo-style) is only a hint. Wi-Fi with no internet or a captive portal looks "connected" to the OS.
- **Green** after any successful ZenLog API response or `/health` ok.
- **Red** after two consecutive classified connectivity failures within 30 s, or one failure confirmed by a failed `/health` probe. This avoids flicker on one dropped packet.
- Connectivity events (airplane toggles) are debounced 1 s.

### 6.2 Probing
- `GET /health` (no auth), timeout 5 s.
- Probe on: app foreground, device connectivity change, user taps Retry, and while DISCONNECTED every 15 s backing off to 2 min.
- While CONNECTED no periodic probe is needed; normal requests act as heartbeat.
- API timeouts: reads 10 s, writes 15 s.

### 6.3 Error classification (one function, used everywhere)

```ts
type ReasonCode =
  | 'NO_NETWORK' | 'TIMEOUT' | 'UNREACHABLE' | 'SSL_ERROR'
  | 'SERVER_ERROR' | 'SERVER_RESTARTING' | 'DB_DOWN' | 'RATE_LIMITED'
  | 'AUTH_EXPIRED' | 'UNKNOWN';

function classify(err: unknown, res?: Response, health?: HealthBody): { code: ReasonCode; retryable: boolean; connectivity: boolean } {
  if (deviceOffline())                       return { code: 'NO_NETWORK',   retryable: true,  connectivity: true };
  if (isTimeout(err))                        return { code: 'TIMEOUT',      retryable: true,  connectivity: true };
  if (isTlsError(err))                       return { code: 'SSL_ERROR',    retryable: true,  connectivity: true };
  if (isDnsOrRefusedOrReset(err))            return { code: 'UNREACHABLE',  retryable: true,  connectivity: true };
  if (res) {
    if (res.status === 401 && looksLikeZenLogJson(res)) return { code: 'AUTH_EXPIRED', retryable: false, connectivity: false };
    if (res.status === 401)                  return { code: 'UNREACHABLE',  retryable: true,  connectivity: true }; // captive portal
    if (health && health.database !== 'connected') return { code: 'DB_DOWN', retryable: true,  connectivity: true };
    if (res.status === 429)                  return { code: 'RATE_LIMITED', retryable: true,  connectivity: true };
    if ([502, 503, 504].includes(res.status))return { code: 'SERVER_RESTARTING', retryable: true, connectivity: true };
    if (res.status >= 500)                   return { code: 'SERVER_ERROR', retryable: true,  connectivity: true };
    if (res.status >= 400)                   return { code: 'REJECTED' as any, retryable: false, connectivity: false }; // 4xx = server said no; connection is fine
  }
  return { code: 'UNKNOWN', retryable: true, connectivity: true };
}
```

Important: **4xx validation errors are not connectivity failures.** They keep the dot green and mark only the affected operation as failed.

### 6.4 One-line reasons shown in Profile (keep ≤ 60 characters)

| Code | Message |
|---|---|
| `NO_NETWORK` | No internet connection. |
| `TIMEOUT` | Server took too long to respond. |
| `UNREACHABLE` | Can't reach the server. |
| `SSL_ERROR` | Secure connection failed. |
| `SERVER_ERROR` | Server error ({status}). |
| `SERVER_RESTARTING` | Server is restarting ({status}). |
| `DB_DOWN` | Server is up, but its database is down. |
| `RATE_LIMITED` | Too many requests. Waiting a moment. |
| `AUTH_EXPIRED` | Session ended. Log in again. (amber, not red) |
| `UNKNOWN` | Unexpected error. |

Secondary warning (amber text under the reason, independent of state): **`CLOCK_SKEW`**: if `/health.server_time` (amendment C2) differs from the device clock by more than 5 min: "Phone clock is {n} min off. Entry times may be wrong."

### 6.5 Monitor API (what the rest of the app uses)

```ts
interface ConnectionSnapshot {
  state: 'unknown' | 'connected' | 'disconnected' | 'auth_required';
  reason?: ReasonCode;
  httpStatus?: number;
  message?: string;          // one-liner from §6.4
  lastSuccessAt?: number;    // epoch ms
  lastAttemptAt?: number;
  clockSkewMin?: number;
}
connection.subscribe(cb); connection.probeNow(); connection.report(result); // report() is called by the API client on every request outcome
```

---

## 7. Offline Writes: Outbox and Sync Engine

### 7.1 Which actions work offline

| Action | Queued? | Endpoint on sync |
|---|---|---|
| New log | Yes | `POST /api/logs` (with `client_id`, `timestamp`) |
| Edit log text/time | Yes | `PUT /api/logs/{id}` |
| Delete log | Yes (after the 5 s undo window) | `DELETE /api/logs/{id}` |
| Override values | Yes | `PATCH /api/logs/{id}/override` |
| Set wake / sleep | Yes | `POST /api/days/{day}/wake`, `POST|PUT /api/days/{day}/sleep` |
| Update profile/targets/goal | Yes (last write wins) | `PUT /api/users/me` |
| Log out | Works offline (§4.3) | `POST /api/auth/logout` later |
| Analyze day, Retry extraction, Insights | **No.** Need the server | Buttons disabled offline with "Needs connection" |
| Login | **No** | — |

### 7.2 Write-ahead save (never lose an entry)
When the user taps Send, in **one database transaction**:
1. insert `local_logs` row `{client_id, text, timestamp: now (IST, +05:30), provisional_date: logicalDate(now), sync_state: 'queued'}`;
2. insert `outbox` row `{type: 'CREATE_LOG', entity_key: client_id, payload: {client_id, text, timestamp}}` with the next `seq`.
Only after the transaction commits does the UI show the new row. Then call `sync.kick()`. If the app is killed one millisecond later, the entry is still there.

`logicalDate(ts) = (ts − DAY_CUTOFF_HOURS).date` with `DAY_CUTOFF_HOURS` taken from `/auth/me` (default 4). This is the one place the client computes a date, and only provisionally. After sync the server's `date` replaces it. Send **`timestamp` only** (not `date`) so the server applies its own rule. Use `date` only for explicit backfills the user picked.

### 7.3 Idempotency (mandatory)
The server may save a log and the response may never arrive. A blind retry would create a **duplicate entry**.
- `CREATE_LOG` sends `client_id` (= `op_id`). The backend must treat `(user_id, client_id)` as unique and, on a replay, return the existing log with `200` (amendment C1). **Without C1 this feature will create duplicates. Don't ship without it.**
- `PUT`, `PATCH`, wake/sleep, profile updates are idempotent by nature.
- `DELETE` of an already-deleted entry (`404`) counts as success.

### 7.4 Coalescing (keep the queue small and correct)

| New action | Existing queued op | Result |
|---|---|---|
| Edit text | `CREATE_LOG` for the same entry, not yet sent | Update the create payload; no new op |
| Edit text | `UPDATE_LOG` queued for the same entry | Replace its payload |
| Delete | `CREATE_LOG` not yet sent | Delete both ops and the local row. No network call ever happens |
| Delete | `UPDATE_LOG` / `OVERRIDE_LOG` queued | Drop them, enqueue `DELETE_LOG` |
| Override | `OVERRIDE_LOG` queued, same entry | Merge fields (latest wins) |
| Set wake/sleep | Same `entity_key` (`wake:{date}`) queued | Replace payload |
| Update profile | `UPDATE_PROFILE` queued | Merge fields (latest wins) |
| Any edit | Op for the same entry is `sending` right now | Wait; apply after it finishes, rewritten with `server_id` |

### 7.5 ID mapping
New entries have `client_id` and no `server_id`. After `CREATE_LOG` succeeds: store `server_id`, set `provisional_date` to the server's `date`, set `sync_state = 'synced'`, replace the entry inside cached `dayView` with the server's object. **Use `client_id` as the list key in the UI** so the row doesn't flicker or re-animate when the id changes. Later ops (`UPDATE`, `DELETE`, `OVERRIDE`) resolve `server_id` from `local_logs` at send time.

### 7.6 Sync engine

```ts
const mutex = new SingleFlight();              // one run at a time, process-wide
async function runSync(reason: string) {
  if (!mutex.tryAcquire()) return;
  try {
    if (auth.state === 'auth_required') return;
    if (connection.state === 'disconnected' && reason !== 'manual' && reason !== 'connectivity') return;
    emit({ syncing: true });
    for (;;) {
      const op = await outbox.nextRunnable(userId, Date.now());   // lowest seq, status queued, next_attempt_at <= now, not blocked by an earlier op on the same entity
      if (!op) break;
      await outbox.setStatus(op.id, 'sending'); await local.markSyncing(op);
      const r = await api.send(op, { idempotencyKey: op.id });     // reports outcome to the connection monitor
      if (r.ok) { await applySuccess(op, r.body); continue; }
      const c = classify(r.err, r.res);
      if (c.code === 'AUTH_EXPIRED') { auth.setRequired(); break; }                 // keep queue, stop
      if (c.retryable)               { await outbox.scheduleRetry(op, backoff(op.attempts + 1), c); break; } // stop run, preserve order
      await outbox.failPermanent(op, c, r.res?.body);                                // 4xx: skip this op, continue with the rest
      await local.markFailed(op, humanReason(r.res));
    }
  } finally { emit({ syncing: false }); mutex.release(); }
  if (queueEmpty()) await refreshAfterSync();     // invalidate dayView/calendar/progress/stats/insights → refetch
}
```

Notes:
- On a **retryable** failure, stop the run (the network is probably down) and keep order. On a **permanent** failure, skip that op and continue; one bad entry must not block the rest.
- Operations on the same entry stay in order; operations on different entries are independent.
- After a flush: invalidate and refetch `dayView` (affected dates), `calendar`, `progress*`, `stats`, and `insights` (the backend purges its cached reports on log changes). Resume polling for extraction.

### 7.7 Retry and backoff
`delay = min(5 min, 2 s × 2^(attempts−1)) ± 20 % jitter` → ~2 s, 4 s, 8 s, 16 s … capped at 5 min. Reset attempts on a connectivity-regained event and on manual Sync. Maximum attempts for retryable errors: unlimited (the entry is real user data), but the entry is **never** marked failed for network reasons.

### 7.8 Triggers

| Trigger | Action |
|---|---|
| App launch (after cache render) | `runSync('boot')` |
| App returns to foreground | `runSync('foreground')` + probe |
| Connectivity regained event (debounced 1 s) | probe → `runSync('connectivity')` |
| Any successful API response while queue non-empty | `runSync('opportunistic')` |
| Timer while app is open and queue non-empty | At `next_attempt_at` of the earliest op |
| User taps Sync now / Retry (Me screen, queued entry) | `runSync('manual')` |
| OS background task (Android WorkManager periodic, iOS BGTaskScheduler) | `runSync('background')`: best-effort (§1.4) |
| After enqueue | `runSync('enqueue')` |

The background worker and the foreground engine must share the same database and the **same lock**. Use a lock row in `kv` with an expiry (60 s, renewed per op) in addition to the in-process mutex, so the OS worker can't run concurrently with the foreground.

### 7.9 Failure classes for queued operations

| Result | Meaning | Entry/op state | User sees |
|---|---|---|---|
| Network, timeout, 5xx, 429 | Retryable | `queued` with `attempts`, `next_attempt_at` | "Queued" (never "failed") |
| 401 | Session ended | Queue paused | Login screen; queue resumes after same-user login |
| 400/422 (e.g. timestamp too old/future, text too long) | Rejected | `failed_permanent` | "Couldn't sync: {short reason}" with Edit / Delete |
| 404 on update/override | Entry no longer exists on the server | `failed_permanent` | "This entry was removed elsewhere" with **Save as new entry** / Delete |
| 404 on delete | Already gone | success | — |

### 7.10 Limits
- Max 500 queued ops per user. Above that, block new entries with "Too many unsynced changes. Connect to sync."
- If the database write fails (disk full): inline error "Couldn't save on this phone." and keep the text in the input. This is the only offline-write failure shown as an error.

---

## 8. UI Changes

### 8.1 Entry states (extends §6.5 of the V3 spec)

| State | Where it comes from | Indicator |
|---|---|---|
| **Queued** | `sync_state = queued` | Chip `cloud-off` + "Queued". Left edge bar dashed `inkFaint`. Caption "Saved on this phone · syncs automatically" |
| **Syncing** | `syncing` | Chip with small spinner "Syncing…" |
| **Reading…** | Server `extraction_status = pending` | As in V3 |
| **Done** | `done` | Chips as in V3 |
| **Queued edit** | `edit_pending` | New text shown, chip "Edit queued", old chips marked "old values" |
| **Sync failed** | `failed_permanent` | danger tint, "Couldn't sync: {reason}" · Edit · Delete |

Queued/edit/delete states use the `info` or neutral tint, **never danger red**. Offline is not an error.

- A queued entry's details sheet shows: "Waiting since {time} · Attempt {n}" and, if present, "Last reason: {short message}". Actions: Edit text (updates the queued op), Delete (removes locally), Sync now.
- Swipe edit/delete work on queued entries per the coalescing rules.

### 8.2 Today screen
- No offline banner and no full-screen error. The app looks normal.
- **Queue pill** in the header, only when the queue is non-empty: cloud-off icon + "3 waiting" (tap → Me connection card). While syncing: "Syncing 2 of 3".
- Under the entries list, when queued entries exist: "2 queued entries not counted yet. Totals update after sync."
- Pace card shows "Pace as of {time}" per §5.8 when data is stale/offline.
- Composer is **always enabled**. Remove the "Needs connection" behavior from V3 P20. "Review my day so far" is disabled offline with "Needs connection".

### 8.3 Days and Insights
- Cached data renders normally. Cards older than 1 hour (or offline) show "Updated {relative time}".
- Not-cached fallbacks per §5.7.
- Pull-to-refresh offline: no error popup; the refresh spinner ends, and the monitor/Profile carries the reason.

### 8.4 Profile (Me): connection card at the bottom

Replaces the old footer "Server connected".

Connected:
```
CONNECTION
● Connected to server                 [Sync now]*
  Last synced 2 min ago
  ZenLog v2.x
```
Disconnected:
```
CONNECTION
● Backend not reachable               [Retry]
  Reason: Server took too long to respond.
  3 entries waiting to sync · Last try 12:41 PM
  ZenLog v2.x
```
Checking: grey dot, "Checking connection…". Auth required: amber dot, "Session ended. Log in again." with a **Log in** button.

Specs:
- Dot = 10 px, `success.fill` / `danger.fill` / `inkFaint` / `warn.fill`, **always paired with the text** (not color only).
- Exactly **one** reason line (§6.4), plus optional amber clock-skew line.
- "N entries waiting to sync" and **Sync now** appear only if the queue is non-empty (Sync now also shown while connected and the queue is non-empty). While syncing: "Syncing 2 of 3…".
- Retry runs `connection.probeNow()` then `runSync('manual')`.
- Long-press the reason to copy a debug string: `{code} · {httpStatus?} · {ISO time}`. Handy for you; invisible to normal use.
- Backed by `connection.subscribe`; updates live.

### 8.5 Dialogs, snackbars (additions to the V3 popup catalog)

| ID | Trigger | Type | Content | Actions |
|---|---|---|---|---|
| **P40** | Log out with queued items | Dialog | "You have {n} unsynced entries." "If you log out now they will be lost." | **Sync first** (if online; runs sync then logs out) · **Log out anyway** (danger) · Cancel |
| **P41** | Queue fully synced after being offline > 30 s | Snackbar | "{n} entries synced" | — |
| **P42** | Permanent sync failure | Inline on entry + one snackbar | "1 entry couldn't sync" | View |
| **P43** | Queue cap reached | Snackbar | "Too many unsynced changes. Connect to sync." | — |
| **P44** | Local save failed | Inline error in composer | "Couldn't save on this phone." | Retry |
| **P45** | Clock skew > 5 min | Inline amber line in Profile + one-time snackbar | "Your phone's clock is {n} min off. Entry times may be wrong." | — |
| **P46** | Offline and user taps an online-only button | Snackbar | "Needs connection." | — |

### 8.6 Overrides to earlier specs
- V3 **P20** (persistent offline banner): removed. Replaced by the queue pill and the Profile connection card.
- V3 **P11b** ("Not saved · Retry" on network failure): removed. A failed network call now means "Queued".
- V3 **P29** (5xx snackbar on mutation): applies only to non-queueable actions. Queueable mutations just queue.
- V3 boot step captions ("Still connecting…"): shown only if there's **no cache** to render.
- V3/V2 rule "client never computes dates": one exception, the provisional `logicalDate` for queued entries (§7.2).
- V3 **P05/P23** unchanged.

### 8.7 Copy

| Situation | Copy |
|---|---|
| Queued entry | "Queued · saved on this phone" |
| Syncing | "Syncing…" |
| Not counted | "{n} queued entries not counted yet. Totals update after sync." |
| Stale card | "Updated {relative time}" |
| Pace stale | "Pace as of {time}" |
| Offline-only fallback | "Offline · generic plan" |
| Needs connection | "Needs connection." |
| Synced | "{n} entries synced" |

No exclamation marks, no red for offline.

---

## 9. Backend Amendments (required)

| # | Change | Why |
|---|---|---|
| **C1** | `POST /api/logs` accepts `client_id` (UUID). Unique index `(user_id, client_id)`. On replay return the existing log with `200` (new log still `201`). Store `client_id` on the log and return it in log objects | **Mandatory** to prevent duplicate entries on retries |
| **C2** | `GET /health` returns `{"status":"ok","database":"connected","server_time":"<ISO>"}`; when MongoDB is unreachable return **HTTP 503** with `{"status":"degraded","database":"disconnected","server_time":"..."}` | Distinguishes `DB_DOWN`; enables clock-skew detection |
| **C3** | `POST /api/logs` timestamp rules: accept up to **+5 min** in the future (clock tolerance), accept up to **14 days** in the past; otherwise `422` with a short message | Predictable permanent-failure reasons |
| **C4** | `GET /api/auth/me` and login responses include `server_time`, `server_today` (already A2) and `day_cutoff_hours` | Provisional date rule and skew check |
| **C5** | `POST /api/auth/logout` is idempotent: already-revoked token returns `200` or `401`, both treated as done | Offline logout revoke |
| **C6** | Return structured errors: `{"code":"...","message":"..."}` on 4xx/401 so the client can distinguish the real API from a captive-portal page | Reliable `AUTH_EXPIRED` vs `UNREACHABLE` |

A batch endpoint (`/api/sync/batch`) is intentionally **not** required: for 1–3 users, sequential requests are fine.

---

## 10. Edge-Case Matrix

| Scenario | Expected behavior |
|---|---|
| Write offline, kill app, reopen offline | Entry present with "Queued" (write-ahead transaction) |
| POST succeeded, response lost | Replay with same `client_id` returns existing log; no duplicate (C1) |
| Edit a queued entry | Create payload updated; one request on sync |
| Delete a queued entry | Both ops removed; zero network calls |
| Delete a synced entry offline | Hidden at once (after undo window), `DELETE` queued; if it permanently fails the entry reappears with an error |
| Edit a synced entry offline | New text shown with "Edit queued"; extraction re-runs after sync |
| Offline for 3 days, entries from each day | Sync in order with their original timestamps; server assigns dates; entries older than 14 days fail permanently with a clear reason (C3) |
| Phone clock wrong | Skew warning (§6.4); entries beyond tolerance rejected `422` with "Phone clock looks wrong" |
| Day rolls over (4 AM) while offline | Provisional date uses the device clock; on reconnect `serverToday` refreshes and entries re-bucket by server date |
| 401 while queue has items | Queue paused and kept; after same-user login it resumes; different user can't flush it |
| Logout with queue | P40; token revoked later via `pending_revoke_token` |
| Backend up, DB down | `/health` 503 → red dot "Server is up, but its database is down." Writes queue; reads from cache |
| Slow server (> 10 s) | `TIMEOUT` after 2 failures; writes queue; no error popups |
| Captive Wi-Fi returning HTML | Classified `UNREACHABLE`, **not** logout |
| Rapid airplane-mode toggling | 1 s debounce; single-flight sync; no duplicate sends |
| App update with new cache schema | Cache wiped and refetched; **outbox/local_logs migrated, never wiped** |
| Two phones, same account | Logs independent; profile edits last-write-wins |
| Server rejects entry (422) | Marked `failed_permanent` for that entry only; others continue; dot stays green |
| Background worker and foreground both start | Lock row ensures one runs |
| Storage full | Composer error P44; text kept |

---

## 11. Test Plan and Acceptance

### 11.1 How to simulate
Airplane mode · Wi-Fi off, mobile data off · stop the backend process · stop only MongoDB (health 503) · add a 15 s delay on the server · return 503/500 from a proxy · return 429 · return a 401 with the correct JSON · return an HTML page with 200/401 (captive portal) · set the phone clock +10 min · kill the app mid-sync · reboot the phone with a non-empty queue.

### 11.2 Acceptance checklist
**Auth**
- [ ] Log in once; kill and reopen with airplane mode → opens Today from cache, still logged in.
- [ ] Backend down for a week → still logged in; no login screen.
- [ ] Revoke the session server-side → next online request ends the session once; queue preserved; same-user login resumes it.
- [ ] Logout offline works; token revoked later; cache and secure token cleared.

**Cache**
- [ ] After one online session, airplane mode shows Today, Days (last 2 months), current week/month insights tiles, profile and a future day's plan.
- [ ] Data older than 24 h refreshes by itself when the server is reachable; offline it shows "Updated N days ago" instead of vanishing.
- [ ] Insights is not fetched in prefetch; opening it online once caches it for 24 h.
- [ ] Future day offline with no cache shows the generic fallback labelled "Offline · generic plan".

**Connection card**
- [ ] Green + "Connected to server" when healthy.
- [ ] Each failure from §11.1 shows the matching one-line reason (§6.4) and red dot; a 422 does **not** turn it red; a 401 shows amber.
- [ ] Dot changes live without leaving the screen; Retry works; long-press copies the debug string.

**Queue**
- [ ] Offline entry appears instantly as "Queued" and survives app kill and reboot.
- [ ] Reconnect → entries sync automatically (foreground) in order, rows change Queued → Syncing → Reading… → Done with no flicker or duplicate rows.
- [ ] Replaying after a lost response creates no duplicate (C1 verified).
- [ ] Edit/delete of a queued entry coalesces (no extra network calls).
- [ ] Permanent rejection marks only that entry; the rest sync.
- [ ] Totals exclude queued entries and the footnote says so; after sync totals refresh.
- [ ] Logout with a non-empty queue shows P40.
- [ ] Background task syncs a closed app on a best-effort basis; otherwise the next open syncs.

**UX**
- [ ] No full-screen errors, no red for offline, no popups on open. Composer always enabled.

---

## 12. Build Order

1. **Storage:** SQLite schema (§3.2), migrations, per-user partitioning, backup exclusion.
2. **Backend C1–C6** (C1 and C2 first).
3. **Auth persistence:** boot-from-cache, 401-only logout, pending revoke token.
4. **Connection monitor:** classify(), snapshot, `/health` probe, debounce, integrate into the API client.
5. **Cache layer:** repositories with stale-while-revalidate, 24 h soft expiry, prefetch, housekeeping, "Updated"/"Pace as of" labels, fallbacks.
6. **Outbox + local entries:** write-ahead save, idempotency, coalescing, ID mapping.
7. **Sync engine:** single-flight, backoff, triggers, post-sync refresh, lock row.
8. **UI:** entry states, queue pill, not-counted footnote, Profile connection card, P40–P46, removal of V3 P20/P11b.
9. **Background workers** (WorkManager / BGTaskScheduler) using the same lock.
10. **Run §11:** test every row of the failure simulation list before release.
