/**
 * The Web_Client per-channel components, extracted from `screens/SensorsTab.tsx`
 * (task 7.3).
 *
 * One import site for the carousel today and `DashboardView` (task 9.9)
 * tomorrow, so both compose the identical channel presentation rather than
 * drifting apart.
 *
 * _Requirements: 3.5, 4.6, 13.1_
 */
export { SensorPage, HERO_KPI_SIZE, DENSE_KPI_SIZE } from './SensorPage';
export { Averages, WindowDetail } from './Averages';
export { BalanceCard, BranchShareCard, TotalsCard, EnvelopeExplainer } from './cards';
