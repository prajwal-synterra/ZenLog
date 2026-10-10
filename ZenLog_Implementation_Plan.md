# ZenLog — Implementation Plan (Personal Edition)

Scope: a personal app for 1–3 people, shipped as an APK, backend on Render, MongoDB, Gemini for extraction.
Every module below lists **Backend (API)**, **App (UI)**, data changes, edge cases, and a "done when" checklist.

## Contents

| # | Module | Effort (rough) |
|---|---|---|
| M1 | Server availability (Render keep-alive + cold-start UX) | 2–4 h |
| M2 | Logging core (backfill, structured log endpoint, idempotency, IST) | 1–2 days |
| M3 | Security & data safety (PIN login, export, backups) | 1 day |
| M4 | Quick actions (water buttons, saved meals, repeat) | 1–2 days |
| M5 | Insight cache (hash-based AI report reuse) | 3–5 h |
| M6 | Photo meal logging | 1–2 days |
| M7 | Packaged-food label scanner + rating (OCR) | 2–4 days |
| M8 | Notifications + Android home widget | 1–2 days |
| M9 | Weight history & trend | 0.5–1 day |
| M10 | Insights upgrades (heatmap, protein spread, late-eating, sleep) | 2 days |
| M11 | App distribution (config, version check, signing) | 3–5 h |
| M12 | Optional extras | as time allows |

Effort numbers are estimates assuming you already know FastAPI and Flutter. Treat them as relative sizes, not promises.

---

## 0. Read this first

### 0.1 What we are NOT building

Event sourcing / CRDT, React web dashboard, command palette, SSE / Mongo Change Streams, WASM voice, leucine-boolean and "anabolic window" features, catch-up that raises tomorrow's target. They solve scale or multi-client problems you don't have, or rest on weak evidence.

### 0.2 Assumptions to VERIFY (this plan was written without seeing your code)

| # | Check | Where it matters |
|---|---|---|
| A1 | Does `POST /api/logs` accept an explicit time, or does it use server time? | M2 |
| A2 | Is `logical_date` computed with a fixed `Asia/Kolkata` zone, stored, and indexed? | M2 |
| A3 | How does login work today (username only? token expiry? revoke on logout?) | M3 |
| A4 | Where is MongoDB hosted (Atlas M0? Render? local)? Do automated backups exist? | M3 |
| A5 | What does `GET /api/calendar` return per day (score, protein %, workout flag)? | M10 |
| A6 | Which Gemini model and SDK are you on, and what are the current free-tier limits in AI Studio? Gemini 1.5 models are old and likely retired. Keep the model name in an env var. | M5–M7 |
| A7 | Which local store does the Flutter app use for the offline queue (Hive / Isar / sqflite / Drift / prefs)? | M2, M4, M7 |
| A8 | Does `RENDER_EXTERNAL_URL` exist in your Render service environment? Render normally sets it for web services. | M1 |
| A9 | How many Render free services do you run? Render's free instance hours are shared per workspace (I recall 750 h/month; verify). One always-on service fits; two do not. | M1 |

### 0.3 Conventions for every new route

- Mounted under `/api`, protected by your existing auth dependency (except `/ping`, `/health`).
- Dates are logical dates `YYYY-MM-DD` (after the 4 AM rule). Timestamps are ISO-8601 **with offset**.
- Every write that can be retried carries a `client_id` (UUID v4 generated on the phone). The server treats a repeated `client_id` as the same request.
- **Do not change existing response shapes.** Add routes and fields. Remove old routes only after every phone runs the new APK.
- Gemini-calling routes return structured errors: `503 {"error":"ai_unavailable","retry_after":N}` on quota/429, so the app can queue and retry.
- Shared deterministic code lives in `app/core/` (timezone, scoring, stats) and gets pytest unit tests.

### 0.4 Build order and why

M1 first (it is your current pain and takes hours). M2 is the foundation: M4, M6 and M7 all create logs through the structured endpoint it introduces. M3 early because the backend is publicly reachable on Render. Then user-visible wins (M4–M7), then retention features (M8–M10), then distribution polish (M11).

---

## M1 — Server availability (Render keep-alive + cold-start UX)

### Goal
The backend should almost never be asleep when someone opens the app. When it is, the app should handle it gracefully.

### The honest part: why a self-ping loop is not enough
- An in-process loop **cannot wake a dead instance**. Once Render spins the service down, the loop is dead too. Only an inbound request from outside wakes it.
- The loop works only while the process is alive. After a redeploy, crash or restart, it stays cold until someone (or something) calls it.
- Ping at **10 minutes, not 14:30**. A 30-second margin against a 15-minute cutoff is too thin once you count network latency and timer drift.
- Reports indicate that a self-request through your *public* URL counts as inbound traffic (it goes through Render's proxy). Do not assume. Verify with the 24-hour test below.

So use three layers: (1) in-process loop, (2) an external pinger as the real safety net, (3) app-side wake-up handling.

### Backend (API)

| Route | Auth | Behaviour |
|---|---|---|
| `GET /ping` | none | Returns `{"ok": true}`. No DB access, so it's cheap and cannot fail on Mongo. |
| `GET /health` (existing) | none | Keep as is. It probes Mongo. Use it for your own checks, not for the 10-minute loop. |

`app/keepalive.py`:

```python
import asyncio, logging, os
import httpx

log = logging.getLogger("keepalive")

async def keepalive_loop() -> None:
    if os.getenv("KEEPALIVE_ENABLED", "true").lower() != "true":
        log.info("keepalive disabled")
        return
    base = os.getenv("RENDER_EXTERNAL_URL")          # set by Render; verify (A8)
    if not base:
        log.info("keepalive skipped: RENDER_EXTERNAL_URL not set")
        return
    interval = int(os.getenv("KEEPALIVE_INTERVAL_SEC", "600"))   # 10 min
    target = f"{base.rstrip('/')}/ping"
    async with httpx.AsyncClient(timeout=20) as client:
        while True:
            await asyncio.sleep(interval)
            try:
                r = await client.get(target)
                log.info("keepalive %s -> %s", target, r.status_code)
            except Exception as exc:                 # never let the loop die
                log.warning("keepalive failed: %s", exc)
```

Wire it into your existing lifespan (merge with the Mongo setup you already have):

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # ... existing startup (Mongo client, indexes) ...
    task = asyncio.create_task(keepalive_loop())
    yield
    task.cancel()
    # ... existing shutdown ...
```

Rules:
- Run **one** worker (plain `uvicorn`, or gunicorn with `-w 1`). Multiple workers each start their own loop.
- Add `httpx` to `requirements.txt` if it's not there.
- Env vars on Render: `KEEPALIVE_ENABLED=true`, `KEEPALIVE_INTERVAL_SEC=600`.
- Silence `/ping` in access logs if it clutters (uvicorn access-log filter), optional.

### External pinger (the real safety net)
- Create a free HTTP monitor on **UptimeRobot** or **cron-job.org** pointing at `https://<your-service>.onrender.com/ping`, every 5 minutes. Check their current free-tier limits.
- Why: it survives redeploys, crashes and restarts, and it emails you when the service is down.
- Optional: a GitHub Actions scheduled workflow with `curl`. Scheduled runs can be delayed by several minutes, so don't make it your only layer.
- Alternative if this keeps hurting: Render's paid always-on instance, or a different host. Decide on what your time is worth, not on principle.

### App (UI)
- **`WakeService`** (Dart): on app launch and on `AppLifecycleState.resumed`, call `GET /ping`. Retry up to ~6 times with 5 s spacing (covers a ~30–60 s cold start).
- **Banner** on Today and Me: "Waking server… (can take up to a minute)" shown only while a wake attempt is running; replaced by the normal connection pill when it succeeds.
- **HTTP client timeouts:** set connect/receive timeouts to ~60–75 s for the first request after idle, ~15 s otherwise. Keep a "warm" flag that flips to true after any successful response and back to false after 12 minutes without one.
- **Offline queue:** do not flush the queue until `/ping` succeeds. This stops a stack of timeouts and duplicate retries (which M2's `client_id` also guards against).
- Me → "This Device & Connection": show "Server: Awake / Waking / Unreachable" and last successful ping time.

### Edge cases
- Render logs fill with ping lines. Fine, or filter them.
- If you move to a paid instance, set `KEEPALIVE_ENABLED=false`.
- Check Render's current free-tier terms on keep-alive traffic before relying on this long term.

### Done when
- [ ] `/ping` responds in under 100 ms and touches no database.
- [ ] External monitor shows green for 24 h.
- [ ] After 30+ minutes with no app use, the first app request returns in under ~2 s (no cold start).
- [ ] Kill the service manually: the app shows the "Waking server" banner, recovers, and flushes the queue without duplicates.

---

## M2 — Logging core (backfill, structured endpoint, idempotency, IST)

### Goal
Logging into any past day works correctly and safely, and every other feature (quick water, saved meals, photos, labels) can create logs through one endpoint without touching Gemini.

### Data model changes (`logs` collection)

| Field | Type | Notes |
|---|---|---|
| `logged_at` | datetime (UTC) | When the event happened (user-claimed). New. |
| `logical_date` | string `YYYY-MM-DD` | Derived from `logged_at` with the IST + 4 AM rule. Stored, not recomputed per query. |
| `tz` | string | Default `"Asia/Kolkata"`. Future-proofing only. |
| `client_id` | string (UUID) | Idempotency key. |
| `source` | enum | `text`, `water_quick`, `saved_meal`, `photo`, `label`, `repeat` |
| `meta` | object | Free-form per source (photo confidence, scan_id, saved_meal_id…). |
| `created_at`, `updated_at` | datetime | Server times. |

Indexes:
- `(user_id, logical_date)` for day views.
- `(user_id, client_id)` **unique, sparse** for idempotency.

Migration script `scripts/migrate_logical_date.py`: for existing logs without `logged_at`/`logical_date`, set `logged_at` from your current timestamp field and compute `logical_date`. Run it once on a copy first.

### Backend (API)

`app/core/timeutil.py`:

```python
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")
BOUNDARY_HOURS = 4

def logical_date(dt: datetime, tz=IST) -> str:
    """dt must be timezone-aware. 00:00–03:59 local belongs to the previous day."""
    local = dt.astimezone(tz)
    return (local - timedelta(hours=BOUNDARY_HOURS)).date().isoformat()
```

Add `tzdata` to `requirements.txt` (slim Docker/Render images may lack the system zoneinfo).

| Route | Change | Behaviour |
|---|---|---|
| `POST /api/logs` | **extend** | Body gains optional `logged_at` (ISO with offset) and `client_id`. Missing `logged_at` → server now. Compute and store `logical_date`. Same `client_id` again → return the existing log (HTTP 200, not an error). Reject `logged_at` more than 5 min in the future (`422`). Extraction still runs in the background, as today. |
| `PUT /api/logs/{id}` | **extend** | May include `logged_at` to move an entry to another time/day; recompute `logical_date`; re-run extraction only if `raw_text` changed. |
| `POST /api/logs/structured` | **new** | Creates a log whose macros are already known: `{raw_text, extracted:{protein_g,calories,water_ml,...}, source, meta?, logged_at?, client_id}`. Marks `extraction_status:"done"`. **No Gemini call.** Used by M4, M6, M7. |
| `POST /api/logs/{id}/repeat` | **new** | Copies an entry (raw text + extracted values) to now, or to `logged_at` if provided; `source:"repeat"`. |

Every create/update/delete must call a small `touch_day(user_id, logical_date)` helper that (a) marks that day's cached AI verdict stale and (b) lets M5's hash logic notice changed data. Put this in one function so you can't forget a code path.

### App (UI)
- **Composer on a past day:** a banner above the input: "Logging to Tue, 6 Oct". Below it, time chips: Breakfast (08:30) · Lunch (13:00) · Dinner (20:30) · Custom. Default chip = last used. Today uses "now".
- **Time picker and the 4 AM rule:** the picker for a logical day runs 04:00 → 03:59 next morning. A "01:30" pick on "Tue" is stored as Wed 01:30 calendar time, which resolves back to Tue's logical day. Show "(after midnight)" next to those times.
- Generate `client_id` when the composer is submitted, store it with the queued item, and reuse it on every retry.
- Entry overflow menu: **Change time / day** (calls `PUT /api/logs/{id}` with `logged_at`).
- Past-day cards (pace, verdict) refresh after a backfill. Show "Data changed since last review" on the day verdict if it was already generated (see M5).

### Edge cases
- Offline backfill queue order: send in the order created; the server's `client_id` makes duplicates harmless.
- DST does not apply in IST, but still use aware datetimes everywhere. Never use naive `datetime.now()`.
- A user who changes phone timezone (travel): the app should send the offset it actually used. Server still uses `Asia/Kolkata` for the logical-date rule unless you later add per-user timezone.

### Done when
- [ ] Logging "dinner" on last Tuesday at 20:30 appears under Tuesday's totals and calendar dot.
- [ ] A 01:30 entry on Wednesday morning lands on Tuesday; 04:00 lands on Wednesday.
- [ ] Sending the same `client_id` twice creates one log.
- [ ] `POST /api/logs/structured` creates a log with no Gemini request in server logs.
- [ ] pytest: `logical_date` boundary cases (03:59, 04:00, 23:59, 00:00).

---

## M3 — Security & data safety (PIN login, export, backups)

### Goal
Your backend is on a public URL. Make sure a guessed username isn't enough to read someone's food and sleep history, and make sure one bad day doesn't erase months of data.

### 3.1 PIN login

Backend:
- `users.pin_hash` (argon2 or bcrypt via `passlib`).
- `POST /api/auth/login` body becomes `{username, pin}`. Constant-time verify. Keep the old username-only path only until every user has a PIN, then remove it.
- **Setting the first PIN must not be an open route**, or whoever calls it first owns the account. Use a CLI script instead: `python scripts/set_pin.py <username>` run by you against production.
- Brute-force protection: `login_attempts` collection with a TTL index. 5 failures per username/IP → 15-minute lockout, returns `429`. (In-memory counters reset whenever Render restarts.)
- Verify token handling (A3): tokens expire, are revoked on `POST /api/auth/logout`, and are stored hashed if you store them.

App:
- Login screen gets a 4–6 digit PIN field (numeric keypad).
- Optional: local biometric gate on app open with `local_auth` (device-only, no backend change).
- Wrong PIN → generic "Username or PIN incorrect." Lockout → "Too many attempts, try in 15 minutes."

### 3.2 Export

Backend:
- `GET /api/export?format=json` streams a zip/JSON of the caller's own logs, day cycles (sleep/wake), weights, saved meals and products. `format=csv` returns logs only.
- Only ever the authenticated user's data.

App:
- Me → "Export my data". Uses `share_plus` (or `file_saver`) so you can send the file to Drive or WhatsApp.

### 3.3 Backups

- Check A4. If you're on Atlas M0, don't assume automated backups exist (verify in the Atlas UI).
- A scheduled GitHub Actions job (private repo, secret `MONGODB_URI`): install MongoDB Database Tools, run `mongodump --uri "$MONGODB_URI" --gzip --archive=zenlog.gz`, upload as an artifact with ~14-day retention. Weekly is enough for 3 users.
- Atlas must allow the runner's IPs (on M0 this usually means `0.0.0.0/0`; weigh that against your PIN protection).
- **Test a restore once** into a throwaway database. A backup you've never restored is not a backup.

### Done when
- [ ] Username-only login no longer works for any user.
- [ ] 6th wrong PIN is locked out, even after a Render restart.
- [ ] Export file opens and contains your last 30 days.
- [ ] Weekly backup artifact exists and a restore test succeeded.

---

## M4 — Quick actions (water buttons, saved meals, repeat)

### Goal
Cut daily logging to one or two taps for the things you repeat constantly, with zero Gemini calls and identical macros every time.

### Backend (API)

All creation goes through M2's `POST /api/logs/structured`.

**Quick water**

| Route | Behaviour |
|---|---|
| `POST /api/logs/structured` with `{source:"water_quick", raw_text:"250 ml water", extracted:{water_ml:250}, client_id, logged_at?}` | Instant log, no AI. |

No new route is needed. Undo uses the existing `DELETE /api/logs/{id}`.

**Saved meals** — new collection `saved_meals`:

```
{ _id, user_id, name, raw_text, extracted:{protein_g, calories, water_ml?, ...},
  use_count, last_used_at, pinned, created_from_log_id?, created_at, updated_at }
```

| Route | Behaviour |
|---|---|
| `GET /api/saved-meals?sort=frequent\|recent&limit=20` | List for the chip row and manager screen. |
| `POST /api/saved-meals` | Create from `{log_id}` (copies raw text + extracted values) or manually from a body. |
| `PUT /api/saved-meals/{id}` | Rename, edit macros, pin/unpin. |
| `DELETE /api/saved-meals/{id}` | Remove. |
| `POST /api/saved-meals/{id}/log` | Body `{portion:1.0, logged_at?, client_id}`. Multiplies macros by `portion` in code, creates a structured log with `source:"saved_meal"`, increments `use_count`, sets `last_used_at`. |
| `GET /api/saved-meals/suggestions` | Normalized `raw_text` (lowercase, collapsed spaces) logged 3+ times in the last 30 days and not yet saved. The app asks "Save as favorite?". |

Portion maths is deterministic: `value * portion`, rounded to 1 decimal for grams and to whole kcal.

### App (UI)
- **Water row on the Pace card:** `+250` and `+500` buttons, long-press for a custom amount. Optimistic update (water bar moves instantly), light haptic, "Undo" snackbar for ~5 s.
- **Favorites chip row** above the composer (top ~6 by use, pinned first). Tap a chip → portion stepper sheet (0.5× / 1× / 1.5× / 2×) → Log. Long-press a chip → edit / delete.
- **Entry overflow menu** on every journal entry: "Save as favorite", "Repeat today".
- Me → "Saved meals" manager: list, rename, edit macros, delete, pin.
- Suggestion prompt: after an entry finishes extraction, if the backend suggests it, show a one-time-per-text dismissible card "You've logged this 3 times. Save it?".

### Edge cases
- Editing a saved meal must not rewrite past logs (they hold copies).
- If a saved meal's macros are empty (extraction failed originally), block saving and ask for manual values.
- Offline: quick water and saved-meal logs are queued with a `client_id` like any log and show immediately in the local totals.

### Done when
- [ ] Tapping `+250` moves the water bar immediately and creates a log with no Gemini request.
- [ ] Logging a favorite at 1.5× gives exactly 1.5× the stored protein and calories.
- [ ] Offline taps sync once with no duplicates.

---

## M5 — Insight cache (hash-based AI report reuse)

### Goal
Stop paying Gemini calls for reports whose data hasn't meaningfully changed, and replace the "delta threshold + background tasks" idea with something simple.

### Data model
New collection `insight_cache`:

```
{ user_id, kind:"week"|"month"|"day", range_start, range_end,
  input_hash, report, prompt_version, model, generated_at }
```

Unique index `(user_id, kind, range_start, range_end)`.

### Hash design (`app/core/insight_hash.py`)

```python
import hashlib, json

def input_hash(days, targets, goal, prompt_version) -> str:
    # Round values so tiny edits (500 ml -> 600 ml) don't invalidate the report.
    rows = [[d.logical_date,
             round(d.protein_g / 5) * 5,
             round(d.calories / 50) * 50,
             round(d.water_ml / 250) * 250,
             bool(d.workout),
             d.sleep_min // 30] for d in days]
    payload = {"d": rows, "t": targets, "g": goal, "v": prompt_version}
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
```

Rounding is your "threshold". Values on a rounding boundary can flip on tiny edits. That's acceptable at this scale.
Include any M10 flags (late-eating %, protein-spread, sleep variance) in the payload once they exist, and bump `prompt_version` whenever you change the prompt.

### Backend (API)

| Route | Behaviour |
|---|---|
| `GET /api/insights/{period}` (new behaviour) | Returns `{status:"fresh"\|"stale"\|"none", report?, generated_at?}`. **Never calls Gemini.** `stale` = the hash of current data differs from the cached one. |
| `POST /api/insights/{period}/generate` | Body `{force?:bool}`. Keeps your 3-day minimum. If hash matches the cache and `force` is false → return cached. Otherwise call Gemini, store, return. Cooldown: one regeneration per period per 10 minutes. |
| `GET /api/days/{day}/verdict` and `POST /api/days/{day}/verdict` | Same pattern for the AI day review, if it isn't already cached. |

Compatibility: keep your existing `GET /api/insights/weekly|monthly` working for old APKs. Remove them after the new app is installed everywhere. Fall back to a stale cached report if Gemini errors (return it with `status:"stale"` plus a warning).

### App (UI)
- Insights screen loads the cached report instantly with "Updated 2 h ago".
- If `status == stale`: chip "Data changed. Refresh review" + Refresh button.
- If `none` and fewer than 3 days logged: existing "Log 3 days to unlock" state.
- Loading state while generating (5–15 s), error state that keeps showing the old report.
- Day verdict card shows the same stale chip after a backfill.

### Done when
- [ ] Opening Insights twice causes zero Gemini calls.
- [ ] Changing water 500 → 600 ml does not mark the weekly report stale; adding a missing 40 g protein meal does.
- [ ] Gemini failure still shows the last report.

---

## M6 — Photo meal logging

### Goal
Photograph a plate (plus an optional hint like "ate half") and get an editable estimate. Always confirm before logging.

### Backend (API)

A two-step flow so abandoned photos never create junk logs.

| Route | Behaviour |
|---|---|
| `POST /api/logs/photo/analyze` (multipart: `image`, `text?`) | Validates type (jpeg/png/webp) and size (≤ 3 MB), strips EXIF, sends bytes to Gemini with a JSON schema, returns a draft. **Does not save a log and does not store the image.** |
| `POST /api/logs/structured` with `source:"photo"` | Called by the app after the user confirms or edits the draft. |

Draft response:

```json
{
  "items": [
    {"name": "Paneer curry", "portion": "1 katori (~150 g)", "protein_g": 14, "calories": 290, "confidence": 0.6}
  ],
  "total": {"protein_g": 14, "calories": 290},
  "notes": "Oil content uncertain.",
  "estimate": true
}
```

Gemini call rules:
- Model name from env (A6). Temperature 0–0.2. Request JSON output with a response schema.
- Prompt: identify each distinct food, estimate portion in common household units, give protein and calories, give a 0–1 confidence per item, never invent items not visible, and apply the user's hint ("ate half") to the portion.
- Rate limiting: per-user cap (e.g., 20 AI calls/hour) in Mongo or memory; on Gemini 429 retry once after ~2 s, then return `503 {"error":"ai_unavailable","retry_after":30}`.
- Realistic expectation: portion and oil estimates from a photo are rough. Show the number as an estimate, always editable.

### App (UI)
- Composer dock gets a camera icon → sheet: **Meal photo**, **Scan label** (M7), **Gallery**.
- Capture with `image_picker` using `maxWidth: 1280` and `imageQuality: 80` so uploads stay small.
- While analyzing: skeleton card "Looking at your plate…".
- **Review sheet:** one row per item with editable protein / calories, a portion slider (0.25×–2×), per-item delete, "Add item", total at the bottom, an "Estimate" badge. Buttons: **Log it** / **Retake**.
- On confirm: build `raw_text` from the item names ("Photo: paneer curry, 2 rotis"), call `/api/logs/structured`. The entry shows a camera tag.
- **Offline:** keep the photo in app storage with a "Waiting to analyze" entry; when back online, analyze and notify "1 photo meal ready to review". Delete the local photo after confirm.

### Edge cases
- Non-food photo → `items: []` and the UI says "I couldn't find food in this photo".
- Large dishes with hidden ingredients (gravy, oil) get low confidence. Surface that in the UI instead of hiding it.

### Done when
- [ ] Analyze returns a draft in under ~15 s and creates no log or stored image.
- [ ] Editing a value in the review sheet is what gets saved.
- [ ] 429 from Gemini shows a friendly retry message and doesn't lose the photo.

---

## M7 — Packaged-food label scanner + rating (OCR)

### Goal
Photograph a packaged product's nutrition label (and optionally ingredients/front), get the numbers extracted, a **transparent 0–100 score**, and the impact of eating a chosen amount on today's targets. Log it in one tap if you eat it.

### Design decisions
- **OCR engine = Gemini vision.** One call does text reading and structuring. Skip a separate on-device OCR (ML Kit) unless you need fully offline scanning later. It makes parsing nutrition tables harder, not easier.
- **Extraction by AI, everything else by code.** Normalization, sanity checks, scoring and day impact are deterministic.
- **The score is a custom heuristic, not Nutri-Score and not medical advice.** Say so in the UI.
- **Never auto-log.** The user confirms and can edit every number, because label OCR misreads.
- Optional barcode lookup (Open Food Facts) is a later add-on. Check its coverage for Indian products before investing.

### Data model
- `food_scans` (TTL 7 days): `{scan_id, user_id, product, per_100g, per_serving, ingredients, flags, score, validation, created_at}`. Deleted automatically unless saved.
- `products` ("My Products"): `{_id, user_id, name, brand, name_key, pack_size_g, serving_size_g, per_100g, ingredients, flags, score_by_goal?, times_logged, created_at}`. Unique `(user_id, name_key)`.

### Backend (API)

| Route | Behaviour |
|---|---|
| `POST /api/foods/scan` (multipart: `images[]` 1–3, ≤ 3 MB each) | Gemini extraction → normalize → validate → score. Stores a `food_scans` doc and returns `ScanResult`. No log created. |
| `PUT /api/foods/scan/{scan_id}` | User corrections to any extracted number or serving size. Recomputes validation + score. |
| `POST /api/foods/scan/{scan_id}/evaluate` | Body `{servings?: number, grams?: number}`. Returns portion macros and `day_impact` for the scan's day (default today). |
| `POST /api/foods/scan/{scan_id}/log` | Body `{servings\|grams, logged_at?, client_id}`. Creates a log through the M2 logic with `source:"label"`, `meta:{scan_id, score, grade}`. |
| `POST /api/foods/products` | Save the scan to My Products (dedupe by `name_key`). |
| `GET /api/foods/products?q=` | Search/list My Products. |
| `POST /api/foods/products/{id}/log` | Log a saved product by portion. No AI call. |
| `DELETE /api/foods/products/{id}` | Remove. |
| *(optional)* `GET /api/foods/barcode/{code}` | Open Food Facts lookup; falls back to scan. |

`ScanResult`:

```json
{
  "scan_id": "…",
  "product": {"name": "…", "brand": "…", "pack_size_g": 200, "serving_size_g": 30, "servings_per_pack": 6.7},
  "per_100g": {"energy_kcal": 480, "protein_g": 6, "carbs_g": 70, "sugar_g": 25, "fat_g": 20,
               "sat_fat_g": 9, "trans_fat_g": 0.1, "fiber_g": 2, "sodium_mg": 400},
  "per_serving": {"energy_kcal": 144, "...": "..."},
  "ingredients": ["wheat flour", "sugar", "palm oil", "..."],
  "flags": ["palm oil", "added colour (INS)"],
  "validation": {"ok": false, "warnings": ["energy_mismatch"], "missing": ["fiber_g"]},
  "score": {"value": 14, "grade": "Skip",
            "reasons": ["High sugar: 25 g/100 g", "High saturated fat: 9 g/100 g", "Low protein density"],
            "breakdown": {"protein": 5.0, "sugar": -25.0, "sat_fat": -15.0}},
  "confidence": 0.8
}
```

**Gemini prompt rules (extraction only):**
- Temperature 0. JSON output with a response schema.
- "Return only values printed on the label. Use `null` for anything not visible. Do not estimate or infer missing values. Record the unit and whether each column is per 100 g/ml or per serving. Return ingredients as a list in printed order."
- Handle label quirks in code, not in the prompt:
  - If only per-serving is present, derive per-100 g as `value / serving_size_g * 100`. If serving size is missing, mark the field missing and ask the user.
  - If the label gives salt instead of sodium: `sodium_mg ≈ salt_g × 400`.
  - kJ → kcal: divide by 4.184.
  - Treat per-100 ml (drinks) the same as per-100 g and mark `is_liquid`.

**Sanity checks (`app/core/label_validation.py`):**

```python
def validate(n):
    warnings = []
    est = 4 * ((n.protein_g or 0) + (n.carbs_g or 0)) + 9 * (n.fat_g or 0)
    if n.energy_kcal and abs(est - n.energy_kcal) / n.energy_kcal > 0.20:
        warnings.append("energy_mismatch")          # likely misread number
    if (n.sugar_g or 0) > (n.carbs_g or 0): warnings.append("sugar_gt_carbs")
    if (n.sat_fat_g or 0) > (n.fat_g or 0): warnings.append("satfat_gt_fat")
    return warnings
```

**Scoring (`app/core/scoring.py`) — v1 heuristic, per 100 g, goal-aware.** Constants live in config so you can tune them.

```python
GOAL_W = {
  "muscle_gain": {"protein": 1.4, "calories": 0.3, "sugar": 1.0},
  "fat_loss":    {"protein": 1.2, "calories": 1.3, "sugar": 1.2},
  "maintenance": {"protein": 1.0, "calories": 0.6, "sugar": 1.0},
  "mindfulness": {"protein": 0.8, "calories": 0.6, "sugar": 1.2},
}
BASE = 55

def clamp(x, lo, hi): return max(lo, min(hi, x))

def score_product(n, ingredients, goal):
    w = GOAL_W.get(goal, GOAL_W["maintenance"])
    kcal = max(n.energy_kcal or 0, 1)
    prot_per_100kcal = (n.protein_g or 0) / kcal * 100
    pts = {
      "protein":   clamp(prot_per_100kcal * 4, 0, 25) * w["protein"],
      "fiber":     clamp((n.fiber_g or 0) * 2, 0, 10),
      "sugar":    -clamp(((n.sugar_g or 0) - 5) * 1.25, 0, 25) * w["sugar"],
      "sat_fat":  -clamp(((n.sat_fat_g or 0) - 1.5) * 2.0, 0, 15),
      "sodium":   -clamp(((n.sodium_mg or 0) - 120) * 0.03125, 0, 15),
      "trans_fat": -10 if (n.trans_fat_g or 0) > 0.2 else 0,
      "additives": -min(9, 1.5 * len(detect_flags(ingredients))),
    }
    if prot_per_100kcal < 8:   # energy density only hurts when protein doesn't offset it
        pts["energy"] = -clamp((kcal - 150) / 20, 0, 10) * w["calories"]
    if (n.protein_g or 0) < 2 and (n.fiber_g or 0) < 1 and (n.sugar_g or 0) > 8:
        pts["empty_calories"] = -15          # sodas, sweet drinks, candy
    value = round(clamp(BASE + sum(pts.values()), 0, 100))
    grade = ("Great" if value >= 70 else "Okay" if value >= 50
             else "Occasional" if value >= 30 else "Skip")
    reasons = top_reasons(pts, n)            # 3 largest-magnitude contributors -> text templates
    return {"value": value, "grade": grade, "reasons": reasons, "breakdown": pts}
```

`detect_flags` is a keyword list you maintain (palm oil, hydrogenated, maltodextrin, glucose/fructose syrup, artificial sweetener names, INS-numbered colours/preservatives).

These constants are a starting point, worked out by hand. Create a fixtures file `tests/fixtures/products.json` with 10–15 products you know (whey, oats, Greek yogurt, roasted chana, biscuits, chips, a cola, a protein bar…) and a test asserting the **rank order** you expect. Tune constants until the order feels right, then freeze it.

**Day impact (`/evaluate`):** for the chosen amount, return portion macros plus: `% of daily calorie budget (if set)`, `% of remaining protein`, and a one-line deterministic summary, e.g. "Adds 12 g protein (27% of what you still need) for 310 kcal (14% of today's budget)." Pull today's totals from the same logic as `GET /api/days/{day}/view`.

Rate limits and errors: the same AI limiter as M6. If extraction confidence is under ~0.5 or all key fields are missing, return `422 {"error":"label_unreadable"}` with a hint to retake the nutrition-table photo.

### App (UI)
- **Scan label flow** (composer camera sheet → Scan label):
  1. Step 1 (required): "Photograph the nutrition table." Tips: fill the frame, avoid glare, flat surface.
  2. Step 2 (optional): ingredients list. Step 3 (optional): front of pack for the product name.
  3. Skeleton "Reading label…".
- **Result screen:**
  - Big score ring with grade word (colour **and** text, not colour alone) and the 3 reasons below it.
  - Editable per-100 g table. Rows flagged by validation get a highlight and a banner: "Calories don't match the macros — check the highlighted numbers."
  - Ingredient flag chips.
  - **Amount selector:** servings stepper, grams field, and "whole pack" button.
  - **Impact on today:** protein and calorie bars showing before/after.
  - Buttons: **Log it**, **Save to My Products**, **Rescan**.
  - Footnote: "Score is a rough guide based on label numbers, not medical advice."
- **My Products screen** (from the composer sheet and Me): search, tap → portion sheet → Log (no AI).
- Optional later: **Compare** two products side by side (reuse the stored scores).

### Edge cases
- Multi-column labels ("as sold" / "as prepared"): ask the user which column to use (a chooser if Gemini reports both).
- Regional label formats (FSSAI): fields like "Total sugars" vs "Added sugars". Map to `sugar_g`, store `added_sugar_g` separately when present.
- Photos are processed and discarded. Don't store images server-side.
- Don't show a score when key fields (energy, protein, sugar, fat) are missing; show "Not enough data to score" and let the user fill them in.

### Done when
- [ ] A clear label photo returns structured values and a score in under ~15 s.
- [ ] A deliberately misread calorie value triggers `energy_mismatch` and the UI highlight.
- [ ] Rank-order test over your fixture products passes.
- [ ] "Log it" creates a log with correct scaled macros and no second AI call.
- [ ] Saving a product and re-logging it works offline-queued with no duplicate.

---

## M8 — Notifications + Android home widget

### Goal
Turn your existing pace maths into nudges and a glanceable widget. Nothing here needs a push server.

### Backend (API)
No new routes are required. The app already gets pace data from `GET /api/days/{day}/view`. Keep reminder settings **on the device**, which is fine for 1–3 people.

### App (UI)

**Settings (Me → Reminders):**
- Water reminders: on/off, window (e.g., 09:00–21:00), interval (1.5 h / 2 h / 3 h).
- Protein nudge: on/off, check time (default 19:00), threshold (default: below 60% of target).
- "Log your day" nudge: on/off, time (default 21:30), only if nothing logged since a chosen hour.
- "Send test notification" button.

**Implementation:**
- `flutter_local_notifications` + `timezone`. Create Android notification channels (Water, Nudges).
- Android 13+: request `POST_NOTIFICATIONS` at runtime when the user enables the first reminder.
- Fixed-time reminders (water, log-your-day): schedule inexact repeating/daily notifications to avoid the exact-alarm permission.
- **Conditional nudges** (protein behind pace): a `workmanager` periodic task (minimum period 15 min; use ~1 h) reads cached day totals and decides whether to fire. Skip it if you can't be bothered; a fixed 19:00 "check your protein" notification is a fine fallback.
- Tapping a notification deep-links to Today with the composer focused.
- Respect the 4 AM rule: "today" for a nudge at 01:00 is still the previous logical day.

**Home-screen widget (`home_widget` package):**
- Shows protein `x / target g`, water `x / target ml`, and a "+250 ml" button.
- After every sync or local update, write values via `HomeWidget.saveWidgetData` and call `HomeWidget.updateWidget`.
- Requires native Android pieces: an `AppWidgetProvider` (Kotlin), a layout XML, and a registered receiver in `AndroidManifest.xml`.
- Tap on the widget opens the app on Today.

### Edge cases
- Some phone brands (Xiaomi/Oppo/Vivo/Samsung battery managers) kill background tasks aggressively. Add an in-app tip: "Allow ZenLog to run in background / disable battery optimization".
- Don't nudge when the day is already "Targets met".
- Cap nudges at one per kind per day to avoid alert fatigue (an explicit goal from your own design doc).

### Done when
- [ ] A test notification arrives and deep-links correctly.
- [ ] Water reminders fire only inside the chosen window.
- [ ] The widget updates within a minute of logging.

---

## M9 — Weight history & trend

### Goal
Replace the single `weight_kg` field with a dated history, a smoothed trend, and automatic g/kg updates.

### Data model
New collection `weight_logs`: `{user_id, logical_date, weight_kg, created_at, updated_at}`, unique `(user_id, logical_date)`.

### Backend (API)

| Route | Behaviour |
|---|---|
| `PUT /api/weight/{day}` | Upsert `{weight_kg}`. Validate 20–300 kg. If `day` is the latest weigh-in, also update `users.weight_kg` so protein g/kg stays current. |
| `DELETE /api/weight/{day}` | Remove. If it was the latest, set `users.weight_kg` to the previous entry (or leave unchanged if none). |
| `GET /api/weight?from=&to=` | Raw points. |
| `GET /api/weight/trend?days=30` | Points + 7-day moving average + `delta_kg` over the window + `kg_per_week`. Computed in Python. |

Use the moving average, not raw points, for any message. Daily weight swings from water and food.

### App (UI)
- Me → Body Metrics: "Log weight" sheet (numeric stepper, date defaults to today, 0.1 kg steps).
- Mini chart (raw dots + moving-average line) and "30-day change: −0.8 kg (≈ −0.2 kg/week)".
- Goal-aware one-liner (deterministic text only, no medical advice): Fat Loss → shows rate; Muscle Gain → shows rate; Maintenance → "Stable within ±0.5 kg".
- Optional toggle: weekly "Weigh-in?" prompt on the morning flow, only if no weight in the last 7 days, always skippable.

### Edge cases
- Backdated weights must not overwrite `users.weight_kg` unless they are the latest entry.
- Show "Not enough data" for trends with fewer than 3 points.

### Done when
- [ ] Logging a weight updates g/kg on the Me screen.
- [ ] Deleting the latest weight reverts to the previous one.
- [ ] Trend ignores one-day spikes (check with a fake +1.5 kg day).

---

## M10 — Insights upgrades (heatmap, protein spread, late-eating, sleep)

### Goal
Longer-term patterns, all computed deterministically from data you already collect, then fed as flags into the weekly AI prompt.

### Backend (API)

New helpers in `app/core/stats_ext.py`; expose via these routes. Keep existing stats routes unchanged and add an `extended` object to the weekly/monthly responses.

| Route | Returns |
|---|---|
| `GET /api/stats/heatmap?weeks=12` | Per day: `{date, protein_pct, calories, workout, score}`. Reuse `GET /api/calendar` if it already returns these (A5). Add `protein_pct` if missing. |
| `GET /api/stats/weekly` / `monthly` → `extended` | `protein_spread`, `late_eating`, `sleep` objects (below). |

**Protein spread:** group protein entries that are close in time into one "meal", then count meals that reach a per-meal threshold.

```python
def protein_meals(entries, gap_min=45):
    meals, cur = [], None
    for e in sorted(entries, key=lambda e: e.logged_at):
        if (e.protein_g or 0) <= 0:
            continue
        if cur and (e.logged_at - cur["last"]).total_seconds() <= gap_min * 60:
            cur["protein_g"] += e.protein_g
            cur["last"] = e.logged_at
        else:
            if cur: meals.append(cur)
            cur = {"start": e.logged_at, "last": e.logged_at, "protein_g": e.protein_g}
    if cur: meals.append(cur)
    return meals
```

Per-meal threshold: default about `0.4 g/kg` of body weight, clamped to 20–40 g. This is a commonly cited ballpark, not a precise physiological line. Make it editable in Me. Output per day: `meals: [{time, protein_g}]`, `meals_at_threshold`.

**Late-eating:**
- `late_calorie_pct` = calories logged after a cutoff (default 21:00, editable) ÷ total calories, using entry times within the logical day (so after-midnight snacks count as late).
- `last_meal_to_sleep_min` = bedtime − time of the last entry with calories, when sleep is recorded.
- Weekly Gemini prompt gets flags such as `[LATE_EATING: 42% after 21:00]` only when the number is notable.

**Sleep:**
- `bedtime_sd_min`: standard deviation of bedtime, measured in minutes since 18:00 (avoids the midnight wrap problem).
- `avg_wake_time`, `avg_sleep_min`.
- `short_sleep_effect`: workout completion on the next day after sleep < 6 h vs ≥ 7 h. Return only when each bucket has at least 5 days; otherwise `null` (the UI says "not enough data yet"). Treat it as a hint, not a finding.

Add all these values to the M5 hash input and bump `prompt_version`.

### App (UI)
- **Consistency heatmap card:** 7 rows × N weeks custom `GridView` (no package needed). Four intensity levels of one hue by `protein_pct`; a small dumbbell dot on workout days; today outlined. Tap a cell → bottom sheet with the day summary and "Open in Today".
- **Protein spread card:** one stacked bar per day with a segment per meal, a dashed line at the per-meal threshold, and "3 of 4 days had 3+ solid protein meals".
- **Late-eating tile:** "% calories after 21:00" and "avg gap last meal → sleep".
- **Sleep consistency tile:** bedtime variation ("±48 min") and the short-sleep hint when available.
- Me → "Meal timing settings": per-meal protein threshold, late-eating cutoff time.

### Done when
- [ ] Two entries 20 minutes apart (eggs + whey) count as one meal.
- [ ] A 00:30 snack counts as late-eating for the previous logical day.
- [ ] Sleep variance doesn't blow up for bedtimes that straddle midnight.
- [ ] The heatmap renders 12 weeks without jank on your phone.

---

## M11 — App distribution (config, version check, signing)

### Goal
Sideloaded APKs don't auto-update. Give your friends a way to learn that a new build exists, and don't break updates through signing mistakes.

### Backend (API)

| Route | Behaviour |
|---|---|
| `GET /api/app/config` (no auth) | `{latest_version_code, latest_version_name, min_supported_version_code, apk_url, notes, features:{photo:true, label_scan:true, ...}}`. Source it from env vars or a small JSON file in the repo. |

- `min_supported_version_code` lets you force an update when a backend change breaks old builds.
- `features` are simple on/off switches so you can disable a flaky feature (e.g., photo analysis when Gemini quota is exhausted) without shipping a new APK.
- The app sends `X-App-Version: <versionCode>` on requests. The backend can log it and reject versions below the minimum with `426`.

### App (UI)
- On launch (after `WakeService`): call `/api/app/config`, compare with `package_info_plus` build number.
- If newer: dialog "Update available — what's new" → opens `apk_url` with `url_launcher`. Android downloads it; the user installs.
- If below `min_supported_version_code`: a blocking "Please update" screen.
- Host APKs on a public GitHub Release or a Drive link with direct download. A private link needs auth and breaks for friends.

### Signing and versioning checklist
- Generate **one upload/release keystore**, back it up in two places (and its passwords). If you lose it or change it, installed apps can't be updated. Users would have to uninstall and lose local data.
- Increase `versionCode` for every build (`pubspec.yaml` build number).
- Always build release APKs with the same keystore (`flutter build apk --release`).
- Enable `REQUEST_INSTALL_PACKAGES` only if you later add in-app installing (`ota_update`). Opening the download link is enough for now.

### Done when
- [ ] Installing build N+1 over build N keeps login and local data.
- [ ] Bumping `latest_version_code` on the server shows the update dialog.
- [ ] Setting a feature flag to `false` hides that entry point in the app.

---

## M12 — Optional extras (only if you have time)

| Extra | Backend | App | Note |
|---|---|---|---|
| **Capped catch-up hint** | None, or a field in the day view: `catchup_hint_g = min(15, 0.5 × yesterday_protein_deficit)` | One line in the "Next Move" card: "Yesterday was ~30 g short — +10–15 g today is plenty." | Never changes the target. Hide it when the deficit is under ~10 g. |
| **Workout history** | Group workout entries by type/muscle group per week (from extracted data) | Weekly "What you trained" chips, "Legs: 0 this week" | Quality depends on Gemini's workout extraction. |
| **Day score breakdown** | Return the score's component list with `GET /api/calendar/{day}` or day view | Tap the score → sheet showing what added/removed points | Builds trust in the number. |
| **Barcode scan** | `GET /api/foods/barcode/{code}` using Open Food Facts | `mobile_scanner` on the scan screen; fall back to label photo if not found | Check Indian product coverage first. |
| **Product compare** | None (reuse saved scores) | Pick 2 My Products → side-by-side table | Tiny once M7 exists. |

---

## Appendix A — Collections and indexes (summary)

| Collection | New/Changed | Key fields | Indexes |
|---|---|---|---|
| `logs` | changed | `logged_at, logical_date, tz, client_id, source, meta` | `(user_id, logical_date)`; unique sparse `(user_id, client_id)` |
| `users` | changed | `pin_hash`, `weight_kg` (kept in sync by M9), meal-timing settings | existing |
| `saved_meals` | new | see M4 | `(user_id, last_used_at)` |
| `insight_cache` | new | see M5 | unique `(user_id, kind, range_start, range_end)` |
| `food_scans` | new | see M7 | TTL on `created_at` (7 days) |
| `products` | new | see M7 | unique `(user_id, name_key)` |
| `weight_logs` | new | see M9 | unique `(user_id, logical_date)` |
| `login_attempts` | new | `{key, count, locked_until}` | TTL on `expires_at` |

## Appendix B — New / changed routes (summary)

| Module | Route | Type |
|---|---|---|
| M1 | `GET /ping` | new |
| M2 | `POST /api/logs` (+`logged_at`, `client_id`) | changed |
| M2 | `PUT /api/logs/{id}` (+`logged_at`) | changed |
| M2 | `POST /api/logs/structured` | new |
| M2 | `POST /api/logs/{id}/repeat` | new |
| M3 | `POST /api/auth/login` (+`pin`) | changed |
| M3 | `GET /api/export` | new |
| M4 | `GET/POST /api/saved-meals`, `PUT/DELETE /api/saved-meals/{id}`, `POST /api/saved-meals/{id}/log`, `GET /api/saved-meals/suggestions` | new |
| M5 | `GET /api/insights/{period}`, `POST /api/insights/{period}/generate`, day verdict GET/POST | new/changed |
| M6 | `POST /api/logs/photo/analyze` | new |
| M7 | `POST /api/foods/scan`, `PUT /api/foods/scan/{id}`, `POST /api/foods/scan/{id}/evaluate`, `POST /api/foods/scan/{id}/log`, `POST/GET /api/foods/products`, `POST /api/foods/products/{id}/log`, `DELETE /api/foods/products/{id}` | new |
| M9 | `PUT/DELETE /api/weight/{day}`, `GET /api/weight`, `GET /api/weight/trend` | new |
| M10 | `GET /api/stats/heatmap`, `extended` in weekly/monthly stats | new/changed |
| M11 | `GET /api/app/config` | new |

## Appendix C — Packages

Backend: `httpx`, `tzdata`, `python-multipart` (uploads), `Pillow` (EXIF strip/resizing), `passlib[argon2]` (or bcrypt), your Gemini SDK (check whether you're still on a superseded one), `pytest`.

Flutter: `image_picker`, `share_plus`, `local_auth` (optional), `flutter_local_notifications`, `timezone`, `workmanager`, `home_widget`, `package_info_plus`, `url_launcher`, optional `mobile_scanner`, optional `image_cropper`.

## Appendix D — Test plan (what to automate, what to test by hand)

Automate (pytest, pure functions, no network):
- `logical_date` boundaries; `input_hash` rounding behaviour; `protein_meals` clustering; label `validate`; product score rank order over fixtures; unit conversions (kJ→kcal, salt→sodium, per-serving→per-100 g); saved-meal portion scaling; idempotent `client_id`.

Test by hand on a real phone:
- Cold start after 30 min idle; offline → online queue flush; backfill to a past day; photo and label capture in dim light; notification delivery with the screen off; update install over a previous APK.

## Appendix E — Risks and decisions to revisit

| Risk | Mitigation |
|---|---|
| Gemini free-tier quota changes or the model is retired | Model name in env; feature flags (M11); cached insights (M5); saved meals/products avoid repeat AI calls. |
| Label/photo estimates look precise but aren't | Estimate badges, mandatory confirmation, validation warnings, editable values. |
| Render free tier behaviour/terms change | External pinger, `KEEPALIVE_ENABLED` flag, paid instance as the fallback. |
| Lost signing key | Back it up in two places on day one. |
| Scoring feels wrong for some foods | Constants in config + fixture test; iterate on real products you eat. |
| Public backend + weak auth | M3 PIN + lockout; consider keeping the API behind a private network later. |

## Suggested sprint plan

1. **Sprint 1:** M1, M2, M3 (reliability, correctness, safety)
2. **Sprint 2:** M4, M5 (daily friction and AI cost)
3. **Sprint 3:** M6, M7 (photo + label scanner)
4. **Sprint 4:** M8, M9 (adherence + body metrics)
5. **Sprint 5:** M10, M11, then M12 as you like

Ship an APK at the end of each sprint and use it for a few days before starting the next one.
