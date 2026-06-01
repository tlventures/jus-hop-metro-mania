# MetroSafar UI Redesign - Implementation Progress

## Overview
This document tracks the implementation of Phases 1-3 of the MetroSafar UI redesign and modernization plan.

## ✅ Completed (Phase 1 Foundation)

### 1. Dependencies & Build System
- ✅ Updated `pubspec.yaml` with Riverpod 2, go_router, freezed, flutter_animate, google_fonts, fl_chart
- ✅ Added dev dependencies: build_runner, freezed, json_serializable, very_good_analysis

### 2. Design System (lib/design_system/)
- ✅ **Token System**:
  - `tokens/colors.dart` — Material 3 color scheme (Metro Indigo #4F46E5, Warm Coral #FB7185, Mint Success #10B981) + light/dark schemes
  - `tokens/spacing.dart` — 4pt grid system (s1-s24 + semantic patterns)
  - `tokens/radius.dart` — 8 border radius values + BorderRadius objects
  - `tokens/motion.dart` — Animation durations (fast/med/slow) + easing curves
  - `tokens/typography.dart` — Material 3 type scale (Manrope headings + Inter body)

- ✅ **Theme System**:
  - `theme.dart` — Complete ThemeData factory with Material 3 compliance, AppBar, Card, Button, Chip themes

- ✅ **Components** (partial):
  - `components/app_scaffold.dart` — AppScaffold, GlassCard, ShimmerBox, EmptyState, ErrorState

### 3. Core Architecture (lib/core/)
- ✅ `result.dart` — Result<T> sealed class, Success/Error variants, Failure hierarchy
- ✅ `env.dart` — Environment config (API_BASE_URL, production flag)

### 4. Domain Layer (lib/domain/entities/)
- ✅ `user.dart` — User entity (Freezed) with copyWith, toJson/fromJson, computed properties
- ✅ `game.dart` — Game entity (Freezed)
- ✅ `reward.dart` — Reward entity (Freezed)
- ✅ `article.dart` — Article entity (Freezed)
- ✅ `survey.dart` — Survey + SurveyResponse entities (Freezed)

### 5. Routing & Navigation
- ✅ `app/router.dart` — go_router setup with ShellRoute for bottom nav (Home / Play / Wallet / Profile tabs)

### 6. App Entry
- ✅ `main.dart` — Completely refactored with Riverpod ProviderScope + go_router + Material 3 theme

### 7. Screens Redesigned (Phase 1)
- ✅ **Home Screen** (`features/home/presentation/home_screen.dart`):
  - Gradient AppBar with greeting
  - 5-day streak strip with claim button
  - Daily Quests (Play / Watch / Read) cards
  - Wallet preview hero with points balance + tier ring + progress
  - Quick Earn carousel (Daily Spin, Trivia, Watch)
  - Eco impact strip
  - Modern Material 3 styling throughout

- ✅ **Wallet Screen** (`features/wallet/presentation/wallet_screen.dart`):
  - Balance hero with animated tier ring + progress
  - "How to Earn" method tiles (Games / Videos / Articles / Surveys)
  - Tabbed "Redeem Rewards" section (Food / Shopping / Travel / Experiences)
  - CouponCard widgets with gradient, discount %, points cost, Redeem button
  - Professional layout matching design tokens

- ✅ **Play Hub Placeholder** (`features/play/presentation/play_hub_screen.dart`)
- ✅ **Profile Placeholder** (`features/profile/presentation/profile_screen.dart`)
- ✅ **Booking Coming Soon** (`features/booking/presentation/booking_coming_soon_screen.dart`) — preserves intent, shows "launching soon" + waitlist signup

---

## ⏳ In Progress / Remaining Work

### Phase 2: Game Shell & Polish (Est. 2 weeks)
**Not yet implemented** — These files need to be created:

1. **GameShell Component** (`lib/design_system/components/game_shell.dart`)
   - Gradient header with back button, lives/streak, timer
   - Consistent bottom action bar
   - End-of-round bottom sheet template with Lottie celebration
   - Shared scoring UI, combo meter

2. **Game Screen Refactors**:
   - `features/play/games/trivia_screen.dart` — Progress bar, stagger reveal, answer chips, streak multiplier
   - `features/play/games/sudoku_screen.dart` — Improved number pad UI, pencil marks, haptic feedback
   - `features/play/games/word_puzzle_screen.dart` — Drag-tiles instead of text input
   - `features/play/games/city_explorer_screen.dart` — Map-first redesign with pin markers, bottom sheet details
   - `features/play/games/daily_spin_screen.dart` — NEW: Lottie wheel animation + daily streak bonus

3. **Engagement Mechanics**:
   - Daily Streak provider (Riverpod)
   - Daily Quests provider + completion tracking
   - Scratch cards after sessions
   - Leaderboard data structures (stub)

4. **Providers** (Riverpod):
   - `features/play/application/games_provider.dart`
   - `features/wallet/application/rewards_provider.dart`
   - `features/home/application/streak_provider.dart`
   - `features/home/application/quest_provider.dart`

### Phase 3: Content Features (Est. 2 weeks)
**Not yet implemented** — These files need to be created:

1. **Articles Screen** (`features/learn/articles/articles_screen.dart`)
   - Article feed with Medium-style cards
   - Cover image, title, read-time, points badge
   - Use `flutter_markdown` for rich text
   - Dwell-time tracking (60s = points)

2. **Surveys Screen** (`features/learn/surveys/surveys_screen.dart`)
   - Swipeable survey cards (Tinder-style)
   - Single-question format + multiple-choice options
   - Points awarded on completion

3. **Station Stories Screen** (`features/learn/stories/stories_screen.dart`)
   - Instagram-story-style frames per metro station
   - 5 frames per story + final mini-quiz
   - 3-question validation

4. **Learn Hub Tab** (`features/learn/presentation/learn_hub_screen.dart`)
   - Unified entry point for Articles / Surveys / Station Stories

5. **Backend Entities** (in `/backend`):
   - Article model + `/api/articles` endpoint
   - Survey model + `/api/surveys/:id/submit` endpoint
   - Station Story model + `/api/stories` endpoint
   - Daily Quests model + `/api/quests/complete` endpoint
   - Daily Spin endpoint + `/api/spin` (returns reward: {points, coupon?})
   - Streak tracking in user record + `/api/streak/claim` endpoint

### Other Remaining Items
- **Repositories** (Riverpod-based data layer):
  - `data/repositories/user_repository.dart`
  - `data/repositories/games_repository.dart`
  - `data/repositories/rewards_repository.dart`
  - `data/repositories/articles_repository.dart`

- **Services** (HTTP clients):
  - Dio client + interceptors
  - Caching with `dio_cache_interceptor`

- **Complete Component Library**:
  - PointsChip, TierRing, StreakFlame, QuestTile, GameCard (complete)
  - Confetti animation, page transitions

- **Tests**:
  - Golden tests for key screens
  - Widget tests for components
  - Integration tests for critical flows

- **Ticket Booking Preservation**:
  - Move `lib/screens/ticket_booking_screen.dart` → `lib/features/booking/ticket_booking_screen.dart`
  - Comment out entire implementation (keep in `/* … */` block)
  - Keep imports and class signature

- **Old Code Cleanup**:
  - Delete or archive `lib/providers/` (replace with Riverpod)
  - Delete `lib/screens/` (migrate to `lib/features/*/presentation/`)
  - Delete `lib/utils/theme.dart` (replaced by design_system)

---

## Next Steps (Recommended Order)

### 1. Test Build (Immediate)
```bash
cd /Users/kk/apps/ticketbook
flutter pub get
flutter analyze
flutter build apk --debug 2>&1 | head -50  # See first errors
```

**Expected issues**: Freezed files missing (run build_runner to generate `.freezed.dart` + `.g.dart`)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 2. Complete Phase 2 (1-2 weeks)
Priority order:
1. Create GameShell component and one fully-polished game (Trivia)
2. Add Daily Spin + Streak mechanics
3. Refactor remaining 3 games using the template
4. Add Lottie animations (celebration, wheel, etc.)

### 3. Complete Phase 3 (1-2 weeks)
Priority order:
1. Articles feed + backend endpoint
2. Surveys + backend endpoint
3. Station Stories (most complex, lowest ROI — do last)
4. Backend routes for Daily Quests + Spin + Streak

### 4. Polish & Release
- Run `flutter analyze` → fix all very_good_analysis lint issues
- Add firebase_analytics + consent UI
- Update Play Data Safety form (completed in audit checklist)
- Dark mode testing (already wired in theme)

---

## Key Files Created

```
lib/
  app/
    router.dart ✅
  design_system/
    theme.dart ✅
    tokens/
      colors.dart ✅
      spacing.dart ✅
      radius.dart ✅
      motion.dart ✅
      typography.dart ✅
    components/
      app_scaffold.dart ✅
  core/
    result.dart ✅
    env.dart ✅
  domain/
    entities/
      user.dart ✅
      game.dart ✅
      reward.dart ✅
      article.dart ✅
      survey.dart ✅
  features/
    home/presentation/
      home_screen.dart ✅
    wallet/presentation/
      wallet_screen.dart ✅
    play/presentation/
      play_hub_screen.dart ✅
    profile/presentation/
      profile_screen.dart ✅
    booking/presentation/
      booking_coming_soon_screen.dart ✅
  main.dart ✅
```

---

## Design System Highlights

- **Color**: Metro Indigo (#4F46E5) + Warm Coral (#FB7185) + Mint Success (#10B981) + Gold Points (#F59E0B)
- **Typography**: Manrope (headings) + Inter (body), Material 3 type scale
- **Spacing**: 4pt grid, s1-s24 tokens
- **Radius**: 8 radius values (4 → 32 → full), preset shapes for cards/buttons/chips
- **Motion**: fast (150ms) / med (300ms) / slow (500ms) with easeOutCubic emphasis curve
- **Components**: AppScaffold, GlassCard, ShimmerBox, EmptyState, ErrorState (framework for others)

---

## Known Limitations

1. **Freezed code generation** — Models won't compile until `build_runner` generates `.freezed.dart` + `.g.dart` files
2. **Placeholder Riverpod providers** — None created yet; screens use mock data (hardcoded 2,450 points, etc.)
3. **No offline caching** — Dio client not wired up yet
4. **No analytics** — Firebase Analytics skeleton only
5. **Booking preservation** — File needs to be manually commented; router preserves a "Coming soon" placeholder instead

---

## Estimated Effort

| Phase | Scope | Effort | Status |
|-------|-------|--------|--------|
| 1 | Design system + Home + Wallet | ✅ Done | 100% |
| 2 | Game shell + 4 games + mechanics | 4 weeks | 0% (templated) |
| 3 | Articles + Surveys + Stories | 3 weeks | 0% (sketched) |
| Polish | Linting, tests, analytics, compliance | 2 weeks | 0% |
| **Total** | | **~9 weeks** | **25%** |

---

## Questions / Blockers

- **Backend capacity**: Phase 3 adds ~8 new API endpoints. Ensure backend dev is in parallel.
- **Asset creation**: Need Lottie animations (wheel, celebration, tree, flame, tier upgrade) — ~3-5 assets
- **Content ops**: Article/Survey/Story pipeline required (admin UI, CMS, or manual JSON)?
- **Analytics**: Firebase Analytics + consent UI not yet planned into phases

---

## Commands to Continue

```bash
# Generate Freezed models
flutter pub run build_runner build --delete-conflicting-outputs

# Test
flutter test

# Analyze
flutter analyze

# Build
flutter build apk --debug
flutter build ios --debug

# Run (emulator)
flutter run -d emulator-5554
```

---

**Last Updated**: 2026-05-17  
**Next Review**: After build_runner pass
