// App version injected at build time from package.json via Vite define.
// Bump the version in package.json — it flows here automatically.
declare const __APP_VERSION__: string;
export const APP_VERSION: string = __APP_VERSION__;
