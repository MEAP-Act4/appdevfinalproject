import { useEffect, useId, useRef, useState } from 'react';

import { CalibrationDialog } from '../components/CalibrationDialog';
import {
  ActionRow,
  Banner,
  Card,
  InfoRow,
  Rows,
  Section,
  SelectRow,
  SliderRow,
  SwitchRow,
  TextRow,
} from '../components/primitives';
import { SUPPORTED_LOCALES, type AppLocale } from '../core/locale';
import { PROTOCOL_VERSION, SENSOR_COUNT, SENSOR_ROLES } from '../core/protocol';
import {
  formatForEditing as formatTariffForEditing,
  parse as parseTariff,
} from '../core/tariff';
import {
  FLOW_UNITS,
  VOLUME_UNITS,
  createFormatter,
  formatBytes,
  type FlowUnitId,
  type VolumeUnitId,
} from '../core/units';
import { monitorStore, useMonitor } from '../state/monitorStore';
import {
  LOGGING_OPTIONS,
  RETENTION_OPTIONS,
  retentionMs,
  settingsStore,
  useSettings,
  type Appearance,
} from '../state/settingsStore';

/**
 * The persistent Requirement 9.4 advisory, shown whenever the light appearance
 * is active.
 *
 * Exported as a single named constant — not an inline literal — so the wording
 * test asserts this constant and the component renders this same constant. One
 * source of truth for the string. The Mobile_Client holds the byte-identical
 * text on its own side (task 3.7), which is what lets task 17.2 / 17.3 compare
 * the two clients for the parity Requirement 9.6 demands.
 *
 * _Requirements: 9.4, 9.6_
 */
export const LIGHT_APPEARANCE_ADVISORY =
  'Light backgrounds sit outside WattVision guidance for prolonged data reading.';

/**
 * The primary Appearance choice, which is every appearance *except* light.
 *
 * Light is demoted out of the primary control into the Accessibility section
 * (Requirement 9.3). It stays reachable and fully functional (Requirement 9.3
 * / 9.5) — it is presented differently, not removed.
 */
type PrimaryAppearance = Exclude<Appearance, 'light'>;

/**
 * The primary Appearance options, in order, using the exact option names the
 * Mobile_Client uses so Requirement 9.6 holds. `hc-dark` is reachable only
 * through this control — the light switch below cannot select it.
 */
const PRIMARY_APPEARANCE_OPTIONS: readonly { id: PrimaryAppearance; label: string }[] = [
  { id: 'dark', label: 'Dark' },
  { id: 'hc-dark', label: 'High contrast dark' },
  { id: 'system', label: 'Follow system' },
];

/** The appearance a fresh session falls back to when Light is switched off. */
const DEFAULT_DARK_APPEARANCE: PrimaryAppearance = 'dark';

/**
 * The Tariff field's supporting copy. Deliberately labels the value as an
 * *editable placeholder* — a starting point the user may overwrite — rather
 * than a billed figure, which is Requirement 5.2's demand. Exported as one
 * source of truth so the parity check against the Mobile_Client (task 11.9)
 * compares this exact string.
 *
 * _Requirements: 5.2_
 */
export const TARIFF_CONTROL_SUBTITLE =
  'A starting placeholder in Bs. per cubic metre, not a billed figure. Enter your own water price to overwrite it.';

/** The Tariff row's title. */
export const TARIFF_CONTROL_TITLE = 'Water tariff';

/**
 * The `localeOverride` select is a "Follow system" option that maps to the
 * empty-string override plus one option per supported locale. The empty string
 * is `resolveLocale`'s "no override" sentinel (Requirement 12.6), so choosing
 * "Follow system" hands locale resolution back to the platform.
 */
const FOLLOW_SYSTEM_LOCALE = '';

/** Human labels for each supported locale, plus the follow-system default. */
const LOCALE_OPTION_LABELS: Readonly<Record<AppLocale, string>> = {
  es: 'Español',
  en: 'English',
};

/** The locale-override options, follow-system first. */
const LOCALE_OPTIONS: readonly { id: string; label: string }[] = [
  { id: FOLLOW_SYSTEM_LOCALE, label: 'Follow system' },
  ...SUPPORTED_LOCALES.map((locale) => ({ id: locale, label: LOCALE_OPTION_LABELS[locale] })),
];

/**
 * The Tariff text control.
 *
 * A close cousin of the `TextRow` primitive, but with the parse/validate/revert
 * behaviour the Tariff needs and `TextRow` does not carry:
 *
 *  - the draft is seeded from `formatForEditing` of the persisted value, so the
 *    field always opens on the ungrouped, trailing-zero-trimmed representation
 *    Requirement 5.6's round-trip is defined over;
 *  - on commit (blur or Enter) the draft runs through `tariff.parse`. On
 *    `ok:true` the accepted value is committed to the store synchronously —
 *    no debounce — so the store re-renders and every Bs_Equivalence picks up the
 *    new value well inside Requirement 5.3's 320ms; on `ok:false` the persisted
 *    value is retained, the field reverts to `formatForEditing(persisted)`, and
 *    the returned range/ambiguity message is shown (Requirement 5.4);
 *  - a successful commit clears any lingering message.
 *
 * The value flows in as a number and is formatted here, rather than the parent
 * formatting it, so the field re-seeds correctly when the store changes under
 * it (a reset, say).
 *
 * _Requirements: 5.1, 5.2, 5.3, 5.4, 12.5_
 */
function TariffRow({
  title,
  subtitle,
  value,
  onCommit,
}: {
  title: string;
  subtitle: string;
  value: number;
  onCommit: (value: number) => void;
}) {
  const [draft, setDraft] = useState(() => formatTariffForEditing(value));
  const [message, setMessage] = useState<string | null>(null);
  const lastExternal = useRef(value);
  const id = useId();
  const messageId = `${id}-message`;

  // Re-seed the field when the persisted value changes from outside — a store
  // reset, or a commit from another mounted copy. Comparing the raw number
  // avoids clobbering an in-progress edit that formats to the same value.
  useEffect(() => {
    if (lastExternal.current !== value) {
      lastExternal.current = value;
      setDraft(formatTariffForEditing(value));
      setMessage(null);
    }
  }, [value]);

  const commit = (): void => {
    const result = parseTariff(draft);
    if (result.ok) {
      setMessage(null);
      setDraft(formatTariffForEditing(result.value));
      onCommit(result.value);
    } else {
      // Requirement 5.4: retain the persisted value, revert the field, and
      // show the accepted-range (or ambiguity) message the model returned.
      setMessage(result.message);
      setDraft(formatTariffForEditing(value));
    }
  };

  return (
    <div className="row row--column">
      <label className="row__title" htmlFor={id}>
        {title}
      </label>
      <span className="row__subtitle">{subtitle}</span>
      <input
        id={id}
        className="textinput"
        type="text"
        inputMode="decimal"
        value={draft}
        aria-describedby={message ? messageId : undefined}
        aria-invalid={message ? true : undefined}
        onChange={(event) => setDraft(event.target.value)}
        onBlur={commit}
        onKeyDown={(event) => {
          if (event.key === 'Enter') {
            commit();
            event.currentTarget.blur();
          }
        }}
      />
      {message ? (
        <span id={messageId} className="row__subtitle" style={{ color: 'var(--alert)' }} role="alert">
          {message}
        </span>
      ) : null}
    </div>
  );
}

/**
 * Tab 2 — settings.
 *
 * Split into what the app controls (appearance, units, alerts, storage) and what
 * the *firmware* controls (noise floor, tolerance, debounce, K factors). Device
 * settings write straight through to the Arduino and persist in its EEPROM, so they
 * are disabled while offline and clearly marked as such.
 */
export function SettingsTab({ onOpenDiagnostics }: { onOpenDiagnostics: () => void }) {
  const monitor = useMonitor();
  const settings = useSettings();
  const [showCalibration, setShowCalibration] = useState(false);
  const [rowCount, setRowCount] = useState<number | null>(null);
  const [sizeBytes, setSizeBytes] = useState<number | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // Turning the light switch off returns to the dark appearance the user had
  // *before* they turned it on, rather than always snapping to Dark. The
  // primary control and the switch are two views of one `appearance` value, so
  // this is the memory that lets the switch restore a High_Contrast_Dark or
  // Follow-system choice instead of quietly demoting it to Dark. If light is
  // already active on mount there is no prior dark choice to remember, so we
  // seed the fallback. Session-scoped: the requirement is continuity within the
  // session, and `appearance` itself is what persists across restarts.
  const [lastDarkAppearance, setLastDarkAppearance] = useState<PrimaryAppearance>(
    settings.appearance === 'light' ? DEFAULT_DARK_APPEARANCE : settings.appearance,
  );

  const lightActive = settings.appearance === 'light';
  // While light is active the primary control has no appearance of its own to
  // reflect, so it shows the dark choice the switch will restore. Selecting any
  // primary option writes that appearance, which turns light off by definition.
  const primaryAppearance: PrimaryAppearance =
    settings.appearance === 'light' ? lastDarkAppearance : settings.appearance;

  const selectPrimaryAppearance = (appearance: PrimaryAppearance): void => {
    setLastDarkAppearance(appearance);
    settingsStore.update({ appearance });
  };

  const toggleLightAppearance = (on: boolean): void => {
    if (on) {
      // Remember where to come back to before leaving the dark family.
      if (!lightActive) setLastDarkAppearance(settings.appearance as PrimaryAppearance);
      settingsStore.update({ appearance: 'light' });
    } else {
      settingsStore.update({ appearance: lastDarkAppearance });
    }
  };

  const formatter = createFormatter(settings.flowUnit, settings.volumeUnit);
  const config = monitor.config;
  const online = monitor.linkState === 'ready' && config !== null;

  const loadStats = async () => {
    setRowCount(await monitorStore.readingCount());
    setSizeBytes(await monitorStore.databaseSizeBytes());
  };

  useEffect(() => {
    void loadStats();
  }, []);

  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(null), 5000);
    return () => clearTimeout(timer);
  }, [notice]);

  return (
    <div className="panel" style={{ paddingBottom: 'var(--s6)' }}>
      <div className="topbar">
        <span className="topbar__title">Settings</span>
        <button
          type="button"
          className="btn btn--icon"
          onClick={onOpenDiagnostics}
          aria-label="Diagnostics"
        >
          ⚕
        </button>
      </div>

      <div style={{ padding: '0 var(--s3)' }}>
        {notice ? (
          <Banner tone="var(--normal)" title="Done" message={notice} icon="✓" />
        ) : null}

        {/* --- Appearance ------------------------------------------------- */}
        <Section
          title="Appearance"
          subtitle="The dashboard is designed dark-first for long sessions of reading data. High contrast dark raises text and border contrast without leaving the dark palette."
        >
          <Card flush>
            <Rows>
              {/* The primary Appearance choice is dark-only: Dark, High contrast
                  dark and Follow system, named exactly as the Mobile_Client
                  names them (Requirement 9.6). Light is not here — it lives in
                  the Accessibility section below (Requirement 9.3). Selecting
                  any option here writes a dark-family appearance, which turns
                  the light switch off. */}
              <SelectRow<PrimaryAppearance>
                title="Theme"
                value={primaryAppearance}
                options={PRIMARY_APPEARANCE_OPTIONS}
                onChange={selectPrimaryAppearance}
              />
              <SwitchRow
                title="Reduce motion"
                subtitle="Removes the ambient pulses and transitions. Values still update, just without the sweep."
                checked={settings.reduceMotion}
                onChange={(reduceMotion) => settingsStore.update({ reduceMotion })}
              />
              <SwitchRow
                title="Show tolerance details"
                subtitle="Adds the expected-imbalance and margin-of-error breakdown to each sensor page."
                checked={settings.showEnvelopeDetails}
                onChange={(showEnvelopeDetails) =>
                  settingsStore.update({ showEnvelopeDetails })
                }
              />
            </Rows>
          </Card>
        </Section>

        {/* --- Accessibility --------------------------------------------- */}
        <Section
          title="Accessibility"
          subtitle="Affordances for readability and comfort. The light appearance lives here rather than in the primary theme choice."
        >
          <Card flush>
            <Rows>
              {/* Light is a switch, not a peer theme option (Requirement 9.3).
                  On → `appearance: 'light'`; off → the dark appearance the user
                  had before turning it on. Turning it on turns off any primary
                  selection, and picking a primary option turns this off — the
                  two controls are one `appearance` value seen two ways. */}
              <SwitchRow
                title="Light appearance"
                subtitle="Use a light background instead of the dark WattVision palette."
                checked={lightActive}
                onChange={toggleLightAppearance}
              />
            </Rows>
          </Card>
          {/* Requirement 9.4: a *persistent* advisory, visible for as long as
              the light appearance is selected. Deliberately not routed through
              the `notice`/Banner-with-timeout mechanism above, which
              auto-dismisses after 5s — this one must stay. */}
          {lightActive ? (
            <div style={{ marginTop: 'var(--s2)' }}>
              <Banner
                tone="var(--watch)"
                title="Outside design guidance"
                message={LIGHT_APPEARANCE_ADVISORY}
                icon="!"
              />
            </div>
          ) : null}
        </Section>

        {/* --- Units ------------------------------------------------------ */}
        <Section
          title="Units"
          subtitle="The board always reports litres per minute. Readings are converted for display only, so changing units never rewrites stored history."
        >
          <Card flush>
            <Rows>
              <SelectRow<FlowUnitId>
                title="Flow rate"
                value={settings.flowUnit}
                options={FLOW_UNITS.map((u) => ({ id: u.id, label: `${u.symbol} — ${u.label}` }))}
                onChange={(id) => settingsStore.setFlowUnit(id)}
              />
              <SwitchRow
                title="Match volume unit to flow unit"
                subtitle="Picking gal/min also switches totals to gallons."
                checked={settings.followFlowUnitForVolume}
                onChange={(value) => settingsStore.setFollowFlowUnit(value)}
              />
              <SelectRow<VolumeUnitId>
                title="Volume"
                value={settings.volumeUnit}
                disabled={settings.followFlowUnitForVolume}
                options={VOLUME_UNITS.map((u) => ({
                  id: u.id,
                  label: `${u.symbol} — ${u.label}`,
                }))}
                onChange={(id) => settingsStore.setVolumeUnit(id)}
              />
              <InfoRow
                title="Preview"
                subtitle="Current inlet reading in the selected units"
                value={formatter.flowText(monitor.latest?.flowLpm[0] ?? 0)}
                valueColor="var(--accent)"
              />
            </Rows>
          </Card>
        </Section>

        {/* --- Tariff & cost --------------------------------------------- */}
        <Section
          title="Tariff & cost"
          subtitle="Set your water price to see a Bolivianos figure alongside every volume. This is display only — no money is ever stored with your readings."
        >
          <Card flush>
            <Rows>
              {/* Requirement 5.1/5.2/5.3/5.4/12.5. The field opens on the
                  ungrouped editing form of the persisted value, commits an
                  accepted value straight to the store (so Bs_Equivalence
                  updates within 320ms), and on a rejected entry reverts to the
                  persisted value and shows the accepted-range message. */}
              <TariffRow
                title={TARIFF_CONTROL_TITLE}
                subtitle={TARIFF_CONTROL_SUBTITLE}
                value={settings.tariffBsPerCubicMetre}
                onCommit={(v) => settingsStore.setTariff(v)}
              />
              {/* Requirement 5.8: the master switch for the Bs_Equivalence
                  display. Off → volume figures show without a cost. */}
              <SwitchRow
                title="Show cost equivalence"
                subtitle="Adds a Bs. figure next to every volume. Turn off to show litres only."
                checked={settings.showCostEquivalence}
                onChange={(showCostEquivalence) =>
                  settingsStore.setShowCostEquivalence(showCostEquivalence)
                }
              />
              {/* Requirement 12.6: the locale override, step 1 of the
                  resolution chain. "Follow system" is the empty-string
                  sentinel that hands resolution back to the platform. */}
              <SelectRow
                title="Number & currency format"
                subtitle="Chooses the decimal and grouping separators for figures and the Bs. amount."
                value={settings.localeOverride}
                options={LOCALE_OPTIONS}
                onChange={(localeOverride) => settingsStore.setLocaleOverride(localeOverride)}
              />
            </Rows>
          </Card>
        </Section>

        {/* --- Sensor labels --------------------------------------------- */}
        <Section
          title="Sensor labels"
          subtitle='Name the channels after what they actually feed — "Kitchen", "Garden tap" — so an alert means something at a glance.'
        >
          <Card flush>
            <Rows>
              {Array.from({ length: SENSOR_COUNT }, (_, i) => (
                <TextRow
                  key={i}
                  title={SENSOR_ROLES[i]!.label}
                  placeholder={SENSOR_ROLES[i]!.description}
                  value={settings.sensorNames[i] ?? ''}
                  onCommit={(name) => settingsStore.renameSensor(i, name)}
                />
              ))}
            </Rows>
          </Card>
        </Section>

        {/* --- Alerts ---------------------------------------------------- */}
        <Section
          title="Alerts"
          subtitle="Which verdicts get your attention while the app is open."
        >
          <Card flush>
            <Rows>
              <SwitchRow
                title="Confirmed leaks"
                subtitle="Fires once the imbalance has persisted long enough to rule out sensor noise."
                checked={settings.alertOnLeak}
                onChange={(alertOnLeak) => settingsStore.update({ alertOnLeak })}
              />
              <SwitchRow
                title="Sensor faults"
                subtitle="Wiring problems and dead sensors."
                checked={settings.alertOnFault}
                onChange={(alertOnFault) => settingsStore.update({ alertOnFault })}
              />
              <SwitchRow
                title="Early warnings"
                subtitle="Also alert on unconfirmed imbalance. Noisier, but gives you a few seconds of head start."
                checked={settings.alertOnWatch}
                onChange={(alertOnWatch) => settingsStore.update({ alertOnWatch })}
              />
              <SwitchRow
                title="Alert sound"
                subtitle="Plays a short tone on a confirmed alarm. Browsers may block it until you interact with the page."
                checked={settings.audibleAlarm}
                onChange={(audibleAlarm) => settingsStore.update({ audibleAlarm })}
              />
            </Rows>
          </Card>
        </Section>

        {/* --- Detection (device) ---------------------------------------- */}
        <Section
          title="Leak detection"
          subtitle="These live on the Arduino, not in the app. Changes are written to its EEPROM and survive a power cycle."
        >
          {!online ? (
            <div style={{ marginBottom: 'var(--s2)' }}>
              <Banner
                tone="var(--idle)"
                title="Device offline"
                message="Connect the module to read or change its detection settings."
                icon="⃠"
              />
            </div>
          ) : null}
          <Card flush>
            <Rows>
              <ActionRow
                title="Run baseline calibration"
                subtitle={
                  config && config.learnedBiasLpm !== 0
                    ? `Last learned bias ${formatter.flowText(config.learnedBiasLpm)}`
                    : 'Not calibrated yet — strongly recommended after install'
                }
                disabled={!online}
                onClick={() => setShowCalibration(true)}
                trailing={
                  <span
                    className="row__value"
                    style={{
                      color:
                        config && config.learnedBiasLpm !== 0
                          ? 'var(--normal)'
                          : 'var(--watch)',
                    }}
                  >
                    {config && config.learnedBiasLpm !== 0 ? '✓' : '!'}
                  </span>
                }
              />
              <SliderRow
                title="Noise floor"
                subtitle="Readings under this are reported as exactly zero. This is what stops an idle system raising false leaks."
                value={config?.noiseFloorLpm ?? 0.12}
                min={0}
                max={1}
                step={0.01}
                disabled={!online}
                format={(v) => formatter.flowText(v)}
                onCommit={(v) => void monitorStore.setNoiseFloor(v)}
              />
              <SliderRow
                title="Minimum margin of error"
                subtitle="Absolute floor on the allowed imbalance, applied on top of the calibration dataset."
                value={config?.toleranceAbsLpm ?? 0.2}
                min={0.05}
                max={2}
                step={0.05}
                disabled={!online}
                format={(v) => formatter.flowText(v)}
                onCommit={(v) =>
                  void monitorStore.setTolerance(v, config?.tolerancePct ?? 0.08)
                }
              />
              <SliderRow
                title="Proportional margin"
                subtitle="Extra allowance as a percentage of inlet flow, for high-flow events."
                value={(config?.tolerancePct ?? 0.08) * 100}
                min={0}
                max={40}
                step={1}
                disabled={!online}
                format={(v) => `${v.toFixed(0)}%`}
                onCommit={(v) =>
                  void monitorStore.setTolerance(config?.toleranceAbsLpm ?? 0.2, v / 100)
                }
              />
              <SliderRow
                title="Confirmation time"
                subtitle="How long an imbalance must persist before the alarm latches. Lower reacts faster but is more twitchy."
                value={config?.leakConfirmSamples ?? 8}
                min={2}
                max={60}
                step={1}
                disabled={!online}
                format={(v) => `${v.toFixed(0)} s`}
                onCommit={(v) =>
                  void monitorStore.setDebounce(
                    Math.round(v),
                    config?.leakClearSamples ?? 5,
                    config?.faultConfirmSamples ?? 10,
                  )
                }
              />
              <SliderRow
                title="Clear time"
                subtitle="Clean samples needed before a latched alarm is retracted."
                value={config?.leakClearSamples ?? 5}
                min={1}
                max={60}
                step={1}
                disabled={!online}
                format={(v) => `${v.toFixed(0)} s`}
                onCommit={(v) =>
                  void monitorStore.setDebounce(
                    config?.leakConfirmSamples ?? 8,
                    Math.round(v),
                    config?.faultConfirmSamples ?? 10,
                  )
                }
              />
              {Array.from({ length: SENSOR_COUNT }, (_, i) => (
                <SliderRow
                  key={i}
                  title={`K factor — ${settings.sensorNames[i]}`}
                  subtitle="Pulses per litre. YF-S201 is 450. Adjust this rather than widening the tolerance if a channel reads consistently off."
                  value={config?.pulsesPerLitre[i] ?? 450}
                  min={200}
                  max={900}
                  step={5}
                  disabled={!online}
                  format={(v) => v.toFixed(0)}
                  onCommit={(v) => void monitorStore.setPulsesPerLitre(i, v)}
                />
              ))}
              <ActionRow
                title="Restore device defaults"
                subtitle="Resets the Arduino tuning, not the app settings."
                danger
                disabled={!online}
                onClick={() => {
                  if (
                    window.confirm(
                      'Restore device defaults? The board goes back to its factory ' +
                        'tolerance, noise floor, debounce and K factors, and the ' +
                        'learned calibration bias is cleared.',
                    )
                  ) {
                    void monitorStore.restoreDeviceDefaults();
                  }
                }}
              />
            </Rows>
          </Card>
        </Section>

        {/* --- Connection ------------------------------------------------ */}
        <Section title="Connection">
          <Card flush>
            <Rows>
              <InfoRow
                title="Status"
                subtitle={
                  monitor.usingSimulator
                    ? 'Simulated feed — no hardware attached'
                    : (monitor.connectedDevice?.name ?? 'Not connected')
                }
                value={
                  monitor.linkState === 'ready'
                    ? 'LIVE'
                    : monitor.stale
                      ? 'STALE'
                      : 'OFFLINE'
                }
                valueColor={
                  monitor.linkState === 'ready'
                    ? 'var(--normal)'
                    : monitor.stale
                      ? 'var(--watch)'
                      : 'var(--idle)'
                }
              />
              <SwitchRow
                title="Reconnect automatically"
                subtitle="Reattaches to the last module on load and after a dropout, with backoff. Browsers only allow this for devices already granted to this site."
                checked={settings.autoReconnect}
                onChange={(autoReconnect) => settingsStore.update({ autoReconnect })}
              />
              <SwitchRow
                title="Require a live link"
                subtitle="On: the app stays locked until the module is connected. Off: you can open stored history without it."
                checked={settings.requireConnectionToBrowse}
                onChange={(requireConnectionToBrowse) =>
                  settingsStore.update({ requireConnectionToBrowse })
                }
              />
              {settings.rememberedDeviceId ? (
                <ActionRow
                  title={`Forget ${settings.rememberedDeviceName}`}
                  subtitle={settings.rememberedDeviceId}
                  danger
                  onClick={() => settingsStore.forgetDevice()}
                />
              ) : null}
              {monitor.linkState === 'ready' || monitor.usingSimulator ? (
                <ActionRow
                  title="Disconnect"
                  subtitle="Returns to the connection screen."
                  danger
                  onClick={() => void monitorStore.disconnect()}
                />
              ) : null}
              <ActionRow
                title="Reboot the board"
                subtitle="Watchdog reset. Readings resume within a second."
                disabled={!online || monitor.usingSimulator}
                onClick={() => {
                  if (
                    window.confirm(
                      'Reboot the Arduino? Cumulative volume counters restart from ' +
                        'zero. Stored history is untouched.',
                    )
                  ) {
                    void monitorStore.rebootDevice();
                  }
                }}
              />
            </Rows>
          </Card>
        </Section>

        {/* --- Data & storage -------------------------------------------- */}
        <Section
          title="Data & storage"
          subtitle="Readings are logged to IndexedDB in this browser. Averages are computed from it, so history survives reloads and dropouts."
        >
          <Card flush>
            <Rows>
              <SelectRow
                title="Logging interval"
                subtitle="The board always streams at 1 Hz; this controls how often a row is written. Rows record how many samples they cover, so averages stay accurate either way."
                value={settings.loggingIntervalId}
                options={LOGGING_OPTIONS.map((o) => ({
                  id: o.id,
                  label: `${o.label} (${o.footprint})`,
                }))}
                onChange={(loggingIntervalId) => settingsStore.update({ loggingIntervalId })}
              />
              <SelectRow
                title="Keep history for"
                value={settings.retentionId}
                options={RETENTION_OPTIONS.map((o) => ({ id: o.id, label: o.label }))}
                onChange={(retentionId) => settingsStore.update({ retentionId })}
              />
              <SwitchRow
                title="Prune automatically"
                subtitle="Removes rows past the retention window on load."
                checked={settings.autoPrune}
                onChange={(autoPrune) => settingsStore.update({ autoPrune })}
              />
              <InfoRow
                title="Stored readings"
                subtitle={
                  sizeBytes === null ? undefined : `Origin storage ${formatBytes(sizeBytes)}`
                }
                value={rowCount === null ? '…' : String(rowCount)}
              />
              <ActionRow
                title="Export to CSV"
                subtitle="Downloads canonical L/min values."
                onClick={() => void exportCsv(setNotice)}
              />
              <ActionRow
                title="Prune now"
                subtitle="Apply the retention window immediately."
                disabled={retentionMs(settings) === null}
                onClick={async () => {
                  const removed = await monitorStore.pruneNow();
                  await loadStats();
                  setNotice(`Removed ${removed} readings`);
                }}
              />
              <ActionRow
                title="Clear all history"
                subtitle="Deletes every reading and event. Cannot be undone."
                danger
                onClick={async () => {
                  if (
                    !window.confirm(
                      'Delete all stored data? Every logged reading and event will ' +
                        'be removed, and the daily, 3-day and weekly averages ' +
                        'restart from empty. This cannot be undone.',
                    )
                  ) {
                    return;
                  }
                  await monitorStore.clearHistory();
                  await loadStats();
                  setNotice('History cleared');
                }}
              />
            </Rows>
          </Card>
        </Section>

        {/* --- About ----------------------------------------------------- */}
        <Section title="About">
          <Card flush>
            <Rows>
              <InfoRow title="App version" value="1.0.0" />
              <InfoRow title="Firmware" value={config?.firmwareVersion ?? '—'} />
              <InfoRow
                title="Link protocol"
                subtitle={`App expects v${PROTOCOL_VERSION}`}
                value={config ? `v${config.protocolVersion}` : '—'}
                valueColor={
                  config
                    ? config.protocolVersion === PROTOCOL_VERSION
                      ? 'var(--normal)'
                      : 'var(--alert)'
                    : undefined
                }
              />
              <ActionRow
                title="Reset app settings"
                subtitle="Appearance, units, alerts and storage preferences. Device tuning and stored readings are untouched."
                danger
                onClick={() => {
                  if (window.confirm('Reset app settings to defaults?')) {
                    settingsStore.resetAll();
                  }
                }}
              />
            </Rows>
          </Card>
        </Section>

        <p className="tiny muted" style={{ textAlign: 'center', marginTop: 'var(--s4)' }}>
          LeakGuard · Arduino Uno + HM-10 · 3-channel balance monitoring
        </p>
      </div>

      {showCalibration ? (
        <CalibrationDialog onClose={() => setShowCalibration(false)} />
      ) : null}
    </div>
  );
}

async function exportCsv(setNotice: (message: string) => void): Promise<void> {
  const csv = await monitorStore.exportCsv();
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  anchor.href = url;
  anchor.download = `leakguard-${stamp}.csv`;
  anchor.click();
  URL.revokeObjectURL(url);
  setNotice('CSV downloaded');
}
