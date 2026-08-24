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

describe('POST /transcriptions', () => {
  it('requires an audio content type', async () => {
    const response = await request(server())
      .post('/transcriptions')
      .set('Content-Type', 'application/octet-stream')
      .send(Buffer.from('not audio'))
      .expect(415);

    expect(response.body.error.message).toContain('audio content type');
    expect(response.headers['cache-control']).toBe('no-store');
  });

  it('rejects an empty recording before invoking speech-to-text', async () => {
    const response = await request(server())
      .post('/transcriptions')
      .set('Content-Type', 'audio/webm')
      .send(Buffer.alloc(0))
      .expect(422);

    expect(response.body.error.message).toContain('empty');
  });

  it('returns 404 for an expired or unknown transcription job', async () => {
    await request(server()).get('/transcriptions/not-a-job').expect(404);
  });
});
