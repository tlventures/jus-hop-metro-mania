/**
 * Migration 001 — Multi-city backfill
 *
 * Backfills every existing user doc with:
 *   activeCityId: "hyd"
 *   cityHistory:  ["hyd"]
 *
 * Also backfills leaderboard, stamp, quest, and streak Firestore documents
 * with cityId: "hyd" so they are scoped correctly once multi-city is live.
 *
 * Usage:
 *   node migrations/001_multi_city.js [--dry-run]
 *
 * The script is idempotent — documents that already have activeCityId set
 * are skipped.
 */

'use strict';

const { Firestore } = require('@google-cloud/firestore');
const firestore = new Firestore();

const DRY_RUN = process.argv.includes('--dry-run');
const DEFAULT_CITY = 'hyd';

if (DRY_RUN) {
  console.log('[DRY RUN] — no writes will be made.');
}

// Collections to backfill with cityId
const COLLECTIONS_TO_BRAND = [
  'leaderboard_entries',
  'user_stamps',
  'user_quests',
  'user_streaks',
  'articles',
  'surveys',
  'stories',
  'audio_episodes',
];

async function migrateUsers() {
  console.log('\n→ Migrating users…');
  const snap = await firestore.collection('metrosafar_users').get();
  let skipped = 0, updated = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.activeCityId) {
      skipped++;
      continue; // already migrated
    }

    const patch = {
      activeCityId: DEFAULT_CITY,
      cityHistory: [DEFAULT_CITY],
    };

    if (!DRY_RUN) {
      await doc.ref.update(patch);
    }
    updated++;
    if (updated % 100 === 0) console.log(`  … ${updated} users updated`);
  }

  console.log(`  ✓ Users: ${updated} updated, ${skipped} skipped (already migrated)`);
}

async function backfillCollectionCityId(collectionName) {
  console.log(`\n→ Backfilling ${collectionName}…`);
  const snap = await firestore.collection(collectionName).get();
  let skipped = 0, updated = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.cityId) { skipped++; continue; }
    if (!DRY_RUN) await doc.ref.update({ cityId: DEFAULT_CITY });
    updated++;
  }

  console.log(`  ✓ ${collectionName}: ${updated} updated, ${skipped} skipped`);
}

async function main() {
  console.log(`Multi-city migration 001 — target city: ${DEFAULT_CITY}`);
  console.log(`Firestore project: ${process.env.GOOGLE_CLOUD_PROJECT || '(default from ADC)'}`);

  await migrateUsers();

  for (const col of COLLECTIONS_TO_BRAND) {
    await backfillCollectionCityId(col);
  }

  console.log('\n✅ Migration 001 complete.');
}

main().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
