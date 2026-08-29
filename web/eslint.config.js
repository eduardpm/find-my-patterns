import js from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist', 'node_modules', 'coverage'] },
  {
    files: ['**/*.{ts,tsx}'],
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    languageOptions: {
      ecmaVersion: 2022,
      globals: { ...globals.browser, ...globals.node },
    },
    plugins: { 'react-hooks': reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      // FR-025: diary content must never be written anywhere that survives the tab. Catching this
      // at lint time is cheaper than catching it in the T066 privacy audit.
      'no-restricted-globals': [
        'error',
        {
          name: 'localStorage',
          message: 'FR-025 forbids persistent browser storage of diary content.',
        },
        {
          name: 'sessionStorage',
          message: 'FR-025 forbids persistent browser storage of diary content.',
        },
      ],
      'no-restricted-properties': [
        'error',
        {
          object: 'window',
          property: 'localStorage',
          message: 'FR-025 forbids persistent browser storage.',
        },
        {
          object: 'window',
          property: 'sessionStorage',
          message: 'FR-025 forbids persistent browser storage.',
        },
        {
          object: 'navigator',
          property: 'serviceWorker',
          message: 'FR-025/FR-020: no service worker.',
        },
      ],
    },
  },
  /*
   * The one file allowed to touch localStorage, and it is deliberately one file.
   *
   * FR-025 forbids persistent browser storage of *diary content* — "entry text, guided answers, or
   * feelings". `theme.ts` stores neither: it stores two enum values naming a palette and a
   * light/dark preference, which say nothing about what was written or felt and would tell an
   * attacker at the machine only that someone prefers a green page. research.md §5 states the
   * decision more broadly than the requirement ("no localStorage" full stop), which is why this
   * exception is written here rather than assumed — it is a narrowing of that decision to the
   * requirement behind it, not a quiet retreat from either.
   *
   * The exception is scoped to the file rather than left as inline disable comments so that the
   * complete list of places that may persist anything is readable in one place. Anything that
   * needs storage and is not appearance does not belong in `theme.ts`.
   */
  {
    files: ['src/theme.ts'],
    rules: {
      'no-restricted-globals': 'off',
      'no-restricted-properties': 'off',
    },
  },
);
