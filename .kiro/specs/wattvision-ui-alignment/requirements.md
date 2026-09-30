# Requirements Document

## Introduction

The smart water leak monitoring system already ships three working components: fixed Arduino firmware, a Flutter mobile client, and a React 19 web client used as an independent cross-check. Both clients already transcribe the WattVision colour, typography, and card tokens correctly, but they render as single-column phone-width stacks and omit several parts of the design system.

This feature reworks the user interface of both clients so that they fully implement the WattVision design system now sourced from the DESIGNmd MCP server (kit `groquispe100inf-max/design-md-sistema-de-monitoreo-el-ctrico-wattvision`, MIT). The work covers five substantive areas:

1. Verified token compliance, so drift from the kit becomes a build-time or test-time failure rather than a review finding.
2. A responsive 12-column grid with the WattVision dashboard composition (three KPI columns across the top, an eight-column main chart, a four-column alerts panel on the right) for laptop and tablet viewports, while keeping the phone carousel intact.
3. A configurable water tariff and a Bolivianos (`Bs.`) cost equivalence displayed alongside volume figures.
4. Table row styling and hover treatment, applied to the calibration dataset and to any alerts list rendered as rows.
5. An explicit resolution of the conflict between the shipped light theme and the kit's prohibition on white backgrounds, plus the water-domain icon language, locale-aware number and currency formatting, and accessibility affordances.

The firmware, the wire protocol, the calibration dataset, and the alarm logic are out of scope and must not change. Canonical storage stays L/min and litres; every unit or currency conversion is presentation-only.

## Glossary

- **WattVision**: The design system defined by the DESIGNmd kit `groquispe100inf-max/design-md-sistema-de-monitoreo-el-ctrico-wattvision`. Sections are cited as WattVision §1 through §6. It is the single authority for colour, typography, component styling, layout, and visual do's and don'ts.
- **Design_Token_Registry**: The per-client module that holds every WattVision value. `flutter_app/lib/core/theme/design_tokens.dart` for the Mobile_Client and `react_app/src/styles/tokens.css` for the Web_Client.
- **Token_Extension**: A colour, size, or motion value used by a client that is not present in WattVision §2 through §5. Each Token_Extension carries a recorded rationale in the Design_Token_Registry.
- **Mobile_Client**: The Flutter application in `flutter_app/`.
- **Web_Client**: The React 19 + TypeScript + Vite application in `react_app/`.
- **Layout_Engine**: The per-client code that resolves the current viewport width to a Layout_Mode and assigns column spans.
- **Layout_Mode**: One of three named width bands. **Compact** is a viewport logical width below 600; **Medium** is 600 to 1023 inclusive; **Expanded** is 1024 or greater. Logical width means device-independent pixels in the Mobile_Client and CSS pixels in the Web_Client.
- **Grid_12**: The 12-column layout grid from WattVision §5. Column widths are equal, gutters and outer padding are multiples of 8, and every element occupies a whole number of columns between 1 and 12.
- **KPI**: A Key Performance Indicator readout — a single headline number with its unit and label, set in the monospaced type at 32px per WattVision §4. In this product the KPIs are the three sensor channels: Main Inlet, Outlet A, and Outlet B.
- **KPI_Row**: The row of three KPI cards placed across the top of the Dashboard_View, each spanning 4 columns of Grid_12.
- **Dashboard_View**: The Medium and Expanded presentation of the Sensors tab: KPI_Row, Main_Chart, and Alerts_Panel composed on Grid_12.
- **Main_Chart**: The primary time-series area chart of flow and volume, spanning 8 columns of Grid_12 in Expanded.
- **Alerts_Panel**: The panel spanning 4 columns of Grid_12 on the right-hand side in Expanded, listing Alert_Entry rows newest-first.
- **Alert_Entry**: One record of a Status transition or fault, carrying a timestamp, the affected channel, the Status, and a human-readable summary.
- **Sensor_Carousel**: The existing Compact presentation — three swipeable per-sensor pages with chevron arrow navigation.
- **Tariff**: The user-configured water price used only for display. Expressed as Bs. per cubic metre, stored as a single numeric value in settings.
- **Bs_Equivalence**: The monetary figure shown next to a volume figure, computed as volume in cubic metres multiplied by the Tariff, rendered with the `Bs.` prefix. Never persisted.
- **Cost_Formatter**: The presentation-only component that converts a canonical litre volume plus the Tariff into a formatted Bs_Equivalence string.
- **Status**: The device-reported state vocabulary, fixed by the firmware protocol: **IDLE** (no flow and no link activity), **OK** (flow within the calibrated envelope), **WATCH** (a deviation observed but not yet confirmed), **LEAK** (a confirmed inlet-versus-outlet mismatch), **FAULT** (sensor or link failure), **CAL** (the device is running a calibration routine).
- **Status_Affordance**: The non-colour signal that accompanies every Status presentation — a text label, a shape, or an icon — so that Status is never conveyed by colour alone.
- **Icon_Language**: The approved icon vocabulary for this product: droplet, valve, gauge/meter, pipe, and wave. WattVision §6 forbids generic lightbulb icons; its recommended "bolt, plug, meter" set is the electrical analogue of this water-domain vocabulary.
- **Reduce_Motion**: The existing accessibility setting that collapses transitions to near-instant and stops ambient animation.
- **Connection_Gate**: The existing mandatory screen that blocks full access until a device link is established, subject to the `requireConnectionToBrowse` setting.
- **Calibration_Table**: The read-only table of the firmware BASELINE_TABLE dataset shown in the Diagnostics_Sheet.
- **Diagnostics_Sheet**: The existing panel showing link health, firmware configuration, Calibration_Table, event log, and raw traffic.

## Requirements

### Requirement 1: Verified Design Token Compliance

**User Story:** As a developer maintaining two clients, I want every WattVision value to live in one verified registry per client, so that visual drift from the design system is caught automatically instead of by eye.

#### Acceptance Criteria

1. THE Design_Token_Registry SHALL define one named token for each colour, radius, padding, spacing step, and type size specified in WattVision §2, §3, §4, and §5.
2. THE Mobile_Client SHALL reference colour, radius, padding, spacing, and type-size values exclusively through the Design_Token_Registry.
3. THE Web_Client SHALL reference colour, radius, padding, spacing, and type-size values exclusively through the Design_Token_Registry.
4. WHEN the compliance test suite runs, THE Mobile_Client SHALL fail the suite IF any Dart source file outside the Design_Token_Registry contains a literal colour value.
5. WHEN the compliance test suite runs, THE Web_Client SHALL fail the suite IF any file under `react_app/src` other than `tokens.css` contains a literal hex colour, `rgb()`, or `hsl()` value.
6. WHEN the compliance test suite runs, THE compliance test suite SHALL assert that each WattVision §2 colour token equals its specified value: background `#121212`, card surface `#1E1E1E`, primary accent `#00E5FF`, alert accent `#FF453A`, secondary accent `#32D74B`, chart gradient partner `#30D158`, row hover `#252525`, border `#2C2C2E`, primary text `#FFFFFF`, secondary text `#98989D`, alert box fill `#3A1C1C`.
7. WHEN the compliance test suite runs, THE compliance test suite SHALL assert that the card radius token equals 16, the card padding token equals 20, the hairline border token equals 1, the title type size equals 24, the KPI type size equals 32, and the body type size equals 14.
8. THE compliance test suite SHALL assert that every spacing token used for layout gaps, gutters, and outer padding is a whole multiple of 8.
9. THE Design_Token_Registry SHALL record, for each Token_Extension, the reason the value is absent from WattVision and the state or surface that consumes the value.
10. THE Design_Token_Registry SHALL declare the amber WATCH colour `#FFD60A` as a Token_Extension with the recorded rationale that WattVision §2 supplies no intermediate advisory colour between the secondary accent and the alert accent.
11. WHEN a Status is presented in the WATCH state, THE Mobile_Client and THE Web_Client SHALL render a Status_Affordance alongside the amber colour.

### Requirement 2: Responsive 12-Column Grid

**User Story:** As someone checking my water usage on a laptop or a tablet, I want the interface to use the full width of the screen, so that I can read all three channels and the history without paging through phone-sized cards.

#### Acceptance Criteria

1. THE Layout_Engine SHALL resolve the current viewport logical width to exactly one Layout_Mode: Compact below 600, Medium from 600 to 1023 inclusive, Expanded at 1024 and above.
2. WHILE the Layout_Mode is Medium or Expanded, THE Layout_Engine SHALL lay out primary content on Grid_12 with equal column widths.
3. WHILE the Layout_Mode is Expanded, THE Layout_Engine SHALL apply a 24 gutter between columns and 32 outer padding.
4. WHILE the Layout_Mode is Medium, THE Layout_Engine SHALL apply a 16 gutter between columns and 24 outer padding.
5. WHILE the Layout_Mode is Compact, THE Layout_Engine SHALL apply 16 outer padding and assign every primary content element the full available width.
6. WHILE the Layout_Mode is Expanded, THE Layout_Engine SHALL cap the grid content width at 1440 and centre the grid horizontally within the viewport.
7. THE Layout_Engine SHALL assign each Grid_12 child a column span that is a whole number from 1 to 12.
8. WHEN the sum of the column spans assigned to one Grid_12 row exceeds 12, THE Layout_Engine SHALL wrap the overflowing children onto the next row.
9. WHEN the viewport logical width changes, THE Layout_Engine SHALL resolve the Layout_Mode from the new width within 200ms.
10. THE Web_Client SHALL allow the root application container to occupy the full viewport width up to the Expanded content cap, replacing the fixed 560 maximum width.
11. FOR ALL viewport logical widths from 320 to 2560, THE Layout_Engine SHALL resolve exactly one Layout_Mode and produce a layout with no horizontally clipped primary content.

### Requirement 3: Wide-Viewport Dashboard Composition

**User Story:** As a home or small-business operator watching for leaks, I want a single dashboard that shows all three channels, the trend chart, and the open alerts at once, so that I can judge the state of the system without navigating.

#### Acceptance Criteria

1. WHILE the Layout_Mode is Expanded, THE Dashboard_View SHALL place the KPI_Row above the Main_Chart and the Alerts_Panel.
2. WHILE the Layout_Mode is Expanded, THE Dashboard_View SHALL render the KPI_Row as three KPI cards, each spanning 4 columns of Grid_12, ordered Main Inlet, Outlet A, Outlet B.
3. WHILE the Layout_Mode is Expanded, THE Dashboard_View SHALL render the Main_Chart spanning 8 columns of Grid_12 and the Alerts_Panel spanning the remaining 4 columns on the right-hand side, both beginning on the same grid row.
4. WHILE the Layout_Mode is Medium, THE Dashboard_View SHALL render the KPI_Row as three KPI cards each spanning 4 columns, THE Main_Chart spanning 12 columns below the KPI_Row, and THE Alerts_Panel spanning 12 columns below the Main_Chart.
5. THE Dashboard_View SHALL render each KPI card with the live flow reading in the monospaced type at the KPI type size, the sensor name from settings, the Status, and a Status_Affordance.
6. THE Dashboard_View SHALL render the per-day, per-3-day, and per-week averages for a channel within that channel's KPI card or within a details surface reachable from that card.
7. THE Main_Chart SHALL render flow history as an area chart with a fill gradient derived from the primary accent and the chart gradient partner colour.
8. THE Main_Chart SHALL render grid lines in the border colour `#2C2C2E` and SHALL render series strokes no thicker than 2.
9. THE Main_Chart SHALL allow the user to select which of the three channels are plotted, with all three selectable simultaneously.
10. WHERE the Diagnostics_Sheet is available, THE Dashboard_View SHALL expose an entry point to the Diagnostics_Sheet in Medium and Expanded Layout_Modes.

### Requirement 4: Continuity Between Carousel and Dashboard

**User Story:** As a user who moves between my phone and my tablet, I want the same information and the same selection wherever I look at it, so that the layout change does not cost me my place.

#### Acceptance Criteria

1. WHILE the Layout_Mode is Compact, THE Mobile_Client and THE Web_Client SHALL present the Sensors tab as the Sensor_Carousel with chevron arrow navigation across three per-sensor pages.
2. WHILE the Layout_Mode is Compact, THE Mobile_Client and THE Web_Client SHALL present two bottom tabs, Sensors and Settings.
3. WHEN the Layout_Mode changes from Compact to Medium or Expanded, THE Dashboard_View SHALL apply the channel that was the active Sensor_Carousel page as the selected channel of the Dashboard_View.
4. WHEN the Layout_Mode changes from Medium or Expanded to Compact, THE Sensor_Carousel SHALL open on the page for the channel that was the selected channel of the Dashboard_View.
5. WHEN the Layout_Mode changes, THE Mobile_Client and THE Web_Client SHALL retain the active connection, the buffered reading history, and the current tab or view selection.
6. THE Sensor_Carousel and THE Dashboard_View SHALL present the same live reading values, the same Status, and the same per-day, per-3-day, and per-week averages for a given channel and instant.
7. WHILE Reduce_Motion is disabled, WHEN the Layout_Mode changes, THE Layout_Engine SHALL animate the transition between presentations using the shared motion tokens.
8. WHILE Reduce_Motion is enabled, WHEN the Layout_Mode changes, THE Layout_Engine SHALL apply the new presentation without animated position or size interpolation.

### Requirement 5: Tariff Configuration

**User Story:** As a household paying a water bill, I want to enter my water price, so that the app can tell me what my usage costs.

#### Acceptance Criteria

1. THE Settings tab SHALL provide a Tariff control that accepts a water price in Bolivianos per cubic metre.
2. THE Settings tab SHALL apply a default Tariff value on first run and SHALL label the default as an editable placeholder rather than a billed figure.
3. WHEN the user commits a Tariff value greater than 0 and less than or equal to 1000, THE Settings tab SHALL persist the value and THE Mobile_Client and THE Web_Client SHALL apply the value to every Bs_Equivalence within 320ms.
4. IF the user commits a Tariff entry that is not a number, is less than or equal to 0, or is greater than 1000, THEN THE Settings tab SHALL retain the previously persisted Tariff and SHALL display a message stating the accepted range.
5. THE Settings tab SHALL persist the Tariff with at most 4 decimal places of precision.
6. FOR ALL accepted Tariff values, parsing the value from the Tariff control text and then formatting the parsed value back to text SHALL produce a string that parses to the same value (round-trip property).
7. THE Mobile_Client and THE Web_Client SHALL store the Tariff in the existing settings store and SHALL exclude monetary values from the reading database.
8. THE Settings tab SHALL provide a control that disables Bs_Equivalence display, and WHILE that control is disabled, THE Mobile_Client and THE Web_Client SHALL present volume figures without a Bs_Equivalence.

### Requirement 6: Bolivianos Cost Equivalence Display

**User Story:** As a user reading my consumption figures, I want the cost in Bs. next to the volume, so that I understand my usage in money as well as in litres.

#### Acceptance Criteria

1. WHILE Bs_Equivalence display is enabled, THE Mobile_Client and THE Web_Client SHALL render a Bs_Equivalence adjacent to every cumulative volume total presented to the user.
2. WHILE Bs_Equivalence display is enabled, THE Mobile_Client and THE Web_Client SHALL render a Bs_Equivalence adjacent to the per-day, per-3-day, and per-week volume figures.
3. THE Cost_Formatter SHALL compute a Bs_Equivalence as the canonical litre volume divided by 1000 and multiplied by the Tariff.
4. THE Cost_Formatter SHALL render a Bs_Equivalence with the prefix `Bs.` followed by a space and the amount at 2 decimal places.
5. THE Mobile_Client and THE Web_Client SHALL render a Bs_Equivalence in the secondary text colour and at the body type size, and SHALL render the accompanying volume figure as the primary value.
6. THE Cost_Formatter SHALL operate on canonical litre values and SHALL NOT write any computed monetary value to the reading database.
7. WHEN the displayed volume unit changes, THE Cost_Formatter SHALL produce an unchanged Bs_Equivalence for the same canonical litre volume.
8. IF the Tariff has not been configured by the user, THEN THE Mobile_Client and THE Web_Client SHALL render the Bs_Equivalence together with an indication that the default Tariff is in use.
9. WHILE Reduce_Motion is disabled, WHEN a Bs_Equivalence changes, THE Mobile_Client and THE Web_Client SHALL interpolate the displayed amount using the existing animated metric behaviour.

### Requirement 7: Alerts Panel

**User Story:** As an operator, I want a panel listing what the system has flagged and when, so that I can see the history of problems without opening diagnostics.

#### Acceptance Criteria

1. THE Alerts_Panel SHALL list Alert_Entry rows ordered newest-first.
2. THE Alerts_Panel SHALL render each Alert_Entry with a timestamp, the affected channel name, the Status, and a summary.
3. WHEN the device reports a Status transition into WATCH, LEAK, FAULT, or CAL, THE Alerts_Panel SHALL add a corresponding Alert_Entry within 1 second.
4. WHILE no Alert_Entry exists, THE Alerts_Panel SHALL display an empty state stating that no alerts have been recorded.
5. THE Alerts_Panel SHALL render an Alert_Entry in the LEAK or FAULT Status with the `#3A1C1C` background, `#FF453A` text, and a 4 left border in `#FF453A`, per WattVision §3.
6. THE Alerts_Panel SHALL render a Status_Affordance on every Alert_Entry.
7. WHILE the Layout_Mode is Compact, THE Mobile_Client and THE Web_Client SHALL make the Alert_Entry list reachable from the Sensors tab.
8. THE Alerts_Panel SHALL scroll independently of the Main_Chart WHILE the Layout_Mode is Expanded.
9. THE Alerts_Panel SHALL source Alert_Entry records from the existing event history and SHALL NOT alter the alarm logic or the device-reported Status.

### Requirement 8: Table Row Styling

**User Story:** As someone reading the calibration dataset or a list of alerts, I want rows that are easy to track across, so that I do not lose my line in a dense table.

#### Acceptance Criteria

1. THE Calibration_Table SHALL render each row with a 1 bottom border in the border colour `#2C2C2E`.
2. WHERE a pointing device is present, WHEN the pointer enters a Calibration_Table row, THE Calibration_Table SHALL change that row background to `#252525`.
3. WHEN a Calibration_Table row receives keyboard focus, THE Calibration_Table SHALL apply the same `#252525` row background together with a visible focus indicator.
4. WHERE the Alerts_Panel renders Alert_Entry records as rows, THE Alerts_Panel SHALL apply the same bottom border and the same `#252525` hover and focus background.
5. THE Calibration_Table SHALL render numeric columns in the monospaced type and SHALL align numeric columns on their trailing edge.
6. THE Calibration_Table SHALL present the same calibration values as the firmware dataset reported over the protocol, without modification.
7. WHILE the Layout_Mode is Compact, THE Calibration_Table SHALL remain readable by horizontal scrolling of the table region rather than by shrinking text below the label type size.

### Requirement 9: Appearance Mode Resolution

**User Story:** As a user who asked for a dark-mode setting, I want an appearance choice that still respects the design system's rule against white backgrounds, so that the product stays readable for long data sessions.

#### Acceptance Criteria

1. THE Settings tab SHALL offer Dark as the default appearance and SHALL apply the WattVision §2 dark palette in that appearance.
2. THE Settings tab SHALL offer a High_Contrast_Dark appearance that keeps the background and surface colours within the WattVision §2 dark family and raises text and border contrast.
3. THE Settings tab SHALL present the light appearance within the accessibility section rather than within the primary appearance choice.
4. WHEN the user selects the light appearance, THE Settings tab SHALL display an advisory stating that light backgrounds are outside the WattVision guidance for prolonged data reading.
5. WHILE the light appearance is selected, THE Mobile_Client and THE Web_Client SHALL preserve all functional behaviour and SHALL meet the contrast criteria of Requirement 11.
6. THE Mobile_Client and THE Web_Client SHALL apply the same set of appearance options with the same names.
7. THE Mobile_Client and THE Web_Client SHALL persist the selected appearance across application restarts.
8. THE Mobile_Client and THE Web_Client SHALL exclude pastel colours from every appearance, per WattVision §6.

### Requirement 10: Icon Language

**User Story:** As a user scanning the interface, I want icons that mean something in a water system, so that I can recognise controls and states at a glance.

#### Acceptance Criteria

1. THE Mobile_Client and THE Web_Client SHALL draw every functional icon from the Icon_Language vocabulary: droplet, valve, gauge/meter, pipe, and wave.
2. THE Mobile_Client and THE Web_Client SHALL exclude lightbulb icons and other generic illumination glyphs, per WattVision §6.
3. THE Mobile_Client and THE Web_Client SHALL use the same glyph for the same meaning in both clients.
4. THE Mobile_Client and THE Web_Client SHALL pair every icon that carries meaning with a text label or an accessible name.
5. THE Mobile_Client and THE Web_Client SHALL render icons in the token colours and SHALL size icons on the 8 spacing scale or the type scale.

### Requirement 11: Accessibility

**User Story:** As a user with reduced vision, reduced colour discrimination, or motion sensitivity, I want the interface to stay usable, so that I can rely on the leak monitor.

#### Acceptance Criteria

1. THE Mobile_Client and THE Web_Client SHALL present body text and secondary text at a contrast ratio of at least 4.5 to 1 against the surface behind the text, in every appearance.
2. THE Mobile_Client and THE Web_Client SHALL present text at the KPI type size and the title type size at a contrast ratio of at least 3 to 1 against the surface behind the text, in every appearance.
3. WHEN the primary accent `#00E5FF` is used as a text or icon colour on the card surface `#1E1E1E`, THE compliance test suite SHALL assert the measured contrast ratio and SHALL fail IF the ratio falls below 4.5 to 1.
4. IF the primary accent fails the 4.5 to 1 threshold for a given text use, THEN THE Mobile_Client and THE Web_Client SHALL apply the accent as a non-text graphical element and SHALL render the associated text in the primary text colour.
5. THE Mobile_Client and THE Web_Client SHALL accompany every Status presentation with a Status_Affordance.
6. WHILE Reduce_Motion is enabled, THE Mobile_Client and THE Web_Client SHALL collapse transitions to at most 1ms and SHALL stop ambient looping animation, including in the Dashboard_View and the Alerts_Panel.
7. THE Web_Client SHALL make the KPI cards, the Main_Chart channel selectors, the Alert_Entry rows, and every Settings control reachable and operable by keyboard, with a visible focus indicator at a contrast ratio of at least 3 to 1 against the adjacent background.
8. THE Mobile_Client and THE Web_Client SHALL provide an accessible name and the current value for every KPI readout and every Bs_Equivalence.
9. THE Mobile_Client and THE Web_Client SHALL present interactive targets of at least 44 by 44 logical units WHILE the Layout_Mode is Compact.
10. WHEN the user increases the platform text scale to 200 percent, THE Layout_Engine SHALL present all primary content without clipping text.

### Requirement 12: Locale-Aware Number and Currency Formatting

**User Story:** As a user in Bolivia, I want numbers and prices written the way they are written here, so that the figures read naturally.

#### Acceptance Criteria

1. THE Mobile_Client and THE Web_Client SHALL format every numeric readout and every Bs_Equivalence using the active locale's decimal and grouping separators.
2. WHERE the active locale is Spanish, THE Mobile_Client and THE Web_Client SHALL format a Bs_Equivalence with a comma as the decimal separator and a period as the grouping separator.
3. WHERE the active locale is English, THE Mobile_Client and THE Web_Client SHALL format a Bs_Equivalence with a period as the decimal separator and a comma as the grouping separator.
4. THE Mobile_Client and THE Web_Client SHALL render the currency prefix as `Bs.` in every locale.
5. THE Tariff control SHALL accept a value entered with the active locale's decimal separator.
6. THE Mobile_Client and THE Web_Client SHALL resolve the active locale from the platform locale and SHALL fall back to English WHERE the platform locale has no available translation.
7. THE Mobile_Client and THE Web_Client SHALL format timestamps in the Alerts_Panel and the event log using the active locale's date and time conventions.

### Requirement 13: Cross-Client Parity and Non-Regression

**User Story:** As a developer using the web client to cross-check the firmware, I want both clients to behave identically and to keep building clean, so that a disagreement between them means a real defect.

#### Acceptance Criteria

1. FOR ALL Layout_Modes, THE Mobile_Client and THE Web_Client SHALL present the same information architecture, the same Layout_Mode thresholds, and the same column spans.
2. WHEN the same telemetry sequence is applied to both clients, THE Mobile_Client and THE Web_Client SHALL present the same Status, the same live readings, the same averages, and the same Bs_Equivalence for each channel.
3. WHEN `tsc` runs in strict mode over `react_app`, THE Web_Client SHALL report 0 errors.
4. WHEN the Vite production build runs over `react_app`, THE Web_Client SHALL complete the build with 0 errors.
5. WHEN `flutter analyze` runs over `flutter_app`, THE Mobile_Client SHALL report 0 errors.
6. THE Mobile_Client and THE Web_Client SHALL preserve the Connection_Gate behaviour, including the `requireConnectionToBrowse` setting.
7. THE Mobile_Client and THE Web_Client SHALL preserve the existing local database schema behaviour, the logging interval settings, the retention settings, and the pruning behaviour.
8. THE Mobile_Client and THE Web_Client SHALL preserve canonical storage in litres per minute and litres, and SHALL treat unit and currency conversion as presentation-only.
9. THE Mobile_Client and THE Web_Client SHALL leave the wire protocol, the firmware configuration, the calibration dataset, and the alarm logic unchanged.
10. THE Mobile_Client and THE Web_Client SHALL preserve the Diagnostics_Sheet contents: link health, firmware configuration, Calibration_Table, event log, and raw traffic.

## Open Decisions

These items are resolved above with a stated default. Each is worth a deliberate confirmation before design.

1. **Light appearance** (Requirement 9). The default taken here keeps the shipped light theme but moves it out of the primary appearance choice into the accessibility section with an advisory, and adds a High_Contrast_Dark option. The alternatives are removing light mode entirely to follow WattVision §6 literally, or leaving it as a peer appearance option.
2. **Localisation scope** (Requirement 12). The default taken here is locale-aware number, currency, and date formatting with English as the fallback UI language. Full Spanish (es-BO) interface copy is not required by these criteria; adding it would extend scope to every string in both clients.
3. **Tariff unit** (Requirement 5). The default is Bs. per cubic metre, which matches how water is billed. Bs. per litre could be offered as an alternative entry unit.
4. **Amber WATCH colour** (Requirement 1). The default keeps `#FFD60A` as a recorded Token_Extension. The alternative is replacing it with the secondary accent plus a distinct Status_Affordance so the palette stays exactly at WattVision §2.
