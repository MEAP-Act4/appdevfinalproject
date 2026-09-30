import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// Root of the compliance suite. Every test lives under here.
const SUITE = 'src/__tests__';

// Files named `*.node.test.ts` run in a Node environment, because they read the
// shared parity fixtures from disk with `node:fs`. Everything else runs in
// jsdom so the component, CSS and accessibility assertions have a DOM.
const NODE_TESTS = `${SUITE}/**/*.node.test.ts`;
const DOM_TESTS = [`${SUITE}/**/*.test.ts`, `${SUITE}/**/*.test.tsx`];

export default defineConfig({
  test: {
    projects: [
      {
        // Same plugin set as vite.config.ts, so module resolution and the JSX
        // transform match the production build exactly.
        plugins: [react()],
        test: {
          name: 'dom',
          environment: 'jsdom',
          include: DOM_TESTS,
          exclude: [NODE_TESTS],
        },
      },
      {
        test: {
          name: 'node',
          environment: 'node',
          include: [NODE_TESTS],
        },
      },
    ],
  },
});
