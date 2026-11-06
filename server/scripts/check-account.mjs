/**
 * Refuses to deploy unless the Cloudflare account is pinned and matches.
 *
 * Without this, `wrangler deploy` against the wrong account does not fail — it
 * creates a second `tunetube-api` worker under that account, on a different
 * workers.dev subdomain, and reports success. The app keeps reading the old
 * URL, so a deploy appears to have shipped when nothing changed. The KV
 * binding would not resolve there either.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const toml = readFileSync(join(root, 'wrangler.toml'), 'utf8');

/** The subdomain in the app's productionBaseURL; the deploy must land here. */
const EXPECTED_SUBDOMAIN = 'tunetube-app';

const fail = (...lines) => {
  console.error('\n✘ Deploy blocked.\n');
  for (const line of lines) console.error('  ' + line);
  console.error('');
  process.exit(1);
};

// `account_id` must be a real 32-hex id, uncommented.
const pinned = toml.match(/^\s*account_id\s*=\s*"([0-9a-f]{32})"/m)?.[1];
if (!pinned) {
  fail(
    'No account_id is pinned in server/wrangler.toml.',
    '',
    'Find it with:   npx wrangler whoami',
    'Then add to wrangler.toml, above [vars]:',
    '',
    '    account_id = "<your 32-character account id>"',
    '',
    `It must be the account owning the "${EXPECTED_SUBDOMAIN}" workers.dev`,
    'subdomain and KV namespace 41bae203afdd463fa9abe75d330c2441 —',
    'any other account deploys to a URL the app does not read.',
  );
}

// If wrangler can see an account, it has to be that one.
let whoami = '';
try {
  whoami = execFileSync('npx', ['wrangler', 'whoami'], {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
} catch (error) {
  const output = `${error.stdout ?? ''}${error.stderr ?? ''}`;
  if (/not logged in/i.test(output)) {
    fail('Not logged in to Cloudflare.', '', 'Run:   npx wrangler login');
  }
  // Any other wrangler failure: let the real deploy surface it.
  console.warn('⚠️  Could not confirm the account; wrangler deploy will verify.');
  process.exit(0);
}

const seen = [...whoami.matchAll(/([0-9a-f]{32})/g)].map((m) => m[1]);
if (seen.length && !seen.includes(pinned)) {
  fail(
    `Logged-in account does not match the pinned account_id.`,
    '',
    `  pinned:    ${pinned}`,
    `  logged in: ${seen.join(', ')}`,
    '',
    'Switch accounts (npx wrangler logout && npx wrangler login),',
    'or correct account_id in wrangler.toml.',
  );
}

console.log(`✓ Cloudflare account ${pinned} confirmed.`);
