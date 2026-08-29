/**
 * The Daylio CSV parser (L-1b, #35), pure and DB-free.
 *
 * Column layout and quoting are verified against a real export file — see
 * `../../src/import/daylio-mood-map.ts`'s doc comment for sources — not invented, so these tests
 * lean on realistic rows (`tests/fixtures/daylio-sample.csv`) as well as synthetic ones for the
 * edge cases the acceptance criteria name explicitly: quoted commas, empty activities, midnight.
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  DAYLIO_CSV_HEADER,
  DaylioCsvFormatError,
  interpretDaylioRow,
  parseDaylioCsv,
} from '../../src/import/daylio-csv-parser';

const FIXTURE = path.resolve(__dirname, '../fixtures/daylio-sample.csv');

function csv(rows: string[]): string {
  return [DAYLIO_CSV_HEADER.join(','), ...rows].join('\n');
}

describe('parseDaylioCsv — structure', () => {
  it('rejects an empty file', () => {
    expect(() => parseDaylioCsv('')).toThrow(DaylioCsvFormatError);
  });

  it('rejects a file with the wrong column layout', () => {
    expect(() => parseDaylioCsv('date,mood\n2026-01-01,good\n')).toThrow(DaylioCsvFormatError);
  });

  it('rejects a header matching by name but not by order', () => {
    const reordered = [...DAYLIO_CSV_HEADER].reverse().join(',');
    expect(() => parseDaylioCsv(`${reordered}\n`)).toThrow(DaylioCsvFormatError);
  });

  it('accepts a header regardless of case', () => {
    const header = DAYLIO_CSV_HEADER.map((c) => c.toUpperCase()).join(',');
    const rows = parseDaylioCsv(
      `${header}\n2026-07-01,1 July,Wednesday,9:15 am,rad,"coffee","",""\n`,
    );
    expect(rows).toHaveLength(1);
  });

  it('rejects a data row with the wrong number of columns', () => {
    expect(() =>
      parseDaylioCsv(csv(['2026-07-01,1 July,Wednesday,9:15 am,rad,"coffee",""'])),
    ).toThrow(DaylioCsvFormatError);
  });

  it('drops a wholly blank trailing line rather than reporting a bogus row', () => {
    const rows = parseDaylioCsv(
      `${DAYLIO_CSV_HEADER.join(',')}\n2026-07-01,1 July,Wednesday,9:15 am,rad,"coffee","",""\n\n`,
    );
    expect(rows).toHaveLength(1);
  });

  it('strips a leading UTF-8 BOM', () => {
    const withBom = `\uFEFF${DAYLIO_CSV_HEADER.join(',')}\n2026-07-01,1 July,Wednesday,9:15 am,rad,"coffee","",""\n`;
    const rows = parseDaylioCsv(withBom);
    expect(rows).toHaveLength(1);
    expect(rows[0].mood).toBe('rad');
  });
});

describe('parseDaylioCsv — quoting', () => {
  it('reads a quoted field containing a comma', () => {
    const rows = parseDaylioCsv(
      csv([
        '2026-07-01,1 July,Wednesday,9:15 am,good,"coffee","","Cooked dinner, played music, a calm evening."',
      ]),
    );
    expect(rows[0].note).toBe('Cooked dinner, played music, a calm evening.');
  });

  it('reads a doubled quote as one literal quote', () => {
    const rows = parseDaylioCsv(
      csv(['2026-07-01,1 July,Wednesday,9:15 am,good,"coffee","","She said ""hi"" to me."']),
    );
    expect(rows[0].note).toBe('She said "hi" to me.');
  });

  it('reads an embedded newline inside a quoted field', () => {
    const rows = parseDaylioCsv(
      csv(['2026-07-01,1 July,Wednesday,9:15 am,good,"coffee","","First line.\nSecond line."']),
    );
    expect(rows[0].note).toBe('First line.\nSecond line.');
  });

  it('reads empty quoted fields as empty strings', () => {
    const rows = parseDaylioCsv(csv(['2026-07-01,1 July,Wednesday,9:15 am,good,"","",""']));
    expect(rows[0].activities).toBe('');
    expect(rows[0].noteTitle).toBe('');
    expect(rows[0].note).toBe('');
  });
});

describe('interpretDaylioRow', () => {
  const base = {
    rowNumber: 1,
    fullDate: '2026-07-05',
    time: '12:00 am',
    mood: 'bad',
    activities: 'work | overtime',
    noteTitle: '',
    note: 'Long day.',
  };

  it('parses full_date as the entry date', () => {
    const parsed = interpretDaylioRow(base);
    expect(parsed.entryDate).toEqual({ year: 2026, month: 7, day: 5 });
  });

  it('reads midnight ("12:00 am") as hour 0', () => {
    const parsed = interpretDaylioRow({ ...base, time: '12:00 am' });
    expect(parsed.createdAt).toMatchObject({ hour: 0, minute: 0 });
  });

  it('reads noon ("12:00 pm") as hour 12', () => {
    const parsed = interpretDaylioRow({ ...base, time: '12:00 pm' });
    expect(parsed.createdAt).toMatchObject({ hour: 12, minute: 0 });
  });

  it('reads an ordinary pm time by adding 12', () => {
    const parsed = interpretDaylioRow({ ...base, time: '9:45 pm' });
    expect(parsed.createdAt).toMatchObject({ hour: 21, minute: 45 });
  });

  it('reads an ordinary am time unchanged', () => {
    const parsed = interpretDaylioRow({ ...base, time: '8:30 am' });
    expect(parsed.createdAt).toMatchObject({ hour: 8, minute: 30 });
  });

  it('is case-insensitive on am/pm', () => {
    const parsed = interpretDaylioRow({ ...base, time: '9:45 PM' });
    expect(parsed.createdAt).toMatchObject({ hour: 21, minute: 45 });
  });

  it('splits, trims and drops empty activities', () => {
    const parsed = interpretDaylioRow({ ...base, activities: ' work  |  overtime | ' });
    expect(parsed.activities).toEqual(['work', 'overtime']);
  });

  it('reads a wholly empty activities field as no activities', () => {
    const parsed = interpretDaylioRow({ ...base, activities: '' });
    expect(parsed.activities).toEqual([]);
  });

  it('trims mood, note_title and note', () => {
    const parsed = interpretDaylioRow({
      ...base,
      mood: ' bad ',
      noteTitle: ' Deadline day ',
      note: ' Long day. ',
    });
    expect(parsed.moodRaw).toBe(' bad '); // trimming for mapping happens in daylio-mood-map.ts
    expect(parsed.noteTitle).toBe('Deadline day');
    expect(parsed.note).toBe('Long day.');
  });

  it('rejects an unparseable date', () => {
    expect(() => interpretDaylioRow({ ...base, fullDate: '07/05/2026' })).toThrow();
  });

  it('rejects a date that does not exist on the calendar', () => {
    expect(() => interpretDaylioRow({ ...base, fullDate: '2026-02-30' })).toThrow();
  });

  it('rejects an unparseable time', () => {
    expect(() => interpretDaylioRow({ ...base, time: '25:00' })).toThrow();
  });

  it('rejects an out-of-range time', () => {
    expect(() => interpretDaylioRow({ ...base, time: '13:00 pm' })).toThrow();
  });
});

describe('the bundled fixture', () => {
  const text = fs.readFileSync(FIXTURE, 'utf-8');

  it('parses as 17 rows with the documented layout', () => {
    const rows = parseDaylioCsv(text);
    expect(rows).toHaveLength(17);
    expect(rows.every((r) => r.rowNumber >= 1 && r.rowNumber <= 17)).toBe(true);
  });

  it('every row interprets cleanly (no parser edge case defeats the fixture)', () => {
    const rows = parseDaylioCsv(text);
    for (const row of rows) {
      expect(() => interpretDaylioRow(row)).not.toThrow();
    }
  });

  it('contains the midnight, noon, embedded-comma and empty-activities cases the README promises', () => {
    const rows = parseDaylioCsv(text).map(interpretDaylioRow);
    expect(rows.some((r) => r.createdAt.hour === 0 && r.createdAt.minute === 0)).toBe(true);
    expect(rows.some((r) => r.createdAt.hour === 12 && r.createdAt.minute === 0)).toBe(true);
    expect(rows.some((r) => r.note.includes(','))).toBe(true);
    expect(rows.some((r) => r.activities.length === 0)).toBe(true);
  });
});
