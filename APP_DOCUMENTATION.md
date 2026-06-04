# MetroSafar — Complete App Documentation

## Executive Summary

**MetroSafar** is a comprehensive metro companion mobile application designed for major Indian metro networks (Hyderabad, Delhi, Bangalore, and Chennai). The app combines commute planning, gamification, rewards, and community engagement to create a delightful daily metro experience. Built with Flutter for mobile and Next.js for admin, it features real-time data synchronization, personalized recommendations, and a sophisticated points/redemption ecosystem.

**Version:** 1.0.21 (Build 22)  
**Tech Stack:** Flutter 3.35.5, Node.js/Express backend, Next.js admin, Firestore, Firebase Auth, Cloud Run  
**Status:** Active development, approaching Play Store release

---

## Core Value Proposition

MetroSafar transforms the daily commute into an engaging experience by:
- **Seamless Trip Planning** — real-time ETA, station guides, and route optimization
- **Gamified Rewards** — daily streaks, quests, and mini-games earn points redeemable for real rewards
- **Community Content** — curated articles, audio stories, trivia, and events
- **Multi-City Support** — consistent experience across 4 major Indian metro networks
- **Admin-Driven Content** — real-time catalog updates without app redeploys

---

## App Architecture

### Technology Stack

| Component | Technology | Details |
|-----------|-----------|---------|
| **Mobile** | Flutter 3.35.5 | Riverpod v2 (state management), go_router (navigation), Material 3 design |
| **Backend** | Node.js/Express | ~3200+ lines, Cloud Run (GCP), Firestore for data, Redis optional |
| **Admin** | Next.js 14 (TypeScript) | Firebase Auth + RBAC, real-time content/flag management |
| **Database** | Firestore | Document collections + composite indexes for queries |
| **Auth** | Firebase Auth | Custom claims RBAC, OAuth/Google Sign-In |
| **Push Notifications** | Firebase Cloud Messaging (FCM) | Topic-based broadcasts, deep-linking, per-city targeting |
| **Ads** | Google Mobile Ads SDK | Test units (development), real AdMob IDs for release |
| **Analytics** | Firebase Analytics + Crashlytics | User telemetry, crash tracking |
| **Hosting** | Google Cloud Run | Fully managed, auto-scaling backend + admin |

### Core Services

1. **BackendService** — HTTP API client (Dio + caching)
2. **NotificationService** — FCM initialization, topic subscriptions, deep-link routing
3. **AnalyticsService** — Firebase event logging
4. **ConnectivityWatcher** — network state monitoring
5. **LocalizationService** — multi-language support (Telugu, Hindi, Kannada, Tamil)

---

## Feature Breakdown

### 1. **Authentication & Onboarding**

**Screens:**
- `LoginScreen` — Google Sign-In + Firebase Auth
- `OnboardingScreen` — language + city selection
- `PermissionsScreen` — location, notifications, storage permissions
- `PrivacyConsentScreen` — GDPR/privacy policy acceptance
- `LanguageSelectorScreen` — language preference (4 languages supported)

**Key Endpoints:**
- `POST /api/auth/signup` — create user profile
- `POST /api/auth/profile` — update user info

**User Profile Fields:**
- Display name, email, phone
- City selection (user's primary metro)
- Language preference
- Points balance & tier (Bronze, Silver, Gold, Platinum)
- Onboarding completion status

---

### 2. **Home Screen & Daily Activity**

**Main Hub:** Central dashboard showing user's daily progress

**Components:**
- **Streak Tracker** — calendar-day based (IST timezone)
  - Current streak + longest streak
  - Visual timeline (M–S days with check marks)
  - Auto-increments on app open if due (next day in IST)
  - Claim bonus: +5 points × day number
  
- **Daily Quests** (0–4 active tasks)
  - Start Ride (30 pts) — begin a trip
  - Watch a Video (15 pts) — complete a 10–30s rewarded ad
  - Read an Article (15 pts) — from the Learn section
  - Answer a Station Quiz (25 pts) — station trivia
  
- **Points Balance** — top-right pill showing current total
- **Tier Badge** — earned through points (Bronze → Silver → Gold → Platinum)
- **Metro Companion Shelf** — quick-access cards (Book Tickets, Stamps, Audio, Events)
- **Start Ride Button** — primary CTA, docked at bottom

**Backend Integration:**
- `GET /api/home` — aggregate endpoint (streak, quests, wallet, games, featured videos)
- Hydrates `streakProvider`, `questsProvider`, `walletProvider` in single round-trip
- Auto-claims daily streak on open if `canClaim` (calendar day mismatch from `lastClaimedAt`)

---

### 3. **Trip Mode (Ride Tab)**

**Purpose:** Track active metro trips with real-time features

**Key Features:**
- **Active Trip Display** — current station, next station, remaining stops, ETA
- **Trip History** — list of completed trips with timestamps
- **Station Detail View** — platform number, accessibility info, nearby POIs
- **QR Verification** — scan ticket QR codes at stations
- **Offline Sync** — outbox queue for connectivity-challenged areas
  - Syncs when connection restored
  - Shows sync badge with pending count

**Data Model:**
```
Trip {
  id, userId, startStation, endStation, 
  startTime, endTime, distance, duration,
  co2Saved, pointsEarned, status, createdAt
}
```

**Backend Endpoints:**
- `POST /api/trips` — start a trip
- `POST /api/trips/:id/end` — end trip, calculate CO₂ + points
- `POST /api/trips/:id/verify-qr` — validate station QR
- `GET /api/trips` — trip history (paginated)

---

### 4. **Play & Gamification Hub**

**Central Gamification Center:** Games, streaks, and mini-challenges

**Games Available:**
- **Daily Spin** — spin-to-win random rewards (test integration)
- **Metro Trivia** — city-specific multiple-choice questions
- **Sudoku** — puzzle game with difficulty levels
- **Word Puzzle** — language-aware word games
- **City Explorer** — landmark/station identification

**Gameplay Mechanics:**
- Each game completion = quest (auto-marked)
- Leaderboard ranking by score
- Daily spin capped at 5/day for balance

**Screens:**
- `PlayHubScreen` — list of games + WatchAndEarnCard (rewarded ads)
- `DailySpinScreen` — spinner UI + prize modal
- `TriviaScreen` — MCQ flow with scoring
- `SudokuScreen` — puzzle solver
- `WordPuzzleScreen` — interactive word game
- `CityExplorerScreen` — landmark quiz

**Backend:**
- `POST /api/games/:gameId/complete` — record game result + points
- `GET /api/games/:gameId/leaderboard` — top 50 players

---

### 5. **Wallet & Redemptions**

**Points Economy:** Earn → redeem for real rewards

**Earning Sources:**
- Daily streaks (+5 per day)
- Quest completion (+15–30 each)
- Game completion (+10–50 per game)
- Rewarded video ads (+15, capped 5/day)
- Referrals (variable)

**Redemption Options:**
- **Code Pools** — pre-seeded codes (e.g., Amazon, Flipkart vouchers)
- **Instant Codes** — auto-generated on redeem
- **Affiliate Links** — partner integrations (future)

**My Redemptions:**
- Track pending, fulfilled, cancelled redemptions
- Push notifications on fulfillment
- Redemption code display/copy

**Screens:**
- `WalletScreen` — points balance, tier progress, redemption history
- `MyRedemptionsScreen` — user's past & pending redemptions
- `RewardsFeatureScreen` — redemption catalog

**Backend:**
- `GET /api/me` — user profile + wallet
- `GET /api/catalog/rewards` — catalog of redeemable items
- `POST /api/rewards/redeem` — request a reward
- `GET /api/me/redemptions` — user's redemption history (paginated)

---

### 6. **Learn Hub & Content**

**Educational Content:** Articles, audio stories, surveys

**Content Types:**
1. **Articles** — metro guides, travel tips, city history
   - Markdown rendering
   - Reading time estimate
   - Share functionality
   
2. **Audio Stories** — "Metro Tales"
   - City-specific narratives (10–30 min)
   - Audio player with controls
   - Offline download support (via just_audio)
   
3. **Surveys & Quizzes** — user feedback + points
   - Station knowledge quizzes
   - User feedback forms
   
4. **Featured Videos** — short clips for Watch & Earn

**Screens:**
- `LearnHubScreen` — tabbed interface (Articles, Audio, Videos)
- `ArticlesScreen` — list + detail views
- `AudioStoriesScreen` — player UI
- `StoriesScreen` — detailed story view
- `SurveysScreen` — survey flow

**Backend:**
- `GET /api/catalog/articles` — article list
- `POST /api/articles/:id/read` — track reading
- `GET /api/audio/stories` — audio catalog
- `POST /api/surveys/:id/submit` — submit survey response

---

### 7. **Notifications & Inbox**

**Real-Time Communication:** Push notifications + in-app inbox

**Notification Triggers:**
- Admin broadcasts (all users / by city / by user list)
- Streak reminders (daily)
- Reward fulfillment (instant)
- Event announcements
- Maintenance alerts

**Features:**
- In-app inbox with detail sheet
- Push → tap → deep link to relevant screen
- Unread badge on bell icon
- Mark-as-read on inbox open
- Detail sheet redesign (circular icon, source label, divider, timestamp)

**Screens:**
- `NotificationsInboxScreen` — list view + detail bottom sheet

**Backend:**
- `GET /api/notifications/feed` — user's inbox
- `POST /api/notifications/:id/read` — mark as read
- Admin sends via `/api/admin/notifications/send` with `screen` deep-link token

**Deep-Link Mapping:**
```
screen: 'my_redemptions' → /my-redemptions
screen: 'game', gameId: 'trivia' → /game/trivia
screen: 'settings' → /settings
screen: 'wallet' → /wallet
... (all 17 routes supported)
```

---

### 8. **Social Features**

**Community & Sharing:**
- **Friends List** — users you follow
- **Referral Program** — invite & earn
- **Leaderboards** — city-wide ranking by score
- **Social Sharing** — share games, articles, achievements

**Screens:**
- `FriendsScreen` — follow/unfollow, view friend's scores
- `ReferralScreen` — referral link + earning tracker

**Backend:**
- `GET /api/leaderboard` — top 50 by score
- `GET /api/friends` — user's following list
- `POST /api/friends/:userId/follow` — add friend
- `POST /api/referral/generate-link` — create ref link

---

### 9. **City-Specific Content**

**Multi-City Support:** Hyderabad, Delhi, Bangalore, Chennai

**City Data Includes:**
- Station list (name, code, line, platform info)
- Accessibility features (elevators, ramps)
- Nearby POIs (restaurants, ATMs, restrooms)
- City-specific trivia content
- Local landmarks
- City-specific stamps/achievements

**Screens:**
- `CityConfirmScreen` — city selection on onboarding
- `CityWaitlistScreen` — for future cities

**Backend:**
- `GET /api/cities` — list of supported cities
- `GET /api/cities/:cityId` — city details + content packs

---

### 10. **Station Stamps & Achievements**

**Collectible Gamification:** Visit stations, earn stamps

**Mechanics:**
- Stamp earned on trip completion at new station
- Visual stamp design per station/city
- Collector achievement badges
- Leaderboard for most stamps

**Screens:**
- `StampsScreen` — grid of collected stamps

**Backend:**
- `GET /api/stamps` — user's collected stamps
- Automatically awarded after `POST /api/trips/:id/end`

---

### 11. **Events & Live Updates**

**Timely Information:** Service announcements, metro events

**Event Types:**
- Maintenance alerts
- Line closures
- Special events (festivals, sports)
- Promotional campaigns

**Screens:**
- `EventsScreen` — live events feed

**Backend:**
- `GET /api/events` — active events (filtered by city, time)

---

### 12. **Booking Coming Soon**

**Future Feature:** Ticket booking integration

**Current State:**
- `BookingComingSoonScreen` — waitlist signup
- `POST /api/booking/waitlist` — capture email for notifications

---

### 13. **Profile & Settings**

**User Personalization:**

**Profile Screen:**
- Avatar (city-themed initial)
- Display name
- Stats (total rides, CO₂ saved, points earned)
- Tier badge
- Activity history preview
- Link to Settings

**Settings Screen:**
- Language preference
- Notification toggles
- Privacy/legal
  - Privacy Policy
  - Terms of Service
  - Data deletion request
- Logout

**Screens:**
- `ProfileScreen` — read-only summary
- `SettingsScreen` — preferences + legal

**Backend:**
- `PATCH /api/me` — update profile
- `DELETE /api/me` — request account deletion

---

## Backend API Reference

### Authentication

All endpoints require Firebase Bearer token (except `/api/auth/signup`, `/api/login`).

```
Authorization: Bearer <firebaseToken>
```

### Rate Limiting (Per-Class)

| Class | Limit | Window |
|-------|-------|--------|
| Game | 60 | 15m |
| Content | 40 | 15m |
| Trip | 30 | 15m |
| Social | 20 | 15m |
| Redeem | 12 | 15m |
| Account | 5 | 15m |
| Build | 3 | 15m |

---

### Core Endpoints

#### Home & Profile
```
GET  /api/home               — aggregate (streak, quests, wallet, games, videos)
GET  /api/me                 — user profile + wallet summary
PATCH /api/me                — update profile
DELETE /api/me               — request deletion
```

#### Streaks & Quests
```
POST /api/streak/claim       — claim daily bonus (idempotent, once/IST day)
GET  /api/quests             — user's daily quests
POST /api/quests/:id/mark    — mark quest complete
```

#### Trips
```
POST /api/trips              — start a trip
POST /api/trips/:id/end      — end trip, award points/CO₂
POST /api/trips/:id/verify-qr — QR validation at station
GET  /api/trips              — trip history (paginated)
GET  /api/trips/:id          — trip details
```

#### Games & Rewards
```
POST /api/games/:gameId/complete    — record game score
GET  /api/games/:gameId/leaderboard — top 50 players
POST /api/rewards/watch-ad          — complete rewarded ad (once/day)
```

#### Catalog
```
GET /api/catalog/rewards     — reward catalog
GET /api/catalog/articles    — articles list
GET /api/catalog/games       — games metadata
GET /api/catalog/quests      — daily quests
GET /api/audio/stories       — audio stories
GET /api/events              — live events
GET /api/stamps              — user's stamps
```

#### Redemptions
```
POST /api/rewards/redeem     — request a reward
GET  /api/me/redemptions     — user's redemptions (paginated)
```

#### Notifications
```
GET /api/notifications/feed  — inbox (paginated)
POST /api/notifications/:id/read — mark as read
```

#### Admin
```
GET  /api/admin/health       — system health + metrics
GET  /api/admin/flags        — feature flags
POST /api/admin/notifications/send — broadcast notification
PATCH /api/admin/cities/:id  — update city info
PATCH /api/catalog/:type/:id — update catalog item
```

---

## Admin Dashboard (Next.js)

**URL:** `https://metrosafar-admin-pxx5jjbiyq-el.a.run.app`  
**Auth:** Firebase + Google Account (email in custom claim `admin: true`)

### Admin Pages

| Page | Purpose |
|------|---------|
| **Dashboard** | System health, metrics, API stats, leaderboard |
| **Notifications** | Compose & send broadcasts (all/by city/by user list) |
| **Catalog** | Create/edit games, articles, rewards, quests, videos |
| **Cities** | View/edit city info, stations, content packs |
| **Flags** | Feature toggles (gated rollouts) |
| **Users** | Search users, view profiles, manage custom claims |
| **Telemetry** | Analytics, funnel analysis, user segments |
| **Audit Log** | Admin action history, API audit trail |
| **Content Packs** | Upload city content (trivia, landmarks, stamps) |
| **Redemptions** | Fulfill/cancel reward requests |

---

## Design System

### Theme
- **Colors:** Indigo primary, teal secondary, neon lime accents
- **Palette:** Light/dark mode auto-detected (system preference)
- **City Themes:** Each city has custom light/dark variants (in `cityLightThemeProvider`, `cityDarkThemeProvider`)
- **Typography:** Material 3 text styles (headline, title, body, label)
- **Spacing:** 8-point grid (s1–s10 tokens)
- **Radius:** 8px, 12px, 16px, 20px, 24px variants
- **Icons:** Material icons + Font Awesome

### Material 3 Components
- Bottom navigation (5 tabs: Home, Ride, Play, Wallet, Profile)
- Floating action buttons (Start Ride)
- Material cards + elevated surfaces
- Bottom sheets (notification details, modals)
- Badges (unread count, tier, status)

---

## State Management (Riverpod v2)

### Key Providers

| Provider | Type | Purpose |
|----------|------|---------|
| `streakProvider` | StateNotifier | Daily streak state + auto-claim |
| `questsProvider` | StateNotifier | User's daily quests |
| `walletProvider` | StateNotifier | Points balance, tier |
| `homeProvider` | StateNotifier | Aggregate home data |
| `gamesProvider` | FutureProvider | Available games catalog |
| `profileProvider` | FutureProvider | User profile |
| `notificationFeedProvider` | FutureProvider | Inbox notifications |
| `currentCityProvider` | StateNotifier | Selected city + geo |
| `featureFlagsProvider` | FutureProvider | Gated features |
| `activeCityProvider` | Selector | Currently active city |
| `commuteProvider` | StateNotifier | Trip-in-progress state |
| `unreadNotificationsProvider` | Provider | Badge count |

### Riverpod Patterns
- **Hydration:** Aggregate endpoints populate multiple providers in `HomeNotifier.fetch()`
- **Auto-invalidation:** Lifecycle observers invalidate stale data on app resume
- **Disposal:** `ConsumerStatefulWidget` cleanup prevents memory leaks
- **Async Management:** `AsyncValue.loading/error/data` for loading states

---

## Navigation (go_router)

### Route Structure
```
/onboarding          — first-time setup
/login               — authentication
/home                — main tab shell
  ├─ /ride           — trip mode
  ├─ /play           — games hub
  ├─ /wallet         — points & redemptions
  ├─ /profile        — user profile
/learn               — articles, audio, videos
/my-redemptions      — redemption history
/notifications-inbox — notification detail
/settings            — preferences
/game/:gameId        — specific game deep-link (trivia, sudoku, etc.)
/booking             — coming soon + waitlist
/friends             — social features
/referral            — referral program
/journey-planner     — live ETAs (feature-gated)
/stamps              — collected stamps
/audio               — audio stories (feature-gated)
/events              — live events (feature-gated)
```

### Deep Linking
- **FCM Payload:** `{ screen: 'game', gameId: 'trivia' }`
- **Resolution:** `NotificationService.routeFromData()` maps to app route
- **Handling:** Foreground + background tap, cold start

---

## Firebase Integration

### Cloud Firestore Structure

```
collections:
├─ metrosafar_users/
│  ├─ {userId}/
│  │  ├─ profile {}
│  │  ├─ wallet { points, tier, ... }
│  │  └─ (activity events as subcollection)
├─ app_notifications/
│  ├─ {notificationId} { title, body, screen, createdAt, ... }
├─ catalog_games/
│  ├─ {gameId} { title, description, rules, ... }
├─ catalog_rewards/
│  ├─ {rewardId} { title, points, redemptionType, ... }
├─ catalog_articles/
│  ├─ {articleId} { title, body, category, ... }
├─ catalog_quests/
│  ├─ {questId} { id, type, points, active, ... }
├─ redemptions/
│  ├─ {redemptionId} { userId, rewardId, status, code, fulfillmentType, ... }
└─ scores/ (materialized leaderboard)
   ├─ {scoreId} { userId, score, completedAt, rank, ... }
```

### Composite Indexes
- `redemptions(userId ASC, createdAt DESC)` — My Redemptions query
- `redemptions(status ASC, createdAt DESC)` — Admin redemptions list
- `scores(score DESC, completedAt ASC)` — Leaderboard query

### Firebase Auth
- **Providers:** Google OAuth, Email/Password, Anonymous (testing)
- **Custom Claims:** `{ admin: true, role: 'superadmin'|'moderator', ... }`
- **Token Lifespan:** 1 hour (auto-refresh)

### Cloud Messaging (FCM)
- **Topics:** `all_users` (broadcast), `city_<cityId>` (geo-targeted)
- **Handlers:** 
  - `onMessage` — foreground notification
  - `onMessageOpenedApp` — tap while backgrounded
  - `getInitialMessage` — tap from cold start
- **Deep-Linking:** Via `routeFromData()` screen token resolution

---

## Performance & Optimization

### Data Loading
- **Splash to Home:** ~2s (Firebase init + home data fetch)
- **Home data refresh:** Single aggregate call (no waterfall)
- **Data hydration:** Pre-loading guard prevents stale state flicker
- **Caching:** Dio HTTP cache + SharedPreferences for preferences
- **Offline:** Trip outbox queues writes for sync on reconnect

### UI/UX Optimizations
- **Loading States:** Proper spinners during async ops (home data load)
- **Pagination:** Infinite scroll on history screens (trips, redemptions, inbox)
- **Image Caching:** cached_network_image for articles, rewards
- **Animations:** Smooth page transitions, card animations
- **Lazy Loading:** Games grid, content lists loaded on demand

### Backend Performance
- **Metrics:** In-memory tracking (request count, latency, errors)
- **Rate Limiting:** Per-class limits prevent abuse
- **Query Optimization:** Firestore composite indexes on hot paths
- **Connection Pooling:** Firestore Admin SDK defaults
- **Logging:** Structured logs via pino (JSON format)

---

## Security & Authentication

### Authorization
- **Firebase Custom Claims:** Admin gate via `custom:admin = true`
- **RBAC:** Admin role + feature flags for gradual rollouts
- **Token Validation:** All endpoints verify Bearer token signature
- **Rate Limiting:** Per-IP + per-class to prevent brute force

### Data Privacy
- **PII:** Email, name stored in Firestore (encrypted at rest by Firebase)
- **Preferences:** City, language in SharedPreferences (local device)
- **Activity:** Trips, games logged to Firestore with `userId` partition key
- **Deletion:** `DELETE /api/me` marks user for anonymization

### API Security
- **HTTPS Only:** Production endpoints on Cloud Run (forced SSL)
- **CORS:** Allowed origins: admin domain only
- **Secret Management:** API keys in Cloud Run env vars (not in code)

---

## Deployment & Infrastructure

### Mobile (Flutter)
- **Debug APK:** Built locally, side-loaded for testing
- **Release AAB:** Signed with debug keystore (to-do: real signing keystore)
- **Version Bump:** Manual in `pubspec.yaml` (next: auto via CI/CD)
- **Ad Units:** Test units for development, real AdMob IDs for Play Store

### Backend (Cloud Run)
- **Service:** `metrosafar-backend-pxx5jjbiyq-el.a.run.app`
- **Build:** Cloud Build from source (`gcloud run deploy --source .`)
- **Environment:** 4 vCPU, 2 GB RAM, 10 min timeout
- **Secrets:** ADMIN_API_KEY (deprecated after bootstrap), Firebase credentials (via ADC)
- **Health:** `/api/health` endpoint returns metrics

### Admin (Cloud Run)
- **Service:** `metrosafar-admin-pxx5jjbiyq-el.a.run.app`
- **Build:** Cloud Build from Next.js standalone Docker
- **Environment:** 1 vCPU, 512 MB RAM
- **Env Vars:** 7 `NEXT_PUBLIC_*` Firebase config vars (passed at build-time)

### Database (Firestore)
- **Project:** `metrosafar-5bcff` (Firebase) + `metrosafar-20260517-223707` (GCP)
- **Datastore:** Firestore (document DB)
- **Backup:** Managed by Firebase (point-in-time recovery)
- **Indexes:** Manually created for read-heavy queries

### Optional: Redis (Memorystore)
- **Purpose:** Rate-limit store, materialized leaderboard, user cache, Socket.io adapter
- **Status:** Optional (degrades gracefully without it)
- **Future:** Provision VPC connector once caching strategy finalized

---

## Development Workflow

### Tech Stack Setup
```bash
# Flutter
flutter pub get
flutter analyze
flutter test

# Backend
npm install
node --check server.js
npm run dev

# Admin
npm install
npm run dev
```

### Local Testing
- **Device:** Android 12 emulator (RZ8N91JKS9R)
- **Backend:** `localhost:8080` or deployed service
- **Ad Units:** Google test IDs
- **Authentication:** Firebase Dev auth (test@example.com)

### CI/CD Checklist
- [ ] Code review (dart analyze, node --check)
- [ ] Unit + integration tests pass
- [ ] UI/E2E smoke test on device
- [ ] Version bump + git tag
- [ ] Build & deploy backend
- [ ] Build & deploy admin
- [ ] Build & deploy app (APK → AAB)
- [ ] Play Store submission (once all sign-off items complete)

---

## Play Store Release Checklist

### Completed ✅
- App architecture (Riverpod + go_router)
- Core features (home, trips, games, rewards, notifications)
- Multi-city support (Hyderabad, Delhi, Bangalore, Chennai)
- Firebase integration (auth, Firestore, FCM, Analytics)
- Admin dashboard (content management, flags, notifications)
- Backend API (with rate limiting, metrics)
- Material 3 UI (light/dark, responsive)
- Onboarding (language, city, permissions)
- Accessibility (labels, content descriptions)

### To-Do ⚠️
- [ ] **Real Signing Keystore** — replace debug key for production
- [ ] **Real AdMob IDs** — swap test units for real ad slots (revenue)
- [ ] **AAB Build** — Google Play requires AAB (not APK)
- [ ] **Privacy Policy** — hosted, linked in Settings + app listing
- [ ] **Data Safety Form** — declare data collection + usage
- [ ] **App Icons** — HD app icon assets (1024×1024+)
- [ ] **Screenshots** — at least 2–5 high-quality screenshots per language
- [ ] **Store Listing** — description, category, content rating
- [ ] **Regional Compliance** — GDPR (EU), local data residency if needed
- [ ] **Testing on Real Devices** — validate on Pixel 4–6, Samsung Galaxy
- [ ] **Pre-Launch Checklist** — Google's internal review (crashes, permissions)

---

## Known Limitations & Future Work

### Current Limitations
- No real booking integration (coming soon)
- Redis not yet provisioned (caching optional)
- Offline support limited (trip outbox only)
- Audio stories feature-gated (can enable via flag)
- No multi-language content (English only; UI translatable)

### Roadmap
- [ ] Ticket booking with partner integrations
- [ ] Socket.io real-time leaderboard updates
- [ ] Memorystore Redis for performance
- [ ] Audio stories in 4 regional languages
- [ ] Venue partnerships (cafes, shops) for redemptions
- [ ] Push-to-web passport feature
- [ ] Android 14+ widget integration
- [ ] Offline maps (city transit network)
- [ ] ML-based personalized recommendations

---

## Support & Contact

**Project Owner:** Krishna (pidaparthy@gmail.com)  
**Admin Access:** Firebase console + GCP Cloud Run  
**Backend Logs:** Cloud Run logs (Structured Logs, JSON format)  
**Metrics:** Admin Dashboard → Dashboard tab  

---

## Glossary

| Term | Definition |
|------|-----------|
| **Streak** | Consecutive daily app opens; calendar-day based (resets daily at 12:00 AM IST) |
| **Quest** | Daily task (ride, video, article, quiz); max 4 active per day |
| **Points** | In-game currency; redeemable for vouchers, codes, affiliate rewards |
| **Tier** | User rank (Bronze → Silver → Gold → Platinum); earned via points |
| **Redemption** | Reward request; fulfilled via code pool, instant code, or affiliate link |
| **Deep Link** | URL-based navigation; FCM uses `screen` token to route to app feature |
| **Leaderboard** | City-wide ranking by total score; materialized in Firestore |
| **Stamp** | Collectible badge earned per unique station visited |
| **Quest Type** | Activity that completes a quest (ride_started, video_watched, etc.) |
| **IST** | Indian Standard Time (UTC+5:30); used for daily rollover logic |

---

## Document Version
- **Created:** 2026-06-04
- **Last Updated:** 2026-06-04
- **App Version:** 1.0.21 (Build 22)
- **Backend:** metrosafar-backend-pxx5jjbiyq-el.a.run.app
- **Admin:** metrosafar-admin-pxx5jjbiyq-el.a.run.app
