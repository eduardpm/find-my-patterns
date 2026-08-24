import type { Provider } from '@nestjs/common';
import { loadConfig } from '../config';
import { assertCompatible } from './compatibility';
import { openDiary, type DiaryDatabase } from './database';
import { seed } from './seed';

export const DIARY_DB = Symbol('DIARY_DB');

/**
 * Opens the diary once for the process lifetime.
 *
 * Order matters: open, verify the schema can be fully interpreted (FR-018), only then seed — and
 * the seed is a no-op on a populated diary (FR-022). A file that cannot be interpreted is never
 * written to at all.
 */
export function createDiaryProvider(databasePath?: string): Provider {
  return {
    provide: DIARY_DB,
    useFactory: (): DiaryDatabase => {
      const path = databasePath ?? loadConfig().databasePath;
      const db = openDiary(path);
      assertCompatible(db);
      seed(db);
      return db;
    },
  };
}
