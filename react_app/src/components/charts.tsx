import { useId } from 'react';

import { useSettings } from '../state/settingsStore';

/** Shared knobs for both the single- and multi-series forms of {@link Sparkline}. */
interface SparklineBaseProps {
  height?: number;
  gridDivisions?: number;
  minRange?: number;
}

/**
 * Single-series form. Kept as an overload over the multi-series body so the
 * existing `values`/`color` call sites (e.g. the channel SensorPage) stay
 * untouched — internally it wraps into single-element `series`/`colors` arrays.
 */
interface SparklineSingleProps extends SparklineBaseProps {
  values: number[];
  color?: string;
  series?: undefined;
  colors?: undefined;
}

/** Multi-series form: one entry per plotted channel, drawn in order. */
interface SparklineMultiProps extends SparklineBaseProps {
  series: number[][];
  colors?: string[];
  values?: undefined;
  color?: undefined;
}

type SparklineProps = SparklineSingleProps | SparklineMultiProps;

/**
 * Area sparkline, hand-rolled in SVG.
 *
 * DESIGN.md §3/§6: grid lines in `--border`, data stroke in the accent, area
 * gradient blending the accent into `--gradient-green`, no heavy borders, and area
 * charts preferred so spikes read as shape rather than noise.
 *
 * No chart library: the whole thing is one path plus a gradient per series, and
 * owning the markup means the tokens apply directly with no theme adapter.
 *
 * Accepts either the single-series (`values`/`color`) or multi-series
 * (`series`/`colors`) form; the single form simply wraps into single-element
 * arrays, so both paths share one renderer. Mirror of the Flutter
 * `FlowSparkline` / `FlowSparkline.multi` pair.
 */
export function Sparkline(props: SparklineProps) {
  const { height = 104, gridDivisions = 3, minRange = 0.5 } = props;

  // Normalise both call forms onto arrays. `color` defaults to the accent token
  // to match the previous single-series default; missing per-series colours in
  // the multi form fall back to the same token.
  const series: number[][] = props.series ?? [props.values];
  const colors: string[] =
    props.colors ??
    (props.series ? [] : [props.color ?? 'var(--accent)']);

  const gradientId = useId();

  // Fixed viewBox with non-uniform scaling: the chart always stretches to the
  // card width, so working in a normalised 100 x height space keeps the maths
  // simple and the stroke crisp via vector-effect.
  const width = 100;
  const usable = height - 6;

  // Drop empty series so a single empty channel does not blank the whole chart,
  // but keep the empty state when nothing has any data yet.
  const drawable = series
    .map((values, index) => ({ values, color: colors[index] ?? 'var(--accent)' }))
    .filter((entry) => entry.values.length > 0);

  if (drawable.length === 0) {
    return (
      <div
        className="small muted"
        style={{ height, display: 'grid', placeItems: 'center' }}
      >
        Waiting for data
      </div>
    );
  }

  // Shared vertical span across every drawn series so they read on one scale.
  const span = Math.max(
    ...drawable.flatMap((entry) => entry.values),
    minRange,
  );

  const geometry = drawable.map(({ values, color }) => {
    const step = values.length <= 1 ? width : width / (values.length - 1);
    const points = values.map((value, index) => {
      const x = step * index;
      const normalised = Math.min(Math.max(value / span, 0), 1);
      return { x, y: height - normalised * usable };
    });

    // Catmull-Rom converted to cubic Béziers — smoother than straight segments
    // without the overshoot a plain spline would introduce.
    let path = `M ${points[0]!.x} ${points[0]!.y}`;
    for (let i = 0; i < points.length - 1; i++) {
      const p0 = points[i === 0 ? i : i - 1]!;
      const p1 = points[i]!;
      const p2 = points[i + 1]!;
      const p3 = points[i + 2 < points.length ? i + 2 : i + 1]!;
      const c1x = p1.x + (p2.x - p0.x) / 6;
      const c1y = p1.y + (p2.y - p0.y) / 6;
      const c2x = p2.x - (p3.x - p1.x) / 6;
      const c2y = p2.y - (p3.y - p1.y) / 6;
      path += ` C ${c1x} ${c1y}, ${c2x} ${c2y}, ${p2.x} ${p2.y}`;
    }

    const area = `${path} L ${points[points.length - 1]!.x} ${height} L ${points[0]!.x} ${height} Z`;
    const head = points[points.length - 1]!;
    return { path, area, head, color };
  });

  // Latest reading of the last (top-most) drawn series drives the label.
  const primary = drawable[drawable.length - 1]!.values;
  const latest = primary[primary.length - 1]?.toFixed(2) ?? '0';

  return (
    <svg
      className="sparkline"
      style={{ height }}
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="none"
      role="img"
      aria-label={`Flow trend, latest ${latest} litres per minute`}
    >
      <defs>
        {geometry.map((g, index) => (
          <linearGradient
            key={index}
            id={`${gradientId}-${index}`}
            x1="0"
            y1="0"
            x2="0"
            y2="1"
          >
            <stop offset="0%" stopColor={g.color} stopOpacity="0.34" />
            <stop offset="60%" stopColor="var(--gradient-green)" stopOpacity="0.1" />
            <stop offset="100%" stopColor="var(--gradient-green)" stopOpacity="0" />
          </linearGradient>
        ))}
      </defs>

      {Array.from({ length: gridDivisions + 1 }, (_, i) => {
        const y = (height * i) / gridDivisions;
        return (
          <line
            key={i}
            className="sparkline__grid"
            x1="0"
            y1={y}
            x2={width}
            y2={y}
            vectorEffect="non-scaling-stroke"
          />
        );
      })}

      {/* One area gradient per series, in draw order, then all strokes on top. */}
      {geometry.map((g, index) => (
        <path key={index} d={g.area} fill={`url(#${gradientId}-${index})`} />
      ))}
      {geometry.map((g, index) => (
        <path
          key={index}
          d={g.path}
          className="sparkline__line"
          style={{ stroke: g.color }}
          vectorEffect="non-scaling-stroke"
        />
      ))}
      {geometry.map((g, index) => (
        <circle
          key={index}
          cx={g.head.x}
          cy={g.head.y}
          r="1.6"
          fill={g.color}
          vectorEffect="non-scaling-stroke"
        />
      ))}
    </svg>
  );
}

/**
 * Horizontal gauge showing how far the current balance sits inside the calibrated
 * tolerance envelope. The track spans -threshold..+threshold; the inner half is
 * the safe band, and the marker rides at the live balance.
 */
export function EnvelopeGauge({
  balanceLpm,
  thresholdLpm,
  expectedLpm,
}: {
  balanceLpm: number;
  thresholdLpm: number;
  expectedLpm: number;
}) {
  const settings = useSettings();
  const threshold = thresholdLpm <= 0 ? 0.5 : thresholdLpm;
  const ratio = Math.max(-2, Math.min(2, balanceLpm / threshold));
  const breaching = Math.abs(balanceLpm) > threshold;
  const markerColor = breaching
    ? balanceLpm > 0
      ? 'var(--alert)'
      : 'var(--watch)'
    : 'var(--normal)';

  const width = 100;
  const height = 44;
  const centreY = height / 2;
  const trackHeight = 10;
  const markerX = Math.max(3, Math.min(width - 3, width / 2 + (ratio / 2) * (width / 2)));
  const expectedRatio = Math.max(-1, Math.min(1, expectedLpm / threshold));
  const expectedX = width / 2 + (expectedRatio / 2) * (width / 2);

  return (
    <div>
      <svg
        className="gauge"
        viewBox={`0 0 ${width} ${height}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={`Balance ${balanceLpm.toFixed(2)} of ${threshold.toFixed(2)} litres per minute allowed`}
      >
        <rect
          x="0"
          y={centreY - trackHeight / 2}
          width={width}
          height={trackHeight}
          rx={trackHeight / 2}
          fill="var(--surface-raised)"
          stroke="var(--border)"
          vectorEffect="non-scaling-stroke"
        />
        <rect
          x={width * 0.25}
          y={centreY - trackHeight / 2}
          width={width * 0.5}
          height={trackHeight}
          rx={trackHeight / 2}
          fill="color-mix(in srgb, var(--normal) 22%, transparent)"
        />
        <line
          x1={width / 2}
          y1={centreY - trackHeight}
          x2={width / 2}
          y2={centreY + trackHeight}
          stroke="var(--text-secondary)"
          opacity="0.5"
          vectorEffect="non-scaling-stroke"
        />
        <line
          x1={expectedX}
          y1={centreY - trackHeight * 0.7}
          x2={expectedX}
          y2={centreY + trackHeight * 0.7}
          stroke="var(--text-secondary)"
          opacity="0.85"
          strokeWidth="1.5"
          vectorEffect="non-scaling-stroke"
        />
        <circle
          cx={markerX}
          cy={centreY}
          r="3.2"
          fill={markerColor}
          style={{
            transition: settings.reduceMotion
              ? 'none'
              : 'cx var(--t-base) var(--ease-enter), fill var(--t-base) var(--ease-enter)',
          }}
        />
      </svg>
      <div className="gauge__scale mono">
        <span>-{threshold.toFixed(2)}</span>
        <span style={{ fontFamily: 'var(--font-sans)' }}>balanced</span>
        <span>+{threshold.toFixed(2)}</span>
      </div>
    </div>
  );
}

/** Thin progress ring used by the calibration dialog. */
export function RingProgress({
  progress,
  size = 110,
  strokeWidth = 6,
  children,
}: {
  progress: number;
  size?: number;
  strokeWidth?: number;
  children?: React.ReactNode;
}) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const clamped = Math.max(0, Math.min(1, progress));

  return (
    <div style={{ position: 'relative', width: size, height: size, margin: '0 auto' }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }} aria-hidden="true">
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="var(--border)"
          strokeWidth={strokeWidth}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="var(--accent)"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - clamped)}
          style={{ transition: 'stroke-dashoffset var(--t-base) var(--ease-enter)' }}
        />
      </svg>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          display: 'grid',
          placeItems: 'center',
          textAlign: 'center',
        }}
      >
        {children}
      </div>
    </div>
  );
}
