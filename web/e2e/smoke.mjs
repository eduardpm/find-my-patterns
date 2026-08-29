import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const baseUrl = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:18080';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
page.setDefaultTimeout(7_000);
const errors = [];
const runId = Date.now();
const originalEntry = `Playwright check ${runId}: a calm tea break after finishing focused work.`;
const editedEntry = `Playwright check ${runId}: edited text remains protected before navigation.`;
page.on('console', (message) => {
  if (message.type() === 'error') errors.push(message.text());
});
page.on('pageerror', (error) => errors.push(error.message));

try {
  if (process.env.E2E_AUTH_EMAIL && process.env.E2E_AUTH_PASSWORD) {
    console.log('0/7 sign in');
    await page.goto(`${baseUrl}/app/today`, { waitUntil: 'networkidle' });
    await page.getByLabel('Email').fill(process.env.E2E_AUTH_EMAIL);
    await page.getByLabel('Password').fill(process.env.E2E_AUTH_PASSWORD);
    await page.getByRole('button', { name: 'Sign in' }).click();
  }

  console.log('1/7 load Today');
  await page.goto(`${baseUrl}/app/today`, { waitUntil: 'networkidle' });
  await page.getByRole('heading', { name: 'Today' }).waitFor();
  await page.screenshot({ path: '/tmp/diary-today.png', fullPage: true });

  console.log('2/7 create and verify unsaved guard');
  // Scoped to the page header: on a day with nothing written yet the empty state offers the same
  // link, and an unscoped lookup is ambiguous on exactly the diaries a fresh test run creates.
  await page.locator('header').getByRole('link', { name: 'Write an entry' }).click();
  await page.waitForURL(/\/app\/new$/);
  await page.getByRole('button', { name: 'Skip the questions and just write' }).click();
  const editor = page.getByLabel('Your diary entry');
  await editor.fill(originalEntry);

  page.once('dialog', async (dialog) => {
    assert.match(dialog.message(), /unsaved writing/i);
    await dialog.dismiss();
  });
  await page.getByRole('link', { name: 'Insights' }).click({ noWaitAfter: true });
  assert.match(page.url(), /\/app\/new$/);

  await page.getByRole('button', { name: 'Save' }).click();
  await page.getByRole('heading', { name: 'How did that feel?' }).waitFor();

  /*
   * The picker is group-first: the vocabulary is past thirty words, so the page shows the four
   * groups and opens one group's feelings in a dialog on demand. Picking a feeling is therefore
   * three acts — open the group, check the feeling, close the dialog — not one click on a chip.
   */
  await page.getByRole('button', { name: 'Uplifted' }).click();
  const groupDialog = page.getByRole('dialog', { name: 'Uplifted' });
  await groupDialog.waitFor();
  /*
   * Clicked through the wrapping label, not by driving the input.
   *
   * The real checkbox is `visually-hidden` — clipped to a pixel with the chip's own dot painted
   * over it — so `.check()` cannot reach it and would need `force`, which would assert that a
   * control nobody can see responds to a synthetic click. The label is what a pointer, a tap and
   * the keyboard all actually land on.
   *
   * `/^Happy/` rather than an exact string: a feeling the local analysis suggested carries a
   * "suggested" hint inside the same label, and whether it does is not this journey's business.
   */
  const happyChip = groupDialog.locator('label.chip').filter({ hasText: /^Happy/ });
  await happyChip.click();
  assert.equal(
    await happyChip.getByRole('checkbox').isChecked(),
    true,
    'Happy should be checked after clicking its chip',
  );
  await groupDialog.getByRole('button', { name: 'Close Uplifted' }).click();
  await groupDialog.waitFor({ state: 'hidden' });

  // The chosen row is the only place the answer stays visible once the dialog is gone, so it is
  // what proves the pick registered rather than merely that a box was ticked.
  await page.getByRole('button', { name: /^Remove Happy/ }).waitFor();

  await page.getByRole('button', { name: 'Done' }).click();
  await page.getByText(originalEntry).waitFor();

  console.log('3/7 edit and verify Cancel guard');
  await page.getByText(originalEntry).click();
  const detailEditor = page.getByLabel('Entry text');
  await detailEditor.fill(editedEntry);
  page.once('dialog', async (dialog) => dialog.dismiss());
  await page.getByRole('button', { name: 'Cancel' }).click();
  assert.match(page.url(), /\/app\/entry\//);
  await page.getByRole('button', { name: 'Save changes' }).click();
  await page.getByText(editedEntry).waitFor();

  console.log('4/7 calendar');
  await page.getByRole('link', { name: 'Calendar' }).click();
  await page.getByRole('heading', { name: 'Monthly overview' }).waitFor();
  assert.equal(await page.evaluate(() => window.scrollY), 0);
  await page.screenshot({ path: '/tmp/diary-calendar.png', fullPage: true });

  console.log('5/7 insights');
  await page.getByRole('link', { name: 'Insights' }).click();
  await page.getByRole('heading', { name: 'Insights' }).waitFor();
  await page.getByRole('button', { name: 'Refresh insights' }).click();

  console.log('6/7 responsive view and browser errors');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('link', { name: 'Today' }).click();
  await page.getByText(editedEntry).waitFor();
  await page.screenshot({ path: '/tmp/diary-mobile.png', fullPage: true });
  const navBox = await page.getByRole('navigation', { name: 'Main' }).boundingBox();
  assert(navBox && navBox.width <= 390 && navBox.y <= 2, 'mobile navigation should remain visible');

  if (process.env.E2E_AUTH_EMAIL) {
    console.log('7/7 sign out and verify protection');
    await page.getByRole('button', { name: 'Sign out' }).click();
    await page.getByText('You have been signed out.').waitFor();
    await page.screenshot({ path: '/tmp/diary-login.png', fullPage: true });
    await page.goto(`${baseUrl}/app/today`);
    await page.getByRole('heading', { name: 'Welcome back' }).waitFor();
  }

  assert.deepEqual(errors, [], `Browser errors: ${errors.join('\n')}`);
  console.log(
    'Playwright smoke journey passed: create, guard, confirm, edit, calendar, insights, responsive UI.',
  );
} catch (error) {
  console.error(`Failure at ${page.url()}`);
  console.error(`Browser errors: ${errors.join('\n')}`);
  await page.screenshot({ path: '/tmp/diary-e2e-failure.png', fullPage: true });
  throw error;
} finally {
  await browser.close();
}
