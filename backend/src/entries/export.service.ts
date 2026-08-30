import { Injectable } from '@nestjs/common';
import type { NaiveDateTime } from '../db/codecs';
import { serializeDate, serializeDateTime } from '../db/codecs';
import type { DiaryEntry, GuidedAnswer, PairingSource, TopicFeelingPairing } from '../domain/types';
import type { Topic } from '../topics/topics.service';
import { EntriesRepository, FeelingsRepository } from './entries.repository';

/**
 * Bumped whenever a field is added, renamed or removed from the JSON export — never for a change
 * that only touches Markdown, which has no consumer that parses it. The Daylio-import ticket (L-1b)
 * this export exists to feed reads this field before it reads anything else.
 */
export const EXPORT_SCHEMA_VERSION = 1;

export interface ExportedGuidedAnswer {
  question_key: string;
  question_text: string;
  answer_text: string;
  order_index: number;
}

export interface ExportedFeeling {
  key: string;
  /**
   * `diary_entries.feeling_source` — one value for the whole entry, repeated on every feeling in
   * this array. There is no per-feeling provenance stored (`docs/export.md` "Feelings").
   */
  source: string;
  intensity: number | null;
}

export interface ExportedTopic {
  /** The topic's canonical name (`topics.name`). */
  topic: string;
  /**
   * The wording actually written in the entry. Not distinctly stored — `entry_topics` records only
   * which canonical topic a mention resolved to, not the phrase that matched — so this repeats
   * `topic` until that is tracked (`docs/export.md` "Topics").
   */
  surface_form: string;
}

export interface ExportedTopicFeeling {
  topic_id: string;
  topic: string;
  feeling_key: string;
  source: PairingSource;
}

export interface ExportedEntry {
  id: string;
  date: string;
  created_at: string;
  mode: DiaryEntry['mode'];
  raw_text: string;
  guided_answers: ExportedGuidedAnswer[];
  feelings: ExportedFeeling[];
  topics: ExportedTopic[];
  topic_feelings: ExportedTopicFeeling[];
}

export interface ExportDocument {
  schema_version: number;
  entries: ExportedEntry[];
}

/** Everything read out of storage for one entry, before either wire shape is built from it. */
interface EntryBundle {
  entry: DiaryEntry;
  guidedAnswers: GuidedAnswer[];
  topics: Topic[];
  topicFeelings: TopicFeelingPairing[];
}

/**
 * Builds the whole-diary export (M-6): the same data every other read endpoint serves, gathered
 * entry by entry and rendered into the two formats a person can carry the diary in. Both formats
 * are built from one query pass — [bundles] — so a JSON export and a Markdown export of the same
 * diary state can never disagree about which entries exist or what is on them.
 *
 * Deterministic by construction: [EntriesRepository.findAll] orders by `created_at` (acceptance
 * criterion 2), every child read is itself ordered (`findGuidedAnswers` by `order_index`,
 * `findTopics` and `findTopicFeelingPairings` by name), and neither format ever serializes a
 * `Record`/map whose key order could vary — feelings, topics and pairings are all built as arrays.
 * A field derived from the wall clock (a "generated at" timestamp) is deliberately never added to
 * either output for the same reason: two exports run back to back over an unchanged diary must be
 * byte-identical.
 */
@Injectable()
export class ExportService {
  constructor(
    private readonly entries: EntriesRepository,
    private readonly feelings: FeelingsRepository,
  ) {}

  toJson(userId: string): ExportDocument {
    return {
      schema_version: EXPORT_SCHEMA_VERSION,
      entries: this.bundles(userId).map(toJsonEntry),
    };
  }

  toMarkdown(userId: string): string {
    const labelFor = this.feelingLabelLookup();
    const sections = this.bundles(userId).map((bundle) => renderMarkdownEntry(bundle, labelFor));
    // A trailing newline, same as every other text file in the repo — not for a reader browsing
    // rendered Markdown, but so a diff or a byte-for-byte determinism check never trips on a
    // missing EOF newline that has nothing to do with diary content.
    return sections.length > 0 ? `${sections.join('\n\n')}\n` : '';
  }

  private bundles(userId: string): EntryBundle[] {
    return this.entries.findAll(userId).map((entry) => ({
      entry,
      guidedAnswers: this.entries.findGuidedAnswers(userId, entry.id),
      topics: this.entries.findTopics(userId, entry.id),
      topicFeelings: this.entries.findTopicFeelingPairings(userId, entry.id),
    }));
  }

  private feelingLabelLookup(): (key: string) => string {
    const labels = new Map(this.feelings.findAll().map((f) => [f.key, f.label]));
    return (key: string) => labels.get(key) ?? key;
  }
}

function toJsonEntry(bundle: EntryBundle): ExportedEntry {
  const { entry } = bundle;
  return {
    id: entry.id,
    date: serializeDate(entry.entryDate),
    created_at: serializeDateTime(entry.createdAt),
    mode: entry.mode,
    raw_text: entry.rawText,
    guided_answers: bundle.guidedAnswers.map((answer) => ({
      question_key: answer.questionKey,
      question_text: answer.questionTextSnapshot,
      answer_text: answer.answerText,
      order_index: answer.orderIndex,
    })),
    feelings: entry.feelingKeys.map((key) => ({
      key,
      source: entry.feelingSource,
      intensity: entry.feelingIntensities[key] ?? null,
    })),
    topics: bundle.topics.map((topic) => ({ topic: topic.name, surface_form: topic.name })),
    topic_feelings: bundle.topicFeelings.map((pairing) => ({
      topic_id: pairing.topicId,
      topic: pairing.topic,
      feeling_key: pairing.feelingKey,
      source: pairing.source,
    })),
  };
}

function renderMarkdownEntry(bundle: EntryBundle, labelFor: (key: string) => string): string {
  const { entry } = bundle;
  const heading = `## ${serializeDate(entry.entryDate)} — ${formatClockTime(entry.createdAt)}`;

  const body =
    bundle.guidedAnswers.length > 0
      ? bundle.guidedAnswers
          .map((answer) => `**${answer.questionTextSnapshot}**\n${answer.answerText}`)
          .join('\n\n')
      : entry.rawText;

  const parts = [heading, body];
  const feelingsLine = renderFeelingsLine(entry.feelingKeys, entry, labelFor);
  if (feelingsLine) parts.push(feelingsLine);
  const topicsLine = renderTopicsLine(bundle.topics);
  if (topicsLine) parts.push(topicsLine);
  return parts.join('\n\n');
}

function renderFeelingsLine(
  keys: string[],
  entry: DiaryEntry,
  labelFor: (key: string) => string,
): string | null {
  if (keys.length === 0) return null;
  const parts = keys.map((key) => {
    const intensity = entry.feelingIntensities[key];
    const detail =
      intensity != null ? `${intensity}/5, ${entry.feelingSource}` : entry.feelingSource;
    return `${labelFor(key)} (${detail})`;
  });
  return `Feelings: ${parts.join(' · ')}`;
}

function renderTopicsLine(topics: Topic[]): string | null {
  if (topics.length === 0) return null;
  return `Topics: ${topics.map((topic) => topic.name).join(', ')}`;
}

/** `h:mm AM/PM`, no leading zero on the hour — the `11:11 PM` shape the issue's example uses. */
function formatClockTime(dt: NaiveDateTime): string {
  const period = dt.hour >= 12 ? 'PM' : 'AM';
  const hour12 = dt.hour % 12 === 0 ? 12 : dt.hour % 12;
  const minute = String(dt.minute).padStart(2, '0');
  return `${hour12}:${minute} ${period}`;
}
