/**
 * T007 — the highest-value test in this feature.
 *
 * SQLite has no date, boolean or JSON type; these columns hold text and integers in a specific
 * shape. Getting any of it wrong fails silently: nothing throws, the app appears to work, and the
 * diary quietly acquires two formats while an installed Android app parses timestamps that shifted.
 *
 * The shape itself is inherited rather than forced — see tests/TESTING.md for how much that is
 * actually worth. What matters here is that exactly one module owns it.
 *
 * See data-model.md "Value encoding" and research.md §1.
 */

import { describe, expect, it } from 'vitest';
import {
  decodeDate,
  decodeDateTime,
  decodeJson,
  decodeBool,
  encodeDate,
  encodeDateTime,
  encodeJson,
  encodeBool,
  serializeDateTime,
  nowUtc,
  todayLocal,
} from '../src/db/codecs';

// The wire and storage shape both clients are built against.
const STORED_DATETIME = '2026-07-28 12:33:49.248359';
const WIRE_DATETIME = '2026-07-28T12:33:49.248359';
const STORED_DATE = '2026-07-28';

describe('datetime storage encoding', () => {
  it('round-trips the exact stored format', () => {
    expect(encodeDateTime(decodeDateTime(STORED_DATETIME))).toBe(STORED_DATETIME);
  });

  it('uses a space separator, not the ISO "T"', () => {
    expect(encodeDateTime(decodeDateTime(STORED_DATETIME))).toContain(' ');
    expect(encodeDateTime(decodeDateTime(STORED_DATETIME))).not.toContain('T');
  });

  it('keeps six fractional digits, not three', () => {
    const encoded = encodeDateTime(decodeDateTime(STORED_DATETIME));
    expect(encoded.split('.')[1]).toHaveLength(6);
    expect(encoded).toMatch(/\.\d{6}$/);
  });

  it('preserves microsecond precision that a Date would truncate', () => {
    // The whole point: `new Date(...).toISOString()` loses the final three digits.
    const viaDate = new Date(STORED_DATETIME.replace(' ', 'T') + 'Z').toISOString();
    expect(viaDate).toContain('.248Z');
    expect(encodeDateTime(decodeDateTime(STORED_DATETIME))).toContain('.248359');
  });

  it('never appends a timezone designator', () => {
    const encoded = encodeDateTime(decodeDateTime(STORED_DATETIME));
    expect(encoded.endsWith('Z')).toBe(false);
    expect(encoded).not.toMatch(/[+-]\d{2}:\d{2}$/);
  });

  it('zero-pads a sub-millisecond fraction rather than dropping digits', () => {
    expect(encodeDateTime(decodeDateTime('2026-01-02 03:04:05.000007'))).toBe(
      '2026-01-02 03:04:05.000007',
    );
  });

  it('emits six digits even when the fraction is zero', () => {
    expect(encodeDateTime(decodeDateTime('2026-01-02 03:04:05.000000'))).toBe(
      '2026-01-02 03:04:05.000000',
    );
  });
});

describe('datetime wire serialization', () => {
  it('uses a "T" separator with microseconds and no zone', () => {
    expect(serializeDateTime(decodeDateTime(STORED_DATETIME))).toBe(WIRE_DATETIME);
  });

  it('does not produce the shape toISOString would', () => {
    const serialized = serializeDateTime(decodeDateTime(STORED_DATETIME));
    expect(serialized).not.toMatch(/Z$/);
    expect(serialized).not.toBe('2026-07-28T12:33:49.248Z');
  });
});

describe('date encoding', () => {
  it('stores and serializes a plain calendar date', () => {
    expect(encodeDate(decodeDate(STORED_DATE))).toBe(STORED_DATE);
  });

  it('does not widen a date into a datetime', () => {
    expect(encodeDate(decodeDate(STORED_DATE))).not.toContain(':');
  });
});

describe('JSON column encoding', () => {
  it('separates array items with ", " — a space after each comma', () => {
    expect(encodeJson(['ate', 'drank', 'coffee'])).toBe('["ate", "drank", "coffee"]');
  });

  it('does not produce the compact form JSON.stringify defaults to', () => {
    expect(encodeJson(['ate', 'drank'])).not.toBe('["ate","drank"]');
  });

  it('round-trips a captured value byte-for-byte', () => {
    const stored = '["ate", "drank", "food", "coffee", "coke"]';
    expect(encodeJson(decodeJson<string[]>(stored))).toBe(stored);
  });

  it('encodes an empty list as the stored literal', () => {
    expect(encodeJson([])).toBe('[]');
  });

  it('decodes into real values', () => {
    expect(decodeJson<string[]>('["ate", "drank"]')).toEqual(['ate', 'drank']);
  });

  // A regex over JSON.stringify output gets the first two of these wrong, which is why the
  // encoder walks the value instead.

  it('escapes non-ASCII as \\uXXXX rather than emitting it literally', () => {
    expect(encodeJson(['unicode: café'])).toBe('["unicode: caf\\u00e9"]');
  });

  it('does not emit non-ASCII literally the way JSON.stringify does', () => {
    expect(encodeJson(['café'])).not.toContain('é');
  });

  it('does not mistake a quoted comma inside a string for a separator', () => {
    expect(encodeJson(['a","b'])).toBe('["a\\",\\"b"]');
  });

  it('leaves an unquoted comma inside a string alone', () => {
    expect(encodeJson(['comma, inside'])).toBe('["comma, inside"]');
  });

  it('escapes embedded quotes', () => {
    expect(encodeJson(['has "quotes"'])).toBe('["has \\"quotes\\""]');
  });

  it('round-trips every case through decode', () => {
    for (const value of [['ate', 'drank'], [], ['a","b'], ['café'], ['comma, inside']]) {
      expect(decodeJson<string[]>(encodeJson(value))).toEqual(value);
    }
  });
});

describe('boolean encoding', () => {
  it('stores integers, not JS booleans', () => {
    expect(encodeBool(true)).toBe(1);
    expect(encodeBool(false)).toBe(0);
  });

  it('decodes SQLite integers back to booleans', () => {
    expect(decodeBool(1)).toBe(true);
    expect(decodeBool(0)).toBe(false);
  });
});

describe('clock sources', () => {
  it('nowUtc produces a storable value in the exact stored shape', () => {
    expect(encodeDateTime(nowUtc())).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}$/);
  });

  it('todayLocal produces a plain local calendar date', () => {
    // Deliberately the *local* date, not UTC — see research.md §3. Reproducing the existing
    // two-clock behaviour is required; unifying them would re-file existing entries.
    expect(encodeDate(todayLocal())).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    const now = new Date();
    const expected = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(
      now.getDate(),
    ).padStart(2, '0')}`;
    expect(encodeDate(todayLocal())).toBe(expected);
  });
});
