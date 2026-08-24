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
);
