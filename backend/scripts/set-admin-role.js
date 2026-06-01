#!/usr/bin/env node
/**
 * set-admin-role.js
 * -----------------
 * Bootstrap or update an admin user's custom claims.
 *
 * Usage:
 *   node scripts/set-admin-role.js --email admin@example.com --role superadmin
 *   node scripts/set-admin-role.js --uid abc123 --role city_admin --cities hyd,blr
 *
 * Roles: superadmin | city_admin | content_editor | analyst | support
 */

const admin = require('firebase-admin');

const VALID_ROLES = ['superadmin', 'city_admin', 'content_editor', 'analyst', 'support'];

function parseArgs() {
  const args = process.argv.slice(2);
  const get = (flag) => {
    const i = args.indexOf(flag);
    return i >= 0 ? args[i + 1] : null;
  };
  return {
    uid:    get('--uid'),
    email:  get('--email'),
    role:   get('--role'),
    cities: get('--cities')?.split(',').map(c => c.trim()).filter(Boolean) || [],
  };
}

async function run() {
  const { uid, email, role, cities } = parseArgs();

  if (!role || !VALID_ROLES.includes(role)) {
    console.error(`❌  --role must be one of: ${VALID_ROLES.join(', ')}`);
    process.exit(1);
  }
  if (!uid && !email) {
    console.error('❌  Provide --uid or --email');
    process.exit(1);
  }

  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT,
  });

  let userRecord;
  if (uid) {
    userRecord = await admin.auth().getUser(uid);
  } else {
    userRecord = await admin.auth().getUserByEmail(email);
  }

  const claims = { role, ...(cities.length ? { cities } : {}) };
  await admin.auth().setCustomUserClaims(userRecord.uid, claims);

  console.log(`✅  Set custom claims on ${userRecord.email || userRecord.uid}:`);
  console.log(JSON.stringify(claims, null, 2));
  console.log('\n⚠️  The user must sign out and sign back in for the new token to carry the claims.');
}

run().catch(err => { console.error(err); process.exit(1); });
