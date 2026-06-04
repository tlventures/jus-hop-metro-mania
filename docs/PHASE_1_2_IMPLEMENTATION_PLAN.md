# Phase 1 & 2 Implementation Plan — Compliance, Security & Fraud Hardening

**Status:** Planning (not yet implemented)
**Author:** Engineering
**Date:** 2026-06-04
**App version at planning time:** 1.0.21+22
**Scope:** Pre-Play-Store blockers (Phase 1) + fraud/revenue protection (Phase 2)

---

## 0. What the code audit changed vs. the strategy document

Before committing to the strategy doc's recommendations verbatim, I audited the actual codebase. **Three of the proposed items are already partly or fully built.** This plan reflects reality, not assumptions:

| Strategy-doc item | Audit finding | Revised scope |
|---|---|---|
| Referral trip-lock (2.3) | **Already trip-gated.** `qualifyReferralForUser(clientId, 'first_trip')` fires on `ride_completed` (`server.js:1989`) and commute-session end (`server.js:2573`). Uses `metrosafar_referrals` with `pending→qualified→rewarded` states + a 10/month referrer cap. | **Narrow fix:** remove the `first_game` qualification trigger (`server.js:1608`) — that is the actual fraud hole (a fake account unlocks the referrer's 150 pts by playing one game, no physical trip). |
| AdMob banner placement (1.4) | **Already compliant.** Banner lives in a dedicated slot in `router.dart:215–232`: top `Divider`, solid `surface` background, 8px top gap, 16px bottom gap, and uses `AdRequest(nonPersonalizedAds: true)` (`ad_banner.dart:36`). | **Minor hardening only:** increase nav-bar gap, and gate the banner off for minors (see 1.1). |
| Account deletion (DPDPA) | **Exists** as `DELETE /api/account` (`server.js:1287`), rate-limited via `accountLimiter`. | Verify the delete **cascades** all subcollections; wire consent-withdrawal to the same path. |

Also confirmed:
- **No age gate** anywhere in onboarding (`onboarding_screen.dart` has 7 pages: welcome→games→learn→rewards→permissions→cityConfirm→privacyConsent).
- **No consent persistence** — `PrivacyConsentScreen.onAccept` calls a callback but writes nothing to the backend. `grep consent backend/server.js` → 0 hits.
- **No mock-location / device-integrity checks** — `safe_device`, `detect_fake_location`, `play_integrity` are **not** in `pubspec.yaml`. `Geolocator.getCurrentPosition()` is called raw in `commute_detector.dart`, `current_city_provider.dart`, `location_provider.dart`, `city_confirm_screen.dart`.
- **No per-station coordinates / distance helper** for trips. Backend only has city-level bbox resolution (`resolveCityFromCoords`, `server.js:202`). **This is a hard dependency for the velocity check (2.1)** — see Open Questions.
- Rewarded-ad points are awarded from the **client** `onUserEarnedReward` callback → `POST /api/rewards/watch-ad` (`watch_and_earn_card.dart:96`, `server.js:2099`), with a server-enforced 5/day cap (`AD_REWARD_DAILY_LIMIT`).

---

## PHASE 1 — Play Store Blockers

> These four are the only items that can get the app **rejected** or create **regulatory liability**. Ship before submission.

---

### 1.1 Age Gate + DPDPA minor containment

**Goal:** Establish a bright-line 18-year threshold during onboarding. For under-18 users, disable AdMob, Firebase Analytics, and persistent location tracking, and route them through a parental-consent flow.

#### New files
- `lib/features/onboarding/presentation/screens/age_gate_screen.dart`
- `lib/features/onboarding/presentation/screens/parental_consent_screen.dart`
- `lib/core/compliance/minor_status.dart` — single source of truth for `isMinor`

#### `minor_status.dart` (new — central gate)
```dart
import 'package:shared_preferences/shared_preferences.dart';

class MinorStatus {
  static const _kDob = 'user_dob';          // ISO yyyy-MM-dd
  static const _kIsMinor = 'user_is_minor'; // bool
  static const _kParentVerified = 'parent_consent_verified';

  /// Synchronous read cached at boot (see main.dart wiring). Defaults to the
  /// SAFE state (treat as minor → ads/analytics OFF) until proven adult.
  static bool isMinorCached = false;

  static Future<void> hydrate() async {
    final p = await SharedPreferences.getInstance();
    isMinorCached = p.getBool(_kIsMinor) ?? false;
  }

  static Future<void> setDob(DateTime dob) async {
    final p = await SharedPreferences.getInstance();
    final age = _age(dob);
    final minor = age < 18;
    await p.setString(_kDob, dob.toIso8601String().substring(0, 10));
    await p.setBool(_kIsMinor, minor);
    isMinorCached = minor;
  }

  static Future<bool> get parentVerified async =>
      (await SharedPreferences.getInstance()).getBool(_kParentVerified) ?? false;

  static int _age(DateTime dob) {
    final now = DateTime.now();
    var a = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) a--;
    return a;
  }
}
```

#### `age_gate_screen.dart` (new)
- Three `CupertinoPicker` wheels (Day / Month / Year), **no pre-selected value** (DPDPA Rule 10 — neutral, non-pre-checked).
- No "Skip" button; `PopScope(canPop: false)`.
- On Continue → `MinorStatus.setDob(dob)`:
  - age ≥ 18 → `onNext()` (continue normal onboarding)
  - age < 18 → push `ParentalConsentScreen`

#### `parental_consent_screen.dart` (new)
- Explainer copy: "Because you're under 18, a parent or guardian must approve. Ads and analytics stay off for your account."
- Collect parent email → `POST /api/auth/parental-consent-request { childUid, parentEmail }`.
- Show "Verification link sent" state. Allow the child to **proceed into a restricted app** (ads/analytics/location-tracking off) while consent is pending — do **not** hard-block, to avoid abandonment; restrictions stay until verification arrives.

#### Wire into onboarding (`onboarding_screen.dart`)
Insert Age Gate as **Page 1** (right after Welcome). Renumber:
```
0 Welcome → 1 AgeGate(NEW) → 2 Games → 3 Learn → 4 Rewards → 5 Permissions → 6 CityConfirm → 7 PrivacyConsent
```
Update `onboarding_provider.dart`: `_totalSteps = 6` → `7`, and fix the page-index comment block.

For minors, **skip the Permissions location prompt** page (or present it as "approximate city only") and pass `requestLocation: !MinorStatus.isMinorCached` into `PermissionsScreen`.

#### Gate AdMob (`admob_config.dart`)
Convert `adsEnabled` from a `const` to a runtime getter:
```dart
static bool get adsEnabled {
  if (MinorStatus.isMinorCached) return false;          // DPDPA §9 — no ads to minors
  return const bool.fromEnvironment('METROSAFAR_ADS_ENABLED', defaultValue: true);
}
```
Both `MetroSafarAdBanner` (`ad_banner.dart:25`) and `WatchAndEarnCard` (`watch_and_earn_card.dart:30,118`) already short-circuit on `AdMobConfig.adsEnabled`, so this one change disables **both** ad surfaces for minors.

#### Gate Analytics + Location (`main.dart`)
- In `_boot()` call `await MinorStatus.hydrate();` **before** `runApp` swaps in the real app, so `isMinorCached` is correct on first frame.
- In `_wireAuthBoundServices()`: only call `AnalyticsService.setUserId(uid)` when `!MinorStatus.isMinorCached`. Also call `FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!isMinor)` and `FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(...)` (keep crash reporting on; disable Analytics behavioral collection).
- `commute_detector.dart` / `commute_provider.dart`: if `MinorStatus.isMinorCached`, do **not** start the background GPS polling loop (no persistent location tracking for minors).

#### Backend (`server.js`)
- Extend the user profile write (`POST /api/auth/profile` / wherever `getUserState` persists) to accept and store `isMinor: bool`, `dobYear: int` (store **year only**, data-minimisation).
- New `POST /api/auth/parental-consent-request` → write `metrosafar_parental_consents/{childUid}`: `{ parentEmail, status:'pending', token, createdAt }`, email the parent a verification link (reuse existing email transport, or stub for v1 and log).
- New `GET /api/auth/parental-consent/verify?token=` → set `status:'verified'`, flip child's `isMinor` restrictions metadata. (App polls `/api/me` or re-reads on next launch.)
- Guard server-side too (defense in depth): in `POST /api/rewards/watch-ad`, if `state.isMinor === true` return `403 { reason:'minor_no_ads' }`. Skip analytics/event-stream writes for minors.

**Effort:** ~3 days. **Verification:** onboard with DOB 2015 → no ads anywhere, Analytics DebugView shows no events; DOB 1990 → ads + analytics present.

---

### 1.2 DPDPA consent audit trail (immutable)

**Goal:** Every consent decision is recorded with a cryptographic timestamp as an auditable trail (DPDPA Rule — itemized, standalone, logged).

#### Backend (`server.js`)
```js
// POST /api/me/consent  (auth required, accountLimiter)
// Body: { analyticsConsent, marketingConsent, appVersion, platform }
// Append-only — never overwrite/delete:
app.post('/api/me/consent', accountLimiter, async (req, res, next) => {
  try {
    const { analyticsConsent, marketingConsent, appVersion, platform } = req.body;
    const entry = {
      analyticsConsent: !!analyticsConsent,
      marketingConsent: !!marketingConsent,
      appVersion: String(appVersion || ''),
      platform: String(platform || ''),
      ip: req.ip,
      ts: new Date().toISOString(),
    };
    await firestore
      .collection('metrosafar_users').doc(req.clientId)
      .collection('consent_log').add(entry);     // auto-ID, append-only
    // Also stamp latest snapshot on the user doc for quick reads:
    await firestore.collection('metrosafar_users').doc(req.clientId)
      .set({ consent: { ...entry } }, { merge: true });
    res.json({ ok: true });
  } catch (e) { next(e); }
});
```
- **Retention:** the `consent_log` subcollection is **excluded** from the `DELETE /api/account` cascade IF legal requires retaining proof-of-consent post-deletion; otherwise anonymize `ip` on deletion. **Decision needed** (see Open Questions).

#### Flutter
- `backend_service.dart`: add
  ```dart
  Future<Map<String, dynamic>> recordConsent(Map<String, dynamic> body) =>
      _sendJson('POST', '/api/me/consent', cacheKey: 'cache_consent', body: body);
  ```
- `privacy_consent_screen.dart`: on **Accept** (and on **Decline**, recording the negative choice), call `recordConsent({...})` with `package_info_plus` version + platform **before** invoking `widget.onAccept()`. Make the button briefly show a spinner; don't block forever on network failure (fire-and-log).

#### Fix broken legal URLs
`privacy_consent_screen.dart` `_PrivacyLink` points to `https://metrosafar.app/privacy` and `/terms` which **do not exist**. Either host real pages or point to a committed placeholder. **A live, reachable Privacy Policy URL is a hard Play Store requirement** (and is also entered in the Play Console listing + Data Safety form).

**Effort:** ~1 day. **Verification:** accept consent → `consent_log` doc appears in Firestore with correct timestamp/version; both legal links open a real page.

---

### 1.3 QR payload schema validation + cryptographic token

**Goal:** Defeat "quishing" — the scanner must reject any QR that isn't an official, unexpired MetroSafar station token, and the backend must cryptographically validate it before awarding.

#### Current state
`ticket_verification_sheet.dart` (`_handleDetect`, ~line 30–50) accepts **any** non-empty `barcode.rawValue` and stuffs it into the text field → sent to backend unvalidated. No schema, no signature.

#### Flutter (`ticket_verification_sheet.dart`)
In the barcode handler, restrict to the MetroSafar URI scheme and extract the token:
```dart
const _kPrefix = 'metrosafar://verify/';
if (!rawValue.startsWith(_kPrefix)) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('Invalid QR — use an official MetroSafar station code.')));
  _handledScan = false;           // allow re-scan
  return;
}
final token = rawValue.substring(_kPrefix.length).trim();
_controller.text = token;
setState(() { _method = 'qr'; _showScanner = false; });
```
> Note `mobile_scanner` only *decodes* — it does not auto-open URLs, so there's no redirect risk in-app. The risk is the **backend awarding on a forged payload**, which the HMAC below closes.

#### Backend — new `backend/lib/qr-tokens.js`
```js
const crypto = require('crypto');
const SECRET = process.env.QR_HMAC_SECRET;   // add to Cloud Run env

function _sig(stationId, bucket) {
  return crypto.createHmac('sha256', SECRET)
    .update(`${stationId}:${bucket}`).digest('hex').slice(0, 16);
}
// Printed/admin-generated token, rotates hourly:
function generateStationToken(stationId) {
  const bucket = Math.floor(Date.now() / 3600000);
  return `${stationId}:${bucket}:${_sig(stationId, bucket)}`;
}
// Validation accepts current + previous hour (clock grace):
function validateStationToken(token) {
  const [stationId, bucketStr, sig] = String(token).split(':');
  const bucket = Number(bucketStr);
  const now = Math.floor(Date.now() / 3600000);
  if (![now, now - 1].includes(bucket)) return { valid: false, reason: 'expired' };
  if (_sig(stationId, bucket) !== sig)  return { valid: false, reason: 'bad_sig' };
  return { valid: true, stationId };
}
module.exports = { generateStationToken, validateStationToken };
```
- Wire `validateStationToken()` into the ride-verification path that currently consumes the scanned value. On `valid:false`, return `400 { reason }` and award nothing.
- Add `QR_HMAC_SECRET` to Cloud Run env (`gcloud run services update ... --set-env-vars QR_HMAC_SECRET=...`). Generate with `openssl rand -hex 32`.
- **Admin:** add a "Generate station QR" action (admin `cities/[stationId]` page) that renders `metrosafar://verify/<generateStationToken(stationId)>` to a printable QR. Because tokens rotate hourly, **physical printed codes must encode the *stationId* and have the app fetch a fresh token** — OR accept a longer rotation (daily) for printed media. **Decision needed** (see Open Questions): hourly rotation suits *dynamic displays* (PSD screens), daily/static suits *printed stickers*.

**Effort:** ~1–1.5 days (excluding admin print UI). **Verification:** scan a random non-MetroSafar QR → rejected client-side; POST a forged token → `400 bad_sig`; valid generated token → award succeeds once.

---

### 1.4 AdMob banner placement hardening (minor)

**Goal:** Already largely compliant — finish the hardening.

#### Current (`router.dart:215–232`) — already good
Dedicated slot, top `Divider`, solid `surface` bg, 8px above, 16px below, `nonPersonalizedAds: true`.

#### Changes
- Increase the gap between the ad and the `NavigationBar` from 16 → **24px** and add an explicit `SizedBox(height: 8)` *below* the `AdWidget` inside the banner so the touch-target separation is unambiguous.
- Confirm no banner renders on the **Ride** trip-control screen directly under interactive controls — since the banner is in the global `ShellRoute`, it appears on all 5 tabs. Verify on the Ride tab that the docked trip controls keep ≥ 24px clearance. If tight, suppress the banner on `/ride` while a trip is active.
- Minors: covered automatically by the `adsEnabled` getter change in 1.1.
- **AdMob console:** register all QA/dev device IDs as **test devices** so live impressions are never counted during testing (prevents invalid-traffic strikes).

**Effort:** ~2 hours.

---

## PHASE 2 — Fraud & Revenue Protection

> Ship within ~2 weeks of launch. The existing server-side daily caps (`DAILY_POINT_CAP`, `AD_REWARD_DAILY_LIMIT=5`) are a meaningful stopgap until these land.

---

### 2.1 GPS mock-location + device-integrity detection

**Goal:** Stop spoofed trips from earning points.

#### Dependencies (add to `pubspec.yaml`)
```yaml
safe_device: ^1.1.1   # isMockLocation, isRealDevice, isJailBroken
```
(Optionally `google_play_integrity` later for server-verified attestation — heavier; defer to a follow-up.)

#### Flutter (`lib/core/commute/commute_detector.dart`)
```dart
import 'package:safe_device/safe_device.dart';

Future<bool> _deviceTrustworthy() async {
  try {
    final mock = await SafeDevice.isMockLocation;
    final real = await SafeDevice.isRealDevice;
    return real && !mock;             // fail-CLOSED for awards
  } catch (_) {
    return true;                      // fail-OPEN on plugin error (don't punish)
  }
}
```
Before recording a `ride_completed`/award event, skip silently if `!await _deviceTrustworthy()` (log, no user-facing accusation). Apply the same guard before `POST /api/activity-events` with `type: 'ride_completed'`.

#### Backend velocity check (`server.js`, `ride_completed` branch ~line 1988 and commute-end ~2551)
**Blocked on a data dependency** — there is currently no per-station coordinate table or distance helper. Two options:
- **(a) Defer** until stations carry `{lat,lng}` (most are in `content/<city>/stations.json` already — verify and add a haversine helper `getStationDistanceKm(cityId, a, b)`).
- **(b) Ship now without distance:** flag only on **impossible cadence** (e.g., > N `ride_completed` events within M minutes per user) — cheap, no coordinates needed.

Recommended: ship **(b)** immediately, add **(a)** when station coords are confirmed:
```js
const MAX_METRO_SPEED_KMH = 90;
if (haveCoords) {
  const km = getStationDistanceKm(session.cityId, startId, endId);
  const speed = (km / durationMin) * 60;
  if (speed > MAX_METRO_SPEED_KMH) await flagTripForReview(tripId, 'velocity_anomaly');
}
```
Flagged trips still complete (don't block honest users on edge cases) but land in a `metrosafar_flagged_trips` collection for admin review / clawback.

**Effort:** ~1 day (b); +1 day (a) once coords confirmed. **Verification:** enable Android "mock location" app → trip earns nothing; normal device → unaffected.

---

### 2.2 AdMob Server-Side Verification (SSV)

**Goal:** Award rewarded-ad points only after **Google's servers** confirm a completed view, not from a client callback that can be replayed.

#### Current
`watch_and_earn_card.dart:96` calls `BackendService().claimAdReward()` from inside `onUserEarnedReward` → `POST /api/rewards/watch-ad`. A scripted client can call that endpoint directly (capped at 5/day, but still free points).

#### Step 1 — AdMob console
Rewarded unit → **Server-side verification** → callback URL:
`https://metrosafar-backend-pxx5jjbiyq-el.a.run.app/api/rewards/admob-ssv`

#### Step 2 — Backend new endpoint (`server.js`)
AdMob calls this via **GET** with signed query params (`signature`, `key_id`, `transaction_id`, `user_id`, `reward_amount`, `timestamp`, …):
```js
const { verifyAdMobSSV } = require('./lib/admob-ssv'); // fetches Google public keys, verifies ECDSA

app.get('/api/rewards/admob-ssv', async (req, res) => {
  try {
    const ok = await verifyAdMobSSV(req.query);              // signature + key_id
    if (!ok) return res.status(400).send('INVALID_SIGNATURE');
    const { transaction_id, user_id, reward_amount } = req.query;

    const txnRef = firestore.collection('ssv_transactions').doc(transaction_id);
    if ((await txnRef.get()).exists) return res.status(200).send('OK'); // idempotent

    await awardAdPointsServerSide(user_id, Number(reward_amount)); // reuse watch-ad award logic + 5/day cap
    await txnRef.set({ userId: user_id, amount: Number(reward_amount), ts: new Date().toISOString() });
    res.status(200).send('OK');
  } catch (e) { logger.error(e, 'SSV failed'); res.status(500).send('ERROR'); }
});
```
- Refactor the existing `/api/rewards/watch-ad` award body into a shared `awardAdPointsServerSide(uid, amount)` so both paths share the daily-cap + points logic.
- Pass `custom_data` (the Firebase uid) from the client via `RewardedAd` `setServerSideVerificationOptions(ServerSideVerificationOptions(userId: uid))` so AdMob echoes it back. Update `watch_and_earn_card.dart` to set this before `ad.show(...)`.

#### Step 3 — Flutter
`onUserEarnedReward` → **stop calling the backend**. Instead show "Points on the way!" snackbar and `ref.invalidate(walletProvider)` after a short delay (SSV lands async, usually < 2s). Keep `/api/rewards/watch-ad` temporarily as a fallback behind a flag, then remove once SSV is verified in prod.

**Effort:** ~3 days (signature verification + key caching is the bulk). **Verification:** complete a test rewarded ad → SSV hit in Cloud Run logs → points credited; direct `POST /api/rewards/watch-ad` no longer the source of truth.

---

### 2.3 Referral fraud fix (narrow — already trip-gated)

**Goal:** Close the one real hole: `first_game` qualification.

#### Change (`server.js:1608`)
In the game-complete handler, **remove** the `qualifyReferralForUser(req.clientId, 'first_game')` call (and its `response.referral` assignment). Leave the `first_trip` triggers at `1989` and `2573` intact. Result: a referrer's 150 pts release **only** after the referee completes a verified physical trip.

Optional hardening: gate the trip qualification behind the 2.1 device-trust check so a spoofed trip can't qualify a referral either.

**Effort:** ~1 hour + regression test on the referral flow. **Verification:** new account applies a code, plays a game only → referrer **not** rewarded; completes a ride → referrer rewarded once.

---

### 2.4 Leaderboard rank via count aggregation (Firestore scalability)

**Goal:** Replace the O(500)-doc-read rank scan with an O(1) aggregation query.

#### Current (`server.js`, `getTriviaRank`, ~line 788)
```js
const snap = await scoresRef.orderBy('score','desc').orderBy('completedAt','asc').limit(500).get();
```
Reads up to 500 docs **every time** anyone checks rank → cost + latency that grows with users.

#### Change
Keep the small top-N read for the displayed leaderboard, but compute the caller's rank with `count()`:
```js
const topSnap = await scoresRef.orderBy('score','desc').limit(limit).get();
const me = await scoresRef.doc(clientId).get();
let rank = null;
if (me.exists) {
  const c = await scoresRef.where('score','>', me.data().score).count().get();
  rank = c.data().count + 1;            // players above me + 1
}
```
- Ties: callers with equal score share the "players strictly above" rank — acceptable for a trivia board; if exact tie-breaking matters, add a secondary `.where('score','==',s).where('completedAt','<',myTs)` count.
- Requires the existing `scores(score DESC, completedAt ASC)` index (already created this session) plus a single-field `score` index (auto).

**Effort:** ~2 hours. **Verification:** rank matches the old method for a seeded board; Firestore "reads" for a rank call drop from ~500 to ~`limit`+1.

---

## 3. Sequencing & dependencies

```
Phase 1 (serial, before submission):
  1.1 Age Gate ──► (unblocks minor-gating used by 1.4)
  1.2 Consent trail + live Privacy URL  (independent)
  1.3 QR HMAC  (needs QR_HMAC_SECRET env + admin print decision)
  1.4 Banner hardening  (after 1.1 for minor gate)

Phase 2 (can parallelize after Phase 1):
  2.3 Referral fix      ← 1 hour, do first (highest value/effort)
  2.4 Leaderboard count ← 2 hours
  2.1 Mock-location     ← needs `safe_device`; backend velocity blocked on station coords
  2.2 AdMob SSV         ← needs AdMob console config + real rewarded unit ID
```

**Recommended order:** 2.3 → 2.4 → 1.4 → 1.2 → 1.3 → 1.1 → 2.1 → 2.2 (cheap/high-value first, heaviest last).

---

## 4. Open questions / decisions needed

1. **Parental consent verification method.** Email-link is the cheapest v1. Strategy doc suggests DigiLocker/Aadhaar OTP — heavier, needs a vendor (e.g., IDfy). Start with email-link, treat the account as restricted until verified?
2. **QR rotation cadence.** Hourly suits dynamic PSD screens; printed stickers need static/daily. Which station media are we using at launch?
3. **Consent log on deletion.** Retain `consent_log` (with `ip` anonymized) as legal proof after `DELETE /api/account`, or purge entirely? (DPDPA leans toward retaining proof-of-consent.)
4. **Station coordinates** for the velocity check (2.1a) — confirm `content/<city>/stations.json` carries `lat/lng` for all stations; if not, ship 2.1b (cadence-only) first.
5. **DPO contact** — DPDPA requires a named Data Protection Officer + grievance channel published in Settings + website. Who, and what email/address?
6. **Real AdMob rewarded unit ID** — SSV requires the production unit; currently the Google test unit (`admob_config.dart:18`).

---

## 5. Definition of done (Phase 1 — submission gate)

- [ ] Under-18 onboarding path verified: no AdMob (banner + rewarded), no Analytics events, no persistent GPS.
- [ ] Adult path unaffected (ads + analytics present).
- [ ] `consent_log` entry written on accept/decline with version + timestamp.
- [ ] Privacy Policy + Terms URLs resolve to live pages (also entered in Play Console + Data Safety form).
- [ ] Forged/random QR rejected client-side and server-side; valid token awards once.
- [ ] Banner ≥ 24px from nav bar; QA devices whitelisted in AdMob console.
- [ ] `dart analyze` + `node --check server.js` clean; on-device smoke test on RZ8N91JKS9R.
