import type { CSSProperties, ReactNode } from 'react';
import { useEffect, useId, useRef, useState } from 'react';

import { createCostFormatter } from '../core/cost';
import { resolveActiveLocale } from '../core/locale';
import type { LeakStatus } from '../core/protocol';
import { useAnimatedNumber } from '../hooks/useAnimatedNumber';
import { useSettings } from '../state/settingsStore';
import { statusVisuals } from './statusVisuals';

// =============================================================================
// Surfaces
// =============================================================================

export function Card({
  children,
  accent,
  raised,
  flush,
  onClick,
  style,
}: {
  children: ReactNode;
  accent?: string;
  raised?: boolean;
  flush?: boolean;
  onClick?: () => void;
  style?: CSSProperties;
}) {
  const className = [
    'card',
    raised ? 'card--raised' : '',
    flush ? 'card--flush' : '',
    onClick ? 'card--tappable' : '',
  ]
    .filter(Boolean)
    .join(' ');

  const merged: CSSProperties = {
    ...(accent ? { borderColor: `color-mix(in srgb, ${accent} 45%, transparent)` } : {}),
    ...style,
  };

  if (onClick) {
    return (
      <button type="button" className={className} style={merged} onClick={onClick}>
        {children}
      </button>
    );
  }
  return (
    <div className={className} style={merged}>
      {children}
    </div>
  );
}

export function CardLabel({ children, trailing }: { children: ReactNode; trailing?: ReactNode }) {
  return (
    <div className="card__label">
      <span>{children}</span>
      {trailing}
    </div>
  );
}

export function Section({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
}) {
  return (
    <section className="section">
      <div className="section__heading">
        <span className="section__title">{title}</span>
        {subtitle ? <span className="section__subtitle">{subtitle}</span> : null}
      </div>
      {children}
    </section>
  );
}

// =============================================================================
// Metrics
// =============================================================================

export function Metric({
  value,
  format,
  unit,
  size = 32,
  color,
}: {
  value: number;
  format: (v: number) => string;
  unit?: string;
  size?: number;
  color?: string;
}) {
  const settings = useSettings();
  const animated = useAnimatedNumber(value, { disabled: settings.reduceMotion });
  return (
    <span className="metric">
      <span
        className="metric__value"
        style={{ fontSize: `${size}px`, ...(color ? { color } : {}) }}
      >
        {format(animated)}
      </span>
      {unit ? (
        <span className="metric__unit" style={{ fontSize: `${Math.round(size * 0.42)}px` }}>
          {unit}
        </span>
      ) : null}
    </span>
  );
}

export function MetricTile({
  label,
  value,
  format,
  unit,
  caption,
  color,
  size = 18,
  footer,
}: {
  label: string;
  value: number;
  format: (v: number) => string;
  unit?: string;
  caption?: string;
  color?: string;
  size?: number;
  /**
   * Optional content rendered beneath the value and caption — used to place the
   * {@link CostEquivalence} next to a volume figure (Requirement 6.5) without
   * disturbing the metric grid's column layout.
   */
  footer?: ReactNode;
}) {
  return (
    <div className="metric-tile">
      <span className="metric-tile__label">{label}</span>
      <Metric value={value} format={format} unit={unit} size={size} color={color} />
      {caption ? <span className="tiny muted">{caption}</span> : null}
      {footer}
    </div>
  );
}

/**
 * The Bs_Equivalence shown beneath a volume figure (Requirements 6.1, 6.2, 6.5,
 * 6.8, 6.9).
 *
 * It takes the *canonical litre* volume — never a display-unit number — so a
 * change of displayed volume unit cannot change the Bs figure for the same
 * litres (Requirement 6.7 / 13.8). The formatter is the single source of the
 * `'Bs. '` prefix, the two-decimal locale body, the `null`-when-disabled
 * contract and the `'--'` non-finite sentinel (`core/cost.ts`).
 *
 * The litre value is run through the same {@link useAnimatedNumber} hook the
 * metrics use, then formatted, so the amount interpolates while Reduce_Motion is
 * off (Requirement 6.9) and snaps under reduce-motion through the existing
 * mechanism — no new CSS or animation. The string renders in the secondary text
 * colour at the body type size next to (beneath) the primary volume value
 * (Requirement 6.5).
 *
 * When display is disabled the formatter returns `null` and this renders
 * nothing extra (Requirement 5.8). When the default Tariff is in use it appends
 * a subtle "default tariff" hint (Requirement 6.8), wording kept consistent with
 * the Mobile_Client.
 */
export function CostEquivalence({ canonicalLitres }: { canonicalLitres: number }) {
  const settings = useSettings();
  const animated = useAnimatedNumber(canonicalLitres, { disabled: settings.reduceMotion });
  const formatter = createCostFormatter({
    tariffBsPerCubicMetre: settings.tariffBsPerCubicMetre,
    locale: resolveActiveLocale(settings.localeOverride),
    enabled: settings.showCostEquivalence,
    isDefaultTariff: !settings.tariffConfiguredByUser,
  });

  const text = formatter.format(animated);
  if (text === null) return null;

  return (
    <span
      className="cost-equivalence"
      style={{
        display: 'block',
        marginTop: 'var(--s1)',
        fontSize: 'var(--size-body)',
        color: 'var(--text-secondary)',
      }}
    >
      {text}
      {formatter.isDefaultTariff ? (
        <span className="tiny muted" style={{ marginLeft: 'var(--s1)' }}>
          default tariff
        </span>
      ) : null}
    </span>
  );
}

export function Bar({
  value,
  thin,
  color,
}: {
  value: number;
  thin?: boolean;
  color?: string;
}) {
  const pct = Math.max(0, Math.min(1, value)) * 100;
  return (
    <div className={thin ? 'bar bar--thin' : 'bar'}>
      <div
        className="bar__fill"
        style={{ width: `${pct}%`, ...(color ? { background: color } : {}) }}
      />
    </div>
  );
}

// =============================================================================
// Status
// =============================================================================

export function StatusPill({ status, live }: { status: LeakStatus; live?: boolean }) {
  const visuals = statusVisuals(status);
  return (
    <span
      className="pill"
      style={{ color: visuals.color, background: `color-mix(in srgb, ${visuals.color} 12%, transparent)` }}
    >
      <span className={live ? 'dot dot--live' : 'dot'} />
      {visuals.label}
    </span>
  );
}

export function Banner({
  tone,
  title,
  message,
  icon,
  onDismiss,
  action,
}: {
  tone: string;
  title: string;
  message: string;
  icon: string;
  onDismiss?: () => void;
  action?: { label: string; onClick: () => void };
}) {
  return (
    <div
      className="banner"
      style={{
        color: tone,
        background: `color-mix(in srgb, ${tone} 12%, transparent)`,
      }}
      role="status"
    >
      <span aria-hidden="true">{icon}</span>
      <div className="banner__body">
        <div className="banner__title">{title}</div>
        <div className="banner__message">{message}</div>
      </div>
      {action ? (
        <button type="button" className="btn btn--ghost" onClick={action.onClick}>
          {action.label}
        </button>
      ) : null}
      {onDismiss ? (
        <button
          type="button"
          className="banner__close"
          onClick={onDismiss}
          aria-label="Dismiss"
        >
          ×
        </button>
      ) : null}
    </div>
  );
}

export function StatusBanner({
  status,
  onDismiss,
  action,
}: {
  status: LeakStatus;
  onDismiss?: () => void;
  action?: { label: string; onClick: () => void };
}) {
  const visuals = statusVisuals(status);
  return (
    <Banner
      tone={visuals.color}
      title={visuals.headline}
      message={visuals.detail}
      icon={visuals.icon}
      {...(onDismiss ? { onDismiss } : {})}
      {...(action ? { action } : {})}
    />
  );
}

// =============================================================================
// Settings rows
// =============================================================================

export function Rows({ children }: { children: ReactNode }) {
  return <div className="rows">{children}</div>;
}

function RowBody({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <span className="row__body">
      <span className="row__title">{title}</span>
      {subtitle ? <span className="row__subtitle">{subtitle}</span> : null}
    </span>
  );
}

export function SwitchRow({
  title,
  subtitle,
  checked,
  onChange,
  disabled,
}: {
  title: string;
  subtitle?: string;
  checked: boolean;
  onChange: (value: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      className={`row row--tappable${disabled ? ' row--disabled' : ''}`}
      onClick={() => onChange(!checked)}
      disabled={disabled}
      role="switch"
      aria-checked={checked}
    >
      <RowBody title={title} subtitle={subtitle} />
      <span className="switch" aria-checked={checked} aria-hidden="true">
        <span className="switch__knob" />
      </span>
    </button>
  );
}

export function SelectRow<T extends string>({
  title,
  subtitle,
  value,
  options,
  onChange,
  disabled,
}: {
  title: string;
  subtitle?: string;
  value: T;
  options: readonly { id: T; label: string }[];
  onChange: (value: T) => void;
  disabled?: boolean;
}) {
  const id = useId();
  return (
    <div className={`row${disabled ? ' row--disabled' : ''}`}>
      <label className="row__body" htmlFor={id}>
        <span className="row__title">{title}</span>
        {subtitle ? <span className="row__subtitle">{subtitle}</span> : null}
      </label>
      <select
        id={id}
        className="select"
        value={value}
        disabled={disabled}
        onChange={(event) => onChange(event.target.value as T)}
      >
        {options.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
    </div>
  );
}

/**
 * Slider that reports only on release. Committing mid-drag would fire a BLE write
 * for every pixel of movement, and the HM-10's UART would not keep up.
 */
export function SliderRow({
  title,
  subtitle,
  value,
  min,
  max,
  step,
  format,
  onCommit,
  disabled,
}: {
  title: string;
  subtitle?: string;
  value: number;
  min: number;
  max: number;
  step: number;
  format: (v: number) => string;
  onCommit: (value: number) => void;
  disabled?: boolean;
}) {
  const [draft, setDraft] = useState<number | null>(null);
  const current = draft ?? value;

  return (
    <div className={`row row--column${disabled ? ' row--disabled' : ''}`}>
      <div className="row-inline">
        <RowBody title={title} subtitle={subtitle} />
        <span className="row__value">{format(current)}</span>
      </div>
      <input
        className="slider"
        type="range"
        min={min}
        max={max}
        step={step}
        value={current}
        disabled={disabled}
        aria-label={title}
        onChange={(event) => setDraft(Number(event.target.value))}
        onPointerUp={() => {
          if (draft !== null) onCommit(draft);
          setDraft(null);
        }}
        onKeyUp={() => {
          if (draft !== null) onCommit(draft);
          setDraft(null);
        }}
      />
    </div>
  );
}

export function ActionRow({
  title,
  subtitle,
  onClick,
  danger,
  disabled,
  trailing,
}: {
  title: string;
  subtitle?: string;
  onClick: () => void;
  danger?: boolean;
  disabled?: boolean;
  trailing?: ReactNode;
}) {
  return (
    <button
      type="button"
      className={[
        'row',
        'row--tappable',
        danger ? 'row--danger' : '',
        disabled ? 'row--disabled' : '',
      ]
        .filter(Boolean)
        .join(' ')}
      onClick={onClick}
      disabled={disabled}
    >
      <RowBody title={title} subtitle={subtitle} />
      {trailing ?? <span className="row__value row__value--muted">›</span>}
    </button>
  );
}

export function InfoRow({
  title,
  subtitle,
  value,
  valueColor,
}: {
  title: string;
  subtitle?: string;
  value: string;
  valueColor?: string;
}) {
  return (
    <div className="row">
      <RowBody title={title} subtitle={subtitle} />
      <span
        className="row__value"
        style={valueColor ? { color: valueColor } : { color: 'var(--text-secondary)' }}
      >
        {value}
      </span>
    </div>
  );
}

export function TextRow({
  title,
  placeholder,
  value,
  onCommit,
  maxLength = 24,
}: {
  title: string;
  placeholder?: string;
  value: string;
  onCommit: (value: string) => void;
  maxLength?: number;
}) {
  const [draft, setDraft] = useState(value);
  const lastExternal = useRef(value);

  useEffect(() => {
    if (lastExternal.current !== value) {
      lastExternal.current = value;
      setDraft(value);
    }
  }, [value]);

  const id = useId();

  return (
    <div className="row row--column">
      <label className="row__title" htmlFor={id}>
        {title}
      </label>
      <input
        id={id}
        className="textinput"
        type="text"
        value={draft}
        placeholder={placeholder}
        maxLength={maxLength}
        onChange={(event) => setDraft(event.target.value)}
        onBlur={() => onCommit(draft)}
        onKeyDown={(event) => {
          if (event.key === 'Enter') {
            onCommit(draft);
            event.currentTarget.blur();
          }
        }}
      />
    </div>
  );
}

// =============================================================================
// Overlays
// =============================================================================

export function Sheet({
  title,
  onClose,
  children,
  actions,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  actions?: ReactNode;
}) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="scrim"
      role="presentation"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title}>
        <div className="sheet__header">
          <span className="sheet__title">{title}</span>
          {actions}
          <button type="button" className="btn btn--icon" onClick={onClose} aria-label="Close">
            ×
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function KeyValue({
  label,
  value,
  valueColor,
}: {
  label: string;
  value: string;
  valueColor?: string;
}) {
  return (
    <div className="kv">
      <span className="kv__key">{label}</span>
      <span className="kv__value" style={valueColor ? { color: valueColor } : undefined}>
        {value}
      </span>
    </div>
  );
}

export function Spinner() {
  return <span className="spinner" aria-hidden="true" />;
}
