#!/usr/bin/env node
/**
 * One-time script to grant superadmin role to a Firebase user by email.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=~/path/to/sa.json node backend/scripts/set-superadmin.js pidaparthy@gmail.com
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

// Resolve the service account key — expand ~ manually since Node doesn't do it
function resolvePath(p) {
  if (!p) return null;
  if (p.startsWith('~/')) return path.join(process.env.HOME || '', p.slice(2));
  return path.resolve(p);
}

const saPath = resolvePath(process.env.GOOGLE_APPLICATION_CREDENTIALS);

let credential;
let projectId;

if (saPath && fs.existsSync(saPath)) {
  const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  credential = admin.credential.cert(sa);
  projectId = sa.project_id;
  console.log(`Using service account from: ${saPath}`);
  console.log(`Project: ${projectId}`);
} else {
  console.log('No GOOGLE_APPLICATION_CREDENTIALS found — using Application Default Credentials');
  credential = admin.credential.applicationDefault();
  projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT;
}

admin.initializeApp({ credential, projectId });

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node backend/scripts/set-superadmin.js <email>');
    console.error('   or: node backend/scripts/set-superadmin.js --uid <uid>');
    process.exit(1);
  }

  let uid;
  if (args[0] === '--uid') {
    uid = args[1];
    if (!uid) { console.error('--uid requires a value'); process.exit(1); }
  } else {
    const email = args[0];
    console.log(`Looking up user by email: ${email}`);
    const user = await admin.auth().getUserByEmail(email);
    uid = user.uid;
    console.log(`Found user: ${user.displayName || email} (${uid})`);
  }

  const currentClaims = (await admin.auth().getUser(uid)).customClaims || {};
  console.log('Current claims:', JSON.stringify(currentClaims));

  await admin.auth().setCustomUserClaims(uid, {
    ...currentClaims,
    role: 'superadmin',
    cities: [],
  });

  const updated = (await admin.auth().getUser(uid)).customClaims;
  console.log('✅ Updated claims:', JSON.stringify(updated));
  console.log('');
  console.log('Done! Sign out and sign back in to the admin console to receive the new token.');
  process.exit(0);
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
