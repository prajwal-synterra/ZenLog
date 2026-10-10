# ZenLog — Complete Feature & Functionality Overview

This document outlines **all active features, functions, and options** available in the ZenLog application across both the Flutter mobile client and the FastAPI backend.

---

## 1. Core Architecture & Philosophy

* **Natural Language Journaling:** Instead of tedious multi-step forms or searching databases, users log in plain English (e.g., *"3 boiled eggs, 1 scoop whey, 500ml water, 45 min chest workout"*).
* **Per-Entry AI Extraction (Gemini):** Every log is parsed in the background into structured metrics: protein, calories, hydration, workout, learning, habits, and mood.
* **Deterministic Calculations:** Totals, remaining targets, pace, and scores are calculated directly by code (not AI guesswork) to guarantee 100% accuracy.
* **4 AM Boundary Rule:** Night owls logging dinner or snacks after midnight (up to 3:59 AM) have their entries correctly assigned to the previous calendar day.
* **Offline-First & Fast Sync:** Entries are cached locally and synchronized seamlessly when internet connectivity is restored.

---

## 2. Screen-by-Screen Features & Options

### Screen 1: "Today" (Home / Journal Flow)
* **Header & Date Strip:**
  * Shows current day greeting, date, and user initials avatar.
  * Interactive 28-day horizontal date strip allowing one-tap switching between past, today, and future dates.
  * Instant "Back to today" shortcut.
  * Light / Dark Mode instant theme toggle button.
* **Circadian Morning Walk Card:**
  * Appears after logging morning wake time.
  * 60-minute countdown encouraging sunlight exposure and morning movement.
* **24-Hour Daily Motivation Quote:**
  * Displays a curated motivational quote for the date (persists for 24h, works offline).
* **Pace Card (Real-Time Target Tracking):**
  * **Protein Progress:** Visual track with expected-by-now progress tick and actual grams vs target.
  * **Water / Hydration Progress:** Intake vs daily target (ml).
  * **Calories:** Intake vs optional calorie budget.
  * **Workout Status:** Indicates if workout is done today, plus weekly workout consistency (e.g., `2/3 this week`).
  * **Sleep Summary:** Shows calculated hours and minutes of last night's sleep.
  * **Pace Status Badge:** Dynamically updates (*On pace*, *Behind*, *Falling short*, *Targets met*).
* **"Next Move" Recommendation Card:**
  * Computes the single most actionable next step (e.g., *"Need ~45g protein across remaining meals"* or water prompt) to prevent alert fatigue.
* **Journal Entries Stream:**
  * Chronological list of today's raw entries with time stamps.
  * **AI Tag Badges:** Displays tags for detected meals, protein, calories, water, and workouts.
  * **Override Values:** Tap any log to manually correct protein, calories, or water numbers.
  * **Edit & Delete:** Edit raw text (triggers re-extraction) or delete with undo toast.
  * **Retry Button:** Re-runs AI extraction if a network hiccup occurred.
* **AI Day Review / Verdict Card:**
  * Tap *"Review my day so far"* or *"Submit day"* to get an on-demand coaching assessment.
  * Produces: Headline summary, Went Well bullet points, What Hurt the Goal, and Actionable Fixes for Tomorrow.
* **Composer Dock:**
  * Always-accessible bottom input bar to type thoughts, meals, workouts, or reflections with one tap.

---

### Screen 2: "Days" (Calendar & Past Day View)
* **Monthly Grid View:**
  * Standard calendar grid with month navigation (previous/next).
  * Status indicator dots on each date:
    * Filled circle: Target met / good day score.
    * Outlined circle: Behind or incomplete.
    * Dumbbell marker: Workout logged on that day.
  * "Today" shortcut button to jump straight to the current month and date.
* **Selected Day Summary Card:**
  * Tap any day in the month to see a snapshot: Day Score (0–100), Rating (*Good*, *Ok*, *Poor*), quote, protein, water, workout, and sleep duration.
  * **"Open Day in Today View":** Navigates to that date in the home stream to view or edit full journal notes.

---

### Screen 3: "Insights" (Trends & AI Period Synthesis)
* **Period Toggle:** Switch between **Week** (7 days) and **Month** (30 days).
* **Headline Alert:** Warns if pacing is falling short over the aggregate window.
* **6 High-Level Metric Tiles:**
  1. *Days Logged* (consistency count)
  2. *Average Protein* (grams per day)
  3. *Target Adherence* (% of days protein target was met)
  4. *Average Sleep Duration* (hours & minutes)
  5. *Workouts Completed* (vs weekly/monthly goal)
  6. *Average Hydration* (ml per day)
* **Protein Trend Bar Chart:**
  * Interactive chart showing daily protein vs dashed target line.
  * Bars dynamically colored according to goal status.
* **AI Life Report (Gemini Period Synthesis):**
  * Guarded by a 3-day data minimum to avoid generating reports on empty data.
  * Includes: Executive narrative summary, Highlights & streaks, Areas to improve, and Coaching notes for next period.

---

### Screen 4: "Me" (User Profile & Targets)
* **User Identity:** Displays display name, @username, and avatar.
* **Goal Selection:**
  * Switch between: *Muscle Gain*, *Fat Loss*, *Maintenance*, *Mindfulness*.
  * Updates scoring logic and pacing advice from today onward.
* **Custom Daily Targets:**
  * **Daily Protein Target:** Grams per day (with automatic g/kg ratio calculation).
  * **Daily Calorie Target:** Optional calorie ceiling (set to 0 to disable).
  * **Daily Water Target:** Intake goal in ml (default: 3000ml).
  * **Weekly Workout Target:** Days per week (0–7).
* **Body Metrics:**
  * Body weight in kg (used to adjust g/kg protein intake).
* **This Device & Connection Monitor:**
  * Real-time backend connection status pill (*Connected*, *Disconnected*, *Session ended*).
  * Queue count showing pending offline entries waiting to sync.
  * Manual "Retry / Sync now" button.
* **Sign Out & Safe Logout:**
  * Warns if unsynced offline entries exist before logging out.

---

## 3. Automation, Prompts & Circadian Flow

### Morning Flow Protocol
* Runs automatically on first app open each morning:
  1. **Forgotten Sleep Check:** If yesterday has entries but was never closed with a sleep time, prompts: *"What time did you sleep last night?"*
  2. **Wake Time Check:** If wake time is not recorded for today, prompts: *"What time did you wake up this morning?"*
  3. **Circadian Walk Activation:** Starts the 60-minute morning outdoor walk countdown card.

### Night Close Protocol
* When ready for bed, the user taps *"Submit Today's Report"*:
  * Option A: **"Sleeping Now"** $\rightarrow$ Saves current time as bedtime, closes day, triggers AI synthesis.
  * Option B: **"Ask me tomorrow morning"** $\rightarrow$ Keeps day open; catches sleep time on tomorrow morning's open.

---

## 4. Backend Endpoints Summary

| Group | Endpoints | Purpose |
| :--- | :--- | :--- |
| **Auth** | `POST /api/auth/login`, `POST /api/auth/logout` | Passwordless token session management |
| **User** | `GET /api/users/me`, `PUT /api/users/me` | Fetch and update targets, weight, goals |
| **Logs** | `POST /api/logs`, `GET /api/logs`, `PUT /api/logs/{id}`, `DELETE /api/logs/{id}`, `PATCH /api/logs/{id}/override`, `POST /api/logs/{id}/retry` | Full CRUD, manual metric overrides, retry failed extractions |
| **Day View** | `GET /api/days/{day}/view` | Single unified endpoint powering the home screen (today / past / future modes) |
| **Day Cycles**| `GET /api/days/prompt-status`, `POST /api/days/wake`, `POST /api/days/sleep`, `PUT /api/days/{day}/sleep`, `POST /api/days/{day}/reprocess` | Sleep/wake tracking and legacy reprocessing |
| **Calendar** | `GET /api/calendar?from=...&to=...` | Month-level grid summary with scores and workout booleans |
| **Quotes** | `GET /api/quotes/{day}` | 24-hour motivational quote with fallback caching |
| **Stats** | `GET /api/stats/daily/{day}`, `GET /api/stats/weekly`, `GET /api/stats/monthly` | Pure deterministic macro averages and adherence math |
| **Insights** | `GET /api/insights/weekly`, `GET /api/insights/monthly` | Gemini periodic synthesized narrative reports |
| **System** | `GET /health` | Healthcheck and MongoDB connection probe |
