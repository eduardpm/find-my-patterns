import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import './styles/base.css';

// No service worker is registered, deliberately: FR-025 forbids diary content in storage that
// survives the tab, and a service worker exists to cache exactly that. This also keeps the web
// client out of the reminder business (FR-020) — the phone stays the only reminder surface.

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
);
