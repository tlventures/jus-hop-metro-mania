#!/usr/bin/env node
/**
 * seed-via-rest.js
 * ----------------
 * Seeds the catalog_* collections via the Firestore REST API using a gcloud
 * access token (owner creds), preserving the exact db.json document IDs.
 * The backend's onSnapshot listeners pick up the writes automatically.
 *
 * Usage:
 *   PROJECT=metrosafar-20260517-223707 \
 *   TOKEN="$(gcloud auth print-access-token)" \
 *   node scripts/seed-via-rest.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');

const PROJECT = process.env.PROJECT;
const TOKEN = process.env.TOKEN;
if (!PROJECT || !TOKEN) { console.error('Set PROJECT and TOKEN env vars'); process.exit(1); }

const db = JSON.parse(fs.readFileSync(path.join(__dirname, '../db.json'), 'utf8'));
const nowIso = new Date().toISOString();

// ---- JS value → Firestore REST typed value ----
function toField(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toField) } };
  return { stringValue: String(v) };
}
function toFields(obj) {
  const out = {};
  for (const [k, val] of Object.entries(obj)) out[k] = toField(val);
  return out;
}

// ---- Build records (mirrors seed-catalog.js shapes) ----
const CATALOGS = {
  catalog_rewards: (db.rewards || []).map((r, i) => ({
    _id: r.id,
    title: r.title || '', discount: r.discount || '', points: Number(r.points) || 0,
    category: r.category || 'General', description: r.description || '',
    active: true, sortOrder: i, stock: null, perUserLimit: 1,
    fulfillmentType: 'manual', affiliateUrl: null, _seededAt: nowIso, _updatedAt: nowIso,
  })),
  catalog_games: (db.games || []).map((g, i) => ({
    _id: g.id,
    title: g.title || '', description: g.description || '', points: Number(g.points) || 0,
    route: g.route || '', durationMinutes: Number(g.durationMinutes) || 5,
    commuteLengthLabel: g.commuteLengthLabel || '', difficulty: g.difficulty || 'medium',
    icon: g.icon || '🎮', active: true, sortOrder: i, _seededAt: nowIso, _updatedAt: nowIso,
  })),
  catalog_articles: (db.articles || []).map((a, i) => ({
    _id: a.id,
    title: a.title || '', body: a.body || '', coverUrl: a.coverUrl || '',
    readTimeMinutes: Number(a.readTimeMinutes) || 3, points: Number(a.points) || 15,
    publishedAt: a.publishedAt || nowIso, active: true, sortOrder: i, _seededAt: nowIso, _updatedAt: nowIso,
  })),
  catalog_surveys: (db.surveys || []).map((s, i) => ({
    _id: s.id,
    question: s.question || s.title || '', options: s.options || [], points: Number(s.points) || 20,
    active: true, sortOrder: i, _seededAt: nowIso, _updatedAt: nowIso,
  })),
  catalog_videos: (db.videos || []).map((v, i) => ({
    _id: v.id,
    title: v.title || '', duration: v.duration || '', points: Number(v.points) || 20,
    description: v.description || '', active: true, sortOrder: i, _seededAt: nowIso, _updatedAt: nowIso,
  })),
  catalog_quests: [
    { _id: 'start_ride',     title: 'Start Ride Mode',       description: 'Begin a metro commute session',         points: 30, type: 'ride_started',           active: true, sortOrder: 0 },
    { _id: 'play_game',      title: 'Play a game',           description: 'Complete any game during your ride',    points: 20, type: 'game_completed',          active: true, sortOrder: 1 },
    { _id: 'read_article',   title: 'Read an article',       description: 'Read any article in Learn',             points: 15, type: 'article_read',            active: true, sortOrder: 2 },
    { _id: 'station_quiz',   title: 'Answer a station quiz', description: 'Test your metro knowledge',             points: 25, type: 'station_quiz_completed',  active: true, sortOrder: 3 },
    { _id: 'check_passport', title: 'Check your passport',   description: 'View your station passport progress',  points: 10, type: 'passport_viewed',         active: true, sortOrder: 4 },
  ].map(q => ({ ...q, _seededAt: nowIso, _updatedAt: nowIso })),
};

function patchDoc(collection, id, fields) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ fields: toFields(fields) });
    const req = https.request({
      method: 'PATCH',
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${PROJECT}/databases/(default)/documents/${collection}/${encodeURIComponent(id)}`,
      headers: {
        'Authorization': `Bearer ${TOKEN}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let data = ''; res.on('data', c => data += c);
      res.on('end', () => res.statusCode < 300 ? resolve() : reject(new Error(`${res.statusCode} ${data.slice(0,200)}`)));
    });
    req.on('error', reject);
    req.write(body); req.end();
  });
}

(async () => {
  let written = 0, failed = 0;
  for (const [collection, items] of Object.entries(CATALOGS)) {
    for (const item of items) {
      const { _id, ...fields } = item;
      try { await patchDoc(collection, _id, fields); written++; process.stdout.write(`✅ ${collection}/${_id}\n`); }
      catch (e) { failed++; process.stdout.write(`❌ ${collection}/${_id}: ${e.message}\n`); }
    }
  }
  console.log(`\n🏁 wrote ${written}, failed ${failed}`);
  process.exit(failed ? 1 : 0);
})();
