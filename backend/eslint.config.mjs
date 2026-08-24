import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist', 'node_modules', 'coverage', 'tests/fixtures'] },
  {
    files: ['**/*.ts', '**/*.mts'],
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.node },
    },
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
    },
  },
  {
    files: ['src/**/*.ts'],
    ignores: ['src/db/database.ts', 'src/db/schema.ts'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: 'Literal[value=/\\b(CREATE|ALTER|DROP)\\s+(TABLE|INDEX|VIEW|TRIGGER)\\b/i]',
          message:
            'FR-022: the backend must never issue DDL. The diary schema is adopted as-is and owned by nothing in this process.',
        },
      ],
    },
  },
);
