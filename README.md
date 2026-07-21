# Budget

A Flutter expense app for individuals and small businesses. It does two jobs
that most trackers keep separate:

- **Track** what has already been spent — record, categorise, budget, and
  understand it.
- **Plan** what will be spent — a set of live calculators for estimating the
  cost of a habit, a commute, a subscription stack, or a new business, before
  the money goes out.

Amounts are in Tanzanian Shillings (TSh).

## Features

### Tracker
- **Quick expense entry** — amount, category, profile, date, note, and receipt
  photos, from a bottom sheet.
- **Profiles** — keep Personal and Business (or any number of wallets)
  separate; every total and chart scopes to the active profile.
- **User-editable categories** — create, rename, recolour and delete. Each
  category owns a colour from a validated palette, so charts never repaint when
  spending changes.
- **Budgets** — give any category a monthly limit and it appears on the home
  screen as a goal card with a progress bar.
- **Search & filter** — by text, category, profile and date range, with a
  running total for whatever is filtered.
- **Analytics** — monthly trend, category breakdown, daily average, biggest
  expense.

### Planner
Six calculators that recalculate live as you type, each saveable as a named
scenario:

| Tool | Answers |
|------|---------|
| Daily Habit | "TSh 5,000 a day on lunch — what's that a year?" |
| Fuel | Litres and cost from distance, efficiency and pump price |
| Subscriptions | Every recurring service, totalled, with next payment dates |
| Business Costs | Operating costs and the revenue needed to cover them |
| Savings | A current habit against a cheaper alternative |
| Long-Term Projection | Cumulative spend over 1 / 3 / 5 / 10 years |

## Getting started

```bash
flutter pub get
flutter run                 # debug, on a connected device or simulator
flutter run --release       # release build (survives unplugging)
```

Run the tests:

```bash
flutter test        # 82 tests
flutter analyze
```

## Project structure

```
lib/
  main.dart              App entry, providers, theme wiring
  theme.dart            Light/dark themes, surfaces, status colours
  models/               Expense, Category, Profile, Scenario, icons, palette
  planner/engine.dart   Pure calculation engine (no Flutter imports)
  sync/merge.dart       Pure conflict-resolution engine for future cloud sync
  services/             Local storage (shared_preferences) + formatting
  state/app_state.dart  Single ChangeNotifier store over every collection
  widgets/              Charts, inputs, stat tiles, pickers
  screens/
    tracker/            Dashboard, expense list, add/edit sheet, filters
    analytics/          Trend, breakdown, stats
    planner/            The six calculators + planner hub
    manage/             Category & profile editors
    scenarios/          Saved scenario list
test/                   Engine, planner, tracker and merge tests
```

## Design notes

- **The calculation engine is pure Dart** (`lib/planner/engine.dart`) with no
  Flutter imports, so every figure is unit-tested against the spec's example
  numbers independently of the UI.
- **Time conventions:** a month is 30 days and a year is 365 days. These
  deliberately disagree (12 × 30 ≠ 365), so yearly figures are always derived
  from the daily rate, never from `monthly × 12` — otherwise long-range
  projections silently lose five days a year.
- **Chart colour is a validated categorical palette.** Categories pick a
  *slot*, not a free colour, and the palette is capped at eight distinguishable
  hues (checked for colour-vision-deficiency separation) plus a neutral
  "Other". Beyond eight, categories go neutral rather than inventing a ninth
  hue no colourblind reader could tell apart.
- **Local-first storage.** All data lives on-device in `shared_preferences`;
  receipts are files in the app's documents directory. The app has no network
  dependency and works fully offline.

## Roadmap

- **Cloud sync** — a pure-Dart merge engine (last-write-wins with delete
  tombstones) and per-record `updatedAt`/`deletedAt` timestamps are already in
  place and tested; the Firebase wiring, auth and security rules are not yet
  built.
- **Smart categories** — per-category custom fields (litres for fuel, kWh for
  electricity, etc.).
- **Reports & richer insights** — export and automatic comparative insights
  from recorded data.

## Stack

Flutter · provider · shared_preferences · fl_chart · intl · uuid ·
image_picker · path_provider
