import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { App } from './App';
import { monitorStore } from './state/monitorStore';
import './styles/global.css';

const container = document.getElementById('root');
if (!container) throw new Error('Root container missing from index.html');

// Open the database and start the aggregate/staleness timers before the first
// paint. The store is a module singleton, so this runs once even under StrictMode's
// double-invoked effects.
void monitorStore.initialise();

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
