/**
 * Reads applicant rows from the applications Excel file and maps each row
 * back into a VisaApplication object that the automation can consume.
 */

import * as XLSX from 'xlsx';
import * as path from 'path';
import * as fs from 'fs';
import { VisaApplication, ApplicationDocuments } from '../types/application-data';

// Static contact/address fields shared by all applicants (Rayna Tourism office details)
const CONTACT_DEFAULTS_FILE = path.resolve('data/config/contact-defaults.json');
const contactDefaults = JSON.parse(fs.readFileSync(CONTACT_DEFAULTS_FILE, 'utf-8'));

// Batch-level fields shared by all applicants (visit details, establishment, etc.)
const BATCH_DEFAULTS_FILE = path.resolve('data/config/batch-defaults.json');
const batchDefaults = JSON.parse(fs.readFileSync(BATCH_DEFAULTS_FILE, 'utf-8'));

/**
 * Reads the Excel workbook at `filePath` and returns one VisaApplication per row.
 * Column headers must match those produced by scripts/json-to-excel.ts.
 */
export function readApplicationsFromExcel(filePath: string): VisaApplication[] {
  // { cellDates: false } prevents xlsx from parsing date-looking cells into
  // JS Date objects, keeping them as the raw string/number the user typed.
  const wb = XLSX.readFile(filePath, { cellDates: false });
  const ws = wb.Sheets[wb.SheetNames[0]];
  // raw: false → use formatted text from cell (respects the display format),
  // so dates stay as "13/10/1973" instead of becoming serial numbers.
  const rawRows = XLSX.utils.sheet_to_json<Record<string, unknown>>(ws, { defval: '', raw: false });

  // xlsx may return numbers for date-like cells (Excel serial dates).
  // Coerce every cell value to a string so .replace() etc. always work.
  const rows = rawRows.map(raw => {
    const r: Record<string, string> = {};
    for (const [k, v] of Object.entries(raw)) {
      r[k] = String(v ?? '');
    }
    return r;
  });

  return rows.map(r => ({
    hostSubmitter: {
      establishmentNameEN: batchDefaults.establishmentNameEN ?? '',
      establishmentNo:     '',
      emirate:             contactDefaults.uaeEmirate ?? 'Dubai',
      activity:            '',
      addressEN:           '',
      poBox:               '',
      email:               contactDefaults.email ?? '',
      mobileNumber:        contactDefaults.mobileNumber ?? '',
    },
    visit: {
      purposeOfVisit:      (batchDefaults.purposeOfVisit || 'Tourism') as 'Tourism',
      dateOfArrival:       batchDefaults.dateOfArrival ?? '',
      dateOfDeparture:     batchDefaults.dateOfDeparture ?? '',
      portOfEntry:         batchDefaults.portOfEntry ?? '',
      accommodationType:   batchDefaults.accommodationType ?? '',
      hotelOrPlaceOfStay:  batchDefaults.hotelOrPlaceOfStay ?? '',
    },
    passport: {
      passportType:            (r['Passport Type'] || 'Normal') as any,
      passportNumber:          r['Passport Number'] ?? '',
      currentNationality:      r['Current Nationality'] ?? '',
      previousNationality:     r['Previous Nationality'] ?? '',
      fullNameEN:              r['Full Name'] ?? '',
      firstName:               r['First Name'] ?? '',
      middleName:              r['Middle Name'] || undefined,
      lastName:                r['Last Name'] ?? '',
      dateOfBirth:             r['Date of Birth'] ?? '',
      birthCountry:            r['Birth Country'] ?? '',
      birthPlaceEN:            r['Birth Place'] ?? '',
      gender:                  (r['Gender'] || 'Male') as 'Male' | 'Female',
      passportIssueCountry:    r['Passport Issue Country'] ?? '',
      passportIssueDate:       r['Passport Issue Date'] ?? '',
      passportExpiryDate:      r['Passport Expiry Date'] ?? '',
      passportPlaceOfIssueEN:  r['Passport Place of Issue'] ?? '',
    },
    applicant: {
      isInsideUAE:         batchDefaults.isInsideUAE ?? false,
      motherNameEN:        r['Mother Name'] ?? '',
      maritalStatus:       (r['Marital Status'] || 'UNSPECIFIC') as any,
      relationshipToHost:  batchDefaults.relationshipToHost || 'Not Related',
      religion:            (r['Religion'] || 'UNKNOWN') as any,
      faith:               r['Faith'] ?? '',
      education:           r['Education'] ?? '',
      profession:          r['Profession'] ?? '',
      firstLanguage:       r['First Language'] ?? '',
      comingFromCountry:   r['Coming From Country'] ?? '',
    },
    contact: {
      email:                 contactDefaults.email ?? '',
      mobileNumber:          contactDefaults.mobileNumber ?? '',
      approvalEmailCopy:     '',
      preferredSMSLanguage:  (contactDefaults.preferredSMSLanguage || 'ENGLISH') as 'ENGLISH' | 'ARABIC',
      uaeEmirate:            contactDefaults.uaeEmirate || 'Dubai',
      uaeCity:               contactDefaults.uaeCity || 'Dubai',
      uaeArea:               contactDefaults.uaeArea || undefined,
      uaeStreet:             contactDefaults.uaeStreet || undefined,
      uaeBuilding:           contactDefaults.uaeBuilding || undefined,
      uaeFloor:              contactDefaults.uaeFloor || undefined,
      uaeFlat:               contactDefaults.uaeFlat || undefined,
      outsideCountry:        r['Outside Country'] || undefined,
      outsideMobile:         contactDefaults.outsideMobile || undefined,
      outsideCity:           r['Outside City'] || undefined,
      outsideAddress:        r['Outside Address'] || undefined,
    },
    documents: resolveDocuments(r['Documents Folder'] ?? ''),
  }));
}

/**
 * Resolves document file paths from a folder name.
 * The folder name (from the Excel "Documents Folder" column) is resolved
 * relative to data/documents/. E.g. "zambia" → data/documents/zambia/
 * Looks for files matching the portal's document type names.
 */
const DOCUMENTS_BASE = path.resolve('data/documents');

function resolveDocuments(folder: string): ApplicationDocuments {
  const empty: ApplicationDocuments = {
    sponsoredPassportPage1:   '',
    passportExternalCoverPage: '',
    personalPhoto:             '',
    hotelReservationPage1:     '',
    returnAirTicketPage1:      '',
  };

  if (!folder) return empty;

  const absFolder = path.join(DOCUMENTS_BASE, folder);
  if (!fs.existsSync(absFolder)) return empty;

  const files = fs.readdirSync(absFolder);

  const find = (pattern: string): string => {
    const match = files.find(f => f.toLowerCase().includes(pattern.toLowerCase()));
    return match ? path.join(absFolder, match) : '';
  };

  return {
    hotelReservationPage1:     find('Hotel reservation') && !find('Page 2') ? find('Hotel reservation') :
                                files.find(f => f.toLowerCase().includes('hotel reservation') && f.toLowerCase().includes('page 1'))
                                  ? path.join(absFolder, files.find(f => f.toLowerCase().includes('hotel reservation') && f.toLowerCase().includes('page 1'))!)
                                  : find('Hotel reservation'),
    hotelReservationPage2:     files.find(f => f.toLowerCase().includes('hotel reservation') && f.toLowerCase().includes('page 2'))
                                  ? path.join(absFolder, files.find(f => f.toLowerCase().includes('hotel reservation') && f.toLowerCase().includes('page 2'))!)
                                  : undefined,
    passportExternalCoverPage: find('Passport External Cover'),
    personalPhoto:             find('Personal Photo'),
    returnAirTicketPage1:      find('Return air ticket'),
    sponsoredPassportPage1:    find('Sponsored Passport'),
  };
}
