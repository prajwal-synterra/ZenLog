# ZenLog v2 — Fixes & Upgrade Blueprint

Scope: personal use (you + 1–2 friends). Everything here is sized for that: no refresh-token systems, no heavy rate limiting, no push infrastructure.

**Assumptions (I can't see your code, so verify):**
- Backend is Python/FastAPI + MongoDB (inferred from the HTTP 409/201 codes, Mongo collections, Pydantic-style payloads). If it isn't FastAPI, the *design* holds; only the code snippets change.
- The date bug root cause below is inferred from the symptoms. Check the exact lines listed in §3.

---

## 0. Summary of What Changes

| # | Problem | Fix |
|---|---------|-----|
| 1 | AI runs only at sleep → no live feedback | Extract **per log entry** in a background task; day totals = sum of entries |
| 2 | Extraction has no "was this good for my goal?" | Per-entry `goal_alignment` + deterministic **day score** + Gemini **verdict report** |
| 3 | Selecting another date shows today's data | One `selectedDate` source of truth + one `GET /api/days/{day}/view` endpoint with `mode: past/today/future` |
| 4 | Future days show nothing motivational | Deterministic "plan for the day" card using targets + this week's shortfall |
| 5 | Progress doesn't warn when behind | **Progress engine**: pace-aware daily status, weekly catch-up math, alerts |
| 6 | Re-login every time | Long-lived **device token** stored in secure storage, validated on app start |
| 7 | Stale/`PROCESSING_FAILED` after edits | Removed. Totals are always computed live from entries |
| 8 | Dinner at 12:40 AM lands on the wrong date | 4 AM day-boundary rule |

---

## 1. Core Architecture Change: Per-Entry Extraction

### 1.1 Old flow (remove)
```
logs → (user submits sleep) → Gemini on whole day → DailyRecord
```

### 1.2 New flow
```
POST /api/logs ─► save log (extraction_status=pending) ─► return 201 immediately
                         │
                         └─► background task: Gemini on THIS entry only
                                   │
                                   ▼
                  log.extracted = {...}, extraction_status = done | failed
                                   │
Day totals / progress / score  ◄───┘  (pure deterministic sum over entries, computed on read)
```

**Why this is right for you:**
- Live protein pill is just a sum. No preview endpoint needed.
- Edit a log → re-extract only that log. Nothing "goes stale".
- Delete a log → its contribution disappears automatically.
- A manual override of one entry's protein can never be overwritten by a re-run.
- Cost: one short Flash-tier call per entry. For 3 users it's negligible.

**Accepted trade-off:** an entry referencing another ("same lunch as yesterday") has no context. Solve by writing fuller entries. If this bothers you later, pass the previous 2–3 entries of that day as read-only context in the prompt (see §6.1 note).

---

## 2. Data Model

### 2.1 `logs` collection

```json
{
  "_id": "ObjectId",
  "user_id": "zen_test_0001",
  "date": "2026-10-01",                 // assigned via 4AM rule (§2.4), stored as string
  "timestamp": "2026-10-01T08:30:00+05:30",
  "text": "Breakfast: 3 eggs and a banana. 500ml water.",
  "text_hash": "sha256...",             // detects edits during a pending extraction
  "extraction_status": "pending",       // pending | done | failed
  "extraction_error": null,
  "extraction_attempts": 0,
  "extracted_at": null,
  "extracted": null,                    // filled by worker, see below
  "overrides": {},                      // manual edits, e.g. {"protein_g": 22}
  "created_at": "...",
  "updated_at": "..."
}
```

### 2.2 `log.extracted` shape

One log may contain several things (a meal + water + a workout). Everything is optional.

```json
{
  "nutrition": {
    "meal_type": "breakfast",            // breakfast|lunch|dinner|snack|null
    "items": [
      {"food": "eggs", "quantity": "3", "protein_g": 18.0, "calories_kcal": 210,
       "source": "estimated", "confidence": "high"},
      {"food": "banana", "quantity": "1", "protein_g": 1.3, "calories_kcal": 105,
       "source": "estimated", "confidence": "high"}
    ],
    "protein_g": 19.3,                   // backend recomputes from items; never trust model sum
    "calories_kcal": 315
  },
  "hydration_ml": 500,
  "workout": {"type": "strength_training", "duration_mins": 45, "intensity": "high",
              "exercises": ["deadlifts", "pull-ups"]},
  "learning": {"activity": "reading", "book": "Atomic Habits", "pages": 15, "duration_mins": null},
  "habits": [{"habit": "morning sunlight", "completed": true}],
  "mood": {"mood": "calm and focused", "context": "after meditation"},
  "goal_alignment": {
    "rating": "good",                    // good | neutral | poor | not_applicable
    "reason": "High-protein breakfast; supports muscle gain.",
    "quality_flags": ["whole_food", "high_protein"]
    // allowed flags: whole_food, high_protein, high_fiber, fried, sugary,
    //                processed, alcohol, skipped_meal, large_portion, light_meal
  }
}
```

**Effective value rule (important):** when summing, use `overrides.protein_g` if present, else `extracted.nutrition.protein_g`. Same for calories and hydration. Totals only count entries with `extraction_status = done`.

### 2.3 `days` collection (small, optional fields only)

```json
{
  "user_id": "zen_test_0001",
  "date": "2026-10-01",
  "wake_time": "07:15",                  // optional
  "sleep_time": "23:00",                 // optional
  "closed": true,
  "closed_at": "2026-10-02T04:05:00+05:30",
  "verdict": { ... },                    // see §5.4, written once at close
  "score": 78,
  "rating": "ok",
  "targets_snapshot": {                  // freeze targets used for this day
    "protein_g": 126, "calories_kcal": 2200, "water_ml": 3000, "goal": "muscle_gain"
  },
  "analysis_count_today": 0              // for on-demand analyze cap
}
```

`targets_snapshot` matters: if you change your protein target later, old days must still be judged against the target you had **then**.

### 2.4 Day-boundary rule (4 AM)

```python
from datetime import timedelta
DAY_CUTOFF_HOURS = 4

def logical_date(ts):                     # ts is tz-aware IST datetime
    return (ts - timedelta(hours=DAY_CUTOFF_HOURS)).date()
```
Apply on create **and** on edit (when timestamp changes). A log at 12:40 AM on Oct 2 gets `date = 2026-10-01`.
`GET /api/logs/today` and "today" everywhere use `logical_date(now_ist)`.
If the user explicitly passes `date` in `POST /api/logs` (backfilling), respect it; do not recompute.

### 2.5 `users` additions

```json
{
  "goal": "muscle_gain",                       // muscle_gain | fat_loss | maintenance | mindfulness
  "body_weight_kg": 70,
  "daily_protein_target_g": 126,
  "daily_calorie_target": 2200,                // NEW
  "daily_water_target_ml": 3000,               // NEW
  "weekly_workout_target": 3,                  // NEW
  "sleep_target_hours": 7.5,                   // NEW (optional, used if you keep wake/sleep)
  "eating_window": {"start": "08:00", "end": "22:00"}   // NEW, drives pace curve
}
```
Sensible defaults on creation: protein = `1.8 × body_weight_kg`; calories left `null` until user sets (see §5.1 for null handling); water 3000 ml; workouts 3/week.

### 2.6 `sessions` collection (see §8)

### 2.7 Indexes
```
logs:     (user_id, date, timestamp)    -- main read path
logs:     (extraction_status, updated_at) -- startup sweeper
days:     (user_id, date) unique
reports:  (user_id, period, period_start) unique
sessions: (token_hash) unique ; TTL on expires_at
```

---

## 3. The Date-Selection Bug (Future/Past Dates Show Current Data)

### 3.1 Likely root causes (check these in your frontend)
1. The home screen fetches `/api/logs/today` and `/api/stats/...` **without a date parameter**, so changing the date picker only changes the highlighted chip, not the query.
2. The selected date is held in local component state in the picker but not lifted to the screen/store, so the data hooks never see it.
3. Query/cache keys don't include the date (e.g. cache key `"today"`), so a cached object is reused for every date.
4. For future dates there's no "mode" concept, so the UI falls back to rendering whatever the last state was.

### 3.2 The fix: one source of truth + one endpoint

**Frontend rule:** `selectedDate` lives in a single store/context. *Every* data hook takes it as an argument and includes it in the cache key.

```ts
// pseudo-code (works for React Query / Riverpod / similar)
const { selectedDate } = useDateStore();            // 'YYYY-MM-DD'
const day = useQuery(['dayView', selectedDate], () => api.get(`/api/days/${selectedDate}/view`));
```

**Backend rule:** the server decides `mode` by comparing the date to the logical today. The UI never guesses.

| mode | Condition | UI shows |
|------|-----------|----------|
| `future` | date > logical today | Motivational plan card, targets, week catch-up hint. Logging disabled |
| `today` | date == logical today | Live stream, live progress with pace, input enabled |
| `past` (with data) | date < today and has logs | Final score, verdict report, entries, totals |
| `past` (empty) | date < today and no logs | "Nothing logged" empty state + optional "add entry for this day" |

**Never** reuse the Today component's state for other dates. Make `DayView` a pure function of the `view` payload.

---

## 4. New & Changed API Routes

All routes: `Authorization: Bearer <device_token>`. All dates `YYYY-MM-DD`.

### 4.1 Logs

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/logs` | POST | Create log. Returns `201` instantly with `extraction_status: "pending"`. Enqueues background extraction. Body: `{text, date?, timestamp?}`. Rejects dates in the future (422) |
| `/api/logs/{id}` | PUT | Edit text/timestamp. Sets `extraction_status=pending`, clears `overrides` only if text changed (keep a flag if you want to preserve), enqueues re-extraction |
| `/api/logs/{id}` | DELETE | Delete. Day totals update automatically |
| `/api/logs/{id}/retry` | POST | Re-run extraction for a `failed` log. Counts against daily cap |
| `/api/logs/{id}/override` | PATCH | Manual correction: `{"protein_g": 22, "calories_kcal": 450, "hydration_ml": 300}` (any subset). Stored in `overrides`. Pass `null` to clear a field |
| `/api/logs` | GET | Range query (`start_date`, `end_date`). Keep, no pagination needed |
| `/api/logs/today` | GET | **Deprecated alias** → same as `/api/days/{logical_today}/view` logs. Keep until frontend migrated |

### 4.2 Day view (the main new endpoint)

`GET /api/days/{day}/view`

Single payload for the whole home/day screen. Returns `mode`, logs, totals, progress, score (if applicable), verdict (if closed), motivation (if future), and `pending_count` for polling.

```json
{
  "date": "2026-10-01",
  "mode": "today",                        // past | today | future
  "is_closed": false,
  "pending_count": 1,                     // UI polls every 2s while > 0 (see §10.4)
  "failed_count": 0,
  "logs": [ { "id": "...", "time_display": "08:30 AM", "text": "...",
              "extraction_status": "done", "extracted": {...}, "overrides": {} } ],
  "totals": {
    "protein_g": 19.3, "calories_kcal": 315, "hydration_ml": 500,
    "workout_done": false, "workout_mins": 0
  },
  "targets": { "protein_g": 126, "calories_kcal": 2200, "water_ml": 3000, "goal": "muscle_gain" },
  "progress": { ... },                    // §5.2 (live, pace-aware when mode=today)
  "score": null,                          // live partial score for today, final for closed past days
  "rating": null,
  "verdict": null,                        // §5.4, only when closed or after on-demand analyze
  "motivation": null,                     // §5.6, only when mode=future
  "week_context": { ... }                 // §5.5, small summary for banners
}
```

Behavior details:
- `mode=future`: `logs=[]`, `totals` all zero, `progress=null`, `motivation` populated, **no Gemini call**.
- `mode=past`, not closed: trigger lazy close (§7.3) *before* building the response if date < logical today. If it closes inline, return the closed result. Run the Gemini verdict as a background task and return `verdict: null, verdict_status: "pending"`; the UI polls.
- Always include `verdict_status`: `none | pending | done | failed`.

### 4.3 Day actions

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/days/{day}/analyze` | POST | On-demand "Analyze my day so far" (today) or re-generate verdict for a past day. Cap: 5/day/user. Runs in background, UI polls `view` |
| `/api/days/{day}/close` | POST | Manual close (optional button). Same logic as lazy close |
| `/api/days/wake` | POST | Optional wake time for today. Keep, but UI does **not** popup |
| `/api/days/{day}/wake` | POST | Optional |
| `/api/days/sleep` | POST | Optional sleep time for today. **Does not** gate processing anymore |
| `/api/days/{day}/sleep` | POST/PUT | Optional. `reprocess` param removed |

### 4.4 Progress & stats

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/progress/week?anchor=` | GET | Week-to-date + catch-up math (§5.5). Default: current logical week (Mon–Sun) |
| `/api/progress/month?anchor=` | GET | Same shape, month scope |
| `/api/calendar?from=&to=` | GET | Extend each day with `score`, `rating`, `mode`, `logs_count`. Fixes calendar dots showing wrong state |
| `/api/stats/*` | GET | Keep, but compute from entries (not DailyRecord). Remove `incomplete` vs `completed` split; use `closed` days |
| `/api/insights/weekly|monthly` | GET | Keep. Guard: if fewer than 3 days with logs, return `{"insufficient_data": true, "days_logged": N}` instead of calling Gemini. Cache in `reports`; invalidate by deleting the cached report whenever a log in that period is created/edited/deleted |

### 4.5 Auth (see §8)

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/auth/login` | POST | Body adds `device_id`, `device_name?`. Returns long-lived token |
| `/api/auth/me` | GET | Cheap token validity check on app start; returns user summary |
| `/api/auth/logout` | POST | Revokes **this device's** session only |

### 4.6 Users

`PUT /api/users/me` now accepts: `goal`, `body_weight_kg`, `daily_protein_target_g`, `daily_calorie_target`, `daily_water_target_ml`, `weekly_workout_target`, `eating_window`.
Changing targets affects **today and future** only; closed days keep their `targets_snapshot`.

### 4.7 Removed
- `POST /api/days/{day}/reprocess`
- `prompt-status` popups (keep the endpoint returning `false/false` for a release if the old app build is in use, then delete)
- `PROCESSING_FAILED / source_logs_changed` logic

---

## 5. Progress, Score & Verdict Engine

**Principle:** numbers, scores and ratings are computed by **backend code**. Gemini only *explains* them. If Gemini says "great day" while your protein is at 40%, the app is lying. Never let the model decide the rating.

### 5.1 Metric definitions

Each metric has a `direction`:

| Metric | Direction | Rule |
|--------|-----------|------|
| Protein | `min` | Want ≥ target |
| Water | `min` | Want ≥ target |
| Workout (daily) | `min` | Done = at least one workout today. Weekly target is what matters |
| Calories | depends on goal | `fat_loss` → `max` (stay at/under target). `muscle_gain` → `range` (target −5% … +15%). `maintenance` → `range` (±10%). `mindfulness` → not scored if no target |

If `daily_calorie_target` is `null`, calories are displayed but **excluded from scoring** and the weight is redistributed.

### 5.2 Per-metric progress object

```json
"progress": {
  "protein":   {"actual": 19.3, "target": 126, "pct": 15.3, "remaining": 106.7,
                "direction": "min", "status": "behind", "expected_pct_now": 25,
                "message": "Behind pace. Aim for ~30g at your next meal."},
  "water":     {"actual": 500, "target": 3000, "pct": 16.7, "remaining": 2500, "status": "on_track", ...},
  "calories":  {"actual": 315, "target": 2200, "pct": 14.3, "direction": "range", "status": "on_track", ...},
  "workout":   {"done": false, "week_done": 1, "week_target": 3, "status": "behind"},
  "alerts": [
    {"level": "warn", "metric": "protein", "text": "106g protein left with 3 meals to go. ~35g per meal."}
  ]
}
```

**Status values:** `met`, `on_track`, `behind`, `far_behind`, `over` (for `max`/`range` exceeded).
UI color mapping: met = green, on_track = blue/neutral, behind = amber, far_behind = red, over = red.

### 5.3 Pace-aware status for TODAY

A plain `pct` is misleading at 9 AM (15% is fine) and at 9 PM (15% is a failure). Compare with the **expected** percentage for the current time.

```python
# default curve for protein/calories (front-loaded to meals), tweak constants to taste
PACE_POINTS = [("08:00", 0.0), ("10:30", 0.25), ("14:30", 0.50), ("19:30", 0.80), ("22:00", 1.0)]
# hydration: linear between eating_window.start and end
```

```python
def expected_fraction(now_t, points):
    # linear interpolation between points; <first -> 0, >last -> 1
    ...

def status_min(actual, target, expected):
    pct = actual / target
    if pct >= 1.0:               return "met"
    if pct >= expected * 0.9:    return "on_track"
    if pct >= expected * 0.6:    return "behind"
    return "far_behind"
```

Shift the curve start/end using `users.eating_window`. After the window end, expected = 1.0, so anything under target = `behind`/`far_behind` and the alert becomes "Day is almost over: 40g protein short."

For `mode=past`, there's no pace; use plain thresholds: ≥100% met, 80–99% on_track (close), 60–79% behind, <60% far_behind.

**Message generation is templated, not AI.** Examples:
- protein `behind`: `"{remaining:.0f}g protein left. ~{per_meal:.0f}g per remaining meal."` (per_meal = remaining / max(1, meals_left_estimate), where meals_left_estimate derives from the pace curve: before 10:30 → 3, before 14:30 → 2, before 19:30 → 1, else 1)
- water `far_behind`: `"Only {actual} ml. Drink 500 ml now."`
- calories `over` for fat_loss: `"{over} kcal over target. Keep dinner light."`

### 5.4 Day score (0–100) and rating

Per-metric sub-score `s ∈ [0,1]`:
- `min`: `s = min(actual / target, 1)`
- `max`: `s = 1` if `actual ≤ target`, else `max(0, 1 − (actual − target) / (0.3 × target))`
- `range [lo, hi]`: `s = 1` inside; outside, linear decay to 0 at 30% beyond the nearest bound
- workout (daily component): `1` if a workout was logged today, else `0`. On planned rest days (see weekly logic) treat as `n/a` and drop the weight.
- food quality: from entry `goal_alignment`: `good = 1`, `neutral = 0.6`, `poor = 0`; average across entries that have a rating (weighted by calories if available). No rated entries → `n/a`.
- habits/mood: `completed habits / total habit observations`; no habits → `n/a`.

**Weights (starting values, tune after 2 weeks of real data):**

| Metric | muscle_gain / maintenance | fat_loss | mindfulness |
|--------|:-:|:-:|:-:|
| Protein | 30 | 25 | 10 |
| Calories | 20 | 30 | 5 |
| Hydration | 15 | 15 | 15 |
| Workout | 15 | 15 | 10 |
| Food quality | 10 | 10 | 10 |
| Habits/mood | 10 | 5 | 50 |

`score = 100 × Σ(w_i × s_i) / Σ(w_i)` over metrics that are applicable (drop `n/a` and redistribute).

**Rating:** `≥ 80 → "good"`, `60–79 → "ok"`, `< 60 → "poor"`. For an **incomplete/barely logged day** (fewer than 2 entries or < 40% of the eating window covered), don't rate: return `rating: "insufficient_data"` so you aren't punishing days you forgot to log.

**Data-quality caveat in UI:** if > 30% of items have `confidence: low` or `unknown`, show "Estimates are rough today" next to the score.

### 5.5 Weekly progress & catch-up math

Week = Monday–Sunday in logical dates.

`GET /api/progress/week` returns:

```json
{
  "week_start": "2026-09-28", "week_end": "2026-10-04",
  "days_elapsed": 4, "days_remaining": 3,
  "protein": {"days_target_met": 2, "days_logged": 4, "avg_g": 98.4,
              "target_g": 126, "status": "behind",
              "needs": "Hit target on 3 of the remaining 3 days to reach 5/7."},
  "workouts": {"done": 1, "target": 3, "remaining_needed": 2, "days_remaining": 3,
               "status": "behind",
               "needs": "2 workouts in the next 3 days. Plan them now."},
  "water": {"avg_ml": 2100, "target_ml": 3000, "status": "behind"},
  "score_avg": 71, "best_day": "2026-09-29", "worst_day": "2026-09-30",
  "alerts": [
    {"level": "warn", "metric": "workouts", "text": "1 of 3 workouts done, 3 days left. No rest days available."}
  ]
}
```

**Weekly status rules:**
- Workouts: `needed = target − done`. If `needed ≤ 0` → `met`. If `needed > days_remaining` → `impossible` ("Target can't be reached this week. Aim for {done+days_remaining}"). If `needed == days_remaining` → `far_behind` ("No rest days left"). If `needed ≥ days_remaining − 1` → `behind`. Else `on_track`.
- Protein: weekly target is **"at least 5 of 7 days meeting ≥ 90% of target"** (make `weekly_protein_days_target` configurable, default 5). Same needs/remaining logic.
- Every `behind`/`far_behind`/`impossible` creates an `alerts[]` entry. The week banner on Home shows the single highest-severity alert.
- Only count days with `rating != insufficient_data` toward adherence; unlogged days count as "unknown", not failures, but show "N days not logged".

### 5.6 Motivation for future days (no AI, no cost)

When `mode=future`, build from templates + facts:

```json
"motivation": {
  "headline": "Thursday: your chance to close the week strong.",
  "message": "You're 1 workout behind this week and 24g short on protein yesterday. Tomorrow's job: train, and start with a 35g protein breakfast.",
  "plan": {
    "protein_g": 126, "calories_kcal": 2200, "water_ml": 3000,
    "suggested_workout": true
  },
  "focus_points": [
    "Training day: you need 2 more workouts this week",
    "Protein: front-load breakfast (~35g)"
  ],
  "tone": "push"          // push | steady | celebrate
}
```

**Template selection:**
- Week status has `behind`/`far_behind` metrics → tone `push`, mention the specific shortfall + exact catch-up number.
- Everything `on_track`/`met` → tone `steady` ("Keep the rhythm.").
- Week targets all `met` → tone `celebrate` ("Targets done. Make tomorrow an easy recovery day.").
- Goal-specific line pool (e.g., fat_loss: calorie ceiling reminder; mindfulness: habit focus).
- Pick headline by weekday + goal; rotate with a deterministic hash of `(user_id, date)` so reopening the same future date shows the same message.
- Optional upgrade: one Gemini call per (user, date), cached in `days.motivation_ai`, fed with the deterministic plan so it only rewrites tone. Not required for v1.

### 5.7 Verdict report (Gemini narrative on top of deterministic numbers)

Generated:
- once at **day close** (lazy, background), and
- on demand via `POST /api/days/{day}/analyze` (today = "so far" mode).

**Input to Gemini** (the backend assembles; the model does not compute numbers):
```json
{
  "goal": "muscle_gain",
  "targets": {...},
  "totals": {...},
  "score": 62, "rating": "ok",
  "metric_statuses": {"protein": "behind", "calories": "on_track", ...},
  "entries": [ {"time": "08:30", "text": "...", "extracted": {...}} ],
  "week_context": {...}
}
```

**Required JSON output:**
```json
{
  "headline": "Solid training, but protein fell short.",
  "verdict_summary": "2–3 sentences, plain language, honest, specific to the entries.",
  "went_well": ["Hit 45-min strength session", "Breakfast was high-protein"],
  "hurt_the_goal": ["Dinner was ~8g protein, the lowest meal of the day", "Only 1.4L water"],
  "food_review": [
    {"entry_time": "13:10", "text_ref": "biryani", "rating": "neutral",
     "comment": "Carb-heavy, low protein for muscle gain."}
  ],
  "fixes_for_tomorrow": [
    "Add 30g protein at dinner (e.g. paneer, chicken, 4 eggs)",
    "Carry a 1L bottle and finish it by 3 PM"
  ],
  "coaching_note": "One short paragraph. No medical claims."
}
```

**Prompt rules to include (verbatim intent):**
- Use only the supplied data. Do not invent foods, quantities, or numbers.
- The `rating` and `score` are final; do not contradict them. Explain them.
- Be direct. If the day was poor, say so and say why. No empty praise.
- Max 3 items in each list. No medical diagnosis, no supplement or drug advice.
- If a metric is `insufficient_data` or low confidence, say the estimate is uncertain.
- Return JSON only. No markdown fences.

**Validation after response:** parse JSON, check required keys, cap list lengths, strip anything with numbers that don't exist in the input (cheap sanity check: ensure any number in `verdict_summary` appears in the input payload; if not, discard and retry once, then fall back to a templated summary).

**Fallback (no Gemini):** build a templated verdict from metric statuses so the day never shows blank.

The `verdict` object stored on `days` also includes the deterministic part:
```json
"verdict": {
  "score": 62, "rating": "ok",
  "metric_breakdown": [{"metric": "protein", "status": "behind", "pct": 71, "sub_score": 0.71}, ...],
  "ai": { ...narrative above... },
  "generated_at": "...", "model": "gemini-...", "status": "done"
}
```

---

## 6. Background Tasks

### 6.1 Per-entry extraction task

**Trigger:** after create, edit (text changed), or retry. Use FastAPI `BackgroundTasks` for v1. It's enough for 3 users. If the server restarts mid-task, the sweeper (§6.3) recovers.

```python
async def extract_log(log_id: str):
    log = await db.logs.find_one({"_id": oid(log_id)})
    if not log: return
    snapshot_hash = log["text_hash"]

    if not await within_daily_cap(log["user_id"]):
        await mark_failed(log_id, "daily_cap_reached"); return

    for attempt in range(1, 4):                       # 3 tries, backoff 1s, 3s, 8s
        try:
            result = await gemini_extract_entry(
                text=log["text"],
                goal=user.goal,
                local_time=log["timestamp"],
                context_entries=await prior_entries_today(log, limit=3)   # optional
            )
            clean = validate_and_recompute(result)     # recompute item sums, clamp absurd values
            # ---- optimistic guard: only write if text unchanged since we started ----
            updated = await db.logs.update_one(
                {"_id": log["_id"], "text_hash": snapshot_hash},
                {"$set": {"extracted": clean, "extraction_status": "done",
                          "extracted_at": now(), "extraction_error": None}})
            if updated.matched_count == 0: return      # user edited meanwhile; the edit enqueued a new task
            await invalidate_reports(log["user_id"], log["date"])
            return
        except Exception as e:
            await db.logs.update_one({"_id": log["_id"], "text_hash": snapshot_hash},
                                     {"$set": {"extraction_attempts": attempt, "extraction_error": str(e)[:200]}})
            await asyncio.sleep([1, 3, 8][attempt - 1])
    await mark_failed(log_id, "gemini_error")
```

**`validate_and_recompute` must:**
- Recompute `nutrition.protein_g` / `calories_kcal` as the sum of items (never trust the model's own total).
- Clamp: protein per item ≤ 150 g, calories per item ≤ 2500, hydration per log ≤ 3000 ml, workout duration ≤ 300 min. Out-of-range → set `confidence: "low"` and cap, or drop the value.
- Drop unknown keys; coerce types; default missing sections to `null`.
- Never let a non-food entry (e.g. "feeling tired") invent nutrition: if the model returns items for a log with no food words, discard.

**Prompt for per-entry extraction (core):**
```
You extract structured facts from ONE short journal entry for a personal health journal.
User goal: {goal}. Entry time (IST): {time}.
Rules:
- Extract only what is stated or clearly implied. If a quantity is missing, estimate a typical Indian portion and set confidence "medium" or "low".
- If the user gave explicit numbers (e.g. "30g protein"), use them with source "explicit_user_value".
- One entry may contain several things: food, water, workout, learning, habits, mood. Fill only what's present; use null otherwise.
- goal_alignment: rate this entry for the goal as good | neutral | poor | not_applicable, with a one-sentence reason and quality_flags from the allowed list.
- Water counts only if a volume or a glass/bottle is mentioned. Assume 1 glass = 250 ml, 1 bottle = 1000 ml unless stated.
- Return JSON only matching the schema. No commentary.
Entry: """{text}"""
```
Use a JSON response schema / structured output mode if your Gemini SDK supports it, and a Flash-tier model.

*Optional context:* pass `context_entries` (the previous ≤ 3 entries that day, text only) labelled "context only, do not extract from these".

### 6.2 Daily cap (cheap guardrail)

```python
DAILY_GEMINI_CAP = 120   # per user per logical day, across extract/retry/analyze
```
Keep a counter on `days.gemini_calls`. Over cap → entry stays `failed (daily_cap_reached)` and logs still save. This is your whole "rate limiting" system.

### 6.3 Sweeper (startup + every 5 min)

```python
# on app startup and via asyncio periodic task / APScheduler
stuck = db.logs.find({"extraction_status": "pending",
                      "updated_at": {"$lt": now() - timedelta(minutes=2)}})
for log in stuck: asyncio.create_task(extract_log(log["_id"]))
```
Without this, a server restart leaves entries pending forever.

### 6.4 Lazy day close

Trigger points (all idempotent): any `GET /api/days/{day}/view` or `GET /api/calendar` call, and app start.

```python
async def ensure_past_days_closed(user_id):
    today = logical_today()
    open_days = await db.days.distinct("date", {"user_id": user_id, "closed": {"$ne": True}, "date": {"$lt": today}})
    # also include dates that have logs but no day doc
    for d in union(open_days, dates_with_logs_before(today)):
        await close_day(user_id, d)

async def close_day(user_id, d):
    # atomic claim to prevent double close
    claimed = await db.days.find_one_and_update(
        {"user_id": user_id, "date": d, "closed": {"$ne": True}, "closing": {"$ne": True}},
        {"$set": {"closing": True}}, upsert=True)
    ...
    # 1. wait/skip for entries still pending: retry them first (max 1 pass)
    # 2. compute totals, progress, score, rating from entries (deterministic)
    # 3. write days doc: closed=True, score, rating, targets_snapshot, verdict.metric_breakdown
    # 4. enqueue gemini_day_verdict(user_id, d) (background)
    # 5. invalidate weekly/monthly cached reports covering d
```

**Optional but nice:** schedule one job at 04:10 IST (`APScheduler` cron) to close yesterday for all users, so the verdict is ready when you wake up. Lazy close remains as the safety net.

**Reopening:** if the user adds/edits a log on a closed past day, set `closed = False`, clear `verdict`, then re-close after the edit settles (debounce 60 s). Simpler v1 alternative: allow edits, and show an "Update verdict" button that calls `/analyze`.

### 6.5 Day verdict task (`gemini_day_verdict`)

Builds the §5.7 payload, calls Gemini once, validates, stores in `days.verdict.ai`, sets `verdict.status`. On failure → templated fallback + `status: "failed"` with a retry button in the UI (`POST /analyze`).

### 6.6 Weekly/monthly insight task

Generate on first request, cache in `reports`. Guard: `days_logged ≥ 3`, else return `insufficient_data` without calling Gemini. Include in the prompt: the deterministic progress object from §5.5 and the per-day scores, so the narrative references real shortfalls ("workouts: 1/3 with 3 days left").

---

## 7. Edge Cases (decide once, handle everywhere)

| Case | Behavior |
|------|----------|
| Log typed for a future date | 422 error. Future days are read-only |
| Backfill a past day | Allowed up to 14 days back. Re-closes that day |
| Gemini down | Log saves; entry shows "Couldn't analyze · Retry". Day totals ignore failed entries and the UI says "N entries not counted" |
| Entry pending when day closes | Close waits for one retry pass; still pending → counted as not analyzed, shown as such |
| User changes protein target mid-week | Today/future use new target; closed days use `targets_snapshot` |
| Zero entries on a past day | `mode=past`, `rating: insufficient_data`, no Gemini call |
| User edits a text after override | Override cleared only if text changed; show "manual value kept" when unchanged |
| Timezone | Everything IST; `logical_date` uses IST. If a friend is in another timezone, add `users.timezone` later |
| Two devices logged in | Allowed; sessions are per-device |

---

## 8. Authentication: Remember the Device

You only want phone + username login and no repeated logins on the same phone. Keep that flow; make the session long-lived and rolling.

### 8.1 Backend

`POST /api/auth/login`
```json
{ "username": "testuser1", "phone_number": "9XXXXXXXXX", "device_id": "uuid-generated-once-by-app", "device_name": "Pixel 7" }
```
Returns:
```json
{ "access_token": "opaque-random-48-bytes-urlsafe", "expires_at": "2027-03-30T...", "user": {...} }
```

**Sessions:**
```json
{ "token_hash": "sha256", "user_id": "...", "device_id": "...", "created_at": "...",
  "last_used_at": "...", "expires_at": "now + 180 days", "revoked": false }
```
- Token lifetime: **180 days, rolling**. On each authenticated request, if `last_used_at` is older than 1 day, update it and push `expires_at` forward 180 days. Active users never see a login screen.
- One session per `(user, device_id)`: logging in again from the same device replaces the old session.
- `POST /api/auth/logout` revokes only the current device's session.
- `GET /api/auth/me`: returns the user if the token is valid, else `401`.
- Add a TTL index on `expires_at` so expired sessions clean themselves up.
- **Minimum brute-force guard** (since phone is the only secret): 5 failed logins per 10 minutes per IP/username → `429`. A tiny in-memory counter is enough.
- If the server is reachable from the public internet, a phone number is guessable. Cheapest hardening: add a `login_code` field per user (a 4–6 digit PIN you set manually in the DB) and require it in addition to the phone. Skip this only if the server is private (Tailscale/LAN).

### 8.2 App

**Storage:** save the token in the platform's secure storage (iOS Keychain / Android Keystore), e.g. `expo-secure-store`, `flutter_secure_storage`, or `react-native-keychain` depending on your stack. Not plain AsyncStorage/SharedPreferences. Also save a generated `device_id` once.

**App start flow:**
```
splash
  ├─ token in secure storage?
  │     ├─ no  → Login screen
  │     └─ yes → GET /api/auth/me
  │               ├─ 200 → Home (cache user locally; show immediately)
  │               ├─ 401 → clear token → Login screen
  │               └─ network error → open Home with cached user, retry in background
```
- Show Home from cache right away; don't block on the network.
- Global API wrapper: on any `401` → clear token and navigate to Login (once, not in a loop).
- Prefill username on the Login screen after logout.

---

## 9. Frontend / App Changes (Screen by Screen)

### 9.1 State (single source of truth)

```
store:
  selectedDate        'YYYY-MM-DD'   (default = server's logical today from /auth/me or /days/.../view)
  user                profile + targets
queries (all keyed by date):
  dayView[date]       GET /api/days/{date}/view
  weekProgress[anchor]
  calendar[month]
```
- **Never** derive "today" from the device clock for logic. Use `mode` from the server (device clock and the 4 AM rule will disagree after midnight).
- After any mutation (create/edit/delete/override), invalidate `dayView[date]`, `weekProgress`, `calendar[month]`.

### 9.2 Home / Day Screen (one component, four modes)

**Header:** date strip (horizontal, ±14 days). Selecting a chip sets `selectedDate` only; the screen re-renders from `dayView[selectedDate]`. Show a loading skeleton, **never** the previous date's data, while fetching (`keepPreviousData: false`).

**Banner (under header):** highest-severity weekly alert from `week_context.alerts[0]` (amber/red). Tap → weekly progress screen.

**Mode: `today`**
1. Progress card: protein, calories, water as rings/bars with the **status color** and pace marker ("expected by now: 50%").
2. Inline alert chips from `progress.alerts` ("106g protein left. ~35g per meal.").
3. Quick log input (enabled).
4. Entry stream. Each entry shows its extraction state:
   - `pending`: subtle shimmer + "Analyzing…"
   - `done`: chips like `+19g protein · 315 kcal · 500 ml`, plus alignment dot (green/grey/red). Tap → detail sheet with items, confidence, **Edit values** (override), **Delete**
   - `failed`: "Couldn't analyze" + **Retry** button
5. "Analyze my day so far" button → `POST /analyze` → verdict card appears (poll).
6. Optional "I'm done for today" button → just opens the optional sleep-time sheet. **No gating popups.**

**Mode: `past` (with data)**
1. Score ring + rating label (Good / OK / Poor) + headline from verdict.
2. Metric breakdown (protein/cal/water/workout with ✓/⚠/✗).
3. Verdict card: went well / hurt the goal / fixes for tomorrow / food review.
4. Entries list (read-only by default; edit icon allowed).
5. If `verdict_status = pending`: skeleton "Writing your review…". `failed`: Retry button.

**Mode: `past` (empty)**
Empty state: "Nothing logged for Tuesday." Button: "Add an entry for this day" (opens input with that date preselected).

**Mode: `future`**
- Hide the input and entry stream.
- Show motivation card (headline, message, focus points, plan targets).
- "Plan for the day" mini card with that day's targets.
- If the user taps Log: tooltip "You can log this day when it arrives."

### 9.3 Progress UI rules

| Status | Color | Copy style |
|--------|-------|-----------|
| met | green | "Target hit" |
| on_track | blue | "On pace" |
| behind | amber | "Behind: {remaining} to go" |
| far_behind | red | "Falling short: {remaining} left" |
| over | red | "{n} over target" |
| impossible (weekly) | grey-red | "Can't reach this week. Aim for {n}" |

- Show **pace marker** (thin tick) on today's bars at `expected_pct_now`.
- At the end of the eating window, if any metric is `behind`/`far_behind`, show a one-time sticky card: "Day almost over: protein 40g short" with a quick suggestion from the template.
- Weekly screen: week bar chart of daily scores (colored by rating), then metric cards with `needs` text from §5.5.

### 9.4 Polling pending extractions

While `pending_count > 0` or `verdict_status = pending`: refetch `dayView[selectedDate]` every 2 s (max 30 s, then stop and show "Taking longer than usual · Retry"). Stop when zero. Optimistic UI: show the new entry immediately with `pending` state.

### 9.5 Calendar screen

Uses extended `/api/calendar`: dot color by `rating` (green/amber/red), grey for `insufficient_data`, hollow for no logs, dashed for future. Tapping a date sets `selectedDate` and switches to the Day screen.

### 9.6 Profile screen additions

Fields: goal, body weight, protein target, calorie target, water target, weekly workout target, eating window. Note under the form: "Changes apply from today onward."

### 9.7 Login screen

Username + phone. On success: save token + device_id in secure storage → Home. Nothing else.

---

## 10. Migration Plan (do in this order)

1. **DB:** add new log fields (`text_hash`, `extraction_status`, `extracted`, `overrides`), new user fields, sessions fields, indexes (§2.7). Existing logs: set `extraction_status = "pending"`.
2. **Backfill script:** run `extract_log` over all existing logs once (sequentially, small sleep between calls). For old days, run `close_day` afterwards.
3. **Backend:** extraction task + sweeper → day view endpoint → progress engine → lazy close + verdict task → new auth behavior → calendar extension. Keep old routes alive (deprecated) until the app build is switched.
4. **Frontend:** date store + `dayView` query → four modes → progress UI → polling → login persistence.
5. **Remove** `/reprocess`, `prompt-status` popups, the `PROCESSING_FAILED` handling.

---

## 11. Test Checklist

**Date logic**
- [ ] Log at 00:40 IST → gets previous `date`; shows under previous day.
- [ ] Select tomorrow → `mode=future`, no logs, motivational card, input hidden.
- [ ] Select 3 days ago → that day's entries/score, not today's. Switch back and forth rapidly: no stale flashes.

**Extraction**
- [ ] Create log → 201 in < 300 ms with `pending`; becomes `done` within a few seconds.
- [ ] Edit text during pending → only latest result is stored (hash guard).
- [ ] Kill Gemini key → log saves, shows `failed`, Retry works after restoring.
- [ ] Override protein → totals update, survive reload, not changed by retry.
- [ ] Restart server with pending logs → sweeper completes them.

**Progress**
- [ ] 9 AM with 15% protein → `on_track`; same numbers at 9 PM → `far_behind` with alert.
- [ ] Workout target 3, 1 done, 3 days left → `far_behind` / "no rest days".
- [ ] `fat_loss` with calories over target → `over` status and score drop.
- [ ] Day with 1 entry → `insufficient_data`, no harsh rating.

**Verdict**
- [ ] Narrative never contradicts the deterministic rating.
- [ ] Numbers in text exist in input (validation works); fallback template renders when Gemini fails.

**Auth**
- [ ] Login once, kill app, reopen → Home without login.
- [ ] Revoke session in DB → app goes to Login on next call, once.
- [ ] Logout on one device doesn't log out the other.

---

## 12. Things I Would Not Build (and why)

- Real-time websockets/SSE: 2-second polling is fine for 3 users.
- Celery/Redis queue: `BackgroundTasks` + sweeper is enough. Revisit only if tasks start getting lost.
- AI-decided ratings: scores must be reproducible and explainable.
- Push notifications: skip for now; the weekly banner and the end-of-window card do the nudging while you're in the app.
- Food database: Gemini estimates are the accepted accuracy level. The override field is your accuracy escape hatch.

---

## 13. Open Decisions For You

1. **Calorie target:** set `daily_calorie_target` per user now; without it, calories are display-only.
2. **Eating window** per user (default 08:00–22:00): drives the pace curve.
3. **Weekly workout target** (default 3) and weekly protein-days target (default 5).
4. **Verdict style:** the default is blunt and specific. If you want it gentler, change only the prompt, never the scoring.
5. **Server exposure:** private (Tailscale/LAN) → current login is acceptable. Public URL → add the PIN field in §8.1.
