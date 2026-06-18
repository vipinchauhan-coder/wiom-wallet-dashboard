#!/usr/bin/env node
// ============================================================
//  push-to-github.js
//  Run this on ANY machine INSIDE Wiom's network.
//  It fetches the wallet report from Metabase and pushes
//  it straight to GitHub — no Git installation required.
//
//  Usage (Windows):
//    set GITHUB_PAT=ghp_xxxYourTokenxxx
//    node push-to-github.js
//
//  Usage (Linux/Mac):
//    GITHUB_PAT=ghp_xxxYourTokenxxx node push-to-github.js
//
//  To automate, add to Windows Task Scheduler:
//    Program : node
//    Args    : C:\path\to\push-to-github.js
//    Env var : GITHUB_PAT=ghp_xxxYourTokenxxx
// ============================================================

const https = require('https');
const http  = require('http');
const url   = require('url');

// ── CONFIG ── edit these if needed ───────────────────────────
const GITHUB_PAT  = process.env.GITHUB_PAT  || '';          // set via env var
const GITHUB_REPO = 'vipinchauhan-coder/wiom-wallet-dashboard';
const MB_URL      = (process.env.MB_URL     || 'https://metabase.wiom.in').replace(/\/$/, '');
const MB_EMAIL    = process.env.MB_EMAIL    || 'Vipin.Chauhan@wiom.in';
const MB_PASSWORD = process.env.MB_PASSWORD || 'Wiom@2117';
const MB_QID      = process.env.MB_QID      || '11227';
// ─────────────────────────────────────────────────────────────

if (!GITHUB_PAT) {
  console.error('[push-to-github] ERROR: GITHUB_PAT env var is required.');
  console.error('  Run:  set GITHUB_PAT=ghp_yourtoken  (Windows)');
  console.error('  Run:  export GITHUB_PAT=ghp_yourtoken  (Linux/Mac)');
  process.exit(1);
}

function request(urlStr, opts = {}, body = null) {
  return new Promise((resolve, reject) => {
    const parsed = url.parse(urlStr);
    const lib = parsed.protocol === 'https:' ? https : http;
    const options = {
      hostname : parsed.hostname,
      port     : parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
      path     : parsed.path,
      method   : opts.method  || 'GET',
      headers  : opts.headers || {},
      timeout  : 60000,
      rejectUnauthorized: opts.allowSelfSigned ? false : true,
    };
    const req = lib.request(options, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString() }));
    });
    req.on('error', err => {
      // retry with self-signed cert allowed if SSL error
      if (!opts.allowSelfSigned && (err.code === 'UNABLE_TO_VERIFY_LEAF_SIGNATURE' || err.code === 'CERT_HAS_EXPIRED' || err.code === 'DEPTH_ZERO_SELF_SIGNED_CERT')) {
        resolve(request(urlStr, { ...opts, allowSelfSigned: true }, body));
      } else {
        reject(err);
      }
    });
    req.on('timeout', () => { req.destroy(); reject(new Error('Request timed out')); });
    if (body) req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

async function ghGet(path) {
  return request(`https://api.github.com/repos/${GITHUB_REPO}/contents/${path}`, {
    headers: {
      'Authorization': `token ${GITHUB_PAT}`,
      'Accept'       : 'application/vnd.github.v3+json',
      'User-Agent'   : 'wiom-wallet-sync/1.0',
    }
  });
}

async function ghPut(filePath, content, message) {
  const existing = await ghGet(filePath);
  const body = {
    message,
    content: Buffer.from(content).toString('base64'),
  };
  if (existing.status === 200) {
    body.sha = JSON.parse(existing.body).sha;
  }
  const r = await request(`https://api.github.com/repos/${GITHUB_REPO}/contents/${filePath}`, {
    method : 'PUT',
    headers: {
      'Authorization': `token ${GITHUB_PAT}`,
      'Content-Type' : 'application/json',
      'Accept'       : 'application/vnd.github.v3+json',
      'User-Agent'   : 'wiom-wallet-sync/1.0',
    }
  }, JSON.stringify(body));
  if (r.status !== 200 && r.status !== 201) {
    throw new Error(`GitHub push failed (${r.status}): ${r.body.substring(0, 300)}`);
  }
  return r.status;
}

async function main() {
  console.log(`\n[push-to-github] ── Wiom Wallet Sync ──`);
  console.log(`[push-to-github] Connecting to Metabase at ${MB_URL} ...`);

  // Step 1: Authenticate with Metabase
  let token;
  for (const payload of [
    { username: MB_EMAIL, password: MB_PASSWORD },
    { email:    MB_EMAIL, password: MB_PASSWORD },
  ]) {
    const r = await request(`${MB_URL}/api/session`, {
      method : 'POST',
      headers: { 'Content-Type': 'application/json' },
      allowSelfSigned: true,
    }, JSON.stringify(payload));
    if (r.status === 200) {
      token = JSON.parse(r.body).id;
      break;
    }
  }
  if (!token) throw new Error('Metabase authentication failed — check email/password');
  console.log(`[push-to-github] Authenticated ✓`);

  // Step 2: Download CSV
  console.log(`[push-to-github] Downloading question ${MB_QID} as CSV ...`);
  const csvRes = await request(`${MB_URL}/api/card/${MB_QID}/query/csv`, {
    method : 'POST',
    headers: {
      'Content-Type'       : 'application/json',
      'X-Metabase-Session' : token,
    },
    allowSelfSigned: true,
  }, JSON.stringify({ parameters: [] }));

  if (csvRes.status !== 200) {
    throw new Error(`CSV download failed (${csvRes.status}): ${csvRes.body.substring(0, 200)}`);
  }
  const rowCount = (csvRes.body.match(/\n/g) || []).length;
  console.log(`[push-to-github] Got ${rowCount} rows (${(csvRes.body.length / 1024).toFixed(1)} KB) ✓`);

  // Step 3: Push to GitHub
  const now = new Date().toISOString();
  const label = now.slice(0, 16).replace('T', ' ') + ' UTC';
  console.log(`[push-to-github] Pushing to GitHub (${GITHUB_REPO}) ...`);
  const csvStatus  = await ghPut('data/latest.csv',    csvRes.body, `chore: sync data ${label}`);
  const tsStatus   = await ghPut('data/last-sync.txt', now,         `chore: update timestamp ${label}`);
  console.log(`[push-to-github] Pushed latest.csv (${csvStatus}) and last-sync.txt (${tsStatus}) ✓`);

  const [owner, repo] = GITHUB_REPO.split('/');
  console.log(`\n[push-to-github] Done! Dashboard live at:`);
  console.log(`  https://${owner}.github.io/${repo}/\n`);
}

main().catch(err => {
  console.error('[push-to-github] ERROR:', err.message);
  process.exit(1);
});
