import { useEffect, useRef, useState } from 'react';

/**
 * Eases a number towards its target over `duration` using requestAnimationFrame.
 *
 * Why not a CSS transition: the value is text, not a style, so the interpolation
 * has to happen in JS. Keeping it in one hook means every metric in the app
 * animates identically and the reduce-motion escape hatch lives in one place.
 */
export function useAnimatedNumber(
  target: number,
  options: { duration?: number; disabled?: boolean } = {},
): number {
  const { duration = 320, disabled = false } = options;
  const [value, setValue] = useState(target);
  const frameRef = useRef<number | null>(null);
  const fromRef = useRef(target);
  const startRef = useRef(0);

  useEffect(() => {
    if (disabled || !Number.isFinite(target)) {
      setValue(Number.isFinite(target) ? target : 0);
      return;
    }

    fromRef.current = value;
    startRef.current = performance.now();

    const tick = (now: number) => {
      const elapsed = now - startRef.current;
      const t = Math.min(elapsed / duration, 1);
      // easeOutQuart — settles without overshooting, which matters for a readout
      // that must never display a value the sensor did not report.
      const eased = 1 - Math.pow(1 - t, 4);
      setValue(fromRef.current + (target - fromRef.current) * eased);
      if (t < 1) {
        frameRef.current = requestAnimationFrame(tick);
      } else {
        frameRef.current = null;
      }
    };

    frameRef.current = requestAnimationFrame(tick);
    return () => {
      if (frameRef.current !== null) cancelAnimationFrame(frameRef.current);
    };
    // `value` is deliberately excluded: including it would restart the tween on
    // every frame it sets.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target, duration, disabled]);

  return disabled ? target : value;
}
