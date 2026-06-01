#!/usr/bin/env node
/**
 * seed-catalog.js
 * ---------------
 * One-time (idempotent) migration: reads db.json and writes each item into
 * the Firestore catalog_* collections.
 *
 * Usage:
 *   node scripts/seed-catalog.js            # dry-run (no writes)
 *   node scripts/seed-catalog.js --write    # actually write
 *   node scripts/seed-catalog.js --force    # overwrite existing docs too
 *
 * Environment:
 *   GOOGLE_APPLICATION_CREDENTIALS or Cloud ADC for Firebase Admin
 *   FIREBASE_PROJECT_ID (optional, falls back to GOOGLE_CLOUD_PROJECT)
 */

const path = require('path');
const fs   = require('fs');
const admin = require('firebase-admin');

const DRY_RUN = !process.argv.includes('--write');
const FORCE   = process.argv.includes('--force');

if (DRY_RUN) {
  console.log('🔍  DRY RUN — pass --write to actually write to Firestore');
}

admin.initializeApp({
  projectId: process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT,
});

const firestore = admin.firestore();
const db = JSON.parse(fs.readFileSync(path.join(__dirname, '../db.json'), 'utf8'));

// ---------------------------------------------------------------------------
// Catalog definitions: { collectionName, sourceKey, transform }
// ---------------------------------------------------------------------------
const CATALOGS = [
  {
    collection: 'catalog_rewards',
    items: (db.rewards || []).map((r, i) => ({
      id: r.id,
      title:        r.title || '',
      discount:     r.discount || '',
      points:       Number(r.points) || 0,
      category:     r.category || 'General',
      description:  r.description || '',
      active:       true,
      sortOrder:    i,
      stock:        null,          // null = unlimited
      perUserLimit: 1,             // default: once per user
      _seededAt:    new Date().toISOString(),
    })),
  },
  {
    collection: 'catalog_games',
    items: (db.games || []).map((g, i) => ({
      id:                 g.id,
      title:              g.title || '',
      description:        g.description || '',
      points:             Number(g.points) || 0,
      route:              g.route || '',
      durationMinutes:    Number(g.durationMinutes) || 5,
      commuteLengthLabel: g.commuteLengthLabel || '',
      difficulty:         g.difficulty || 'medium',
      icon:               g.icon || '🎮',
      active:             true,
      sortOrder:          i,
      _seededAt:          new Date().toISOString(),
    })),
  },
  {
    collection: 'catalog_articles',
    items: (db.articles || []).map((a, i) => ({
      id:               a.id,
      title:            a.title || '',
      body:             a.body || '',
      coverUrl:         a.coverUrl || '',
      readTimeMinutes:  Number(a.readTimeMinutes) || 3,
      points:           Number(a.points) || 15,
      publishedAt:      a.publishedAt || new Date().toISOString(),
      active:           true,
      sortOrder:        i,
      _seededAt:        new Date().toISOString(),
    })),
  },
  {
    collection: 'catalog_surveys',
    items: (db.surveys || []).map((s, i) => ({
      id:        s.id,
      question:  s.question || s.title || '',
      options:   s.options || [],
      points:    Number(s.points) || 20,
      active:    true,
      sortOrder: i,
      _seededAt: new Date().toISOString(),
    })),
  },
  {
    collection: 'catalog_quests',
    // These IDs are referenced in user completion state — never rename them.
    items: [
      { id: 'start_ride',     title: 'Start Ride Mode',       description: 'Begin a metro commute session',          points: 30, type: 'ride_started',           active: true, sortOrder: 0 },
      { id: 'play_game',      title: 'Play a game',           description: 'Complete any game during your ride',     points: 20, type: 'game_completed',          active: true, sortOrder: 1 },
      { id: 'read_article',   title: 'Read an article',       description: 'Read any article in Learn',              points: 15, type: 'article_read',            active: true, sortOrder: 2 },
      { id: 'station_quiz',   title: 'Answer a station quiz', description: 'Test your metro knowledge',              points: 25, type: 'station_quiz_completed',  active: true, sortOrder: 3 },
      { id: 'check_passport', title: 'Check your passport',   description: 'View your station passport progress',   points: 10, type: 'passport_viewed',         active: true, sortOrder: 4 },
    ].map(q => ({ ...q, _seededAt: new Date().toISOString() })),
  },
  {
    collection: 'catalog_videos',
    items: (db.videos || []).map((v, i) => ({
      id:          v.id,
      title:       v.title || '',
      duration:    v.duration || '',
      points:      Number(v.points) || 20,
      description: v.description || '',
      active:      true,
      sortOrder:   i,
      _seededAt:   new Date().toISOString(),
    })),
  },
];

async function seed() {
  let totalWritten = 0;
  let totalSkipped = 0;

  for (const catalog of CATALOGS) {
    console.log(`\n📦  ${catalog.collection} (${catalog.items.length} items)`);
    for (const item of catalog.items) {
      const ref = firestore.collection(catalog.collection).doc(item.id);
      if (!DRY_RUN) {
        if (!FORCE) {
          const snap = await ref.get();
          if (snap.exists) {
            console.log(`   ⏭  skip  ${item.id} (already exists; use --force to overwrite)`);
            totalSkipped++;
            continue;
          }
        }
        const { id: _id, ...data } = item;
        await ref.set({ ...data, _updatedAt: new Date() });
        console.log(`   ✅  write ${item.id}`);
        totalWritten++;
      } else {
        console.log(`   📝  would write ${item.id}: ${JSON.stringify(item).slice(0, 80)}…`);
        totalWritten++;
      }
    }
  }

  console.log(`\n🏁  Done. ${DRY_RUN ? 'Would write' : 'Wrote'} ${totalWritten}, skipped ${totalSkipped}.`);
  if (DRY_RUN) console.log('    Run with --write to apply.');
}

seed().catch(err => { console.error(err); process.exit(1); });
