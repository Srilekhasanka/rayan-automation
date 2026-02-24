import { test } from '@playwright/test';
import * as fs   from 'fs';
import * as path from 'path';
import { fillApplicationForm } from '../src/automation/gdrfa-portal';
import { readApplicationsFromExcel } from '../src/utils/excel-reader';

// On EC2, SERVER_ID picks the right session; locally falls back to auth/session.json
const SERVER_ID = process.env.SERVER_ID;
const SESSION_FILE = SERVER_ID
  ? path.resolve(`auth/sessions/session-${SERVER_ID}.json`)
  : path.resolve('auth/session.json');
const EXCEL_FILE = path.resolve('data/applications/applications.xlsx');

// Multi-server partitioning: each EC2 server processes only its chunk of applicants
const TOTAL_SERVERS = parseInt(process.env.TOTAL_SERVERS || '1', 10);
const serverIndex   = SERVER_ID ? parseInt(SERVER_ID, 10) : 1;

// ─── Helpers ──────────────────────────────────────────────────────────────────

function ensureDir(dir: string) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

// ─── Pre-flight checks ────────────────────────────────────────────────────────

test.beforeAll(() => {
  if (!fs.existsSync(SESSION_FILE)) {
    throw new Error(
      'Session not found: auth/session.json\n' +
      'Run "npm run auth" to log in manually and save your session first.'
    );
  }
  if (!fs.existsSync(EXCEL_FILE)) {
    throw new Error(
      `Excel file not found: ${EXCEL_FILE}\n` +
      'Run "npm run excel" to generate the applications spreadsheet first.'
    );
  }
});

// ─── Tests run in parallel (up to 20 workers) ───────────────────────────────

test.describe.parallel('GDRFA Visa Application — Fill Only (No Submission)', () => {

  const allApplications = readApplicationsFromExcel(EXCEL_FILE);
  const totalAll        = allApplications.length;

  // Partition: each server gets its own slice of applicants
  const chunkSize    = Math.ceil(totalAll / TOTAL_SERVERS);
  const startIndex   = (serverIndex - 1) * chunkSize;
  const applications = allApplications.slice(startIndex, startIndex + chunkSize);
  const total        = applications.length;

  if (TOTAL_SERVERS > 1) {
    console.log(`[Server ${serverIndex}/${TOTAL_SERVERS}] Processing rows ${startIndex + 1}–${startIndex + total} of ${totalAll}`);
  }

  if (total === 0) {
    test('no applicants found', () => {
      throw new Error(
        'No rows found in the Excel file.\n' +
        'Add applicant data to: ' + EXCEL_FILE
      );
    });
  }

  for (let i = 0; i < applications.length; i++) {
    const application  = applications[i];
    const globalIndex  = startIndex + i + 1; // Original row number in the Excel
    const label        = `applicant-${String(globalIndex).padStart(String(totalAll).length, '0')}`;
    const prefix       = `[Applicant ${globalIndex}/${totalAll} — ${label}]`;

    test(`${label} — Fill form (no submission)`, async ({ page }) => {
      console.log(`\n${prefix} Loading application...`);
      console.log(
        `${prefix} Filling form for: ` +
        `${application.passport.fullNameEN} | ${application.passport.passportNumber}`
      );

      await fillApplicationForm(page, application);

      ensureDir('test-results');
      await page.screenshot({
        path: `test-results/${label}-form-filled.png`,
        fullPage: true,
      });
      console.log(`${prefix} Screenshot saved.`);
    });
  }

});
