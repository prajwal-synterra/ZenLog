# ZenLog — Complete UI Guide (Prompt + Spec)

**Use this file as the single brief for building/updating the ZenLog app UI.**
Companion file: `ZENLOG_V2_UPGRADE.md` (backend v2 contract). Where this guide and the reference mockups disagree, **this guide wins**, because it follows the real backend.

---

## 0. Instructions to the builder (AI or human)

You are updating an existing, working ZenLog mobile app so that **every screen, card, button and number maps to a real backend field or endpoint**.

Hard rules:
1. **No invented features.** If an element has no endpoint/field in §4–§5, don't build it. Section 1 lists mockup elements that must be removed or replaced.
2. **The server decides, the UI renders.** Never compute scores, ratings, statuses, "today", or day mode on the client. Read them from the API (`mode`, `status`, `rating`, `progress.*`).
3. **One source of truth for the selected date.** All data hooks take `selectedDate` and include it in the cache key. Never show data from another date while loading (show skeleton).
4. **Every async thing has 4 states:** loading, empty, error, success. Entries and verdicts also have `pending`/`failed`.
5. **Keep the existing visual identity** (green wellness theme, §2). Don't redesign; extend.
6. Stack is not specified here. Write code for the app's existing framework and state/query library. Keep names below as the contract.

Deliverables, in this order: (1) API client + types, (2) auth/boot flow, (3) date store + Day screen with 4 modes, (4) entry detail sheet, (5) Days calendar, (6) Insights, (7) Profile, (8) polish (empty/error states, polling).

---

## 1. Audit: Reference Mockups vs Backend Reality

| Mockup element | Problem | Decision |
|---|---|---|
| Login: **"Continue with OTP"** | No OTP endpoint exists | **Remove** the button and the "OR" divider |
| Profile: **"Change Password"** | No passwords in the system (username + phone) | **Remove**. Keep only Log out |
| Profile: avatar photo + edit pencil | No avatar field | Render **initials circle**. Remove pencil |
| Profile: tagline "Better habits. Greater goals." | No backend field | **Remove** |
| Home: **"Sleep & Synthesize Day"** card | v2 removes day-closing gate; days close automatically | **Replace** with "Analyze my day so far" card (§5.4) |
| Home: **"What time did you sleep last night?"** popup | v2 removes prompt popups | **Remove**. Sleep/wake are optional (§5.5) |
| Home: protein pill only | v2 tracks protein, calories, water, workout | Pill stays; add status color + extra cards (§5.4) |
| Home: date shown as static "Thu, Oct 1 📅" | Can't browse days → causes the date bug | Replace with **date strip** (§5.4) |
| Home: hydration card shows "500 ml" with a bar, no target | Bar is meaningless without target | Show `500 / 3000 ml` |
| Days: week strip duplicated above the month grid (27–3 then full month) | Rendering glitch in the mockup | **One** month grid only |
| Days: green ✓ / amber ○ / grey ○ | Old states `completed/incomplete` | Map to **rating** (§5.6) |
| Insights: "Protein Trend" bar chart by weekday | `/stats/weekly` returns aggregates only, no per-day series | Needs `daily[]` — **backend amendment A1** (§11) |
| Insights: sparkle icon (top-right) | No defined action | Make it "Refresh AI report" → re-fetch insights; hide if none |
| Loading screen: "68%" progress | Fake percentage | Show **real steps** from boot (§5.1) |
| Profile "My Goals" chips: Muscle Gain / Fat Loss / Mindfulness | v2 adds `maintenance` | Four chips |
| Profile fields: only weight + protein target | v2 adds calorie, water, workout target, eating window | Add fields (§5.8) |
| Welcome screen "Get Started" | Fine, client-only | Show **only on first launch** (no token ever stored) |

---

## 2. Design Tokens (from the reference screens)

> Colors below are **estimated by eye** from the screenshots. Sample exact hex values from the source images before shipping, and store them as theme tokens, never inline.

**Palette (tokens)**
| Token | Approx value | Use |
|---|---|---|
| `bg` | `#F2F7F1` | Screen background (soft mint-white) |
| `surface` | `#FFFFFF` | Cards, sheets |
| `surfaceTint` | `#E8F1E8` | Chips, inactive pills, stat tiles |
| `primary` | `#2E5E4B` | Primary buttons, active tab, selected chip |
| `primaryDark` | `#1F3F33` | Headings |
| `accent` | `#4F8F63` | Leaf accents, progress fill, links |
| `barFill` | `#8DB48E` | Chart bars |
| `textMuted` | `#6B7A72` | Secondary text |
| `warn` | `#E0A030` | `behind` status, amber dots |
| `danger` | `#D14B4B` | `far_behind`, `over`, Log out, failed states |
| `success` | `#2E7D5B` | `met`, completed check |

**Status color map (differs slightly from v2 doc: no blue in this theme)**
`met` → `success` + ✓ · `on_track` → `accent` · `behind` → `warn` · `far_behind` / `over` → `danger` · `impossible` → `danger` (muted) · `insufficient_data` → `textMuted`.

**Type:** rounded geometric/humanist sans (Inter or Plus Jakarta Sans). Scale: Title 28/700, Section 20/600, Card title 16/600, Body 15/400, Caption 12/400, Number-large 24/700.
**Shape:** card radius 20, input/pill radius 999, button height 52, tap target ≥ 44.
**Elevation:** very soft shadow (0 4 16 rgba(31,63,51,0.06)); no hard borders except 1px `#DCE8DC` on inputs.
**Icons:** outline, 1.75 stroke, rounded caps (Lucide-style): utensils (meal), dumbbell/running (workout), droplet (water), book (learning), smile (mood), calendar-check (habits), sparkle (AI), moon (sleep), sun (wake).
**Decoration:** leaf illustrations only on Welcome / Login / Boot. None on data screens.
**Bottom nav:** 4 tabs: Home, Days, Insights, Profile. Active = `primary` icon + label; inactive = `textMuted`.
**Motion:** 150–200 ms ease-out; skeleton shimmer for loading; progress fills animate on change; no confetti.

---

## 3. App Architecture

### 3.1 Boot and navigation
```
App start
 ├─ first launch (no device_id stored)? → generate UUID device_id, store
 ├─ token in secure storage?
 │    ├─ no  → (never logged in) Welcome → Login   |  (logged out before) Login
 │    └─ yes → show Boot screen with real steps:
 │             1. GET /api/auth/me                 ("Checking your session")
 │             2. GET /api/days/{today}/view       ("Loading today")      ← today from /auth/me.server_today
 │             3. GET /api/progress/week           ("Reading your week")
 │             → Home
 ├─ 401 on /auth/me → clear token → Login (prefill last username)
 └─ network error on /auth/me → open Home using cached user; retry in background
```
Tabs: `Home` (Day screen for `selectedDate`), `Days` (calendar), `Insights`, `Profile`. Tapping a calendar date sets `selectedDate` and switches to Home.

### 3.2 Global state
```
authStore:   token, deviceId, user (profile+targets), serverToday   // serverToday = logical date from API
dateStore:   selectedDate ('YYYY-MM-DD')  default = serverToday
uiStore:     insightsPeriod ('weekly'|'monthly'), calendarMonth ('YYYY-MM')
```
- **Never use the device clock to decide what "today" is.** Use `serverToday` (the 4 AM rule: a log at 00:40 belongs to the previous day).
- Refresh `serverToday` on app foreground and on `/auth/me`. If it changed (crossed 4 AM), and the user was viewing the old "today", move `selectedDate` to the new one and show a toast "New day started".

### 3.3 API client (single module)
- Base URL from config. Header `Authorization: Bearer <token>`. JSON in/out.
- Global response interceptor: `401` → clear token → navigate to Login **once** (debounce to avoid loops). `429` → toast "Too many attempts, wait a bit". `5xx`/network → typed `ApiError` with `retryable: true`.
- All dates `YYYY-MM-DD`; all times display in IST, 12-hour (`08:30 AM`). Use server `time_display` for logs.
- Query keys: `['dayView', date]`, `['progressWeek', anchor]`, `['progressMonth', anchor]`, `['calendar', 'YYYY-MM']`, `['insights', period, anchor]`, `['stats', period, anchor]`, `['me']`.
- Mutation invalidation matrix:

| Mutation | Invalidate |
|---|---|
| create/edit/delete log, override, retry | `dayView[date]`, `progressWeek`, `progressMonth`, `calendar[month]`, `stats`, `insights` |
| analyze | `dayView[date]` (then poll) |
| update profile/targets | `me`, `dayView[selectedDate]`, `progressWeek` |
| wake/sleep | `dayView[date]` |

---

## 4. Type Contracts (match the backend exactly)

```ts
type Goal = 'muscle_gain' | 'fat_loss' | 'maintenance' | 'mindfulness';
type DayMode = 'past' | 'today' | 'future';
type ExtractionStatus = 'pending' | 'done' | 'failed';
type MetricStatus = 'met' | 'on_track' | 'behind' | 'far_behind' | 'over' | 'impossible';
type Rating = 'good' | 'ok' | 'poor' | 'insufficient_data';

interface User {
  user_id: string; name: string; username: string; goal: Goal;
  body_weight_kg: number;
  daily_protein_target_g: number;
  daily_calorie_target: number | null;
  daily_water_target_ml: number;
  weekly_workout_target: number;
  eating_window: { start: string; end: string };   // 'HH:mm'
}

interface LogEntry {
  id: string; date: string; timestamp: string; time_display: string; text: string;
  extraction_status: ExtractionStatus;
  extraction_error?: string | null;
  extracted: null | {
    nutrition?: { meal_type: string | null; protein_g: number; calories_kcal: number;
                  items: { food: string; quantity: string; protein_g: number; calories_kcal: number;
                           source: 'explicit_user_value' | 'estimated' | 'unknown';
                           confidence: 'high' | 'medium' | 'low' | 'unknown' }[] } | null;
    hydration_ml?: number | null;
    workout?: { type: string; duration_mins: number; intensity: 'high'|'moderate'|'low'; exercises: string[] } | null;
    learning?: { activity: string; book?: string; pages?: number; duration_mins?: number } | null;
    habits?: { habit: string; completed: boolean }[] | null;
    mood?: { mood: string; context?: string } | null;
    goal_alignment?: { rating: 'good'|'neutral'|'poor'|'not_applicable'; reason: string; quality_flags: string[] } | null;
  };
  overrides: { protein_g?: number; calories_kcal?: number; hydration_ml?: number };
}

interface MetricProgress {
  actual: number; target: number; pct: number; remaining: number;
  direction: 'min' | 'max' | 'range'; status: MetricStatus;
  expected_pct_now?: number;          // only mode=today
  message: string;                    // ready-to-display, templated by backend
}
interface Alert { level: 'info' | 'warn' | 'danger'; metric: string; text: string }

interface DayView {
  date: string; mode: DayMode; is_closed: boolean;
  pending_count: number; failed_count: number;
  logs: LogEntry[];
  totals: { protein_g: number; calories_kcal: number; hydration_ml: number; workout_done: boolean; workout_mins: number };
  targets: { protein_g: number; calories_kcal: number | null; water_ml: number; goal: Goal };
  progress: null | { protein: MetricProgress; water: MetricProgress; calories?: MetricProgress;
                     workout: { done: boolean; week_done: number; week_target: number; status: MetricStatus };
                     alerts: Alert[] };
  score: number | null; rating: Rating | null;
  verdict_status: 'none' | 'pending' | 'done' | 'failed';
  verdict: null | {
    score: number; rating: Rating;
    metric_breakdown: { metric: string; status: MetricStatus; pct: number }[];
    ai: null | { headline: string; verdict_summary: string; went_well: string[]; hurt_the_goal: string[];
                 food_review: { entry_time: string; text_ref: string; rating: string; comment: string }[];
                 fixes_for_tomorrow: string[]; coaching_note: string };
  };
  motivation: null | { headline: string; message: string; focus_points: string[];
                       plan: { protein_g: number; calories_kcal: number | null; water_ml: number; suggested_workout: boolean };
                       tone: 'push' | 'steady' | 'celebrate' };
  week_context: { alerts: Alert[]; days_remaining: number };
  wake_time?: string | null; sleep_time?: string | null;
}

interface CalendarDay { date: string; mode: DayMode; rating: Rating | null; score: number | null;
                        logs_count: number; protein_g: number; protein_target_g: number; workout: boolean }

interface WeekProgress {                      // also used for month (same shape, different scope)
  week_start: string; week_end: string; days_elapsed: number; days_remaining: number;
  daily: { date: string; protein_g: number; protein_target_g: number; score: number | null;
           rating: Rating | null; workout: boolean }[];                       // ← amendment A1
  protein: { days_target_met: number; days_logged: number; avg_g: number; target_g: number; status: MetricStatus; needs: string };
  workouts: { done: number; target: number; remaining_needed: number; days_remaining: number; status: MetricStatus; needs: string };
  water: { avg_ml: number; target_ml: number; status: MetricStatus };
  score_avg: number | null; best_day: string | null; worst_day: string | null; alerts: Alert[];
}

interface Insight { insufficient_data?: boolean; days_logged?: number;
  summary?: { completed_days: number; incomplete_days: number; average_protein_g: number;
              protein_target_adherence_percent: number; workout_days: number; average_hydration_ml: number };
  insight?: { summary: string; highlights: string[]; areas_to_improve: string[]; coaching_notes: string };
  generated_at?: string; period_start?: string; period_end?: string }
```

---

## 5. Screens

For each screen: layout (top → bottom), element → data source, states, interactions.

### 5.1 Boot / Loading screen
**Visual:** leaf-sprout illustration, title "Getting your day ready…", a progress bar.
**Data:** the bar advances per **completed real step** (`/auth/me` → `dayView[today]` → `progressWeek`), with the caption showing the current step ("Checking your session", "Loading today", "Reading your week"). Remove the "68%" number. Minimum display 400 ms to avoid a flash; if a step takes > 8 s, show "Taking longer than usual…" + Retry.
**Errors:** `/auth/me` 401 → Login. Network failure → "Can't reach ZenLog" + Retry + "Open offline view" (cached user only).

### 5.2 Welcome (first launch only)
Elements: logo, tagline "Small steps. Big changes.", headline, 6 feature tiles (Nutrition & Macros, Workouts & Activity, Hydration, Habits & Routine, Mood & Wellness, AI Insights), hero image, **Get Started** → Login. All static. Never shown again after the first successful login.

### 5.3 Login
Elements: logo, "Welcome Back", **Username** field, **Phone Number** field (numeric keypad, accepts `+91` or 10 digits; strip spaces), **Login** button, footer "Your data is private & secure".
**Remove:** "OR" divider, "Continue with OTP".
**API:** `POST /api/auth/login { username, phone_number, device_id, device_name }` → store `access_token` in **secure storage** (Keychain/Keystore) and `user` in authStore.
**States:** button disabled until both fields valid; loading spinner in button; `401/404` → inline error "Username and phone number don't match"; `429` → "Too many attempts. Try again in a few minutes"; network → "Can't reach server".
**Behavior:** after logout, prefill the last username. Never store the phone number in plain storage.

### 5.4 Home / Day screen (the core screen)

One component, **`DayScreen`**, driven entirely by `dayView[selectedDate]`. Same layout skeleton in every mode; blocks switch on `mode`.

**Header**
- Greeting: "Good morning/afternoon/evening, {name}" for `today`; for other dates show the weekday + date ("Tuesday, Sep 30") instead of the greeting.
- Initials avatar (opens Profile tab).
- **Date strip** (horizontal scroll, ±14 days around `serverToday`): chip = weekday letter + day number. States: selected (`primary` fill), today (dot under), future (dimmed but tappable), has-entries (small dot, from calendar data). Tapping sets `selectedDate`. A "Today" pill appears when `selectedDate ≠ serverToday` and jumps back.
- **Week banner** (below the strip, only if `week_context.alerts` is non-empty): highest severity alert text, tinted `warn`/`danger`; tap → Insights (weekly).

**Mode `today`**
1. **Progress card** (replaces the protein pill row; the compact pill still shows in the header area on scroll):
   - Rows for Protein, Water, Calories (only if `targets.calories_kcal != null`), Workout.
   - Each row: icon, label, `actual / target unit`, progress bar filled to `pct` (cap visual at 100%), a thin **pace tick** at `expected_pct_now`, a status chip (`met`, `on pace`, `behind`, `falling short`, `over`) using the color map, and `progress.<metric>.message` as a one-line hint under the row.
   - Workout row: "Today: Done ✓ / Not yet" and "This week: `week_done`/`week_target`".
2. **Alert chips** from `progress.alerts` (max 2 visible, "+N more" expands).
3. **Quick log input** card: multiline text field, placeholder "What did you eat, do, or reflect on?", **+ Log** button. Enter submits only via button (multiline). Empty text disabled. On submit: optimistic insert as `pending`, clear field, `POST /api/logs`. A small "calendar" icon lets you change the entry time/date (default now; only past dates allowed; max 14 days back).
4. **Today's stream** (timeline): each `EntryCard`:
   - Left: category icon chosen from `extracted` (meal → utensils, workout → running, learning → book, mood only → smile, none → pencil).
   - Time (`time_display`), `text`.
   - Right: pencil (edit text/time), trash (delete with confirm).
   - Footer chips by `extraction_status`:
     - `pending`: shimmer chip "Analyzing…"
     - `done`: chips like `+19g protein`, `315 kcal`, `500 ml`, `Workout 45m`, `Mood: calm and focused`; a small dot for `goal_alignment.rating` (good = green, neutral = grey, poor = red). Chips show **effective values** (override wins) and a tiny ✎ if overridden.
     - `failed`: red chip "Couldn't analyze · Retry" → `POST /api/logs/{id}/retry`.
   - Tap card → **Entry detail sheet** (§5.9).
5. **Summary tiles** (Hydration, Protein) can remain as in the mockup, but they must use `totals` + `targets` and the same status colors. Add Calories and Workout tiles in a 2×2 grid (the Progress card in step 1 may replace these; pick one, don't duplicate).
6. **"Analyze my day so far" card** (replaces "Sleep & Synthesize Day"): subtitle "Get a quick review of today". Tap → `POST /api/days/{date}/analyze` → show verdict skeleton → poll. Disabled with a hint when cap reached (`429` from backend → "Daily limit reached").
7. **Verdict card** (when `verdict` present) — see §5.7.
8. Footer link: "Log wake / sleep time (optional)" → §5.5 sheet.

**Mode `past` (with logs)**
- Top: **Score ring** (`score`), rating label (Good/OK/Poor), AI `headline`.
- **Metric breakdown** rows from `verdict.metric_breakdown` (status icon ✓ / ⚠ / ✗ + `pct`).
- **Verdict card** (§5.7).
- **Entries** list (same `EntryCard`, but delete/edit behind the overflow menu; still allowed).
- "Add entry for this day" button (opens input with this date preselected).
- Status badge next to the date: "Reviewed" if `is_closed && verdict_status == 'done'`, "Writing review…" if pending, "Review failed · Retry" if failed.

**Mode `past` (no logs)**
- Illustration-free empty state: "Nothing logged for {Weekday}." + **Add an entry for this day** (primary button) + hint "You can backfill up to 14 days."
- `rating = insufficient_data` → no ring.

**Mode `future`**
- **Hide** the input, stream, progress card, analyze card.
- **Motivation card** from `motivation`: `headline` (large), `message`, `focus_points` as a checklist-style list, tone styling (`push` → amber accent, `steady` → green, `celebrate` → success with leaf icon).
- **Plan for the day** card: targets from `motivation.plan` (protein, calories if set, water, "Training day suggested" if `suggested_workout`).
- A disabled input row reading "You can log this day when it arrives." (tap shows toast, no API call).

**Loading / error**
- While `dayView[selectedDate]` is loading: skeleton blocks in the shape of the current layout. **Never** render the previous date's data.
- On error: inline card "Couldn't load this day" + Retry. Keep header and date strip functional.

**Polling**
- If `pending_count > 0` **or** `verdict_status == 'pending'`: refetch `dayView[selectedDate]` every 2 s for up to 30 s. Then stop and show "Taking longer than usual · Retry" on the pending items. Resume polling only on user action.

### 5.5 Optional Wake/Sleep sheet
Bottom sheet reached from the Day screen footer link. Two time pickers: "Woke up" (`POST /api/days/{date}/wake {wake_time}`), "Went to sleep" (`POST /api/days/{date}/sleep {sleep_time}` — for an already-added day use `PUT`). Pre-fill from `dayView.wake_time/sleep_time`. These are **optional**; never auto-popup, never gate anything. If you want a nudge: a single dismissible inline row in the Day header, "Add wake time?", shown only on `today` when `wake_time == null`, dismissed state remembered per date locally.

### 5.6 Days (calendar) screen
- Header: back arrow, "Your days", calendar icon (jumps to current month).
- **Month selector** `‹ October 2026 ›` (changes `calendarMonth`).
- **Single month grid** (Sun–Sat). **Do not** render the extra week strip seen in the mockup.
- Data: `GET /api/calendar?from=<first>&to=<last>` (include leading/trailing days shown in the grid).
- Day cell markers:
  | Condition | Marker |
  |---|---|
  | `rating = good` | filled green circle with ✓ |
  | `rating = ok` | filled amber circle |
  | `rating = poor` | filled red circle |
  | `insufficient_data` with logs | grey filled dot |
  | `logs_count = 0`, past | hollow outline |
  | `mode = future` | dashed/dimmed outline |
  | today | ring in `primary` + dot |
  | `workout = true` | tiny dumbbell badge at top-right of cell |
- Tap a cell → set `selectedDate`, switch to Home tab.
- **Selected-day summary card** (bottom, like the mockup): date + "Today"/"Reviewed" badge; protein `x / y g`, hydration, workout Yes/No, mood (from the day's extracted mood if available via `dayView`); "Journal entries (n)" mini list (first 3) with chevrons; **View full day →** switches to Home.
  - For future dates the card shows the motivation headline instead of stats.
- Legend row: Good · OK · Poor · Not rated · No entries.
- Loading: grid skeleton; error: retry card.

### 5.7 Verdict card (shared component)
Appears on `today` (after Analyze) and on `past` days.
- Header: sparkle icon + headline; rating pill.
- `verdict_summary` paragraph.
- Two columns/blocks: **Went well** (✓ list) and **Hurt your goal** (⚠ list); each max 3.
- **Food review**: rows `time · text_ref · rating dot · comment`.
- **Fixes for tomorrow**: numbered list.
- **Coaching note**: tinted box with lightbulb.
- Footer: "Generated {time}" + "Regenerate" (calls analyze; hidden if cap reached).
- States: `pending` → skeleton "Writing your review…"; `failed` → "Review unavailable" + Retry; if only the deterministic part exists (`ai == null`), show the metric breakdown and a "Generate review" button.
- Tone: never show positive-colored UI for `poor` ratings; headline color follows rating.

### 5.8 Insights screen
- Header: back, "Your insights", sparkle (refresh AI report → refetch `insights`, no new endpoint).
- Toggle **Weekly | Monthly** (`insightsPeriod`).
- A **period navigator** ("Sep 28 – Oct 4" with ‹ ›) driving the `anchor` param; default current period.
- **Stat tiles (2×2)** from `/api/stats/{weekly|monthly}`:
  | Tile | Field |
  |---|---|
  | Completed days | `completed_days` |
  | Avg protein | `average_protein_g` (g) |
  | Target adherence | `protein_target_adherence_percent` (%) |
  | Workout days | `workout_days` |
  Color the adherence tile by status (≥ 80% green, 50–79 amber, < 50 red).
- **Progress alert banner** from `progressWeek.alerts[0]` (e.g. "1 of 3 workouts done, 3 days left").
- **Protein Trend chart** from `progress.daily[]`: bars = `protein_g`, dashed line = `protein_target_g`, bar color by rating (green/amber/red/grey). Future days in the period render as empty slots, not zeros. Tap a bar → tooltip with date, grams, score; tap tooltip → jump to that day.
  - Monthly: same chart, bars per day (scrollable) or per week; keep it readable on a phone.
- **Week "needs" cards**: Workouts (`needs`), Protein days (`needs`), Water (avg vs target) with status colors.
- **AI Life Report card** from `/api/insights/{weekly|monthly}`:
  - `insight.summary`; **Key wins** = `insight.highlights`; **Areas to improve** = `insight.areas_to_improve`; **Coaching note** = `insight.coaching_notes`; badge "Weekly"/"Monthly".
  - If `insufficient_data`: card reads "Log at least 3 days to unlock your report ({days_logged}/3)" with a progress hint. No empty AI card.
  - Loading: skeleton. Error: retry. Generating can take several seconds; show shimmer.

### 5.9 Entry detail sheet
Opened from any `EntryCard`.
- Title: time + date; original `text` (editable inline via pencil → `PUT /api/logs/{id}`; after save, status returns to `pending`).
- **Extracted facts** (read-only unless overridden): item table (food, quantity, protein, kcal, confidence badge `low/unknown` = amber "rough estimate"), hydration, workout, learning, habits, mood, alignment reason + flags.
- **Edit values** button → fields for protein (g), calories, hydration (ml) → `PATCH /api/logs/{id}/override`. Shows "manual value" tag; "Reset to AI value" clears (`null`).
- `failed` → big **Retry analysis** button.
- **Delete** (destructive, confirm) → `DELETE /api/logs/{id}`.
- `extraction_error = daily_cap_reached` → message "Daily AI limit reached. Try tomorrow, or add values manually," and expose Edit values.

### 5.10 Profile screen
- Header: initials avatar, name, `@username`. No tagline, no edit pencil.
- **My Goals** card: chips `Muscle Gain | Fat Loss | Maintenance | Mindfulness` (single-select, `PUT /api/users/me {goal}`), and two stat tiles: Body weight, Daily protein target (tap to edit).
- **Targets** card (new): Protein target (g), Calorie target (kcal, optional "Not set"), Water target (ml), Workouts per week, Eating window (start/end time pickers). Footnote: "Changes apply from today onward."
  - Editing: tap a row → bottom sheet with numeric input + Save; validate (protein 20–400, calories 800–6000, water 500–8000, workouts 0–7, window end > start). Save → `PUT /api/users/me`, optimistic update, rollback on error.
  - Helper: next to the calorie row, "Not set: calories won't count toward your score".
- **Personal information** list: Name, Username (read-only), Goal, Body weight, Daily protein target (rows open the same editors; username not editable, no endpoint).
- **Security & Account**: **Log out** only → `POST /api/auth/logout` (revokes this device) → clear secure storage + caches → Login. Remove "Change Password".
- Footer small text: app version.

---

## 6. Shared Components (build once)

| Component | Props | Notes |
|---|---|---|
| `DateStrip` | `selected`, `today`, `markers`, `onSelect` | Windowed ±14 days |
| `StatusChip` | `status` | Color/label from §2 map |
| `MetricRow` | `label, icon, progress` | Bar + pace tick + message |
| `ProgressRing` | `score, rating` | For score display |
| `EntryCard` | `entry, mode` | Handles pending/done/failed |
| `ExtractionChips` | `extracted, overrides` | Effective values |
| `VerdictCard` | `view` | §5.7 |
| `MotivationCard` | `motivation` | Tone variants |
| `BottomSheet` | — | Used for entry detail, editors, wake/sleep |
| `EmptyState` | `title, action` | No illustrations needed |
| `Skeleton` | `variant` | Day/Calendar/Insights shapes |
| `Toast` | `message, type` | Non-blocking errors |
| `TimeField` / `NumberField` | — | Validation inline |

---

## 7. Copy Catalog (keep voice: calm, direct, no cheerleading)

| Status/State | Copy |
|---|---|
| `met` | "Target hit" |
| `on_track` | "On pace" |
| `behind` | Use backend `message` (e.g. "106g left. ~35g per meal.") |
| `far_behind` | Use backend `message` |
| `over` | "{n} over target" |
| `impossible` | "Can't reach this week. Aim for {n}" |
| Entry pending | "Analyzing…" |
| Entry failed | "Couldn't analyze · Retry" |
| Verdict pending | "Writing your review…" |
| Verdict failed | "Review unavailable · Retry" |
| Day empty | "Nothing logged for {Weekday}." |
| Future logging | "You can log this day when it arrives." |
| Insights locked | "Log at least 3 days to unlock your report ({n}/3)" |
| Offline | "Can't reach ZenLog. Showing saved data." |
| Low confidence | "Rough estimate" |

Always prefer **backend-provided `message`/`needs`/`text`** over re-inventing wording.

---

## 8. Behavior Rules

1. **Optimistic log creation:** insert `pending` immediately; if `POST` fails, mark the card `failed` with "Not saved · Retry" (this is a *save* failure, distinct from extraction failure) and keep the text so nothing is lost.
2. **Draft safety:** persist the unsent input text locally per date; restore on reopening.
3. **Rapid date switching:** cancel in-flight requests for the previous date; ignore late responses (key by date).
4. **Pull-to-refresh** on Home, Days, Insights → invalidate respective queries.
5. **App foreground:** refresh `serverToday`, refetch `dayView[selectedDate]` if stale (> 60 s).
6. **Haptics:** light tap on log submit and status transitions (optional).
7. **Numbers:** protein/calories rounded to integers in chips, 1 decimal in detail sheet; water in ml below 1000, liters with 1 decimal (`2.2 L`) above; percentages as integers.
8. **Time display:** IST 12-hour; dates "Thu, Oct 1".
9. **Destructive actions** (delete log, log out) always confirm.
10. **Accessibility:** status is never color-only (icon + text), tap targets ≥ 44 pt, text scales with system font size, progress bars have accessible labels ("Protein 19 of 126 grams, behind pace").

---

## 9. Error & Empty-State Matrix

| Situation | UI |
|---|---|
| No network on launch, cached user | Home from cache, offline banner, retry in background |
| `401` anywhere | Clear session → Login (once) |
| `422` on create log (future date) | Inline "You can't log a future day" |
| `429` login | Login inline message |
| `429`/cap on analyze/retry | Toast "Daily AI limit reached" |
| Gemini failures | Entry `failed` chip + retry; totals footnote "N entries not counted" |
| Day has `pending_count` stuck > 30 s | "Taking longer than usual · Retry" |
| Calendar fetch error | Retry card, grid still shows month skeleton |
| Insights `insufficient_data` | Locked-state card |

---

## 10. Acceptance Checklist

**Date handling**
- [ ] Tapping tomorrow shows the motivation + plan cards; no entries or input; no data from today visible, even briefly.
- [ ] Tapping 3 days ago shows that day's entries/score, never today's.
- [ ] Log typed at 00:40 appears under the *previous* day; `serverToday` flips only after 4 AM.
- [ ] Rapid chip tapping never shows mismatched data.

**Entries**
- [ ] New entry appears instantly as `Analyzing…`, resolves to chips within seconds.
- [ ] Editing text re-triggers analysis; override survives reload; failed entry has Retry.
- [ ] Today's progress bars and status update without leaving the screen.

**Progress and verdict**
- [ ] Same 15% protein reads `on pace` in the morning and `falling short` at night (pace tick visible).
- [ ] Week banner shows the top alert; Insights shows `needs` text.
- [ ] Poor days never use green styling; verdict text never contradicts rating.

**Auth**
- [ ] Login once; kill/reopen app → Home with no login screen.
- [ ] Logout returns to Login with username prefilled; other device unaffected.
- [ ] No OTP or password UI anywhere.

**Profile**
- [ ] Target edits persist; footnote visible; closed days unchanged.

**Visual**
- [ ] Matches theme tokens; leaf art only on Welcome/Login/Boot; no duplicate week strip in Days.

---

## 11. Backend Amendments This UI Requires

The v2 backend doc needs these small additions so the UI never has to invent data:

| # | Change | Why |
|---|---|---|
| **A1** | Add `daily[]` (`date, protein_g, protein_target_g, score, rating, workout`) to `GET /api/progress/week` and `/month` | Insights trend chart; `/stats/*` returns only aggregates |
| **A2** | `GET /api/auth/me` and `POST /api/auth/login` return `server_today` (logical date, 4 AM rule) | UI must not use device clock |
| **A3** | `GET /api/days/{day}/view` includes `week_context.alerts` and `wake_time/sleep_time` | Week banner, optional sheet prefill |
| **A4** | `GET /api/calendar` returns `mode, rating, score, logs_count, protein_g, protein_target_g, workout` per day | Calendar markers and summary card |
| **A5** | `POST /api/logs/{id}/retry` and `POST /api/days/{day}/analyze` return `429` with `{"code":"daily_cap_reached"}` | Cap messaging |
| **A6** | `POST /api/auth/login` accepts `device_id`, `device_name` | Rolling device sessions |

---

## 12. Build Order (hand to the builder as the task list)

1. API client, types (§4), secure-storage auth, `/auth/me` boot flow, real-step Boot screen.
2. `dateStore` + `dayView` query + `DayScreen` skeleton with the four modes (§5.4), `DateStrip`.
3. `EntryCard`, optimistic log creation, polling, entry detail sheet with override/retry/delete.
4. Progress card with pace tick, alerts, week banner.
5. Verdict card + Analyze flow; Motivation + Plan cards for future dates.
6. Days calendar with rating markers and summary card.
7. Insights: stat tiles, trend chart from `daily[]`, needs cards, AI report with locked state.
8. Profile: goal chips, targets editors, logout; remove OTP/password/avatar-edit/tagline.
9. Empty/error states, offline handling, accessibility pass, run §10 checklist.
