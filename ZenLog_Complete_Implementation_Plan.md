# ZenLog — Complete V1 Implementation Plan

## 1. Project Overview

**ZenLog** is a private, minimal personal journaling and tracking application for two predefined users.

The core interaction is intentionally simple:

> The user writes what happened during the day in natural English. ZenLog stores those raw entries. When the user goes to sleep, the backend sends the day's entries to Gemini, converts them into structured data, stores the result in MongoDB Atlas, and exposes the data through calendar, statistics, and insight views.

### Primary V1 Goal

Build a reliable end-to-end system for:

```text
Natural-language logging
        ↓
Raw log storage
        ↓
Day completion / sleep submission
        ↓
Gemini structured extraction
        ↓
Validated daily document
        ↓
MongoDB Atlas
        ↓
Calendar + daily history + statistics
        ↓
Weekly/monthly insights
```

The first version should be deliberately simple. Do not introduce unnecessary microservices, complex authentication, recommendation engines, wearable integrations, social features, or heavy UI frameworks.

---

# 2. V1 Technology Stack

## Mobile Application

- Flutter
- Dart
- Simple Material-based UI
- No heavy UI framework
- REST communication with FastAPI
- Local state management can initially remain simple; introduce a state-management package only if the implementation actually needs it

## Backend

- Python
- FastAPI
- Pydantic
- HTTP client for Gemini API
- MongoDB driver
- Environment-based configuration
- Structured logging
- Automated API tests

## Database

- MongoDB Atlas
- Flexible document model
- MongoDB aggregation pipelines for statistics

## AI

- Gemini API
- Gemini structured output / JSON Schema
- AI is responsible for interpretation and extraction, not authoritative arithmetic

## Authentication

- Two predefined users
- No public registration
- Username + phone-number based login
- Backend-controlled access
- Session/token mechanism should be implemented rather than trusting the Flutter client

---

# 3. Core Product Principles

## 3.1 Raw Data Is the Source of Truth

Never overwrite the original natural-language entry with AI output.

Example:

```json
{
  "timestamp": "2026-10-01T08:30:00+05:30",
  "text": "Had 3 eggs and a banana for breakfast."
}
```

Gemini's interpretation is derived data.

This allows ZenLog to:

- audit AI extraction
- regenerate structured data later
- correct AI mistakes
- improve prompts/models without losing original information

---

## 3.2 Flexible Input, Controlled Analytical Schema

The user can write anything.

The analytical schema should not be completely arbitrary.

Correct architecture:

```text
Flexible natural-language input
            ↓
Controlled semantic categories
            ↓
Flexible MongoDB document
```

Possible categories:

- nutrition
- hydration
- fitness
- sleep
- learning
- habits
- mood
- productivity
- custom observations

Only fields supported by the day's information should be populated.

---

## 3.3 AI Should Not Invent Facts

If the user says:

> "Ate chicken biryani."

Gemini may not know the exact portion size or exact nutrition.

The structured output must distinguish between:

- explicitly provided values
- estimated values
- unknown values

Example:

```json
{
  "food": "Chicken biryani",
  "quantity": "1 plate",
  "protein_g": 28,
  "protein_source": "estimated",
  "confidence": "medium"
}
```

The system must not present estimates as exact measurements.

---

# 4. V1 Scope

## Included

### Authentication

- Login for two predefined users
- Logout
- Current-user profile
- User-specific data isolation

### Daily Logging

- Add natural-language entry
- Edit entry
- Delete entry
- View today's entries
- Timestamp each entry automatically

### Day Completion

- "Sleeping Now" action
- Capture sleep time
- Process the completed day
- Next-morning fallback for forgotten submission

### AI Processing

- Bundle daily raw entries
- Send to Gemini
- Receive structured JSON
- Validate JSON using Pydantic
- Store AI-derived daily data

### Nutrition

- Food-level extraction
- Meal-level protein
- Daily protein total
- Hydration
- Calories when supported/available
- Confidence/source indicators for estimated nutrition

### Muscle-Gain Tracking

- User-specific body weight
- Daily protein target
- Protein consumed
- Target percentage
- Remaining protein
- Workout information

### History

- Calendar
- Daily detail view
- Historical raw entries
- Historical structured data

### Analytics

- Daily statistics
- Weekly aggregation
- Monthly aggregation
- Protein trends
- Workout consistency
- Hydration trends where data exists

### AI Reports

- Weekly insight
- Monthly insight
- Gemini receives aggregated data rather than the entire raw history

---

# 5. Explicitly Out of Scope for V1

Do not build these initially:

- Public registration
- Social features
- Chat between users
- Wearable integration
- Apple Health / Google Fit integration
- Automated food recommendation engine
- Complete nutrition database
- Medical diagnosis
- Complex calorie planning
- Microservices
- Kubernetes
- Message queues
- Real-time WebSockets
- Admin dashboard unless needed for initial user provisioning
- Advanced notification infrastructure
- Complex offline synchronization
- Large-scale multi-tenant architecture

These can be evaluated after the core system works.

---

# 6. High-Level Architecture

```text
                    ┌──────────────────┐
                    │   Flutter App    │
                    │                  │
                    │ Login            │
                    │ Journal          │
                    │ Calendar         │
                    │ Statistics       │
                    │ Reports          │
                    └────────┬─────────┘
                             │ HTTPS REST
                             ▼
                    ┌──────────────────┐
                    │    FastAPI       │
                    │                  │
                    │ Auth             │
                    │ Journal Service  │
                    │ Day Service      │
                    │ Analytics        │
                    │ AI Service       │
                    └──────┬─────┬─────┘
                           │     │
              ┌────────────┘     └──────────────┐
              ▼                                 ▼
    ┌──────────────────┐              ┌──────────────────┐
    │ MongoDB Atlas    │              │ Gemini API       │
    │                  │              │                  │
    │ Users            │              │ Extraction       │
    │ Logs             │              │ Insights         │
    │ Daily Records    │              └──────────────────┘
    │ Reports          │
    └──────────────────┘
```

---

# 7. Backend Internal Architecture

Use a clean but not over-engineered FastAPI structure.

Suggested structure:

```text
backend/
│
├── app/
│   ├── main.py
│   │
│   ├── core/
│   │   ├── config.py
│   │   ├── security.py
│   │   └── logging.py
│   │
│   ├── db/
│   │   ├── mongodb.py
│   │   └── indexes.py
│   │
│   ├── models/
│   │   ├── user.py
│   │   ├── log.py
│   │   ├── daily_record.py
│   │   └── report.py
│   │
│   ├── schemas/
│   │   ├── auth.py
│   │   ├── user.py
│   │   ├── log.py
│   │   ├── day.py
│   │   ├── statistics.py
│   │   └── insights.py
│   │
│   ├── routes/
│   │   ├── auth.py
│   │   ├── users.py
│   │   ├── logs.py
│   │   ├── days.py
│   │   ├── calendar.py
│   │   ├── stats.py
│   │   └── insights.py
│   │
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── log_service.py
│   │   ├── day_service.py
│   │   ├── analytics_service.py
│   │   └── insight_service.py
│   │
│   └── ai/
│       ├── gemini_client.py
│       ├── extraction_service.py
│       ├── insight_service.py
│       └── prompts.py
│
├── tests/
├── .env.example
├── requirements.txt
└── README.md
```

The exact structure can be simplified if the implementation becomes unnecessarily fragmented.

---

# 8. MongoDB Collections

V1 should use a small number of collections.

## 8.1 users

Purpose:

- predefined accounts
- user profile
- muscle-gain targets
- authentication information

Example:

```json
{
  "_id": "...",
  "user_id": "user_01",
  "username": "prajwal",
  "phone": "...",
  "name": "Prajwal",
  "goal": "muscle_gain",
  "body_weight_kg": 70,
  "daily_protein_target_g": 126,
  "created_at": "..."
}
```

Sensitive authentication data must not be stored carelessly or exposed through API responses.

---

# 9. Daily Logs Collection

Collection:

```text
daily_logs
```

Each natural-language entry is stored independently.

Example:

```json
{
  "_id": "...",
  "user_id": "user_01",
  "date": "2026-10-01",
  "timestamp": "2026-10-01T08:30:00+05:30",
  "text": "Had 3 eggs and a banana for breakfast.",
  "created_at": "..."
}
```

Advantages:

- easy editing
- easy deletion
- preserves original text
- simple chronological retrieval
- no need to rewrite an entire day document whenever a new log arrives

---

# 10. Daily Records Collection

Collection:

```text
daily_records
```

One completed document per user per day.

Example:

```json
{
  "user_id": "user_01",
  "date": "2026-10-01",
  "status": "completed",

  "sleep": {
    "sleep_time": "23:30",
    "source": "user"
  },

  "nutrition": {
    "meals": [
      {
        "meal": "breakfast",
        "items": [
          {
            "food": "egg",
            "quantity": "3",
            "protein_g": 18,
            "calories_kcal": 210,
            "protein_source": "estimated",
            "confidence": "high"
          },
          {
            "food": "banana",
            "quantity": "1",
            "protein_g": 1.3,
            "calories_kcal": 105,
            "protein_source": "estimated",
            "confidence": "high"
          }
        ],
        "meal_protein_g": 19.3
      }
    ],

    "daily_totals": {
      "protein_g": 19.3,
      "calories_kcal": 315,
      "hydration_ml": 500
    }
  },

  "fitness": {
    "workouts": [
      {
        "type": "running",
        "duration_mins": 30
      }
    ]
  },

  "learning": {},
  "habits": {},
  "mood": {},

  "insights": {
    "growth_wins": [],
    "areas_to_improve": [],
    "coaching_notes": ""
  },

  "processing": {
    "processed_at": "...",
    "model": "...",
    "prompt_version": "v1"
  }
}
```

---

# 11. Important Daily Record State Machine

A day should have an explicit state.

Recommended states:

```text
OPEN
  ↓
PROCESSING
  ↓
COMPLETED
```

Failure state:

```text
PROCESSING
  ↓
PROCESSING_FAILED
```

The backend should not allow duplicate processing to silently create multiple daily records.

Recommended uniqueness:

```text
user_id + date
```

must be unique in `daily_records`.

---

# 12. Authentication API

## POST /api/auth/login

Request:

```json
{
  "username": "prajwal",
  "phone": "..."
}
```

Response should contain the authenticated session/token.

The backend verifies the credentials against the predefined user record.

Do not trust a user ID supplied by Flutter.

---

## POST /api/auth/logout

Invalidates/removes the current session if server-side session handling is used.

---

## GET /api/users/me

Returns safe profile information.

Do not return sensitive authentication information.

---

## PUT /api/users/me

Allows modification of permitted profile/goal fields.

---

# 13. Journal API

## GET /api/logs/today

Returns today's raw entries.

---

## POST /api/logs

Request:

```json
{
  "text": "Drank 750ml water and had chicken rice for lunch."
}
```

Backend automatically determines:

- authenticated user
- current local date
- timestamp

---

## PUT /api/logs/{log_id}

Allows correction of a raw entry.

---

## DELETE /api/logs/{log_id}

Deletes an entry belonging to the authenticated user.

A user must never be able to access another user's log by changing the ID.

---

# 14. Sleep / Day Processing API

## POST /api/days/sleep

Normal flow.

Request:

```json
{
  "sleep_time": "23:30"
}
```

Backend:

1. Identify authenticated user.
2. Identify current local date.
3. Check the day is still processable.
4. Save sleep time.
5. Retrieve all raw logs for the day.
6. Build Gemini input.
7. Send structured-output request.
8. Validate response.
9. Calculate authoritative totals.
10. Save `daily_records`.
11. Mark day completed.
12. Return daily summary.

---

# 15. Next-Morning Fallback

## POST /api/days/{date}/sleep

Used when yesterday was not completed.

Example:

```text
POST /api/days/2026-09-30/sleep
```

The backend must verify:

- requested date belongs to a reasonable previous-day window
- authenticated user owns the day
- day has not already been completed

This endpoint should not allow arbitrary modification of old completed days.

---

# 16. Gemini Processing Pipeline

The extraction pipeline should be explicit.

```text
Raw Logs
   ↓
Normalize input
   ↓
Create extraction prompt
   ↓
Gemini structured output
   ↓
Parse JSON
   ↓
Pydantic validation
   ↓
Business validation
   ↓
Calculate authoritative totals
   ↓
Persist
```

---

# 17. Gemini Responsibilities

Gemini should identify:

### Nutrition

- meals
- food items
- quantity
- protein
- calories where reasonably inferable
- hydration
- nutrition confidence

### Fitness

- workout type
- duration
- intensity if explicitly stated
- exercises if explicitly mentioned

### Sleep

- sleep time
- wake time if available
- sleep duration if derivable

### Learning

- book
- pages
- study duration
- learning activity

### Habits

- habit completion
- relevant user-stated behaviors

### Mood

Only when the user explicitly expresses a mood/emotion.

### General observations

- growth wins
- areas to improve
- useful coaching observations

The AI should not invent events.

---

# 18. Nutrition Extraction Rules

This is particularly important because ZenLog is intended to track muscle gain.

For every identifiable food:

```json
{
  "food": "chicken",
  "quantity": "150g",
  "protein_g": 46,
  "calories_kcal": 250,
  "protein_source": "estimated",
  "confidence": "medium"
}
```

Each meal should have:

```text
meal_protein_g
```

The daily record should have:

```text
daily protein total
```

This allows:

```text
Food → Meal → Day → Week → Month
```

analysis.

---

# 19. Nutrition Confidence

Possible values:

```text
high
medium
low
unknown
```

Possible sources:

```text
explicit_user_value
estimated
derived
unknown
```

Example:

```json
{
  "protein_g": 30,
  "protein_source": "estimated",
  "confidence": "medium"
}
```

Do not represent an AI estimate as an exact measurement.

---

# 20. Authoritative Calculations

Gemini may extract individual food values, but the backend should calculate totals.

For example:

```text
Food A = 20g
Food B = 15g
Food C = 8g

Daily protein = 43g
```

The backend should calculate:

- meal totals
- daily totals
- target percentage
- remaining protein
- weekly averages
- monthly averages
- consistency metrics

Do not ask Gemini to perform these calculations when normal backend code can do them deterministically.

---

# 21. Calendar API

## GET /api/calendar

Parameters:

```text
from
to
```

Example:

```text
GET /api/calendar?from=2026-09-01&to=2026-09-30
```

Return lightweight summaries only.

Example:

```json
[
  {
    "date": "2026-09-30",
    "status": "completed",
    "protein_g": 118,
    "protein_target_g": 126,
    "workout": true
  }
]
```

Do not return the complete raw journal and AI document for every calendar cell.

---

# 22. Daily History API

## GET /api/days/{date}

Returns the complete daily view:

- raw logs
- processed meals
- food items
- protein
- calories
- hydration
- workouts
- sleep
- learning
- habits
- insights
- processing metadata where appropriate

---

# 23. Statistics APIs

## GET /api/stats/daily/{date}

Returns:

- protein consumed
- protein target
- target percentage
- hydration
- workout
- sleep
- other available metrics

---

## GET /api/stats/weekly

MongoDB aggregation should calculate:

- average protein
- protein target adherence
- workout count
- average hydration
- completed days
- incomplete days
- average sleep where available

---

## GET /api/stats/monthly

Same concept over a monthly range.

---

# 24. Reports / Insights

## Weekly

The backend first aggregates numerical information.

Example:

```json
{
  "days_completed": 6,
  "average_protein_g": 118,
  "protein_target_g": 126,
  "workout_days": 4,
  "average_hydration_ml": 2100
}
```

Only this summarized information plus selected growth observations is sent to Gemini.

Gemini generates a human-readable report.

---

## Monthly

Same principle.

Do not send 30 complete raw daily documents to Gemini.

Correct:

```text
MongoDB
   ↓
Aggregation
   ↓
Compact monthly summary
   ↓
Gemini
   ↓
Monthly report
```

---

# 25. Flutter Screens

V1 can be limited to the following screens.

## 1. Login

- username
- phone number
- login button

---

## 2. Home / Today

Display:

- greeting
- current date
- today's progress
- recent journal entries
- add-log input
- Sleeping Now button

The main action should remain:

> Write what happened.

---

## 3. Add Log

Simple text field.

Example placeholder:

```text
"What did you eat, drink, do, learn, or feel?"
```

Submit.

No complex forms.

---

## 4. Daily Summary

After processing:

- protein
- meals
- hydration
- workout
- sleep
- learning
- AI insights

---

## 5. Calendar

Monthly calendar.

Completed/incomplete days can have subtle indicators.

Selecting a date opens the daily record.

---

## 6. Statistics

Simple cards/charts:

- protein trend
- protein target adherence
- workouts
- hydration
- sleep
- consistency

Do not overload V1 with dozens of charts.

---

## 7. Reports

Tabs/sections:

- Weekly
- Monthly

Show AI-generated narrative alongside important numerical metrics.

---

# 26. Flutter API Layer

Keep API access centralized.

Example:

```text
lib/
├── core/
│   ├── api/
│   │   ├── api_client.dart
│   │   └── api_endpoints.dart
│   └── storage/
│
├── features/
│   ├── auth/
│   ├── journal/
│   ├── calendar/
│   ├── statistics/
│   └── reports/
│
└── main.dart
```

Do not scatter HTTP calls throughout widgets.

---

# 27. Time and Date Handling

This needs to be designed carefully.

ZenLog defines a daily window as:

```text
12:00 AM → 11:59 PM
```

The backend should use a consistent timezone for the user's daily boundary.

For V1, since the application is private and intended for two users in the same environment, configure the application timezone explicitly rather than relying blindly on the server timezone.

Store timestamps in a consistent format.

Use:

```text
ISO 8601
```

for timestamps.

The `date` field should represent the user's local ZenLog date.

---

# 28. Security

Even though there are only two users, security should not be ignored.

## Backend

- Gemini API key only in backend environment
- MongoDB credentials only in backend environment
- HTTPS in deployed environments
- Authentication on protected endpoints
- User ownership checks
- Request validation
- Rate limiting can be added later if required

## Flutter

Never embed:

- Gemini API key
- MongoDB credentials

Flutter communicates only with FastAPI.

---

# 29. Environment Variables

Example:

```env
APP_ENV=development

MONGODB_URI=
MONGODB_DATABASE=zenlog

GEMINI_API_KEY=

JWT_SECRET=
ACCESS_TOKEN_EXPIRE_MINUTES=...

TIMEZONE=Asia/Kolkata
```

Never commit `.env`.

Provide:

```text
.env.example
```

instead.

---

# 30. MongoDB Indexes

At minimum:

### Users

```text
user_id
username
```

### Daily Logs

Compound index:

```text
user_id + date + timestamp
```

### Daily Records

Unique compound index:

```text
user_id + date
```

This prevents duplicate daily records.

---

# 31. Error Handling

The backend must distinguish between:

### Validation errors

Invalid request data.

### Authentication errors

Invalid login/session.

### Not found

Requested day/log does not exist.

### AI processing errors

Gemini unavailable, timeout, invalid structured response, etc.

### Database errors

MongoDB connectivity or persistence problems.

If Gemini fails:

**Do not delete the raw logs.**

The day should remain recoverable.

Example:

```text
Raw logs
   ↓
Gemini failure
   ↓
PROCESSING_FAILED
   ↓
Retry
```

---

# 32. AI Retry Strategy

Do not endlessly retry Gemini.

Recommended initial approach:

```text
Attempt 1
   ↓
Failure
   ↓
Short retry
   ↓
Failure
   ↓
Mark processing_failed
```

The user should be able to retry processing without losing the raw journal.

---

# 33. Prompt Versioning

Every AI-generated daily record should record the prompt/model version.

Example:

```json
{
  "processing": {
    "model": "gemini-model-name",
    "prompt_version": "daily-extraction-v1",
    "processed_at": "..."
  }
}
```

This becomes important when the extraction schema changes.

---

# 34. AI Schema Versioning

Store:

```text
schema_version: "1.0"
```

inside processed records.

If the schema later changes:

```text
1.0 → 1.1 → 2.0
```

old records remain understandable.

---

# 35. Data Ownership and Privacy

ZenLog contains highly personal journal data.

Therefore:

- each user can only access their own data
- raw logs should never be returned to the other user
- authentication is enforced server-side
- API responses should expose only necessary fields
- secrets must never be committed
- production database access should be restricted

The fact that only two users exist does not justify bypassing access control.

---

# 36. Testing Strategy

## Backend Unit Tests

Test:

- nutrition calculations
- target percentage
- date handling
- ownership checks
- state transitions
- aggregation functions

## API Tests

Test:

- login
- unauthorized access
- adding log
- editing log
- deleting log
- sleep submission
- duplicate sleep submission
- historical day retrieval
- calendar
- statistics

## AI Tests

Use fixed sample journal inputs.

Verify that:

- valid JSON is produced
- Pydantic accepts expected outputs
- missing information remains missing
- AI does not create unsupported events
- nutrition confidence is preserved
- meal-level protein exists when identifiable

Do not rely exclusively on live Gemini calls in automated tests.

---

# 37. Example End-to-End Scenario

User writes:

```text
08:00 - Had 3 eggs and a banana.
10:30 - Drank 500ml water.
13:15 - Had chicken rice for lunch.
18:00 - Did 45 minutes of strength training.
21:00 - Read 15 pages of Atomic Habits.
23:30 - Sleeping now.
```

System flow:

```text
1. Flutter sends each log
2. FastAPI stores each raw log
3. User presses Sleeping Now
4. FastAPI stores sleep time
5. FastAPI retrieves all logs
6. FastAPI creates Gemini request
7. Gemini extracts structured information
8. Pydantic validates the response
9. Backend calculates totals
10. MongoDB stores daily_record
11. API returns daily summary
12. Flutter displays the completed day
```

---

# 38. Example AI Extraction Result

Conceptually:

```json
{
  "schema_version": "1.0",
  "nutrition": {
    "meals": [
      {
        "meal": "breakfast",
        "items": [
          {
            "food": "egg",
            "quantity": "3",
            "protein_g": 18,
            "protein_source": "estimated",
            "confidence": "high"
          },
          {
            "food": "banana",
            "quantity": "1",
            "protein_g": 1.3,
            "protein_source": "estimated",
            "confidence": "high"
          }
        ]
      },
      {
        "meal": "lunch",
        "items": [
          {
            "food": "chicken",
            "quantity": "unspecified",
            "protein_g": null,
            "protein_source": "unknown",
            "confidence": "unknown"
          },
          {
            "food": "rice",
            "quantity": "unspecified",
            "protein_g": null,
            "protein_source": "unknown",
            "confidence": "unknown"
          }
        ]
      }
    ],
    "hydration": {
      "water_ml": 500
    }
  },

  "fitness": {
    "workouts": [
      {
        "type": "strength_training",
        "duration_mins": 45
      }
    ]
  },

  "learning": {
    "activities": [
      {
        "book": "Atomic Habits",
        "pages": 15
      }
    ]
  }
}
```

The backend then computes totals only from available values.

It should not manufacture a protein number for unspecified chicken quantity.

---

# 39. Daily Processing Idempotency

This is critical.

If the user taps:

```text
Sleeping Now
Sleeping Now
Sleeping Now
```

the backend must not create three daily records.

Use:

```text
user_id + date
```

as the logical daily identifier.

The operation should be idempotent or explicitly reject duplicate completion.

---

# 40. Recommended Development Phases

## Phase 1 — Project Setup

Build:

- FastAPI project
- Flutter project
- MongoDB Atlas connection
- environment configuration
- basic health endpoint

Success condition:

```text
Flutter → FastAPI → MongoDB
```

works.

---

## Phase 2 — Authentication

Implement:

- predefined users
- login
- session/token
- logout
- `/users/me`

Success condition:

Two users can log in and cannot access each other's data.

---

## Phase 3 — Raw Journal

Implement:

- today's logs
- add
- edit
- delete
- timestamps

Success condition:

Natural-language entries persist correctly.

---

## Phase 4 — Day Lifecycle

Implement:

- open day
- Sleeping Now
- sleep timestamp
- previous-day fallback
- day states

Success condition:

A day can move safely from:

```text
OPEN → PROCESSING → COMPLETED
```

---

## Phase 5 — Gemini Extraction

Implement:

- Gemini client
- extraction prompt
- structured schema
- Pydantic validation
- error handling
- retry
- prompt/schema versioning

Success condition:

A real day's raw logs become a validated daily record.

---

## Phase 6 — Nutrition and Muscle-Gain Tracking

Implement:

- meal extraction
- food-level protein
- meal protein
- daily protein
- protein target
- target percentage
- confidence/source

Success condition:

The app can explain exactly where the day's protein came from.

---

## Phase 7 — Calendar and History

Implement:

- calendar endpoint
- calendar Flutter UI
- daily history
- completed-day indicators

Success condition:

The user can select any completed date and inspect it.

---

## Phase 8 — Statistics

Implement MongoDB aggregation pipelines for:

- daily
- weekly
- monthly
- protein
- hydration
- workout consistency
- completion consistency

Success condition:

Statistics are calculated by the backend, not Gemini.

---

## Phase 9 — AI Reports

Implement:

- weekly aggregation
- monthly aggregation
- Gemini report generation
- report persistence/caching

Success condition:

Gemini receives compact analytical summaries rather than raw history.

---

## Phase 10 — Testing and Hardening

Test:

- authentication
- ownership
- date boundaries
- duplicate processing
- Gemini failure
- malformed AI output
- MongoDB failure
- Flutter API errors
- empty days
- incomplete days

---

# 41. V1 Definition of Done

ZenLog V1 is complete when both users can:

1. Log in.
2. Open today's journal.
3. Add natural-language entries throughout the day.
4. Edit/delete mistakes.
5. Press "Sleeping Now".
6. Have the backend process the day's entries.
7. Receive structured nutrition/activity/learning/etc. data.
8. See food-level and meal-level protein.
9. See daily protein against their personal target.
10. Browse previous days through a calendar.
11. Open a historical day.
12. View weekly statistics.
13. View monthly statistics.
14. Receive weekly/monthly AI insights.
15. Recover a missed previous-day sleep submission.
16. Never access the other user's private data.

---

# 42. Future V2 Possibilities

Only after V1 is stable:

- food recommendation system
- meal suggestions based on remaining protein
- smarter muscle-gain coaching
- body-weight trend analysis
- workout progression
- custom habit templates
- reminders
- push notifications
- voice logging
- image-based food logging
- wearable integration
- advanced natural-language historical querying
- personalized AI coach
- richer correlation analysis

These are intentionally not part of the initial implementation.

---

# 43. Final Architecture Decision

The V1 architecture is:

```text
                    ZENLOG V1

                 ┌──────────────┐
                 │    Flutter   │
                 │    Mobile    │
                 └──────┬───────┘
                        │
                     REST API
                        │
                        ▼
                 ┌──────────────┐
                 │   FastAPI    │
                 │   Backend    │
                 └──┬────────┬──┘
                    │        │
             MongoDB Atlas   │
                    │        │
                    │     Gemini API
                    │        │
                    ▼        ▼
              Historical   AI-derived
                 Data        Data
                    │        │
                    └───┬────┘
                        ▼
                 Analytics/Reports
```

### Core rule

```text
User language → AI interpretation
AI interpretation → validated structured data
Backend → authoritative calculations
MongoDB → persistent history
Gemini → insights
Flutter → presentation
```

This keeps ZenLog simple, maintainable, private, and extensible without overengineering the first release.
