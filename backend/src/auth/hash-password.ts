import { hashPassword } from './password';

async function main(): Promise<void> {
  const password = process.env.DIARY_AUTH_PASSWORD;
  if (!password) {
    throw new Error(
      'Set DIARY_AUTH_PASSWORD for this one command (for example with `read -s`) and run again.',
    );
  }
  process.stdout.write(`${await hashPassword(password)}\n`);
}

void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
