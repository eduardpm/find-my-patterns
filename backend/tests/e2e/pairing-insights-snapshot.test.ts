/**
 * E-1a acceptance criterion: "No change to insights output (snapshot the payload before/after)."
 *
 * Task 4's determinism guard: pairing suggestions are proposals, and nothing in this ticket may
 * change any pattern computation — that is E-1b's job, not this one's. This snapshots `GET
 * /insights` against the golden fixture, writes a confirmed pairing through the real write
 * endpoint on one of its patterned entries, and asserts the second snapshot is byte-for-byte the
 * first (`last_updated_at`/`withdrawn_at` and friends included — a real, not merely
 * structural, comparison).
 */

import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bootOnCopy, teardown, type Harness } from '../helpers/app';

let h: Harness;
const server = () => h.app.getHttpServer();

beforeEach(async () => {
  h = await bootOnCopy();
});
afterEach(async () => {
  await teardown(h);
});

// One of the golden fixture's "coca cola … sleepy" entries — part of the materialised pattern the
// engine already reports on, and linked to a topic (see `tests/fixtures/README.md`). Pairing
// *this* entry's own topic and feeling is the strictest version of the test: if a pairing write
// were ever allowed to leak into counting, this is exactly the row that would move a number.
const PATTERNED_ENTRY_ID = '6fd3f393-704e-44ee-a41b-6a975d9a09c7';
const PATTERNED_TOPIC_ID = '4680a43c-c0c9-4a81-8710-377e5cbeca09';
const PATTERNED_FEELING_KEY = 'sleepy';

describe('a confirmed pairing changes nothing about /insights (E-1a determinism guard)', () => {
  it('leaves the insights payload identical before and after', async () => {
    const before = await request(server()).get('/insights').expect(200);

    await request(server())
      .put(`/entries/${PATTERNED_ENTRY_ID}/topic-feelings`)
      .send({ pairings: [{ topic_id: PATTERNED_TOPIC_ID, feeling_key: PATTERNED_FEELING_KEY }] })
      .expect(200);

    const after = await request(server()).get('/insights').expect(200);

    expect(after.body).toEqual(before.body);
  });

  it('leaves the entry read payload identical apart from the new topic_feelings field', async () => {
    const before = await request(server()).get(`/entries/${PATTERNED_ENTRY_ID}`).expect(200);
    expect(before.body.topic_feelings).toEqual([]);

    await request(server())
      .put(`/entries/${PATTERNED_ENTRY_ID}/topic-feelings`)
      .send({ pairings: [{ topic_id: PATTERNED_TOPIC_ID, feeling_key: PATTERNED_FEELING_KEY }] })
      .expect(200);

    const after = await request(server()).get(`/entries/${PATTERNED_ENTRY_ID}`).expect(200);

    const withoutTopicFeelings = (entry: Record<string, unknown>): Record<string, unknown> => {
      const { topic_feelings, ...rest } = entry;
      void topic_feelings; // only the rest of the payload is compared below
      return rest;
    };
    expect(withoutTopicFeelings(after.body as Record<string, unknown>)).toEqual(
      withoutTopicFeelings(before.body as Record<string, unknown>),
    );
    expect((after.body as { topic_feelings: unknown }).topic_feelings).toEqual([
      {
        topic_id: PATTERNED_TOPIC_ID,
        topic: 'coca cola',
        feeling_key: PATTERNED_FEELING_KEY,
        source: 'overridden',
      },
    ]);
  });
});
