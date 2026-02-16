import { render } from 'preact';
import { App } from './app';
import { initApp } from './state';
import { initRouter } from './router';
import { applyDynamicType } from './services/dynamicType';
import { initCastSync } from './services/cast';
import './style.css';

// Initialize router
initRouter();

// Initialize app data from IndexedDB
initApp();

// Dynamic Type probe
applyDynamicType();

// Cast sync (reactive effect — SDK loaded lazily on Cast button tap)
initCastSync();

// Keyboard handling (PRD 6.4)
window.visualViewport?.addEventListener('resize', () => {
  const keyboardOpen = window.visualViewport!.height < window.innerHeight * 0.75;
  document.documentElement.classList.toggle('keyboard-open', keyboardOpen);
});

// Render
render(<App />, document.getElementById('app')!);
