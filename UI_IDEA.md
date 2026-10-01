# ZenLog Mobile — UI/UX Design System & Architectural Blueprint

> **Inspired by Organic Zen Aesthetics, Frosted Glassmorphism, and Apple-grade Micro-interactions.**

---

## 1. Visual & Emotional Philosophy

ZenLog transforms daily self-reflection, nutrition tracking, and habit journaling into a calm, mindful ritual. Drawing directly from the reference design language:
- **Biophilic & Organic**: Calming sage, matcha, and deep forest tones evoke mental clarity, steady growth, and grounded focus.
- **Translucent Depth (Glassmorphism)**: Frosted glass containers (`backdrop-filter: blur`), subtle 1px luminous borders, and soft organic drop shadows that feel physical and touchable.
- **Airy Breathing Room**: Generous padding, clean negative space, and modern typographic hierarchy (Playful bold display headings paired with crisp geometric body typography).
- **Tactile Floating Controls**: Pill buttons, floating dock navigation bars, and rounded squircles that feel delightful under the thumb.

---

## 2. Color Palette & Design Tokens

```css
/* Core Botanical Palette */
--zen-sage-bg:        #F1F5F2;       /* Ultra-soft sage ambient background */
--zen-sage-surface:   #FFFFFF;       /* Crisp card surface */
--zen-sage-glass:     rgba(255, 255, 255, 0.72); /* Frosted glass */
--zen-sage-border:    rgba(46, 80, 58, 0.08);    /* Delicate inner border */

--zen-forest-dark:    #193222;       /* High-contrast headlines & primary CTAs */
--zen-forest-medium:  #284F38;       /* Secondary text & active icons */
--zen-emerald-accent: #22C55E;       /* Brand highlight & progress metrics */
--zen-mint-glow:      #A7F3D0;       /* Glow effects & scan reticles */
--zen-sage-pill:      #E4ECE6;       /* Neutral pill containers */

/* Semantic Status */
--zen-protein-amber:  #F59E0B;       /* Protein target tracking */
--zen-hydration-cyan: #06B6D4;       /* Water intake */
--zen-workout-purple: #8B5CF6;       /* Fitness & strength metrics */
```

---

## 3. Screen Breakdown & Flow

### Screen 1: Onboarding & Mindful Welcome
- **Top Bar**: Social proof trust pill (`🌿 Loved by 10k+ Mindful Achievers` with overlapping modern avatars).
- **Hero Display**: Photorealistic, 3D zen botanical hero (lush peace lily / bonsai with dew drops and floating leaves).
- **Headline**: Two-tone bold typography:
  > **Mindful**  
  > **Daily Flow**  
  > *AI journal & nutrition intelligence on the go.*
- **Interactive Action**: Dark forest-green pill container with a smooth swipe/tap circular arrow button (`Get Started →`).
- **Footer**: Subtle "Already have an account? Sign In" action sheet trigger.

---

### Screen 2: Zen Home Dashboard
- **Header**:
  - Left: User profile avatar with soft border, greeting ("Good morning, Prajwal"), and status tag (`Mindful Streak 🔥 7 Days`).
  - Right: Circular frosted glass notification bell button with unread indicator dot.
- **Dynamic Headline**:
  > **What Are We**  
  > **Reflecting On** Today?
- **Quick-Log Pill Input**:
  - Pill-shaped entry field: `"Breakfast: 3 eggs, 45m workout..."` with a floating quick-add (+) action button.
- **Hero Synthesis Card ("Sleep & Process Day")**:
  - Frosted glass banner featuring a 3D zen visual, status chip (`Day Open`), and a direct CTA to close the day with sleep time and trigger AI extraction.
- **Quick Action Squircle Grid**:
  1. **Nutrition** (Live protein target ring, hydration counter, calories)
  2. **Workouts** (Strength sets, minutes, cardio)
  3. **Mind & Mood** (Gratitude notes, habit check-offs)
  4. **AI Insights** (Weekly and monthly synthesis)
- **Today's Timeline Stream**:
  - Chronological live journal stream with parsed entity tags (`🍳 3 Eggs (18g protein)`, `💧 750ml`, `🏋️ 45m Gym`).
- **Floating Dock Navigation Bar**:
  - Pill-shaped frosted glass bottom dock:
    - 🌿 **Home**
    - 📅 **Calendar**
    - 📊 **Insights**
    - 👤 **Profile**

---

### Screen 3: Live AI Sleep & Extraction Studio
- **Modal / Scanner Reticle**:
  - Aesthetic camera / radar animation with glowing emerald corners simulating AI extraction.
- **Live Analysis Breakdown**:
  - Progress bar (`Extracting nutrition, workouts, and mood... 100%`).
  - Extracted cards with confidence tags (`High Confidence`, `Estimated`).
  - Instant macro recalculation against the user's daily protein target (e.g. `18g / 126g · 14.3% achieved`).

---

### Screen 4: Visual Calendar & History
- Multi-day horizontal interactive date picker with completion status rings (Green check for processed days, Amber for open days).
- Deep-dive into any past day’s structured record, raw entries, and sleep timings.

---

### Screen 5: AI Periodic Insights & Analytics
- Toggle between **Weekly** and **Monthly** AI Reports.
- Growth Wins, Coaching Notes, Areas to Improve, and High-protein achievement percentages.
- Clean bar charts and streak metrics powered by the backend MongoDB stats endpoints.

---

## 4. Backend Integration Mapping

| Mobile UI Component | Backend API Endpoint |
| :--- | :--- |
| Auth & Auto-login | `POST /api/auth/login`, `GET /api/users/me` |
| Profile & Protein Target | `PUT /api/users/me` |
| Quick Journal Add / Stream | `POST /api/logs`, `GET /api/logs/today` |
| Day Status & Raw Entries | `GET /api/days/{date}` |
| Nightly Sleep Submission | `POST /api/days/sleep` |
| Multi-Day Calendar | `GET /api/calendar?from=...&to=...` |
| Aggregated Analytics | `GET /api/stats/daily/...`, `weekly`, `monthly` |
| AI Synthesized Reports | `GET /api/insights/weekly`, `GET /api/insights/monthly` |

---

## 5. Mobile Engineering Stack
- **Framework**: Flutter 3.47+ (Dart 3.13+)
- **Design System**: Custom `ZenTheme` with Cupertino/Material hybrid glassmorphism, `google_fonts` (Plus Jakarta Sans / Outfit).
- **State Management**: Clean service/notifier pattern with reactive streams.
- **HTTP Client**: Resilient REST client connecting directly to the FastAPI backend.
