#!/usr/bin/env node
// Fetches latest CSV from Metabase and saves to data/latest.csv
// Run by GitHub Actions every hour

const https = require('https');
const http  = require('http');
const fs    = require('fs');
const path  = require('path');
const url   = require('url');

const MB_URL  = (process.env.MB_URL  || 'https://metabase.wiom.in').replace(/\/$/, '');
const EMAIL   = process.env.MB_EMAIL    || 'Vipin.Chauhan@wiom.in';
const PASS    = process.env.MB_PASSWORD || 'Wiom@2117';
const QID     = process.env.MB_QID      || '11227';

function request(urlStr, opts = {}, body = null) {
  return new Promise((resolve, reject) => {
    const parsed = url.parse(urlStr);
    const lib = parsed.protocol === 'https:' ? https : http;
    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
      path: parsed.path,
      method: opts.method || 'GET',
      headers: opts.headers || {},
      timeout: 30000,
    };
    const req = lib.request(options, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString() }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Request timed out')); });
    if (body) req.write(body);
    req.end();
  });
}

async function main() {
  console.log(`[fetch-data] Authenticating with ${MB_URL} as ${EMAIL}...`);

  // Step 1: Authenticate
  const authRes = await request(`${MB_URL}/api/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  }, JSON.stringify({ username: EMAIL, password: PASS }));

  if (authRes.status !== 200) {
    const authRes2 = await request(`${MB_URL}/api/session`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, JSON.stringify({ email: EMAIL, password: PASS }));

    if (authRes2.status !== 200) {
      throw new Error(`Auth failed: ${authRes2.status} ${authRes2.body}`);
    }
    var token = JSON.parse(authRes2.body).id;
  } else {
    var token = JSON.parse(authRes.body).id;
  }
  console.log(`[fetch-data] Auth OK, token: ${token.substring(0, 8)}...`);

  // Step 2: Fetch CSV
  console.log(`[fetch-data] Fetching question ${QID} as CSV...`);
  const csvRes = await request(`${MB_URL}/api/card/${QID}/query/csv`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Metabase-Session': token,
    },
  }, JSON.stringify({ parameters: [] }));

  if (csvRes.status !== 200) {
    throw new Error(`CSV fetch failed: ${csvRes.status} ${csvRes.body.substring(0, 200)}`);
  }

  const rowCount = (csvRes.body.match(/\n/g) || []).length;
  console.log(`[fetch-data] Got CSV: ~${rowCount} rows, ${csvRes.body.length} bytes`);

  // Step 3: Save files
  const dataDir = path.join(__dirname, 'data');
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir);

  fs.writeFileSync(path.join(dataDir, 'latest.csv'), csvRes.body, 'utf8');
  fs.writeFileSync(path.join(dataDir, 'last-sync.txt'), new Date().toISOString(), 'utf8');

  console.log(`[fetch-data] Saved to data/latest.csv ✓`);
}

main().catch(err => {
  console.error('[fetch-data] ERROR:', err.message);
  process.exit(1);
});
