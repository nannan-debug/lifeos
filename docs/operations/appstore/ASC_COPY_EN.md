# LifeOS · App Store Connect — English Localization

> Copy each section into the corresponding ASC field under the **English (U.S.)** localization.
> Tone: gentle, non-judgmental, no hustle culture, no feature-dumping.
> Last updated: 2026-06-17

---

## 0. How to add English localization in ASC

1. App Store Connect → LifeOS → Distribution → iOS App → your current version
2. Top-left language dropdown → **Add Localization** → **English (U.S.)**
3. Fill in each field below. The app binary stays the same — no need to re-upload.

---

## 1. App Name

```
LifeOS
```

Same as Chinese — no localization needed.

---

## 2. Subtitle (max 30 characters)

```
Brain dump, gently sorted
```

26 characters. Captures the core UX: say anything, AI sorts it for you.

---

## 3. Promotional Text (max 170 chars, can be changed anytime without review)

```
Not another productivity app. LifeOS is a gentle life-tracking system — brain-dump one sentence and AI sorts it into tasks, time blocks, and moods. No streaks, no shame.
```

169 characters.

---

## 4. Description

```
LifeOS is not another productivity app.

It's a gentle life-tracking system designed for people whose brains don't work in neat categories — especially (but not only) those with ADHD. Say one sentence, and AI sorts it into the right bucket: a task, a time block, a mood note, or a daily check-in.

The underlying philosophy borrows from DBT (Dialectical Behavior Therapy): observe first, then adjust. See yourself clearly, and action follows naturally.

4 TABS, ONE GENTLE DAY
- Today — daily check-ins and tasks, grouped by your own tags
- Time — time-block tracking to see where your hours went
- Notes — thoughts, feelings, gratitude, and dreams — give your emotions a name
- Settings — iCloud sync, data management, language toggle

GLOBAL AI INPUT
A floating input bar lives at the bottom of every screen. Type "call mom at 9am tomorrow, pick up flowers first" and it splits into a task + a time block. Don't want to go online? Tap the lightning bolt for fully local parsing — nothing leaves your phone.

ADHD-FRIENDLY PROMISES
- No streaks (missing one day shouldn't make you quit)
- No "you haven't opened the app in X days" notifications
- No completion percentages, rankings, or week-over-week guilt trips
- Every input field can be submitted empty
- "Rest day" and "maybe tomorrow" instead of "incomplete" and "failed"

PRIVACY
- Data lives on your iPhone only; uninstall = gone
- Only when you tap the AI button does your current text go to our Cloudflare server → DeepSeek for parsing, then immediately discarded
- No IDFA, no analytics SDK, no tracking, no ads, no in-app purchases

For everyone whose brain works a little differently.
Look in the mirror gently — you'll see yourself clearly, in time.
```

---

## 5. Keywords (max 100 characters, comma-separated, no spaces around commas)

```
ADHD,brain dump,journal,mood,todo,habits,time tracking,self care,reflection,AI,planner,mindfulness
```

98 characters.

---

## 6. What's New — 1.13.0

```
- New onboarding questionnaire so your cat companion learns your name, job, and goals.
- Customize your cat's name, personality, speaking style, and memory preferences.
- Upgraded memory system: long-term profile, interaction preferences, recent status, and plans.
- Emotional check-ins now happen naturally inside conversations instead of a separate mode.
- Stability fixes for weekly reviews and the Trace Dashboard.
```

For future versions, keep the English What's New in sync with the Chinese version in `ASC_COPY_DRAFT_v1.md §0`.

---

## 7. What's New — template for minor updates

```
Bug fixes and small improvements. We're still here, still gentle.
```

Use this as a fallback when a release is mostly internal fixes.

---

## 8. Pricing and Availability note

Since June 2026, LifeOS is available in **all territories including China mainland**.

No pricing changes needed — the app is free worldwide.

---

## 9. Checklist: adding English localization to a new ASC version

- [ ] In ASC version page, add English (U.S.) localization if not already present
- [ ] Copy Subtitle from §2
- [ ] Copy Promotional Text from §3 (or update if there's a timely message)
- [ ] Copy Description from §4 (update only if features changed significantly)
- [ ] Copy Keywords from §5
- [ ] Write English What's New for this version (translate from Chinese draft in `ASC_COPY_DRAFT_v1.md §0`)
- [ ] Screenshots: can reuse Chinese screenshots initially; consider English-UI screenshots later
- [ ] Save → the English localization submits together with the Chinese one
