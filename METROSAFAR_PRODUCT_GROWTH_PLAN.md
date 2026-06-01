# MetroSafar Product Growth Plan and 6-Month Vision

Created: May 18, 2026  
Planning horizon: Now through roughly November 2026  
Scope: Product, app, backend, retention, rewards, and commuter engagement. Ticketing is assumed to be implemented separately and integrated into this roadmap when ready.

## Executive Summary

MetroSafar should become more than a metro ticketing app. The stronger opportunity is to make it the daily companion for metro commuters: useful during a ride, rewarding between rides, and personal over time.

The current app already has the right early ingredients: onboarding, home, games, learn, wallet, profile, streaks, quests, rewards, and a backend. The next step is to connect these into a single habit loop:

1. Start commute.
2. Enter Ride Mode.
3. Complete a short game, quest, story, survey, or station action.
4. Earn points, streak progress, badges, and station passport progress.
5. Compare with friends, crew, station, or city.
6. Redeem rewards or unlock metro benefits.
7. Return tomorrow because progress, identity, and commute utility are waiting.

The product should feel like a metro-native rewards and entertainment layer, not a generic games tab attached to a ticketing app.

## Current App Snapshot

Current app identity:

- MetroSafar is a Flutter commuter app for Hyderabad Metro journeys.
- Booking is currently disabled behind a coming-soon screen.
- Current navigation uses five main tabs: Home, Play, Learn, Wallet, Profile.
- The backend already supports home/profile/rewards/games/streaks/quests/leaderboards/articles/surveys/stories/waitlist.

Current feature areas:

- Home: greeting, streak strip, daily quests, wallet preview, commute-oriented entry points.
- Play: Daily Spin, Trivia, Sudoku, Word Puzzle, City Explorer.
- Learn: Articles, Surveys, Station Stories.
- Wallet: points, tier, earn methods, redeem categories.
- Profile: activity stats, settings, language, notifications, legal/support.
- Booking: intentionally disabled for this release, with a coming-soon experience.

Current strengths:

- The app has a habit-oriented structure already.
- The tab model is understandable and production-friendly.
- Play, Learn, Wallet, and Home can support retention even before ticketing.
- Backend endpoints already cover many engagement primitives.
- Booking being disabled does not prevent the app from shipping as a companion/rewards app, provided expectations are clear.

Current gaps:

- The engagement loop is not yet tied strongly enough to the real metro journey.
- Games can feel separate from commuting unless session length and rewards are designed around ride time.
- Wallet value needs stronger real-world meaning.
- Leaderboards and rewards need server-side anti-abuse rules before meaningful public use.
- The app needs more personalization based on route, station, time of day, and commute behavior.
- Social and community mechanics are still missing.
- Notifications need to become useful and contextual rather than generic reminders.

## Product Positioning

Recommended positioning:

> MetroSafar is the daily metro companion that makes every commute useful, rewarding, and a little more fun.

Avoid positioning it only as:

- A ticket booking utility.
- A generic games app.
- A coupons wallet.
- A transit information app with some extras.

The moat should come from combining:

- Metro context.
- Daily commute frequency.
- Rewards.
- Local station identity.
- Short-form entertainment.
- Social competition.
- Practical journey help.

## Core Retention Loops

### Daily Commute Loop

User opens MetroSafar during commute, starts Ride Mode, receives a short checklist, earns points, and grows streak/passport progress.

Key mechanics:

- One-tap Ride Mode.
- Ride session timer.
- Commute-length game recommendations.
- Daily station quest.
- Streak multiplier.
- Wallet progress after every ride.

### Station Passport Loop

User builds a collectible map of stations visited, stories read, quizzes completed, and badges unlocked.

Key mechanics:

- Station badges.
- Line completion progress.
- Station trivia.
- Local stories.
- Visit/check-in history.
- Special badges for first station, interchange station, weekend ride, full line completion.

### Rewards Loop

User earns points from commute actions and redeems them for meaningful benefits.

Key mechanics:

- Points.
- Tiers.
- Scratch cards.
- Limited reward drops.
- Partner offers.
- Future ticketing benefits.
- Referral rewards.

### Social Loop

User competes and cooperates with friends, office groups, college groups, and station communities.

Key mechanics:

- Friend leaderboard.
- Station leaderboard.
- Weekly leagues.
- Crews.
- Crew goals.
- Referral invites.
- Shared achievements.

### Utility Loop

User comes back because the app helps with the journey itself.

Key mechanics:

- Favorite routes.
- Fare estimate.
- Station info.
- Last-mile suggestions.
- Platform/gate tips.
- Service alerts when available.
- Crowd-sourced commute tips.

## Feature Improvements To Prioritize

### 1. Ride Mode

Ride Mode should become the main commute experience.

What it does:

- Starts a commute session.
- Lets user select source/destination or reuse a favorite route.
- Shows estimated ride time.
- Suggests activities based on ride length.
- Tracks commute streaks.
- Rewards completion at the end.

Why it matters:

- It gives the app a clear daily reason to open.
- It connects games, learning, rewards, and metro usage into one flow.
- It prepares the product for future ticketing without depending on it immediately.

Minimum version:

- Start Ride button on Home.
- Manual station selection.
- Ride timer.
- Suggested activity cards.
- End Ride button.
- Points and streak reward.

Future version:

- Auto-suggest frequent route.
- Location-aware station detection with opt-in permissions.
- Notifications before regular commute time.
- Ticketing handoff when booking is enabled.

### 2. Station Passport

Station Passport should make Hyderabad Metro feel collectible.

What it does:

- Shows a visual metro line map or station list.
- Tracks stations visited, read about, played at, or completed.
- Unlocks badges and station facts.
- Rewards exploration.

Why it matters:

- It creates long-term progress.
- It makes repeat metro use feel personal.
- It gives non-ticket users a reason to explore the app.

Minimum version:

- Station list grouped by line.
- Badge state: locked, discovered, completed.
- Station detail page with story, trivia, and reward.
- Passport progress on Home and Profile.

Future version:

- Map-based passport.
- Limited-time station events.
- AR/photo-style station collectibles.
- Sponsored station quests.

### 3. Commute-Length Games

Games should be designed around real ride durations.

Game categories:

- 2-minute games for one-stop rides.
- 5-minute games for short rides.
- 10-minute games for longer rides.
- Daily challenge for repeat engagement.

Recommended improvements:

- Add time labels to each game.
- Add "perfect for your ride" recommendation in Ride Mode.
- Add daily seed/version for each puzzle.
- Add clear win/loss/reward screens.
- Add streak bonus for finishing one game during a ride.

New game ideas:

- Metro Rush: quick reflex game themed around route switching.
- Station Match: match station names, icons, or facts.
- Fare Guess: guess fare or route distance.
- Line Builder: connect stations in correct order.
- Crowd Sense: choose best coach/gate based on clues.

### 4. Daily Quests And Missions

Quests should become metro-specific and time-sensitive.

Quest examples:

- Start Ride Mode today.
- Complete one 5-minute game during a ride.
- Read one station story.
- Answer one station quiz.
- Check your wallet progress.
- Complete a Blue Line challenge.
- Invite one commuter friend.

Quest structure:

- Daily quests: quick, reliable, low reward.
- Weekly quests: larger commitment, higher reward.
- Event quests: time-bound and themed.
- Station quests: tied to metro location or selected route.

### 5. Leaderboards And Leagues

Leaderboards should create lightweight competition without overwhelming casual users.

Leaderboard types:

- Friends.
- Station.
- Route.
- City.
- Weekly league.
- Crew.

League design:

- Users start in Bronze.
- Top users move up weekly.
- Inactive users drop slowly.
- Rewards are mostly status, badges, and small point boosts.
- Avoid making rewards too easy to farm.

### 6. Crews

Crews are small commuter groups.

Crew examples:

- Office team.
- College group.
- Apartment group.
- Friends who commute on the same line.

Crew features:

- Crew leaderboard.
- Weekly crew goal.
- Shared point milestone.
- Invite link.
- Crew chat is optional and should not be part of the first version.

Minimum version:

- Create crew.
- Join crew by code/link.
- Crew members list.
- Weekly crew points.
- Crew rewards.

### 7. Reward Drops

Rewards should feel alive, limited, and worth checking.

Reward types:

- Daily scratch card.
- Weekly city drop.
- Station-specific reward.
- Partner coupon.
- Future ticket-related discount or cashback.
- Tier-based reward unlocks.

Rules:

- All meaningful rewards must be controlled by backend.
- Redemption must have inventory limits.
- Points and redemptions must be auditable.
- Abuse prevention must exist before real-money rewards.

### 8. Metro Wrapped

Metro Wrapped should summarize commute identity.

What it shows:

- Most used line.
- Favorite station.
- Total rides.
- Minutes spent commuting.
- Games completed.
- Stories read.
- Points earned.
- Badges unlocked.

Cadence:

- Monthly recap.
- Year-end recap.
- Special event recap.

Why it matters:

- It creates shareability.
- It turns commuting into identity and memory.
- It can drive organic acquisition.

### 9. Personalized Notifications

Notifications should be genuinely useful.

Notification types:

- "Your usual commute window is starting."
- "A 5-minute puzzle is ready for your ride."
- "You are one ride away from keeping your streak."
- "A reward drop is live near your line."
- "Your crew is close to this week's goal."
- "Read today's station story before your trip."

Rules:

- User must control notification preferences.
- Avoid spam.
- Use behavior-based timing.
- Start with local notifications; move to backend-triggered push later.

### 10. Practical Metro Utility

Utility features create trust and justify daily use.

Useful additions:

- Favorite routes.
- Route planner.
- Fare estimate.
- First/last train info.
- Station facilities.
- Gate/landmark guidance.
- Line status alerts if reliable source is available.
- Last-mile options.
- Saved station notes or tips.

Ticketing will be stronger if these utility foundations exist first.

## Backend And Data Plan

The backend should become the source of truth for points, rewards, streaks, leaderboards, and abuse-sensitive actions.

Recommended collections/tables:

- users
- user_profiles
- user_preferences
- activity_events
- ride_sessions
- station_progress
- station_badges
- game_sessions
- daily_challenges
- quests
- user_quest_progress
- wallets
- wallet_transactions
- rewards
- reward_inventory
- reward_redemptions
- scratch_cards
- leaderboards
- crews
- crew_members
- notifications
- waitlist_entries

Core backend principles:

- Client sends activity intent, server decides reward.
- Every point change creates an immutable transaction.
- Leaderboards are computed or safely aggregated server-side.
- Reward redemption is transactional and inventory-aware.
- Game completion needs basic fraud checks.
- All event writes should include client ID, user ID when available, app version, timestamp, and source.

Recommended APIs:

- POST /api/rides/start
- POST /api/rides/end
- GET /api/rides/history
- GET /api/stations
- GET /api/stations/:stationId
- GET /api/passport
- POST /api/passport/:stationId/check-in
- GET /api/quests/today
- POST /api/activity-events
- POST /api/games/:gameId/start
- POST /api/games/:gameId/complete
- GET /api/leaderboards
- POST /api/crews
- POST /api/crews/join
- GET /api/crews/:crewId
- GET /api/rewards
- POST /api/rewards/:rewardId/redeem
- GET /api/notifications/preferences
- PUT /api/notifications/preferences

Security and abuse controls:

- Add authentication before real rewards or ticketing.
- Rate-limit reward-sensitive endpoints.
- Validate game sessions using start/end timestamps.
- Cap daily point earnings.
- Detect repeated device/client abuse.
- Keep server-side reward rules out of the app binary.
- Log all reward and redemption events.

## Mobile App Architecture Plan

The current Riverpod/go_router direction is suitable. The next six months should strengthen feature boundaries and state consistency.

Recommended app modules:

- home
- ride
- station_passport
- play
- learn
- wallet
- rewards
- crews
- profile
- notifications
- backend/core services

Recommended app foundations:

- Unified ActivityEvent model.
- Unified RewardResult model.
- Shared loading/error/empty states.
- Offline cache for stations, rewards, articles, and profile.
- Remote config for feature flags.
- App version and environment display in debug builds.
- Crash/error reporting before large release.

Feature flags:

- booking_enabled
- ride_mode_enabled
- station_passport_enabled
- crews_enabled
- real_rewards_enabled
- push_notifications_enabled
- ticket_rewards_enabled

## Detailed Implementation Roadmap

### Phase 0: Production Safety With Booking Disabled

Goal:

- Make the current app safe to release as a non-ticketing metro companion.

Work:

- Keep booking behind a clear coming-soon screen.
- Remove or avoid any claims that users can currently buy metro tickets.
- Ensure backend ticket endpoints return a safe disabled response.
- Verify app store text does not advertise active ticketing until ready.
- Confirm privacy, terms, support, and contact flows work.
- Use release signing and locked-down API keys before public store release.

Exit criteria:

- User cannot accidentally enter an incomplete payment/ticketing flow.
- Booking disabled state is clear and intentional.
- Core non-ticketing flows work without crashes.

### Phase 1: Unified Engagement Core

Goal:

- Make points, streaks, quests, games, and wallet feel like one system.

Work:

- Add ActivityEvent model.
- Add server-side reward calculation.
- Add immutable wallet transactions.
- Connect game completion, quest completion, article read, survey completion, and streak claim to the same reward pipeline.
- Add consistent reward result UI.
- Add daily earning caps.

Exit criteria:

- Every earning action produces a traceable backend event.
- Wallet balance is backend-derived.
- Home can show a reliable daily progress summary.

### Phase 2: Ride Mode MVP

Goal:

- Give commuters a daily in-ride experience.

Work:

- Add Ride tab entry point or prominent Home card.
- Build source/destination selector.
- Add favorite route support.
- Add ride timer.
- Recommend games/articles based on ride length.
- Award Ride Mode completion points.
- Track ride sessions in backend.

Exit criteria:

- User can start and end a ride.
- Ride history is saved.
- Ride completion affects streak/points.
- At least three activities can be launched from Ride Mode.

### Phase 3: Station Passport MVP

Goal:

- Turn the metro network into long-term collectible progress.

Work:

- Add station data seed.
- Add station list grouped by line.
- Add station detail screen.
- Add station badges.
- Add station quiz/story hooks.
- Add passport progress card on Home/Profile.

Exit criteria:

- User can see all stations.
- User can unlock station progress.
- Passport progress is persisted backend-side.

### Phase 4: Better Games For Commutes

Goal:

- Make Play feel intentionally designed for metro rides.

Work:

- Add game duration labels.
- Add daily puzzle seeds.
- Add start/complete game sessions.
- Add reward rules by difficulty and duration.
- Add one new metro-native game.
- Add post-game reward and share screen.

Exit criteria:

- Games are categorized by commute length.
- Game rewards are server-controlled.
- Daily play loop is visible on Home.

### Phase 5: Rewards And Wallet Upgrade

Goal:

- Make wallet progress feel valuable and trustworthy.

Work:

- Add wallet transaction history.
- Add reward inventory.
- Add redemption flow with backend validation.
- Add scratch card inventory.
- Add tier rules.
- Add reward terms display.

Exit criteria:

- Users can see why their balance changed.
- Redemptions are auditable.
- Real rewards can be introduced safely.

### Phase 6: Leaderboards And Crews

Goal:

- Add social pressure and shared progress.

Work:

- Add friend/station/weekly leaderboards.
- Add league tiers.
- Add crew creation and join flow.
- Add crew weekly goal.
- Add abuse protection for leaderboard scoring.

Exit criteria:

- Users can compare progress.
- Crews can earn weekly progress.
- Leaderboards cannot be trivially spammed from the client.

### Phase 7: Notifications And Personalization

Goal:

- Bring users back at the right commute moment.

Work:

- Add notification preferences.
- Add local notification scheduling.
- Add commute-time reminders.
- Add streak reminders.
- Add reward drop reminders.
- Add backend push later when auth and tokens are stable.

Exit criteria:

- Notifications are opt-in and configurable.
- Users receive timely commute-related prompts.
- Notifications drive users into specific app states.

### Phase 8: Ticketing Integration

Goal:

- Integrate ticketing without weakening the companion experience.

Work:

- Add authenticated user account.
- Add booking flag rollout.
- Add ticketing entry from Home and Ride Mode.
- Add ticket purchase history.
- Add ticket-linked rewards.
- Add refund/support flows.
- Add compliance and payment review.

Exit criteria:

- Ticketing works reliably for controlled rollout users.
- Existing rewards/ride loops continue to work for non-ticket users.
- Booking does not dominate the app at the expense of daily engagement.

## 6-Month Product Vision: Around November 2026

By November 2026, MetroSafar should feel like a polished metro lifestyle companion with ticketing as one important feature, not the whole product.

### What The App Should Feel Like

The app should open with a strong sense of "this knows my commute."

Home should answer:

- What is useful for my commute right now?
- What can I earn today?
- What progress am I close to completing?
- What should I do during this ride?
- Is anything important happening on my route?

The tone should be energetic, local, and rewarding. It should feel closer to a daily companion than a government-style utility screen.

### Ideal November 2026 Navigation

Recommended tabs:

- Home
- Ride
- Play
- Wallet
- Profile

Where Learn goes:

- Learn should become part of Ride, Station Passport, and Home rather than remain a standalone destination forever.
- If content grows strongly, Learn can stay as a secondary section under Explore.

Possible future structure:

- Home: daily summary, streak, route, quests, reward drops.
- Ride: current ride, route planner, station passport, commute activities.
- Play: games, daily challenges, tournaments.
- Wallet: points, rewards, redemptions, tier.
- Profile: identity, crews, history, settings.

### Home In 6 Months

Home should include:

- Personalized greeting based on commute time.
- Favorite route card.
- Start Ride button.
- Today's commute quest.
- Streak and tier status.
- Daily reward drop.
- One recommended activity for ride duration.
- Passport progress teaser.
- Crew progress teaser.

Example Home experience:

- "Evening commute ready."
- "Ameerpet to Raidurg usually takes 24 minutes."
- "Start Ride Mode."
- "Today's quest: complete one Blue Line challenge."
- "You are 2 rides away from Silver."
- "A 5-minute station puzzle is ready."

### Ride Mode In 6 Months

Ride Mode should be the hero experience.

It should include:

- Current or selected route.
- Estimated ride duration.
- Stop progress.
- Suggested game/article/story/survey based on remaining time.
- End ride action.
- Points earned during ride.
- Station tips and gate guidance where available.
- Ticket card when ticketing is enabled.

Long-term potential:

- Auto-detect station proximity with explicit consent.
- Show reminders for interchange stations.
- Suggest last-mile options.
- Integrate active ticket QR or booking status.

### Station Passport In 6 Months

Station Passport should be visually memorable.

It should include:

- Metro line map or collectible station grid.
- Station completion states.
- Badges for lines and milestones.
- Station stories.
- Station quizzes.
- Exploration rewards.
- Monthly station events.

The goal is for users to feel, "I am building my metro identity."

### Play In 6 Months

Play should be commute-native.

It should include:

- Daily challenge.
- Recommended by ride length.
- Weekly tournaments.
- Friends and station rankings.
- Metro-themed games.
- Reward previews.
- Clear session completion.

The best games will be:

- Short.
- Repeatable.
- Metro-themed.
- Fair.
- Rewarding without being financially risky.
- Fun even without rewards.

### Wallet In 6 Months

Wallet should feel like a status and benefits hub.

It should include:

- Points balance.
- Tier progress.
- Transaction history.
- Available rewards.
- Limited reward drops.
- Redemption history.
- Future ticket-linked offers.
- Clear reward terms.

The wallet must be trustworthy. Users should always understand why points increased or decreased.

### Profile In 6 Months

Profile should become the user's commuter identity.

It should include:

- Metro level/tier.
- Favorite route.
- Passport completion.
- Badges.
- Monthly stats.
- Crew membership.
- Privacy and notification controls.
- Language settings.
- Support and legal.

Profile should not just be settings. It should make progress visible.

### Social Experience In 6 Months

The app should include light social mechanics, not heavy social networking.

Recommended features:

- Invite friends.
- Crew code/link.
- Weekly crew challenge.
- Friends leaderboard.
- Station leaderboard.
- Shareable achievement cards.

Avoid in the first six months:

- Open public chat.
- Complex feeds.
- Heavy moderation surfaces.
- Anything that distracts from commute utility.

### Backend In 6 Months

The backend should support production-grade engagement.

Required capabilities:

- Authenticated users.
- Server-controlled rewards.
- Wallet ledger.
- Ride sessions.
- Station progress.
- Game sessions.
- Leaderboards.
- Crews.
- Reward inventory.
- Notification preferences.
- Admin/config tooling for rewards and quests.
- Analytics export.
- Abuse detection.

Backend reliability goals:

- No client-trusted points.
- No unbounded reward farming.
- Idempotent reward actions.
- Clear audit trail.
- Safe feature flag rollout.

### Design Direction In 6 Months

MetroSafar should look more distinctive and local.

Recommended visual direction:

- Metro map-inspired surfaces.
- Line colors used meaningfully.
- Bold commute cards.
- Friendly reward animations.
- Collectible badges.
- Clear iconography for route, play, wallet, and station identity.
- Strong empty states that explain what to do next.

Avoid:

- Generic finance-app wallet design.
- Generic casino-style reward design.
- Overly dark or neon game styling.
- Too many unrelated card styles.

The visual system should feel like Hyderabad Metro plus a modern consumer rewards app.

## Success Metrics

Retention:

- Day 1 retention.
- Day 7 retention.
- Day 30 retention.
- Weekly active commuters.
- Monthly active commuters.

Engagement:

- Ride Mode starts per active user.
- Ride Mode completion rate.
- Daily quest completion rate.
- Game sessions per commute day.
- Station Passport progress per user.
- Reward drop opens.
- Crew participation.

Monetization and value:

- Reward redemption rate.
- Partner reward conversion.
- Ticketing conversion once enabled.
- Repeat ticketing usage once enabled.
- Cost per retained commuter.

Trust and quality:

- Crash-free sessions.
- API error rate.
- Support tickets per active user.
- Reward fraud rate.
- Redemption failure rate.
- App store rating.

## Product Principles

- Build around the commute, not around tabs.
- Reward real engagement, not random tapping.
- Make progress visible after every session.
- Keep ticketing important but not mandatory.
- Keep games short and metro-native.
- Make wallet trustworthy before adding high-value rewards.
- Use notifications carefully and contextually.
- Add social mechanics only where they improve retention.
- Prefer server-side rules for anything involving points, rewards, or leaderboards.
- Keep the product useful even when ticketing is unavailable.

## Recommended Next Decisions

These decisions should be made before implementation starts:

- Should Ride become its own main tab, or should it remain a Home hero action first?
- Which station dataset will be treated as the source of truth?
- What rewards can be safely offered before commercial partnerships are ready?
- Will users authenticate with phone number, email, Google, or anonymous-to-auth migration?
- What daily point cap is acceptable before real rewards are live?
- Which analytics stack will be used for retention and funnel tracking?
- Which features must be in the first public release versus the first growth release?

## Suggested First Build Slice

The best first implementation slice is:

1. Unified ActivityEvent and RewardResult.
2. Backend wallet ledger.
3. Ride Mode MVP.
4. Station data seed.
5. Passport MVP.
6. Game duration labels and ride recommendations.
7. Wallet transaction history.

This slice creates the core identity of the app without waiting for ticketing.

## Summary

MetroSafar can become sticky if it owns the daily commute moment. Ticket booking will be valuable, but the addictive layer comes from Ride Mode, Station Passport, metro-native games, daily quests, social crews, and a trustworthy reward wallet.

In six months, the app should feel like opening MetroSafar is part of taking the metro. It should know the user's route, offer something useful for the ride, reward consistent behavior, and make the metro network feel personal.
