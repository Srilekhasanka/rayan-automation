import { test as setup, expect } from '@playwright/test';
import * as path from 'path';
import * as fs from 'fs';

const PORTAL_URL  = 'https://smart.gdrfad.gov.ae/SmartChannels_Th/Login.aspx';
const PORTAL_HOME = 'https://smart.gdrfad.gov.ae/SmartChannels_Th/';

// SESSION_ID env var: when set, saves to auth/sessions/session-<id>.json
// When not set (or on EC2), defaults to auth/session.json
const SESSION_ID = process.env.SESSION_ID;
export const SESSION_FILE = SESSION_ID
  ? path.resolve(`auth/sessions/session-${SESSION_ID}.json`)
  : path.resolve('auth/session.json');

const KEEP_ALIVE_INTERVAL_MS = 4 * 60 * 1000; // 4 min — well within the 15-min idle timeout
const TOTAL_SESSIONS = parseInt(process.env.TOTAL_SESSIONS || '1', 10);
const START_SESSION  = parseInt(process.env.START_SESSION  || SESSION_ID || '1', 10);

setup('Manual login & save session', async ({ page }) => {
  setup.setTimeout(0);

  const sessionsDir = path.resolve('auth/sessions');
  if (!fs.existsSync(sessionsDir)) {
    fs.mkdirSync(sessionsDir, { recursive: true });
  }

  // Loop through sessions — for single auth (no TOTAL_SESSIONS), runs once
  for (let i = START_SESSION; i < START_SESSION + TOTAL_SESSIONS; i++) {
    const sessionFile = path.resolve(`auth/sessions/session-${i}.json`);
    console.log(`\n[Auth] ═══ Session ${i} of ${START_SESSION + TOTAL_SESSIONS - 1} ═══`);

    // 1. Clear stale cookies for a fresh login
    await page.context().clearCookies();

    // 2. Navigate to the login page
    await page.goto(PORTAL_URL, { waitUntil: 'domcontentloaded' });
    if (!page.url().includes('Login.aspx')) {
      console.warn('[Auth] Portal redirected away from Login.aspx — retrying...');
      await page.goto(PORTAL_URL, { waitUntil: 'domcontentloaded' });
    }

    // 3. Pause — Solve CAPTCHA, login, then click Resume
    console.log(`[Auth] Solve CAPTCHA and login for session ${i}, then click Resume.`);
    await page.pause();

    // 4. Save this session
    await page.context().storageState({ path: sessionFile });
    console.log(`[Auth] Session ${i} saved → ${sessionFile}`);
    expect(fs.existsSync(sessionFile)).toBeTruthy();
  }

  // 5. Start keep-alive for the last session
  const keepAlive = setInterval(async () => {
    try {
      await page.evaluate(async (url: string) => {
        await fetch(url, { method: 'GET', credentials: 'include' });
      }, PORTAL_HOME);
      console.log('[KeepAlive] Session ping sent — idle timer reset.');
    } catch {
      // Ignore — browser may be mid-navigation
    }
  }, KEEP_ALIVE_INTERVAL_MS);

  console.log('\n[Auth] ─────────────────────────────────────────────────────────');
  console.log(`[Auth] All ${TOTAL_SESSIONS} session(s) saved in auth/sessions/`);
  console.log('[Auth] Keep-alive pinging every 4 min.');
  console.log('[Auth] ► Open a NEW terminal and run:  npm test');
  console.log('[Auth] ► Once done, click Resume here to close.');
  console.log('[Auth] ─────────────────────────────────────────────────────────\n');
  await page.pause();

  clearInterval(keepAlive);
  console.log('[Auth] Keep-alive stopped. Auth browser closed.');
});
