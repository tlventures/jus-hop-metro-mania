# MetroSafar — Session History & Change Log

**Period:** late May → 2 June 2026
**App version at end of session:** `1.0.5+6`
**Maintainer:** pidaparthy@gmail.com

This document records every significant action taken so there is a durable history of what changed, why, and what remains. Newest work is at the top of each section.

---

## 0. TL;DR — current state

- **Mobile app:** `1.0.5+6`, debug builds installed on Samsung **SM-F415F** (Android 12). Source under git.
- **Backend:** Express/Node on Cloud Run, **redeployed with all this session's changes** → project **`metrosafar-20260517-223707`** (billing ON), service `metrosafar-backend`, revision `00010-cmc`.
- **Admin console:** Next.js on Cloud Run, **live** at **https://metrosafar-admin-pxx5jjbiyq-el.a.run.app** (scales 0→3).
- **Auth:** Firebase project `metrosafar-5bcff`. `pidaparthy@gmail.com` granted **superadmin**.
- **Repo:** now under git (was not at session start). `admin/` is a nested git repo / submodule.

---

## 1. Version history (`scripts/bump_version.sh`)

A bump script was added; patch (y in `1.x.y`) increments on every change unless a major/minor is specified.

| Version | What shipped |
|---|---|
| `1.0.0+1` | Starting point |
| `1.0.1+2` | Version-bump script added; `google_mobile_ads ^8 → ^7` (fixed pub resolution on Flutter 3.35) |
| `1.0.2+3` | Launch indicator (animated splash), responsive onboarding/login, consistent brand logo |
| `1.0.3+4` | Android 12 OS-level animated splash spinner |
| `1.0.4+5` | Rate-limiter split, daily-cap surfacing, server-truth points, redemption admin queue |
| `1.0.5+6` | Instant code-pool fulfillment + affiliate links + "My Redemptions" screen |

---

## 2. Backend changes (`backend/server.js`, `backend/phase56.js`, `backend/lib/*`)

### Live catalog migration (out of `staticData` → Firestore)
- Added in-memory `catalog` cache for rewards/games/articles/surveys/quests/videos, seeded from `staticData` fallback, loaded from Firestore at startup, kept live via **`onSnapshot` listeners** (multi-instance safe).
- Refactored all read paths (`/api/home`, `/api/games`, `/api/rewards`, articles, surveys, quests) to read from `catalog.*`.
- **Generic CRUD factory** mounts list/get/create/update/patch/soft-delete for all 6 catalog types under `/api/admin/catalog/:type`, with zod schemas + audit logging.
- `POST /api/admin/catalog/reload`, `GET /api/admin/catalog` (overview).
- Scripts: `scripts/seed-catalog.js` (db.json → Firestore), `scripts/set-admin-role.js` (bootstrap claims).

### Performance (B1–B4)
- **B1 Home aggregate:** `getHomePayload` now returns profile + streak + quests + wallet in ONE user-doc read; `buildQuestsForState` shared helper. (Also fixed a silent bug where `streak` was never in `/api/home`.)
- **B2 Redis:** `lib/redis.js` (singleton + pub/sub clients, graceful no-op without `REDIS_HOST`). `getUserState` cached 5s; invalidated on `saveUserState`/`claimTransaction`. Rate limiters use Redis store. socket.io uses `@socket.io/redis-adapter`.
- **B3 Materialized leaderboard:** `lib/leaderboard.js` — 30s background refresher writes one summary doc instead of 500-doc scan per request; per-user rank via Firestore `count()` + Redis cache.
- **B4 Static catalog + CDN:** public `GET /api/catalog/:type` (Cache-Control 60/300s) + `GET /api/me/catalog-state` overlay.

### Usage fixes
- **Rate limiters split** from one shared 10/min limiter (across 16 endpoints) into per-class limiters: game 60, content 40, trip 30, social 20, redeem 12, account 5 — each with its own store key.
- Game completion now **auto-completes the `play_game` quest server-side** (1 call instead of 2–3 per round).
- Daily-cap surfaced (trip flow message); `WalletState` carries `dailyCapReached`.
- Server-truth points: `applyEarnResult` trusts server `totalPoints`.
- 5xx error handler no longer leaks internal `detail`.

### Reward redemption system
- Redeem fixed for **stock** + **perUserLimit** (repeatable rewards); atomic stock decrement.
- **Redemption records** persisted to `redemptions` collection (status pending/fulfilled/cancelled).
- **Fulfillment types:** `manual` (admin queue), `instant_code` (auto-assign from per-reward **code pool** — `catalog_rewards/{id}/codes`), `affiliate_link` (deliver URL). All resolved atomically in the redeem transaction.
- Admin: `GET/PATCH /api/admin/redemptions`, `POST/GET /api/admin/catalog/rewards/:id/codes` (bulk upload + counts).
- User: `GET /api/me/redemptions` (code exposed only when fulfilled).
- **FCM push** to the user when a manual redemption is marked fulfilled.

### CO₂ fix
- Formula corrected to `points * 0.05` (was `18 + points * 0.19`); `treesEquivalent` floor removed.

### Deploy-time fixes (2 June)
- `buildLimiter` now uses `ipKeyGenerator()` for anonymous fallback — `express-rate-limit` v7 throws on raw `req.ip` for IPv6, which was **crashing new Cloud Run revisions at startup**.
- Global `/api` auth gate recognises `ADMIN_API_KEY` so `requireAdmin`'s key fallback is reachable (bootstrap path).
- `/api/admin/rbac/set-role` accepts `email` (resolves uid server-side).

---

## 3. Mobile app changes (`lib/**`, `android/**`)

- **Launch experience:** `main.dart` runs immediately via `BootstrapApp`; animated `SplashScreen` (rotating ring + pulsing logo) shown during init; edge-to-edge.
- **Android 12 splash:** OS-level animated spinner (`splash_spinner.xml`, `values-v31/styles.xml`, `core-splashscreen`, `MainActivity.installSplashScreen`).
- **Responsive UI:** welcome + login screens centered/max-width for phones/foldables/tablets; responsive headline; branded backgrounds (no white band).
- **Consistent branding:** `MetroSafarLogo` widget (renders the real launcher asset) replaces the lime square + 🚇 emoji circle.
- **Home aggregate client:** `home_provider.dart` fetches once and hydrates streak/quests/wallet (was 3–5 calls).
- **Redemption client:** `BackendService.getMyRedemptions()`, **My Redemptions screen** (`/my-redemptions`), copyable codes, affiliate "Open" button; 429 handling (`BackendRateLimitException`).
- `google_mobile_ads` pinned `^7.0.0`.

---

## 4. Admin console (`admin/` — Next.js)

- Pre-existing console (dashboard, users, cities, content packs, flags, telemetry, notifications, audit) **extended** with:
  - **Catalog CRUD** pages (`/catalog`, `/catalog/[type]`) for all 6 types — create/edit/delete/reorder/toggle.
  - **Redemptions** page (`/redemptions`) — status tabs, fulfill dialog (voucher code + note), counts.
  - **Reward code-pool manager** (🎟 dialog) — upload codes, availability counts; `fulfillmentType`/`affiliateUrl` fields on the reward form.
  - Sidebar reorganised (Overview / Catalog / Operations / System).
- `next.config.ts` → `output: 'standalone'` (required for the Cloud Run Docker build).
- `cloudbuild.yaml` → `--allow-unauthenticated` (browser access; real gating is Firebase + RBAC).

---

## 5. Infrastructure & GCP actions (2 June 2026)

All on host project **`metrosafar-20260517-223707`** (#1009975908945, billing ON) unless noted.

1. **Backend redeployed** from source (`gcloud run deploy metrosafar-backend --source .`) → revision `00010-cmc`. Now serves all this session's code. URL: `https://metrosafar-backend-pxx5jjbiyq-el.a.run.app`.
   - Env added: `ADMIN_API_KEY` (bootstrap), `ADMIN_ORIGINS` (admin URL for CORS). Existing env preserved (`FIREBASE_PROJECT_ID=metrosafar-5bcff`, etc.).
2. **Artifact Registry** repo `metrosafar` created (asia-south1) — was missing, blocked first admin build.
3. **Admin UI built & deployed** (`gcloud builds submit cloudbuild.yaml`) → Cloud Run service `metrosafar-admin`, min 0 / max 3, 512Mi/1cpu. URL: **https://metrosafar-admin-pxx5jjbiyq-el.a.run.app**.
   - `allUsers` granted `roles/run.invoker` (the `--allow-unauthenticated` flag didn't apply on first deploy → fixed via explicit IAM binding).
4. **Identity Toolkit API enabled** on `metrosafar-20260517-223707` (needed for `getUserByEmail`/`setCustomUserClaims`).
5. **IAM:** backend runtime SA `1009975908945-compute@developer.gserviceaccount.com` granted `roles/firebaseauth.admin` on **`metrosafar-5bcff`** (so it can set custom claims cross-project).
6. **Superadmin role** set for `pidaparthy@gmail.com` (uid `mdiaKcSA7QMOEZaMeHE8tXpddYm2`) on metrosafar-5bcff via the rbac endpoint + API key.
7. **Firebase authorized domains** (metrosafar-5bcff) — added `metrosafar-admin-pxx5jjbiyq-el.a.run.app` and `metrosafar-admin-1009975908945.asia-south1.run.app` (so Google sign-in popup works).

### Project topology discovered
- `metrosafar-5bcff` — Firebase Auth project (users live here). **Billing OFF.**
- `metrosafar-20260517-223707` (#1009975908945) — billing ON, hosts backend + admin.
- `metrosafar-tlv-20260520` — local gcloud ADC quota project (constrained; couldn't change).
- The app's older backend URL `...-682046427985...` maps to a project not visible in this account.

---

## 6. Security notes / decisions

- **`ADMIN_API_KEY`** is currently set on the backend (value saved at `/tmp/metrosafar_admin_key.txt`). It grants full superadmin to anyone holding it. **Recommended: remove now that the Google account is superadmin** — `gcloud run services update metrosafar-backend --region asia-south1 --project metrosafar-20260517-223707 --remove-env-vars ADMIN_API_KEY`.
- Admin Cloud Run edge is public (`allUsers` invoker) **by design** — gating is Firebase login + RBAC + backend `requireAdmin`. This keeps idle cost ~$0 (scale-to-zero) vs. IAP (needs a 24/7 load balancer).
- ID tokens are issued by metrosafar-5bcff; the backend verifies them (works because `FIREBASE_PROJECT_ID=metrosafar-5bcff`).

---

## 7. Cost expectation (admin + backend, ~10k DAU)
≈ **$120–165/month**; idle floor ≈ $50 (Redis + min instances). Admin alone scales to zero ≈ $0 idle. See earlier cost breakdown in chat.

---

## 7a. 🚀 Play Store release checklist (what's left before launch)

Status legend: 🔴 blocker (store rejects or app broken) · 🟠 required for store · 🟡 strongly recommended.

### A. Signing & build
- [ ] 🔴 **Generate an upload keystore** and create `android/key.properties`. Builds are currently **debug-signed** (`build.gradle.kts` falls back to the debug config), which Play **rejects**.
- [ ] 🔴 **Build an AAB**, not an APK: `flutter build appbundle --release`. (Debug APKs installed on the test phone are *not* shippable.)
- [ ] 🟡 Verify `targetSdk ≥ 35` (resolved via `flutter.targetSdkVersion` on Flutter 3.35 — confirm).

### B. Ads (AdMob)
- [ ] 🔴 Replace **Google TEST IDs** with real ones, or disable ads for launch. `adsEnabled` defaults **true**; app + unit IDs are Google's public test IDs → policy violation + zero revenue if shipped as-is.

### C. Backend the shipped app talks to ✅ RESOLVED (3 Jun, v1.0.7+8)
- [x] **Repointed `api_config.dart`** → `https://metrosafar-backend-pxx5jjbiyq-el.a.run.app` (the updated backend in `metrosafar-20260517-223707`). WebSocket (`realtime_service.dart`) follows automatically. App now uses live catalog + redemptions + code pools.
- [x] Catalog seeded + indexes created on the pxx5jjbiyq backend (done 3 Jun).
- ⚠️ **Data note:** the new backend has its **own Firestore** (separate from the old 682 backend), so existing test-user state (points/progress) does **not** carry over — users start fresh on first call. Fine for testing; if the 682 backend held real user data, plan a migration before public launch.
- [ ] 🟡 Provision Memorystore (Redis) for the rate-limit store / cache / socket.io adapter (degrades gracefully without it).

### D. Play Console submission requirements
- [ ] 🟠 **Hosted privacy-policy URL** (public HTTPS). The in-app legal sheet does **not** satisfy the Data Safety form.
- [ ] 🟠 **Data Safety form** — declare collection of location, camera, FCM token, account data.
- [ ] 🟠 **Foreground-service declaration** (media playback — used by audio stories).
- [ ] 🟠 **Content rating** questionnaire.
- [ ] 🟠 **Store listing assets** — title, short/full description, **phone + tablet/foldable screenshots**, feature graphic, 512px icon.
- [ ] 🟠 **Prominent disclosure** in-app for location + camera permissions.
- [ ] 🟡 Roll out via **Internal testing → Closed → Production** tracks.

### E. Rewards actually deliver value
- [ ] 🟠 Load **real coupon supply**: voucher **code pools** (admin 🎟 uploader), **affiliate links**, or partner deals — otherwise redemptions hand out nothing.
- [ ] 🟡 Confirm the **fulfillment loop end-to-end**: FCM token storage + the "redemption fulfilled" push + My Redemptions code display.

### F. Code hygiene (non-blocking but do before launch)
- [ ] 🟡 Remove unused `google_maps_flutter` dependency (declared, never used → bloats the AAB).
- [ ] 🟡 Delete dead code: `lib/domain/` (0 imports), `lib/providers/` (0 imports), `lib/utils/theme.dart` (0 imports).
- [ ] 🟡 Add money-path tests (redeem balance/limit/daily-cap) — currently only 3 test files.

---

## 8. Pending / next steps

### ✅ Completed 3 June 2026
- [x] **Fixed admin page crashes** (Telemetry/Flags/Audit/Cities showed "This page couldn't load"). Cause: backend wraps list responses in envelopes (`{cities|flags|users|events|entries}`) but the admin API client returned them as bare arrays → pages did `.map()` on an object → render crash. Fix: unwrap envelopes in `admin/lib/api.ts`. Redeployed → `metrosafar-admin-00003-t7t`.
- [x] **Fixed "Failed to send notification"** — backend SA lacked FCM permission on metrosafar-5bcff. Granted `roles/firebase.admin` (includes `cloudmessaging.messages.create`) + ensured FCM API enabled. (Note: "All Users" sends to FCM topic `all_users`; delivery requires the app to subscribe to that topic.)
- [x] **Fixed leaderboard log spam** — created composite index `scores(score DESC, completedAt ASC)` for the materializer query.
- [x] **Fixed admin "not loading".** Root cause: the admin `Dockerfile` didn't declare the `NEXT_PUBLIC_*` build args, so `cloudbuild.yaml`'s `--build-arg` values never reached `next build` → Firebase config compiled to `undefined` → Firebase Auth couldn't init → blank app (shell returned 200 but JS bundle had no config). Fix: added `ARG`+`ENV` for all 7 vars in the Dockerfile, rebuilt → revision `metrosafar-admin-00002-sfp`. Verified `metrosafar-5bcff` config is now present in the served JS bundle.
- [x] **Removed `ADMIN_API_KEY`** from the backend env (revision `00011-sbf`). Verified the key is now rejected. Admin access is solely Firebase + RBAC. Temp key file shredded.
- [x] **Catalog seeded** to `metrosafar-20260517-223707` Firestore — 38 docs with exact db.json IDs, via `scripts/seed-via-rest.js` (Firestore REST + gcloud owner token; local Admin-SDK ADC lacked Firestore write perms). Backend `onSnapshot` picked it up; `/api/catalog/rewards` confirms 16 rewards live.
- [x] **Firestore composite indexes created** (async build) and recorded in `firestore.indexes.json`:
  - `redemptions(userId ASC, createdAt DESC)` — My Redemptions query
  - `redemptions(status ASC, createdAt DESC)` — admin redemptions list

### Still pending
- [ ] **Provision Memorystore (Redis)** + VPC connector to activate the rate-limit store, user cache, and socket.io adapter (all degrade gracefully without it).
- [ ] **Close the redemption loop fully:** confirm FCM token storage + the My Redemptions push end-to-end.
- [ ] **Play Store release prep** (separate track): real signing keystore (still debug-signed), real AdMob IDs (currently Google test IDs), Data Safety form, hosted privacy policy. See earlier launch-readiness assessment.
- [ ] Remove unused `google_maps_flutter` dependency; delete dead `lib/domain/`, `lib/providers/`, `lib/utils/theme.dart`.

---

## 9. Key URLs & identifiers

| Item | Value |
|---|---|
| Admin console | https://metrosafar-admin-pxx5jjbiyq-el.a.run.app |
| Backend (deployed this session) | https://metrosafar-backend-pxx5jjbiyq-el.a.run.app |
| Backend (app's existing prod) | https://metrosafar-backend-682046427985.asia-south1.run.app |
| Host project (admin + backend) | metrosafar-20260517-223707 (#1009975908945) |
| Firebase / auth project | metrosafar-5bcff |
| Superadmin user | pidaparthy@gmail.com (uid mdiaKcSA7QMOEZaMeHE8tXpddYm2) |
| Test device | Samsung SM-F415F, Android 12 (RZ8N91JKS9R) |
