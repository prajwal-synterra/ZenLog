# ZenLog — UI/UX Design System & Flow Spec (v3 "Ink & Paper")

This file **replaces the visual direction** of `ZENLOG_UI_GUIDE.md`. The data contracts (types, endpoints, query keys, amendments A1–A6) from that guide and from `ZENLOG_V2_UPGRADE.md` are still valid. Anything about colors, typography, layout, components, popups and flows is overridden by this file.

---

## 0. Instructions to the builder

You are re-skinning and re-structuring an existing, working ZenLog app. Follow these rules:

1. **Replace the theme first**, before touching screens. No mint-green wellness palette, no navy cards, no emoji in UI chrome. Use only the tokens in §3.
2. **Every number, status, rating, and sentence about the user's day comes from the API** (§9). The client formats and colors; it never computes scores, statuses, or "today".
3. **Fix the audit items in §1 before adding anything new.** Several screens currently show fake or unwired data.
4. **One modal at a time.** No popups on app open except a session-ended notice. Interruptions are earned (§7 rules).
5. Build for **Android first** (back-button behavior in §4.3), but keep iOS parity.
6. Stack is unspecified: use the app's existing framework, router and query library. Names in this file are the contract.

---

## 1. Audit of the Current Build (from your 4 screenshots)

I'm judging only what's visible in the screenshots. Confirm each in code.

| # | Where | What I see | Why it's a problem | Severity |
|---|---|---|---|---|
| 1 | Insights | Tiles say `0 completed days / 0.0 g / 0%`, but the chart shows bars `82, 96, 104, 88, 102, 19` | Those are the exact numbers from the reference mockup. The chart is hardcoded, not wired to data. The screen contradicts itself | **Blocker** |
| 2 | Insights | AI Life Report text: "…shows no completed days and no recorded…" | A paid Gemini call was spent describing empty data. The ≥3-days guard is missing or not honored | **Blocker** |
| 3 | Insights | Chart bars Mon–Fri all green though every one is below the 126 g target; Saturday amber | Color logic is arbitrary. Color must follow `rating` | High |
| 4 | Days | Today (Oct 1) has no marker, and the summary card is empty with only a dumbbell and "None" | Calendar isn't wired to `/api/calendar`. Home shows entries for today, so this is a data bug | **Blocker** |
| 5 | Home | Date strip shows 17–23 (Sep) with no selected chip visible | The strip doesn't scroll to or highlight the selected date. You land on today but can't see it | High |
| 6 | Home | Dark navy Progress card | Off-brand, heaviest element on the screen, and it makes a normal mid-day state look like an alarm | High |
| 7 | Home | `Score: 24/100` at 4 PM | A final-looking grade for a day still in progress is misleading and discouraging | High |
| 8 | Home | Two stacked red alerts: "118g protein left. ~118g per remaining meal." | 118 g in one meal is not a realistic instruction. Two red banners at once is alarm fatigue | High |
| 9 | Home | The "Log Entry" button floats over the list and covers the delete icon of the second entry | Primary action blocks content and touch targets | Medium |
| 10 | Home | Orange and green dots beside entry times with no legend | Color-only meaning with no explanation | Medium |
| 11 | Insights/Profile | Emoji icons (avocado, target, weightlifter, scale, leaf) mixed with line icons | Inconsistent, looks templated | Medium |
| 12 | Profile | Goal chips clipped: "Maintenance" cut off, "Mindfulness" hidden, no scroll cue | Hidden options | Medium |
| 13 | Insights | Tile says "Completed days" and shows 0 while today has entries | "Completed" means closed days; users read it as "days I logged". Rename and define | Medium |
| 14 | Profile | 126 g protein target at 54 kg is ~2.3 g/kg | Near the top of commonly cited ranges. Fine if intentional, but the app should show g/kg so you can see why scores feel harsh | Low |

Why the UI "looks the same": the previous guide told the builder to keep the reference visual identity (§0 rule 5). This version removes that rule.

---

## 2. Design Principles

1. **Journal first.** Writing an entry is always one tap away, in the thumb zone, never covered by anything.
2. **One next move.** Show the single most useful action, not a wall of warnings.
3. **Honest, not punishing.** Don't grade an unfinished day. Color follows real status, and red is reserved for "genuinely off track" (the backend decides).
4. **Numbers you can trace.** Every figure maps to an API field (§9).
5. **Interruptions are earned.** No popups unless the user did something or the system genuinely needs input.
6. **Readable at 5 AM and midnight.** First-class dark theme; large numerals; high contrast.
7. **Calm density.** Hairlines instead of shadows, generous spacing, one accent color used sparingly.

---

## 3. Visual Identity — "Ink & Paper"

Concept: a well-made paper journal. Warm paper background, ink-black text, one marigold accent, and editorial serif headlines for dates and verdicts. Distinct from the green wellness template.

### 3.1 Color tokens

```json
{
  "light": {
    "bg": "#F7F3EA",
    "surface": "#FFFDF8",
    "surfaceAlt": "#EFE9DB",
    "line": "#E3DCCB",
    "ink": "#1D1B17",
    "inkMuted": "#6B665B",
    "inkFaint": "#9A9487",
    "onInk": "#F7F3EA",
    "accent": "#E8A33D",
    "onAccent": "#1D1B17",
    "success": { "fill": "#2F7D5B", "tint": "#E1F0E7", "text": "#1F5A40" },
    "info":    { "fill": "#3E6A8A", "tint": "#E0EBF3", "text": "#2B4D68" },
    "warn":    { "fill": "#D98E04", "tint": "#FBEFD3", "text": "#7A4B00" },
    "danger":  { "fill": "#C0412F", "tint": "#F8E0DB", "text": "#8E2B1D" },
    "scrim": "rgba(29,27,23,0.45)"
  },
  "dark": {
    "bg": "#14130F",
    "surface": "#1D1B16",
    "surfaceAlt": "#26231D",
    "line": "#34312A",
    "ink": "#F3EEE2",
    "inkMuted": "#A8A294",
    "inkFaint": "#7A7568",
    "onInk": "#14130F",
    "accent": "#F2B544",
    "onAccent": "#14130F",
    "success": { "fill": "#5DBB8A", "tint": "rgba(93,187,138,0.16)", "text": "#8FD7B0" },
    "info":    { "fill": "#7FB0D6", "tint": "rgba(127,176,214,0.16)", "text": "#A9CBE6" },
    "warn":    { "fill": "#F2B544", "tint": "rgba(242,181,68,0.16)",  "text": "#F6CC7E" },
    "danger":  { "fill": "#E8715E", "tint": "rgba(232,113,94,0.16)",  "text": "#F2A394" },
    "scrim": "rgba(0,0,0,0.6)"
  }
}
```

Hex values are my design choices, not sampled from anything. Run a contrast check: body text must hit WCAG AA (4.5:1), large text 3:1. Never put `fill` colors behind small text; use `tint` + `text`.

**Status → token mapping (single source):**

| Status / rating | Token | Icon | Label |
|---|---|---|---|
| `met`, rating `good` | success | check-circle | Target hit / Good |
| `on_track` | info | trending-up | On pace |
| `behind`, rating `ok` | warn | alert-circle | Behind / OK |
| `far_behind`, `over`, rating `poor` | danger | alert-triangle | Falling short / Over / Poor |
| `impossible` | danger (tint only) | ban | Can't reach this week |
| `insufficient_data`, no data | inkFaint | minus-circle | Not enough data |

Never convey status by color alone: always icon + text.

### 3.2 Typography

- **Display (dates, verdict headlines, motivation, big numerals):** Fraunces (variable, weights 500–700). Fallback `Georgia, serif`.
- **UI:** Inter with `font-variant-numeric: tabular-nums` on every number so digits don't jitter while animating. Fallback system sans.
- Bundle fonts as app assets (no runtime network fetch).

| Style | Font | Size/Line | Weight |
|---|---|---|---|
| Display XL (day name) | Fraunces | 40/44 | 600 |
| Display (verdict headline) | Fraunces | 28/34 | 600 |
| Title | Inter | 22/28 | 650 |
| Heading | Inter | 18/24 | 600 |
| Body | Inter | 16/24 | 400 |
| Body-S | Inter | 14/20 | 400 |
| Caption | Inter | 12/16 | 500 |
| Numeral-L (metric value) | Inter | 28/32 | 700 |
| Numeral-S (chips) | Inter | 13/16 | 600 |

Support system font scaling up to 130% without clipping.

### 3.3 Shape, spacing, elevation

- Spacing grid 4: `4, 8, 12, 16, 20, 24, 32, 40`. Page margin 16. Gap between cards 12.
- Radius: card 16, input 12, chip 999, sheet top corners 24, button 14.
- **Cards use a 1 px `line` border and no shadow** (paper feel). Only sheets, the composer dock and toasts have elevation (`0 -8 32 rgba(29,27,23,0.12)`).
- Tap targets ≥ 48 dp. Primary button height 52.
- Bottom nav height 64 + safe area. Composer dock min height 56.

### 3.4 Iconography

Lucide outline set, 1.75 stroke, 22 px. **No emoji in app chrome.** Emoji allowed only inside the user's own entry text. Mapping: meal `utensils`, water `droplet`, workout `dumbbell`, learning `book-open`, mood `smile`, habits `calendar-check`, AI `sparkles`, sleep `moon`, wake `sun`, today `sun-dim`, settings `sliders-horizontal`.

### 3.5 Motion & haptics

- Durations 120 / 200 / 320 ms; easing `cubic-bezier(0.2, 0.8, 0.2, 1)`.
- Pace bars and numbers animate 600 ms when data changes. New entry slides down 200 ms. Sheets rise 320 ms.
- Skeleton shimmer 1.2 s loop, low contrast.
- Respect OS "reduce motion": replace with fades.
- Haptics: light on send, selection change; success on status → `met`; none on errors except a single warning tick on destructive confirms.

### 3.6 Theme behavior

Default: follow system. Override in Me → Appearance (System / Light / Dark), stored locally. All components consume tokens, never raw hex.

---

## 4. Information Architecture & Navigation

### 4.1 Map

```
Splash ──► (no token) ─► Welcome carousel (first launch only) ─► Login ─► Setup wizard (first login only) ─┐
   │                                                                                                      │
   └─► (token) ─► Shell skeleton ─► /auth/me ──────────────────────────────────────────────────────────────┤
                                                                                                          ▼
                       ┌──────────── Bottom tabs ────────────────────────────────────────────────┐
                       │  Today   │   Days    │   Insights    │    Me                           │
                       └──────────┴───────────┴───────────────┴─────────────────────────────────┘
Today:  date strip · pace card · next move · entries · composer dock
        ├─ Entry detail sheet ─► Edit text · Override values · Retry · Delete (undo)
        ├─ Verdict (inline) ─► Regenerate
        ├─ Time/Date picker sheet (backfill)
        └─ Wake/Sleep sheet
Days:   month grid · day summary card ─► "Open day" ─► Today tab with that date
Insights: Week|Month · tiles · trend chart · needs · AI report
Me:     goals · targets editors · appearance · this device · log out
```

Tab labels: **Today · Days · Insights · Me**.

### 4.2 Global state
Same as the previous guide §3.2: `authStore` (token, deviceId, user, `serverToday`), `dateStore.selectedDate`, `uiStore`. Plus `themeStore`, `coachmarksSeen` (local flags), `composerDraft[date]`.

### 4.3 Back-button rules (Android)
1. Close keyboard → 2. Close topmost sheet/dialog → 3. If on a non-Today tab, go to Today → 4. On Today with `selectedDate ≠ serverToday`, jump to today → 5. On Today and today, press back twice within 2 s to exit (toast "Press back again to exit").

---

## 5. Core Workflows

### W1 First launch
Splash → Welcome carousel (3 slides, skippable) → Login → Setup wizard → Today. Flag `welcomeSeen` set at "Get started" or "Skip".

### W2 Returning launch
Splash (≤ 800 ms logo) → app shell with skeletons → `/auth/me`. `200` → render from cache then refresh; `401` → Login with username prefilled and notice P01; network error → cached Today + offline banner (P20).

### W3 Log an entry
Write → (optional time chip) → Send → optimistic card `Analyzing…` → chips appear → pace bars animate → next-move text updates. Failures: save failed (P11b), extraction failed (P09), cap (P10).

### W4 Fix an entry
Tap entry → Details sheet → Edit text (re-analyzes) / Override numbers / Retry / Delete with undo snackbar.

### W5 Browse days
Date strip or Days calendar → `selectedDate` → server returns `mode` → Today screen renders one of 4 modes.

### W6 Review a day
Past day: score ring + verdict. Today: **Analyze day so far** → pending → verdict card.

### W7 Weekly check
Insights → period toggle/navigation → tiles → chart → needs → AI report (or locked state).

### W8 Adjust targets
Me → tap row → editor sheet → Save → `PUT /api/users/me` → toast "Applies from today onward".

### W9 Session end
Logout (confirm) or `401` → clear secure storage + caches → Login. Unsent composer drafts stay locally and are restored after login.

### W10 Day rollover (4 AM)
On foreground/refresh, if `serverToday` changed and the user was on the old today → move `selectedDate` and show toast "New day started" (P19).

---

## 6. Screen Specs

Each screen: purpose → wireframe → element/data map → states.

### 6.1 Splash & Shell
- Logo: wordmark "ZenLog" in Fraunces, ink on paper, with a marigold dot after the "g". No spinner, no fake percentage.
- After 800 ms, render the app shell with skeletons. If `/auth/me` takes > 3 s, show a caption "Still connecting…" under the shell header.
- Error: network failure → cached state; never block on a spinner.

### 6.2 Welcome carousel (first launch only)

```
┌────────────────────────────────┐
│ ZenLog•                  Skip  │
│                                │
│  Write your day.               │  ← Fraunces 40
│  We'll do the math.            │
│                                │
│  ┌──────────────────────────┐  │
│  │ Breakfast: 3 eggs and a  │  │  ← slide 1: faux composer, typing animation
│  │ banana. Drank 500 ml.  ▮ │  │
│  └──────────────────────────┘  │
│                                │
│  ● ○ ○                         │
│  [      Get started        ]   │
└────────────────────────────────┘
```
- Slide 1 "Just write it." Typing animation of an example entry.
- Slide 2 "ZenLog reads it." Chips pop in: `+19 g protein`, `315 kcal`, `500 ml`.
- Slide 3 "See if you're on pace." A mini pace bar with a "now" tick and a status chip.
- Pure typography and UI fragments: no stock photos, no leaves. All static client content.
- CTA on last slide: **Get started** → Login. Swipeable; dots; skip always visible.

### 6.3 Login

```
┌────────────────────────────────┐
│ ZenLog•                        │
│ Welcome back.                  │  ← Fraunces 32
│ Use the username and phone     │
│ number you were set up with.   │
│                                │
│ Username                       │
│ [ prajwal              ]       │
│ Phone number                   │
│ [ +91 98765 43210      ]       │
│                                │
│ [          Log in          ]   │
│                                │
│ No account? Ask the person who │
│ set up ZenLog for you.         │
│ Your journal stays private.    │
└────────────────────────────────┘
```
- No OTP, no password, no sign-up (none exist in the backend).
- API: `POST /api/auth/login { username, phone_number, device_id, device_name }`. Store token in secure storage.
- Validation: username non-empty; phone digits, optional `+91`, spaces stripped. Button disabled until valid.
- Errors inline under the form: `401/404` "Username and phone number don't match."; `429` "Too many attempts. Try again in a few minutes."; network "Can't reach the server." with **Check connection** (pings `GET /health`).
- Prefill username after logout. Keyboard: numeric for phone, `Done` submits.

### 6.4 First-run Setup wizard (after first successful login)
Four steps, one decision per screen, progress dots, back allowed, **Skip for now** (defaults kept). One `PUT /api/users/me` at the end.

1. **Goal**: four cards, 2×2 grid, none clipped: Muscle gain · Fat loss · Maintenance · Mindfulness. Each has a one-line description of what ZenLog will emphasize.
2. **Body & protein**: body weight input; protein target input prefilled with `1.8 × weight`. Under it, a live `x.x g/kg` readout (local arithmetic, informational only). If outside 1.2–2.4 g/kg: neutral hint "That's {x} g/kg, outside the usual range. You can keep it."
3. **Daily targets**: calories (optional; "Skip: calories won't count toward your score"), water (default 3000 ml), workouts per week (stepper 0–7).
4. **Your eating window**: two time pickers (default 08:00–22:00). Explainer: "ZenLog uses this to judge your pace through the day."

Finish → Today. Flag `setupDone` stored locally (and in `users.setup_completed` if amendment B4 is added). If skipped, show a dismissible inline card on Today: "Set your targets for accurate pacing", once per day max.

### 6.5 Today screen

#### Header and date strip
```
┌────────────────────────────────┐
│ Thursday                  (P)  │  ← Fraunces 40; avatar = initials, opens Me
│ 1 October                      │  ← Inter 14 muted; "Today" pill if today
│                                │
│  M   T   W  [T]  F   S   S     │  ← strip, selected chip filled ink
│ 28  29  30  [1]  2   3   4     │     marker dot = has entries; marigold dot = today
└────────────────────────────────┘
```
- Strip: horizontal scroll with snap, ±14 days, **auto-scrolls so the selected chip is centered on mount and whenever `selectedDate` changes**. Selected = ink fill with `onInk` text. Today = small marigold dot. Future days dimmed (tappable). Entry markers come from `/api/calendar` for the visible window.
- A **Back to today** pill appears at the right of the header when `selectedDate ≠ serverToday`.
- For non-today dates, the header greeting is replaced with the weekday and full date, plus a mode badge: `Reviewed`, `Writing review…`, `Review failed`, `Planned`, `Not logged`.

#### Mode: today

```
│ ▌ Behind on protein and water. │  ← state line = progress.headline (Inter 16/600)
│                                │
│ ┌────────────────────────────┐ │
│ │ PACE                 Behind│ │  ← pace label chip (worst metric status)
│ │ Protein      8 / 126 g     │ │
│ │ [▓░░░░░░░░░░░░░¦░░░░░░░░]  │ │  ← fill = actual; ¦ tick = expected by now
│ │  hatch between fill & tick │ │     in status tint
│ │ Water      1000 / 3000 ml  │ │
│ │ [▓▓▓▓▓░░░░░░░░¦░░░░░░░░░]  │ │
│ │ Calories   (only if set)   │ │
│ │ Workout  ○ None today ·    │ │
│ │          this week 1 / 3   │ │
│ └────────────────────────────┘ │
│ ┌────────────────────────────┐ │
│ │ NEXT MOVE                  │ │  ← progress.next_action; single card
│ │ Aim for ~40 g protein at   │ │
│ │ your next meal.            │ │
│ │                  2 more ▸  │ │  ← expands remaining alerts
│ └────────────────────────────┘ │
│ ENTRIES                        │
│ │ ● 04:12 PM                   │
│ │ ▌I had Palav for breakfast   │
│ │   [+8 g protein][350 kcal]   │
│ │ ● 04:12 PM                   │
│ │ ▌I have taken 1 L of water   │
│ │   [1000 ml]                  │
│ ┌────────────────────────────┐ │
│ │ ＋  Write what you ate…  ➤ │ │  ← composer dock (docked, not floating)
│ └────────────────────────────┘ │
│  Today   Days   Insights   Me  │
```

**Pace card rules**
- Surface card with hairline border (no navy block). Header row: label `PACE` + pace chip (worst status among protein, water, calories; text from §3.1 map). If every metric is `met`: chip "Targets met".
- **Do not show a numeric score on today.** A day in progress is not graded. Score appears only on `past` days.
- Each metric row: label, `actual / target unit` (Numeral-S), a 10 px track. Fill color follows the status token. The **expected-by-now tick** sits at `expected_pct_now`. The gap between fill and tick is hatched with the status `tint`. Tap the row → popover explaining: "Expected by now: {expected_pct_now}% of your target, based on your eating window."
- Calories row only if `targets.calories_kcal != null`; otherwise no row (the Me screen carries the "set calorie target" CTA).
- Workout row: today done/not done and weekly progress `week_done / week_target` with status chip.
- Numbers animate on change.

**Next Move card**
- Shows `progress.next_action.text` (amendment B1). Fallback: `progress.alerts[0].text`.
- Only one card; remaining alerts collapse behind "N more". Alerts never appear as stacked full-width red banners.
- Tint follows the status of the metric it refers to (usually warn; danger only for `far_behind` + time past 70% of the eating window).
- **Realistic wording (amendment B2):** if the remaining amount per remaining meal exceeds ~45 g protein, the backend text must switch to recovery wording, e.g. "Today's full target is out of reach. Get ~40 g at dinner and reset tomorrow." The UI shows exactly what the backend returns.

**Entries (journal lines)**
- Timeline rail on the left with a small icon node (meal, workout, water, learning, mood, or pencil if unknown).
- Row: time (Caption muted), text (Body), chips beneath. A 3 px **left edge bar** shows goal alignment color (good/neutral/poor). The legend is in the Entry detail sheet and in a one-time coachmark.
- Chips (Numeral-S, tint backgrounds): `+19 g protein`, `315 kcal`, `500 ml`, `Workout 45 min`, mood text. Effective values (override wins) with a tiny pencil if overridden. Low-confidence items get a dotted underline and the "Rough estimate" popover.
- `pending`: chips replaced by a shimmer pill "Reading…". `failed`: danger tint row with "Couldn't read this · Retry".
- Gestures: swipe left = delete (danger), swipe right = edit; both also reachable from the ⋯ menu and from the details sheet (accessibility).
- Empty state (no entries yet today): "Nothing here yet. Write your first line below." with an arrow to the composer.

**Composer dock** (replaces the floating button)
- Docked above the tab bar, always visible on `today` and editable `past` modes. Collapsed: one line + send button. Expands up to 6 lines.
- On focus, a **quick-start chip row** appears above the keyboard: `Meal`, `Water`, `Workout`, `Mood`, `Reading`. They insert starter text only (e.g. `Lunch: ` chosen by device time of day, `Drank 500 ml water`, `Workout: `, `Feeling `, `Read `). Water chips: `+250 ml`, `+500 ml`, `+1 L` insert plain text. These are client conveniences that still send one text log to `POST /api/logs`.
- **Time chip** "Now ▾": opens the time picker (P13) for earlier times today; "Another day" opens the backfill date picker (P12). When set, the dock shows a context line "Logging for Tue 29 Sep, 8:30 AM" with an ✕ to reset.
- Send disabled for empty or whitespace text. Client max length 1000 chars (confirm the backend limit). Draft saved per date.
- Keyboard: dock lifts with the keyboard; bottom nav hides while the keyboard is open.

**Analyze card** (today, collapsed under entries): "Review my day so far", subtitle "Get a quick read on today". Disabled with hint after cap. Tap → `POST /api/days/{date}/analyze` → verdict skeleton → poll.

**Footer links:** "Add wake / sleep time" opens P15 (optional, never auto-shown).

#### Mode: past (with entries)
```
│ Wednesday               Reviewed │
│ 30 September                     │
│        ┌─────┐                   │
│        │ 71  │  OK               │  ← score ring (Fraunces numerals), rating chip
│        └─────┘                   │
│ "Solid training, protein short." │  ← verdict headline (Fraunces 28)
│ Protein   ✓/⚠/✗  88%  ...        │  ← metric breakdown rows (verdict.metric_breakdown)
│ [Verdict note]                   │
│ ENTRIES (read-only by default)   │
│ [＋ Add to this day]             │
```
Composer dock appears in "Add to this day" mode (collapsed button that expands the dock).

#### Mode: past (no entries)
Editorial empty state: Fraunces "Nothing written for Tuesday." Body: "You can add entries for up to 14 days back." Primary button **Write an entry**.

#### Mode: future
```
│ Friday                    Planned │
│ 2 October                         │
│                                   │
│ This is your catch-up day.        │  ← motivation.headline (Fraunces 32)
│ You're 1 workout behind this week │  ← motivation.message
│ and finished 24 g short on        │
│ protein yesterday.                │
│                                   │
│ FOCUS                             │
│ ☐ Train: 2 more workouts needed   │  ← focus_points (decorative checkboxes, not stateful)
│ ☐ Start with ~35 g protein        │
│                                   │
│ PLAN FOR THE DAY                  │
│ Protein 126 g · Water 3000 ml     │
│ Calories 2200 (if set) · Train    │
│ ┌───────────────────────────────┐ │
│ │ You can write this day when   │ │  ← disabled composer row
│ │ it arrives.                   │ │
│ └───────────────────────────────┘ │
```
Tone variants: `push` → warn tint accent bar; `steady` → neutral; `celebrate` → success tint. No entries list, no pace card, no analyze card.

#### Loading and error
Skeleton in the shape of the current mode; never show the previous date's data. Error: card "Couldn't load this day." + **Try again**; header and strip stay usable.

### 6.6 Entry details sheet
Opened by tapping an entry (full-height sheet, 90%).

```
┌────────────────────────────────┐
│ ━━                             │
│ 04:12 PM · Thu 1 Oct       ⋯   │
│ "I had Palav for breakfast"    │  [Edit text]
│                                │
│ WHAT ZENLOG UNDERSTOOD         │
│ Meal: breakfast                │
│ ┌──────────────────────────┐   │
│ │ Palav · 1 plate  8g 350  │   │  ← items table (food, qty, protein, kcal, confidence)
│ └──────────────────────────┘   │
│ Water 0 ml · Workout — · Mood —│
│                                │
│ FOR YOUR GOAL                  │
│ ▌ Neutral · "Carb-heavy, low   │  ← goal_alignment.rating + reason + quality_flags
│   protein for muscle gain."    │
│ [carb-heavy] [low protein]     │
│                                │
│ [ Edit values ]  [ Retry ]     │
│ [ Delete entry ]  (danger text)│
└────────────────────────────────┘
```
- Alignment legend: Good (success), Neutral (inkFaint), Poor (danger), each with icon + word.
- Confidence badges: `low`/`unknown` → "Rough estimate" with an info popover (P22).
- **Edit values** switches the table to inline numeric fields (protein g, kcal, water ml) with validation (§7 P08). Save → `PATCH /api/logs/{id}/override`. Shows "Manual value" tag and **Reset to AI value**.
- **Retry** visible for `failed` (primary) or as secondary after edits.
- Delete uses the undo pattern (P04), not a dialog.

### 6.7 Verdict note (shared component)
Editorial block, used on `past` days and after "Review my day so far".

```
│ ◆ DAY REVIEW                  OK │
│ Solid training, protein short.   │  ← Fraunces 28, color = rating text token
│ 2–3 sentence summary.            │
│                                  │
│ WENT WELL           HURT THE GOAL│
│ ✓ 45-min strength   ⚠ Dinner 8 g │
│ ✓ High-protein bfst ⚠ 1.4 L water│
│                                  │
│ FOOD, ENTRY BY ENTRY             │
│ 13:10 · biryani · ◐ Neutral      │
│   Carb-heavy, low protein.       │
│ FIXES FOR TOMORROW               │
│ 1 Add ~30 g protein at dinner    │
│ COACHING NOTE                    │
│ ┌──────────────────────────────┐ │
│ │ ...                          │ │
│ └──────────────────────────────┘ │
│ Generated 5:04 AM · Regenerate   │
```
States: `pending` → skeleton "Writing your review…"; `failed` → "Review unavailable" + Retry; `ai == null` but breakdown present → breakdown + **Generate review**. Tone: never use success styling for `poor` days.

### 6.8 Days (calendar)

```
┌────────────────────────────────┐
│ Journal                        │
│ ‹  October 2026  ›      [Today]│
│ S  M  T  W  T  F  S            │
│             (1)  2  3          │  ← today: marigold ring; selected: ink outline
│  4  5  6  7  8  9 10           │
│ ...                            │
│ ● Good ● OK ● Poor ○ None ◌ Not│
│   rated                        │
│ ┌────────────────────────────┐ │
│ │ Thursday, Oct 1      Today │ │
│ │ Protein 8 / 126 g          │ │
│ │ Water 1000 ml · Workout No │ │
│ │ 2 entries                  │ │
│ │ Palav · 1 L water          │ │
│ │ [ Open day ]               │ │
│ └────────────────────────────┘ │
```
- Data: `GET /api/calendar?from&to` for the visible grid. Cell = day number on a rounded square tinted by rating (good/ok/poor tints), grey for `insufficient_data`, hollow for no entries (past), dashed outline for future. A tiny dumbbell badge on `workout = true`.
- Month change by arrows or horizontal swipe. **Today** pill jumps to the current month and selects today.
- Tapping a cell updates the summary card (does not navigate). **Open day** sets `selectedDate` and switches to the Today tab.
- Summary card for a past day shows score, rating chip, protein, water, workout, entry count, first 2 entries. For today shows live totals. For future shows the planned headline and targets.
- Loading: grid skeleton. Error: retry card above a muted grid.

### 6.9 Insights

```
┌────────────────────────────────┐
│ Insights                    ✦  │  ← ✦ refreshes the AI report
│ [ Week ][ Month ]              │
│ ‹  Sep 28 – Oct 4  ›           │
│                                │
│ You're 1 workout behind with   │  ← headline = progress.alerts[0].text; hidden if none
│ 3 days left.                   │
│ ┌──────────┐ ┌──────────┐      │
│ │ 4        │ │ 102 g    │      │  ← Days logged | Avg protein
│ │ Days     │ │ Avg      │      │
│ │ logged   │ │ protein  │      │
│ └──────────┘ └──────────┘      │
│ ┌──────────┐ ┌──────────┐      │
│ │ 75%      │ │ 1 / 3    │      │  ← Target adherence | Workouts (done / target)
│ └──────────┘ └──────────┘      │
│ PROTEIN                        │
│ 150┤- - - - - - - - target 126 │
│    │   ▇   ▇  ▇  ▇             │  ← bars from progress.daily[], color by rating
│    └─M──T──W──T──F──S──S──     │
│ WHAT THIS WEEK NEEDS           │
│ Workouts · 2 in the next 3 days│  ← progress.workouts.needs
│ Protein · 3 of 3 remaining days│  ← progress.protein.needs
│ AI LIFE REPORT        Weekly   │
│ ...                            │
```
- **Tiles:** Days logged (rename of "Completed days"; = `progress.daily` entries with `logs > 0`, or `days_logged` from amendment B5) · Avg protein `average_protein_g` · Adherence `protein_target_adherence_percent` · Workouts `workouts.done / workouts.target`. Each tile has a one-line definition under an info icon.
- **Chart (fix for audit #1, #3):** only from `progress.daily[]`. Bar color = rating token (good/ok/poor, inkFaint for insufficient data). Target = dashed line at `protein_target_g`. Future days = empty dotted slots, not zero bars. Today's bar is partial (hatched top). Tap a bar → tooltip (date, grams, score) → tap tooltip opens that day. Month view: horizontally scrollable daily bars with week separators. Zero-data period: chart replaced by an empty state "Nothing logged this week."
- **AI Life Report:** serif headline = `insight.summary`; **Key wins** = `highlights`; **Areas to improve** = `areas_to_improve`; **Coaching note** = `coaching_notes`. If `insufficient_data` (fewer than 3 days logged): locked card "Log at least 3 days to unlock your report (1/3)" with a progress meter. **Never render an AI card describing empty data.**
- ✦ refetches `insights` only (no regenerate endpoint). Hide it if there's no report.

### 6.10 Me

```
┌────────────────────────────────┐
│ (P)  Prajwal                   │
│      @prajwal                  │
│ GOAL                           │
│ ┌────────────┐┌────────────┐   │  ← 2×2 grid, single select
│ │ Muscle gain││ Fat loss   │   │
│ └────────────┘└────────────┘   │
│ ┌────────────┐┌────────────┐   │
│ │ Maintenance││ Mindfulness│   │
│ └────────────┘└────────────┘   │
│ DAILY TARGETS                  │
│ Protein           126 g  2.3 g/kg ›
│ Calories          Not set   ›  │
│ Water            3000 ml    ›  │
│ Workouts / week    3 days   ›  │
│ Eating window  08:00–22:00  ›  │
│ Changes apply from today onward│
│ BODY                           │
│ Body weight        54.0 kg  ›  │
│ APPEARANCE                     │
│ Theme   System ▾               │
│ THIS DEVICE                    │
│ Pixel 7 · signed in            │
│ [ Log out ]                    │
│ ZenLog v2.x · Server connected │  ← GET /health
└────────────────────────────────┘
```
- Goal grid replaces clipped chips. Changing goal opens confirm dialog P17.
- Protein row shows `g/kg` (local arithmetic: `protein / body_weight`).
- Calorie "Not set" shows a helper line: "Calories won't count toward your score until you set a target."
- Username is read-only (no endpoint). No password, no avatar upload, no tagline.
- Footer "Server connected" from `GET /health` (green dot) or "Can't reach server" (danger).

---

## 7. Popup, Sheet, Dialog, Toast & Banner Catalog

**Global rules**
1. **Max one modal (dialog or sheet) at a time.** Never stack. A new modal replaces the current one only if the current has no unsaved input.
2. **No popups on app open** except P01. First-run coachmarks (P23) run once, only after the first successful log.
3. Prefer **inline states and snackbars** over dialogs. Dialogs only for destructive or semantic changes.
4. One snackbar at a time (queue the rest, 4 s each, 6 s with an action). Snackbars sit above the composer dock.
5. Every sheet: drag handle, swipe-down and back button close; confirm discard only when there's unsaved input.
6. Backdrop tap closes sheets, never dialogs.

| ID | Trigger | Type | Content | Actions | Notes / API |
|---|---|---|---|---|---|
| P01 | `401` in any call | Full-screen route + notice | "Your session ended. Log in again." | Log in | Clear token once; draft kept; username prefilled |
| P02 | Login failure | Inline (form) | Wrong combo / `429` / network messages (§6.3) | Check connection | `GET /health` for the check |
| P03 | Tap Log out | Dialog | "Log out of this device?" "Your journal stays saved." | Log out · Cancel | `POST /api/auth/logout`; warn tick haptic |
| P04 | Delete entry (swipe, ⋯, details) | Snackbar with Undo | "Entry deleted" | Undo (5 s) | Client waits 5 s, then `DELETE /api/logs/{id}`. App killed in that window → entry stays (safe) |
| P05 | Close composer with ≥ 20 chars unsent and user navigates away | Inline "Draft saved" chip | — | — | No dialog: drafts autosave per date and restore silently with a toast on return "Draft restored" |
| P06 | Tap entry | Sheet (90%) | Entry details (§6.6) | Edit text · Edit values · Retry · Delete | — |
| P07 | Edit text | Inline in sheet | Textarea + Save/Cancel | Save → `PUT /api/logs/{id}` | Row returns to `pending` |
| P08 | Edit values | Inline in sheet | protein (0–150 g), kcal (0–2500), water (0–3000 ml), whole numbers | Save · Reset to AI value | `PATCH /api/logs/{id}/override`; validate before send; `null` to clear |
| P09 | Extraction `failed` | Inline row state | "Couldn't read this · Retry" | Retry | `POST /api/logs/{id}/retry`; totals footnote "1 entry not counted" |
| P10 | `429 daily_cap_reached` (retry, analyze, extraction error) | Sheet (small) | "Daily AI limit reached. You can still add values by hand, or try tomorrow." | Edit values · OK | Disable Retry/Analyze for the rest of the day |
| P11 | Tap composer on a future day | Snackbar | "You can write this day when it arrives." | — | No API call |
| P11b | `POST /api/logs` network failure | Inline row state | "Not saved · Retry" (text preserved) | Retry · Delete | Distinct from extraction failure |
| P12 | Time chip → "Another day" | Sheet | Calendar for the last 14 days (future disabled) | Select | Sets composer context; `date` param on create |
| P13 | Time chip | Sheet | Time wheel (not in the future for today) | Set | Sets `timestamp` |
| P14 | "Review my day so far" | Inline loading in card | Skeleton "Writing your review…" | — | `POST /analyze`; poll `dayView` every 2 s ≤ 30 s |
| P15 | Footer "Add wake / sleep time" | Sheet | Two time rows: Woke up · Went to sleep | Save | `POST /api/days/{date}/wake`, `POST|PUT /api/days/{date}/sleep` |
| P16 | Tap a target row | Sheet (small) | Numeric input with unit, validation, helper (g/kg for protein) | Save · Cancel | `PUT /api/users/me`; validate ranges below |
| P17 | Change goal | Dialog | "Change goal to Fat loss?" "Scoring and calorie rules change from today. Past days keep their old targets." | Change goal · Cancel | `PUT /api/users/me {goal}` |
| P18 | Back with unsaved edits in an editor sheet | Dialog | "Discard changes?" | Discard · Keep editing | Only when fields changed |
| P19 | 4 AM rollover detected | Snackbar | "New day started" | View today | Moves `selectedDate` if user was on yesterday's "today" |
| P20 | Network down | Banner (top, persistent) | "Offline. Showing saved data." | Retry | Hides on success; writes queue is not supported, so the composer shows "Needs connection" and keeps the draft |
| P21 | Load error (day/calendar/insights) | Inline card | "Couldn't load this {day/month/report}." | Try again | Keeps shell interactive |
| P22 | Tap a low-confidence chip | Popover | "Rough estimate. ZenLog guessed the portion. Edit values if you know the exact amount." | Edit values | Only when `confidence` is low/unknown |
| P23 | After first successful log, then after first `done` entry, then after first week banner | Coachmark (max 3 total, one per session) | 1) "Tap a line to see how ZenLog read it." 2) "The tick shows where you should be by now." 3) "Colored edge = how it fits your goal." | Got it | Flags in `coachmarksSeen`; never repeat |
| P24 | Insights < 3 days data | Inline locked card | "Log at least 3 days to unlock your report (n/3)" | Go to Today | No API cost |
| P25 | Setup skipped | Inline card on Today | "Set your targets for accurate pacing." | Set targets · Dismiss | Shown at most once per day |
| P26 | End of eating window with unmet metric | Inline card (not modal) | "Day is almost over: protein 40 g short." | Open details | Uses backend `progress.alerts` |
| P27 | Week target impossible | Inline in Insights + week banner | `impossible` text from backend | — | No modal |
| P28 | Concurrent edit during `pending` | Silent | — | — | Backend hash guard; UI shows latest `pending` then `done` |
| P29 | Server error 5xx on mutation | Snackbar | "Something went wrong. Try again." | Retry | Keep optimistic state in failed form |
| P30 | App returns from background after > 60 s | Silent refresh | Skeleton only on first load | — | Refetch `dayView`, refresh `serverToday` |
| P31 | Health ping fails (Me footer) | Inline status | "Can't reach server" | Retry | `GET /health` |

**Not included on purpose:** push-notification permission prompt (no push in v1), rating prompts, update nags, "rate us", marketing modals.

**Validation ranges (client, mirror backend):** protein target 20–400 g; calories 800–6000 kcal; water 500–8000 ml; workouts 0–7; weight 20–300 kg; eating window end after start, at least 8 hours long.

---

## 8. Component Library (build once, tokens only)

| Component | Variants / states | Spec |
|---|---|---|
| `Button` | primary (ink fill, onInk text), secondary (surfaceAlt), tertiary (text), danger (text + icon) | 52 high; loading shows spinner replacing label, width fixed |
| `Input` | default, focus (2 px ink), error (danger tint + message), disabled | Label above, helper below |
| `Chip` | stat, status, filter, selectable | Tint bg + text token; 28 high |
| `StatusChip` | by status token | Icon + label, never color only |
| `PaceBar` | normal, no-target, over (clamped + overflow cap), loading | Track 10 px, tick at `expected_pct_now`, hatch gap |
| `PaceCard` | today | Header chip + 2–4 rows |
| `NextMoveCard` | tones warn/info/success | Left accent bar, one action text, "N more" |
| `DateStrip` | selected, today, future, marker | Snap + auto-center |
| `EntryRow` | pending, done, failed, overridden, past (read-only) | Left edge bar color, swipe actions |
| `ExtractionChips` | by data type | Effective values, low-confidence underline |
| `Composer` | idle, focused, with-context (date/time), disabled (future), sending | Quick-start chips row |
| `ScoreRing` | good/ok/poor/insufficient | Fraunces numeral center |
| `VerdictNote` | pending, done, failed, partial | §6.7 |
| `MotivationHero` | push/steady/celebrate | Fraunces headline |
| `CalendarCell` | rating tints, today, selected, future, workout badge | 44×44 min target |
| `TrendChart` | week, month, empty, locked | From `daily[]` only |
| `StatTile` | with definition info | Numeral-L + label |
| `Sheet` / `Dialog` / `Snackbar` / `Banner` / `Popover` | per §7 | One at a time |
| `Skeleton` | day, calendar, insights, entry, card | Shaped like final layout |
| `EmptyState` | per screen | Fraunces title, one action |
| `ThemeProvider` | light, dark | Token context; no raw hex outside tokens file |

---

## 9. Data-to-UI Rules & Backend Amendments

### 9.1 Rules
1. The client never calculates: score, rating, status, pace expected %, `mode`, "today". It may do **presentation-only math**: formatting, g/kg readout in editors, sorting.
2. If a field is `null`, hide its component rather than showing `0`.
3. Prefer backend strings (`message`, `needs`, `headline`, `next_action.text`) over client-written copy.
4. All dates/times shown in IST, 12-hour. Use `time_display` for entries.
5. Query keys and invalidation matrix: unchanged from the previous guide §3.3.

### 9.2 New backend amendments required by this design (in addition to A1–A6)

| # | Change | Why |
|---|---|---|
| **B1** | `GET /api/days/{day}/view` → `progress.headline` (one sentence), `progress.next_action {metric, text}`, `progress.pace_label` (`ahead|on_pace|behind|far_behind|met`) | State line, Next Move card, pace chip without client logic |
| **B2** | Realistic-gap rule: if remaining protein ÷ remaining meals > 45 g, `message`/`next_action` switch to recovery wording; add `catch_up_possible_today: bool` | Fixes "118 g per remaining meal" |
| **B3** | `score = null` and `rating = null` when `mode = today` | UI must not grade unfinished days |
| **B4** | `users.setup_completed: bool` (set by wizard) | Wizard shows once across devices (otherwise local flag only) |
| **B5** | `/api/stats/{weekly|monthly}` returns `days_logged` alongside `completed_days` | Honest tile naming |
| **B6** | Verify `insufficient_data` guard (< 3 logged days) in `/api/insights/*` before calling Gemini | Audit #2 |

---

## 10. Copy & Voice

Voice: calm, direct, specific, no cheerleading, no guilt. Short sentences. Numbers first.

| Situation | Copy |
|---|---|
| Composer placeholder | "Write what you ate, did or felt…" |
| Entry pending | "Reading…" |
| Entry failed | "Couldn't read this · Retry" |
| Pace chip | "Ahead" · "On pace" · "Behind" · "Falling short" · "Targets met" |
| Empty past day | "Nothing written for {Weekday}." |
| Future composer | "You can write this day when it arrives." |
| Insights locked | "Log at least 3 days to unlock your report ({n}/3)." |
| Offline | "Offline. Showing saved data." |
| Cap reached | "Daily AI limit reached. Add values by hand or try tomorrow." |
| Delete | "Entry deleted" + Undo |
| New day | "New day started" |
| Low confidence | "Rough estimate" |
| Targets footnote | "Changes apply from today onward." |

Avoid: "Great job!", exclamation marks, streak shaming, "you failed".

---

## 11. Accessibility, Performance, Platform

- **Accessibility:** status = icon + text; targets ≥ 48 dp; labels for pace bars ("Protein: 8 of 126 grams, behind pace"); swipe actions duplicated in ⋯ menu; screen-reader order = header → pace → next move → entries → composer; focus returns to the triggering control after a sheet closes; font scaling to 130%; reduced motion honored.
- **Performance:** render cached data instantly then revalidate; virtualize long entry lists; memoize chart; polling only while `pending_count > 0` or `verdict_status = pending` (2 s, max 30 s); cancel in-flight requests when `selectedDate` changes; image-free design keeps cold start light.
- **Localization:** en-IN, 12-hour time, `ml`/`g`/`kcal`, `1,000` grouping with lakh formatting not needed at these magnitudes.
- **Dark mode:** same layout, token swap; test every status tint for contrast.

---

## 12. QA Checklist

**Audit regressions**
- [ ] Insights chart shows real `daily[]` data; with no data it shows the empty state, never `82/96/104/88/102/19`.
- [ ] Insights with < 3 logged days shows the locked card and **no** AI text.
- [ ] Days calendar marks today and shows its real summary when Home has entries.
- [ ] Today's chip is centered and selected on launch, and after tapping Back to today.
- [ ] No navy/dark card in light theme; no emoji in chrome.
- [ ] No numeric score on today; score appears on closed past days.
- [ ] Only one Next Move card; no stacked red banners; no "118 g per meal".
- [ ] Composer dock never covers an entry or its actions.
- [ ] Goal selector shows all four options, none clipped.

**Flows**
- [ ] First launch: Welcome → Login → Setup → Today; second launch: straight to Today with no login.
- [ ] Logout returns to Login with username prefilled; a 401 mid-use does the same once and keeps the draft.
- [ ] Delete shows Undo; Undo restores; killing the app during the 5 s window keeps the entry.
- [ ] Edit text re-analyzes; override survives reload; Retry works after failure.
- [ ] Future day: plan + motivation only, composer disabled. Past empty: "Write an entry" works with the right date.
- [ ] 4 AM rollover shows the toast and moves selection when appropriate.

**Popups**
- [ ] Never two modals at once; back button closes in the order of §4.3.
- [ ] P10 cap sheet disables Retry/Analyze; P17 goal confirm; P18 discard only with changes.
- [ ] Coachmarks appear max 3 times total, once per session.

**Theming/A11y**
- [ ] Light and dark both pass contrast checks.
- [ ] Screen reader reads every pace bar with values and status.
- [ ] 130% font scale: no clipping on Today, Insights, Me.

---

## 13. Build Order

1. **Theme layer**: tokens (§3), fonts, `ThemeProvider`, icon set swap (remove emoji).
2. **Fix audit blockers**: wire Insights chart to `daily[]` (A1), wire Days to `/calendar` (A4), min-data guard (B6), date strip centering.
3. **Shell & flows**: Splash/Shell, Welcome carousel, Login copy/errors, Setup wizard, tab bar.
4. **Today screen**: header + strip, `PaceCard` with tick, `NextMoveCard` (B1/B2), `EntryRow`, composer dock + time/date sheets.
5. **Entry details**, override, retry, delete-with-undo.
6. **Verdict note** + Analyze; future-day Motivation hero; past-day score ring (B3).
7. **Days** summary card; **Insights** tiles/needs/AI/locked; **Me** goal grid, targets editors, g/kg readout, appearance, device, logout, health footer.
8. **Popup catalog** (§7) end to end, coachmarks, offline banner, rollover toast.
9. **Dark theme pass**, accessibility pass, run §12.
