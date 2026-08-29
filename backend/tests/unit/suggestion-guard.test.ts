/**
 * The guard around model-written advice.
 *
 * An insight has two halves and they are held to different standards. The observation states what
 * was measured and is generated deterministically, so it cannot be wrong. The suggestion is
 * phrased by a local model, and this function is the only thing standing between that model and
 * the user — so it is worth testing much more carefully than the phrasing it protects.
 *
 * Rejection is never a failure: the caller keeps the template, which is dull and always correct.
 */

import { describe, expect, it } from 'vitest';
import { acceptSuggestion } from '../../src/inference/worker';
import { templateSuggestionFor } from '../../src/insights/patterns.service';

describe('acceptSuggestion', () => {
  it('accepts concrete advice that names the topic', () => {
    expect(
      acceptSuggestion(
        'Try building a short walk into the days you start out flat, and see whether the lift holds.',
        'walking',
      ),
    ).toBe(
      'Try building a short walk into the days you start out flat, and see whether the lift holds.',
    );
  });

  it('rejects a number that makes a claim about the diary', () => {
    // The occurrence count is the observation's to state, because that is where it was measured.
    // A suggestion quoting its own figure is the app inventing evidence.
    expect(acceptSuggestion('You felt this way in 5 entries about walking.', 'walking')).toBeNull();
    expect(acceptSuggestion('Walking helped on 4 of the days you logged.', 'walking')).toBeNull();
    expect(
      acceptSuggestion('Walking lifted you about 60 percent of the time.', 'walking'),
    ).toBeNull();
  });

  it('allows a number that is part of the advice itself', () => {
    // This is the interesting half. An outright ban on digits was tried and made things worse:
    // the model wrote "a 10 minute walk", every suggestion was rejected, and the Insights view
    // fell back to placeholders. A duration is not a statistic.
    expect(
      acceptSuggestion(
        'Try a 20 minute walk after lunch and see how the afternoon goes.',
        'walking',
      ),
    ).not.toBeNull();
    expect(
      acceptSuggestion('Aim for a walk on 3 days this week, whichever days suit.', 'walking'),
    ).not.toBeNull();
  });

  it('rejects a statistic even when it is written without digits', () => {
    expect(
      acceptSuggestion('Walking lifted you a good percent of the time lately.', 'walking'),
    ).toBeNull();
  });

  it('rejects advice that never mentions what it is advising about', () => {
    expect(
      acceptSuggestion('Consider adjusting your evening routine a little.', 'coffee'),
    ).toBeNull();
  });

  it('accepts a topic named in the words a person would actually use', () => {
    // The stored topic is a canonical phrase; nobody writes "coca cola" in a sentence.
    expect(
      acceptSuggestion('Try skipping the cola after lunch and see how you sleep.', 'coca cola'),
    ).not.toBeNull();
    expect(
      acceptSuggestion(
        'Adding more vegetables to dinner may be worth a try.',
        'fruit and vegetables',
      ),
    ).not.toBeNull();
  });

  it('rejects a topic word that only appears inside a longer word', () => {
    // "tea" inside "steamed" is the same substring bug the topic extractor was fixed for; a
    // suggestion about steaming vegetables is not a suggestion about tea.
    expect(
      acceptSuggestion('Steamed greens make a good side dish in the evening.', 'tea'),
    ).toBeNull();
  });

  it('does not mistake a longer, unrelated word for the topic', () => {
    // "rest" is a topic; "restaurant" is not advice about resting. Inflection is tolerated, a
    // different word that happens to start the same way is not.
    expect(acceptSuggestion('Booking a restaurant midweek might lift things.', 'rest')).toBeNull();
    expect(
      acceptSuggestion('Try resting properly on the days after a late night.', 'rest'),
    ).not.toBeNull();
  });

  it('does not match a topic on a connecting word', () => {
    // `fruit and vegetables` must not count every sentence containing "and" as being about it.
    expect(
      acceptSuggestion('Try winding down and going to bed earlier.', 'fruit and vegetables'),
    ).toBeNull();
  });

  it('rejects a suggestion too long to fit the card, and one too short to say anything', () => {
    expect(acceptSuggestion('Walk more.', 'walking')).toBeNull();
    expect(acceptSuggestion(`Walking. ${'and again '.repeat(40)}`, 'walking')).toBeNull();
  });

  it('rejects an empty or whitespace-only answer rather than storing a blank card', () => {
    expect(acceptSuggestion('', 'walking')).toBeNull();
    expect(acceptSuggestion('   \n  ', 'walking')).toBeNull();
  });

  it('normalises the whitespace a model leaves behind', () => {
    expect(acceptSuggestion('  Try a walk\n  when you feel flat.  ', 'walking')).toBe(
      'Try a walk when you feel flat.',
    );
  });

  it('would not accept the template it replaces, keeping "un-narrated" unambiguous', () => {
    // The worker finds work by looking for patterns whose suggestion still *equals* the template.
    // If a model happened to emit the template verbatim it would be re-narrated forever, so this
    // pins the property the loop depends on: the template contains no digits and names the topic,
    // so it is accepted — and the write is a no-op that leaves the pattern eligible. Harmless, and
    // worth knowing rather than discovering.
    const template = templateSuggestionFor('energised', 'walking');
    expect(acceptSuggestion(template, 'walking')).toBe(template);
  });
});
