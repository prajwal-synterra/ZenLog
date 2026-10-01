# ZenLog Backend — Complete Feature Blueprint & API Contract

> **Purpose of this Document:**  
> This blueprint documents **every single real feature, data model, endpoint, and behavior** currently implemented in the ZenLog backend.  
> Use this as your single source of truth when designing the user interface, ensuring that every button, card, and input in your UI directly maps to an actual backend capability with zero unwanted or fantasy features.

---

## 1. What ZenLog Backend Actually Is (Core Concept)

ZenLog is a **private, mindful daily journaling system with AI-powered health & habit synthesis**:
1. **Throughout the Day:** The user types quick, natural-language journal entries (e.g., *"Breakfast: 3 eggs and a banana"*, *"Ran 5km in 28 mins"*, *"Feeling calm and focused after meditating"*).
2. **At Night / Next Morning:** The user submits their **sleep time** to close the day.
3. **Automatic AI Fact Extraction (Gemini):** The backend sends the day's raw notes to Gemini and extracts structured facts: **Meals & Foods**, **Protein & Calories**, **Hydration**, **Workouts**, **Learning**, **Habits**, and **Moods**.
4. **Deterministic Calculation:** The backend (not the AI) deterministically calculates macro totals: total protein, protein target percentage, remaining protein, and hydration.
5. **Periodic Analytics & Insights:** The backend aggregates data over 7 or 30 days and generates **Weekly & Monthly AI Life Reports** (Summary, Highlights, Coaching Notes, Areas to Improve).

---

## 2. Comprehensive Feature Breakdown

### Feature 1: Authentication & Session Management
* **How it works:** Passwordless authentication using `username` and `phone_number`.
* **Session Lifetime:** 12-hour bearer token stored and validated against MongoDB session collection.
* **Security:** Tokens are hashed using SHA-256 in MongoDB. Revoked immediately on logout.
* **Endpoints:**
  * `POST /api/auth/login` $\rightarrow$ Logs in user, creates session, returns `access_token` and user summary.
  * `POST /api/auth/logout` $\rightarrow$ Revokes the active session token.

---

### Feature 2: User Profile & Goal Customization
* **How it works:** Each user has a profile with health goals and a daily protein target.
* **Available Profile Fields:**
  * `name` (String, e.g. "Prajwal")
  * `username` (String, e.g. "testuser1")
  * `goal` (String, e.g. "muscle_gain", "fat_loss", "mindfulness")
  * `body_weight_kg` (Float, e.g. `70.0`)
  * `daily_protein_target_g` (Float, e.g. `126.0`)
* **Endpoints:**
  * `GET /api/users/me` $\rightarrow$ Returns current user profile (excludes private phone number).
  * `PUT /api/users/me` $\rightarrow$ Updates user goals, body weight, or daily protein target.

---

### Feature 3: Raw Daily Journaling (Core Input Stream)
* **How it works:** Fast, friction-free stream of raw notes throughout the day.
* **Features:**
  * Auto-timestamps in IST (Indian Standard Time) if timestamp is omitted.
  * Date-tagged (default: today).
  * Entries can be created, edited, and deleted.
  * **Intelligent Invalidation:** Editing or deleting a log automatically marks that day's AI extraction as stale (`PROCESSING_FAILED / source_logs_changed`) and invalidates cached weekly/monthly reports so statistics stay 100% accurate.
* **Endpoints:**
  * `POST /api/logs` $\rightarrow$ Create a new journal entry.
  * `GET /api/logs/today` $\rightarrow$ Retrieve all entries logged today in chronological order.
  * `GET /api/logs?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD` $\rightarrow$ Retrieve entries across a date range.
  * `PUT /api/logs/{log_id}` $\rightarrow$ Edit a journal entry's text or timestamp.
  * `DELETE /api/logs/{log_id}` $\rightarrow$ Permanently delete an entry.

---

### Feature 4: Morning Wake Time Tracking & Prompt Protocol
* **Why it matters:** Morning wake time is logged to establish the day's baseline, calculate active walking/waking hours, and anchor circadian rhythms.
* **The "Once-Per-Day" Morning Check (`GET /api/days/prompt-status`):**
  * When the user opens the app for the first time in the day:
    1. **Check 1: Did user forget last night's sleep?**
       If yesterday had logs but sleep was never submitted (`needs_yesterday_sleep == true`):
       * The app shows a popup: *"What time did you sleep last night?"*
       * User submits sleep $\rightarrow$ calls `POST /api/days/{yesterday}/sleep`.
       * The backend immediately runs Gemini extraction and computes yesterday's entire report.
    2. **Check 2: What time did you wake up today?**
       If today has no wake time logged yet (`needs_today_wake == true`):
       * The app shows a popup: *"What time did you wake up today?"*
       * User inputs time (e.g. `07:15`) $\rightarrow$ calls `POST /api/days/wake`.
       * The backend logs this wake time to today's record.
    3. **Subsequent app opens on the same day:**
       Both flags return `false`, so **no popups are shown** for the rest of the day.
* **Endpoints:**
  * `GET /api/days/prompt-status` $\rightarrow$ Checks if yesterday sleep or today wake is needed.
  * `POST /api/days/wake` $\rightarrow$ Records wake time for today (`{"wake_time": "07:15"}`).
  * `POST /api/days/{day}/wake` $\rightarrow$ Records wake time for a specific date.

---

### Feature 5: Nightly Close & "Sleeping Now vs Tomorrow" Option
* **When user taps "Submit Today's Report" / "Sleep":**
  * The app displays a popup:
    > *"Are you sleeping right now, or should I ask you for your sleep time tomorrow morning?"*
  * **Option A: "Sleeping Now"** $\rightarrow$ User confirms/enters sleep time $\rightarrow$ calls `POST /api/days/sleep` $\rightarrow$ Day is processed and saved immediately.
  * **Option B: "Ask me tomorrow morning"** $\rightarrow$ The day stays open. The next morning when they open the app, the Prompt Protocol (Feature 4) detects that yesterday's sleep is pending, asks for it, processes yesterday, and then asks for today's wake time!
* **Endpoints:**
  * `POST /api/days/sleep` $\rightarrow$ Submits sleep for today and processes the day.
  * `POST /api/days/{day}/sleep` $\rightarrow$ Submits sleep for yesterday (next-morning fallback).

---

### Feature 6: Editing Already Added Logs & Days (Reprocessing)
* **1. Edit an Individual Log Entry (`PUT /api/logs/{log_id}`):**
  * Change text, timestamp, or date of any entry.
  * The backend automatically invalidates stale AI reports so data remains accurate.
* **2. Edit Sleep Time on an Already Submitted Day (`PUT /api/days/{day}/sleep`):**
  * Allows user to correct their sleep time on a completed day.
  * Optionally set `{"sleep_time": "23:45", "reprocess": true}` to automatically re-run Gemini extraction on all entries.
* **3. Edit Wake Time on an Already Added Day (`POST /api/days/{day}/wake`):**
  * Updates or overwrites the recorded wake time.
* **4. Reprocess an Already Completed Day (`POST /api/days/{day}/reprocess`):**
  * If a user edited their journal entries on a past day and wants Gemini to re-calculate macros, workouts, and insights without hitting HTTP 409 conflict, calling this route cleanly re-extracts and saves the updated record.

---

### Feature 7: AI Fact Extraction & Macro Aggregation (The Gemini Engine)
When a day is closed with sleep, Gemini parses the day's logs into structured categories:
1. **Nutrition:**
   * Meals (`breakfast`, `lunch`, `dinner`, `snack`).
   * Food items with estimated quantities.
   * `protein_g` and `calories_kcal` per item and per meal.
   * Confidence level: `"high" | "medium" | "low" | "unknown"`.
   * Estimation type: `"explicit_user_value" | "estimated" | "unknown"`.
2. **Deterministic Daily Totals (Calculated by backend):**
   * Total daily protein (`protein_g`).
   * Total daily calories (`calories_kcal`).
   * Total water intake (`hydration_ml`).
   * Target percentage achieved (`target_percentage`, e.g. `43.9%`).
   * Remaining protein needed (`remaining_protein_g`, e.g. `70.7g`).
3. **Fitness & Workouts:**
   * Workout type (`strength_training`, `running`, `swimming`, etc.).
   * Duration in minutes (`duration_mins`).
   * Intensity (`high`, `moderate`, `low`).
   * List of specific exercises recorded.
4. **Learning Activities:**
   * Activity type, book title, pages read, duration.
5. **Habit Observations:**
   * Habit name and completion status (`true` / `false`).
6. **Mood & Energy:**
   * Explicit mood expression and context.
7. **Daily Insights:**
   * Daily growth wins, areas to improve, coaching note.

---

### Feature 8: Journal Calendar (Multi-Day Overview)
* **How it works:** Queries a date window (e.g., this week or this month) to show the user's consistency.
* **Data returned per day:**
  * `date`: `YYYY-MM-DD`
  * `status`: `"completed"` | `"incomplete"` | `"processing"` | `"processing_failed"`
  * `protein_g`: Total protein tracked that day.
  * `protein_target_g`: The user's target on that day.
  * `workout`: Boolean (`true` if a workout occurred).
* **Endpoint:**
  * `GET /api/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD`

---

### Feature 9: Deterministic Statistics (Daily, Weekly, Monthly)
* **Daily Statistics:** Returns log count, protein totals, percentage, hydration, and workout boolean for a specific day.
* **Weekly & Monthly Aggregates:** Computes high-level consistency without AI hallucinations:
  * `completed_days` (Days where sleep & extraction was completed).
  * `incomplete_days` (Days with logs but not closed).
  * `average_protein_g` (Mean protein on completed days).
  * `protein_target_adherence_percent` (% of completed days meeting target).
  * `workout_days` (Total days with workout).
  * `average_hydration_ml` (Average water intake).
* **Endpoints:**
  * `GET /api/stats/daily/{day}`
  * `GET /api/stats/weekly?anchor=YYYY-MM-DD` (defaults to current week)
  * `GET /api/stats/monthly?anchor=YYYY-MM-DD` (defaults to current month)

---

### Feature 10: Periodic AI Life Reports (Weekly & Monthly Synthesis)
* **How it works:** Takes the 7-day or 30-day aggregate statistics and feeds them to Gemini to generate high-level coaching feedback.
* **Cached in MongoDB:** Generated reports are cached in `reports` collection.
* **Auto-invalidated:** If the user edits an old log from that week/month, the report cache is automatically purged so stale reports are never shown.
* **Report Contents:**
  * `summary`: Executive narrative of the period.
  * `highlights`: 3–5 bullet points of biggest wins and positive streaks.
  * `areas_to_improve`: 1–3 gentle, grounded areas needing attention.
  * `coaching_notes`: Practical advice for the next week/month.
* **Endpoints:**
  * `GET /api/insights/weekly?anchor=YYYY-MM-DD`
  * `GET /api/insights/monthly?anchor=YYYY-MM-DD`

---

### Feature 11: Health & Infrastructure
* **Endpoint:** `GET /health`
* **Response:** `{"status": "ok", "database": "connected"}`

---

## 3. Complete API Endpoint Reference Table

| Route | Method | Auth Required | Request Payload / Params | Response Summary |
| :--- | :---: | :---: | :--- | :--- |
| `/health` | `GET` | No | None | `{"status": "ok", "database": "connected"}` |
| `/api/auth/login` | `POST` | No | `{"username": "...", "phone_number": "..."}` | `{"access_token": "...", "user": {...}}` |
| `/api/auth/logout` | `POST` | Yes | Bearer Token | `{"success": true, "message": "Logged out"}` |
| `/api/users/me` | `GET` | Yes | Bearer Token | `{"user_id": "...", "name": "...", "daily_protein_target_g": 126}` |
| `/api/users/me` | `PUT` | Yes | `{"goal": "...", "daily_protein_target_g": 130}` | Updated profile object |
| `/api/logs` | `POST` | Yes | `{"text": "...", "date": "...", "timestamp": "..."}` | Created Log object (HTTP 201) |
| `/api/logs/today` | `GET` | Yes | None | Array of today's logs sorted by time |
| `/api/logs` | `GET` | Yes | `?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD` | Array of logs in date range |
| `/api/logs/{id}` | `PUT` | Yes | `{"text": "updated text"}` | Updated Log object |
| `/api/logs/{id}` | `DELETE` | Yes | None | HTTP 204 No Content |
| `/api/days/prompt-status`| `GET` | Yes | None | `{"needs_yesterday_sleep": bool, "needs_today_wake": bool, ...}` |
| `/api/days/wake` | `POST` | Yes | `{"wake_time": "07:15"}` | Records wake time for today |
| `/api/days/{day}/wake` | `POST` | Yes | `{"wake_time": "07:15"}` | Records wake time for specific day |
| `/api/days/sleep` | `POST` | Yes | `{"sleep_time": "23:00"}` | Full processed `DailyRecord` with nutrition & workout facts |
| `/api/days/{day}/sleep`| `POST` | Yes | `{"sleep_time": "23:00"}` | Processed `DailyRecord` for yesterday |
| `/api/days/{day}/sleep`| `PUT` | Yes | `{"sleep_time": "23:45", "reprocess": false}` | Edits sleep time on an already added day |
| `/api/days/{day}/reprocess`| `POST` | Yes | `{"sleep_time": "23:00"}` (optional) | Re-runs AI fact extraction on an already added day |
| `/api/days/{day}` | `GET` | Yes | None | Day state: `{"status": "...", "logs": [...], "record": {...}}` |
| `/api/calendar` | `GET` | Yes | `?from=YYYY-MM-DD&to=YYYY-MM-DD` | Array of day summaries (status, protein, workout bool) |
| `/api/stats/daily/{day}`| `GET` | Yes | None | Daily stats (log count, protein %, hydration, workout) |
| `/api/stats/weekly` | `GET` | Yes | `?anchor=YYYY-MM-DD` (optional) | Weekly stats (completion rate, avg protein, adherence) |
| `/api/stats/monthly`| `GET` | Yes | `?anchor=YYYY-MM-DD` (optional) | Monthly stats (completion rate, avg protein, adherence) |
| `/api/insights/weekly`| `GET` | Yes | `?anchor=YYYY-MM-DD` (optional) | AI synthesized weekly report (summary, wins, coaching) |
| `/api/insights/monthly`|`GET` | Yes | `?anchor=YYYY-MM-DD` (optional) | AI synthesized monthly report (summary, wins, coaching) |

---

## 4. Exact JSON Payloads for UI Design

### Daily Journal Entry (Log Object)
```json
{
  "id": "673f8a...",
  "user_id": "zen_test_0001",
  "date": "2026-10-01",
  "timestamp": "2026-10-01T08:30:00+05:30",
  "time_display": "08:30 AM IST",
  "text": "Breakfast: 3 eggs and a banana. Drank 500ml water."
}
```

### Processed Day Record (`DailyRecord`)
```json
{
  "record_id": "673f9b...",
  "user_id": "zen_test_0001",
  "date": "2026-10-01",
  "status": "COMPLETED",
  "sleep": {
    "sleep_time": "23:00",
    "source": "user"
  },
  "nutrition": {
    "meals": [
      {
        "meal": "Breakfast",
        "meal_protein_g": 19.3,
        "items": [
          {
            "food": "eggs",
            "quantity": "3",
            "protein_g": 18.0,
            "calories_kcal": 210.0,
            "protein_source": "estimated",
            "confidence": "high"
          },
          {
            "food": "banana",
            "quantity": "1",
            "protein_g": 1.3,
            "calories_kcal": 105.0,
            "protein_source": "estimated",
            "confidence": "high"
          }
        ]
      }
    ],
    "daily_totals": {
      "protein_g": 19.3,
      "calories_kcal": 315.0,
      "hydration_ml": 500,
      "protein_target_g": 126.0,
      "target_percentage": 15.3,
      "remaining_protein_g": 106.7
    }
  },
  "fitness": {
    "workouts": [
      {
        "type": "strength_training",
        "duration_mins": 45,
        "intensity": "high",
        "exercises": ["deadlifts", "pull-ups"]
      }
    ]
  },
  "learning": {
    "activities": [
      {
        "activity": "reading",
        "book": "Atomic Habits",
        "pages": 15
      }
    ]
  },
  "habits": {
    "observations": [
      {"habit": "morning sunlight", "completed": true}
    ]
  },
  "mood": {
    "observations": [
      {"mood": "calm and focused", "context": "after meditation"}
    ]
  },
  "insights": {
    "growth_wins": ["Hit morning hydration immediately"],
    "areas_to_improve": ["Add afternoon protein snack"],
    "coaching_notes": "Great morning momentum. Keep protein distribution balanced."
  }
}
```

### Period AI Report (`InsightReport`)
```json
{
  "report_id": "673fa1...",
  "period": "weekly",
  "period_start": "2026-09-28",
  "period_end": "2026-10-01",
  "generated_at": "2026-10-01T12:00:00Z",
  "summary": {
    "completed_days": 4,
    "incomplete_days": 0,
    "average_protein_g": 102.5,
    "protein_target_adherence_percent": 75.0,
    "workout_days": 3,
    "average_hydration_ml": 2200.0
  },
  "insight": {
    "summary": "Strong discipline shown across training days with steady macro intake.",
    "highlights": [
      "Hit 75% adherence on your 126g daily protein goal.",
      "Completed 3 high-intensity strength training sessions.",
      "Averaged 2,200ml hydration daily."
    ],
    "areas_to_improve": [
      "Rest day protein was 20% lower than workout days."
    ],
    "coaching_notes": "Try preparing protein snacks in advance for non-workout days."
  }
}
```

---

## 5. Ideal UI Screen Hierarchy (Clean & Unbloated)

To avoid unwanted features (like plant scanners, watering reminders, or generic diagnostics), the ideal ZenLog UI needs only **4 focused screens**:

### Screen 1: Today's Journal & Flow (Home)
* **Top Bar:** Greeting, avatar, protein progress pill (e.g. `19g / 126g`).
* **Quick Log Input:** Text box: *"What did you eat, do, or reflect on?"* with a simple `+ Log` button.
* **Today's Stream:** List of today's raw entries with time stamps, edit/delete swipe actions.
* **Nightly Sleep Card:** Once user is done for the day, a single tap: *"Sleep & Synthesize Day"* $\rightarrow$ input sleep time (e.g., `23:00`) $\rightarrow$ shows AI extraction breakdown.

### Screen 2: Calendar & Past Days
* **Horizontal Date Picker:** Tap any day this week/month.
* **Status Badge:** Green check for completed days, amber for open days.
* **Day Summary:** Shows the extracted macros, workouts, mood, and raw entries for that selected date.

### Screen 3: Trends & Periodic Insights
* **Top Toggle:** `Weekly` vs `Monthly`.
* **Stats Cards:** Completed days count, Average protein (g), Adherence rate (%), Workout count.
* **Gemini Narrative:** Executive summary card, Key wins checklist, Coaching recommendations.

### Screen 4: Profile & Targets
* **Goal Settings:** Target protein slider (e.g. `126g`), body weight (`70kg`), primary goal (`muscle_gain`).
* **Session & Account:** Current user details, Logout button.
