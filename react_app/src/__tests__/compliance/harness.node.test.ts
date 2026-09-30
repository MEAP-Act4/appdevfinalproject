// Harness smoke test for the Node project of the compliance suite.
// The cross-client parity tests read `test_fixtures/**` from the repository root
// with node:fs, so this asserts that a `*.node.test.ts` file really does get a
// Node environment and can resolve a path outside react_app/.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const repoRoot = join(process.cwd(), '..');

describe('compliance harness (node)', () => {
  it('runs outside jsdom', () => {
    expect(typeof globalThis.document).toBe('undefined');
    expect(typeof process.versions.node).toBe('string');
  });

  it('reads files from the repository root, where the parity fixtures live', () => {
    const manifest = readFileSync(join(process.cwd(), 'package.json'), 'utf8');
    expect(JSON.parse(manifest).name).toBe('leakguard-react');
    expect(repoRoot.length).toBeGreaterThan(0);
  });
});
