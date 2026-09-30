// Harness smoke test for the WattVision compliance suite (jsdom project).
// Proves the three things later tasks depend on: the runner executes, the DOM
// is available for the component/CSS assertions, and fast-check drives at least
// 100 generated cases per property.
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';

describe('compliance harness (dom)', () => {
  it('runs in a DOM environment', () => {
    const el = document.createElement('div');
    el.dataset.layout = 'compact';
    document.body.append(el);

    expect(document.body.querySelector('div')?.dataset.layout).toBe('compact');
    el.remove();
  });

  it('exposes computed styles, which the token assertions need', () => {
    const el = document.createElement('div');
    el.style.setProperty('--probe', '16px');
    document.body.append(el);

    expect(getComputedStyle(el).getPropertyValue('--probe').trim()).toBe('16px');
    el.remove();
  });

  it('runs fast-check properties over at least 100 cases', () => {
    let cases = 0;
    fc.assert(
      fc.property(fc.integer({ min: 320, max: 2560 }), (width) => {
        cases += 1;
        return Number.isInteger(width) && width >= 320 && width <= 2560;
      }),
      { numRuns: 100 },
    );

    expect(cases).toBeGreaterThanOrEqual(100);
  });
});
