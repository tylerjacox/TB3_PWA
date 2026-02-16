// Inline SVG Icons (PRD 8 — filled + outlined for tab states)

export function IconHome({ filled = false }: { filled?: boolean }) {
  if (filled) {
    return (
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M12 3l9 8v10a1 1 0 01-1 1h-5v-7h-6v7H4a1 1 0 01-1-1V11l9-8z" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M3 12l9-9 9 9" /><path d="M5 10v10a1 1 0 001 1h3v-6h6v6h3a1 1 0 001-1V10" />
    </svg>
  );
}

export function IconCalendar({ filled = false }: { filled?: boolean }) {
  if (filled) {
    return (
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M7 2v2H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V6a2 2 0 00-2-2h-2V2h-2v2H9V2H7zM5 10h14v10H5V10z" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <rect x="3" y="4" width="18" height="18" rx="2" /><line x1="16" y1="2" x2="16" y2="6" /><line x1="8" y1="2" x2="8" y2="6" /><line x1="3" y1="10" x2="21" y2="10" />
    </svg>
  );
}

export function IconClock({ filled = false }: { filled?: boolean }) {
  if (filled) {
    return (
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 11h-4v-2h3V7h2v6z" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" />
    </svg>
  );
}

export function IconPerson({ filled = false }: { filled?: boolean }) {
  if (filled) {
    return (
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M12 12c2.76 0 5-2.24 5-5s-2.24-5-5-5-5 2.24-5 5 2.24 5 5 5zm0 2c-3.33 0-10 1.67-10 5v2h20v-2c0-3.33-6.67-5-10-5z" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle cx="12" cy="8" r="5" /><path d="M20 21v-2a7 7 0 00-7-7h-2a7 7 0 00-7 7v2" />
    </svg>
  );
}

export function IconCheck() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" width="16" height="16">
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );
}

export function IconChevronLeft() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" width="20" height="20">
      <polyline points="15 18 9 12 15 6" />
    </svg>
  );
}

export function IconChevronRight() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" width="20" height="20">
      <polyline points="9 6 15 12 9 18" />
    </svg>
  );
}

export function IconChevronDown() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" width="16" height="16">
      <polyline points="6 9 12 15 18 9" />
    </svg>
  );
}

export function IconPlus() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true" width="20" height="20">
      <line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" />
    </svg>
  );
}

export function IconMinus() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true" width="20" height="20">
      <line x1="5" y1="12" x2="19" y2="12" />
    </svg>
  );
}

export function IconMore() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" width="24" height="24">
      <circle cx="12" cy="5" r="2" /><circle cx="12" cy="12" r="2" /><circle cx="12" cy="19" r="2" />
    </svg>
  );
}

export function IconClose() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true" width="20" height="20">
      <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

export function IconCast({ connected = false }: { connected?: boolean }) {
  if (connected) {
    return (
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" width="24" height="24">
        <path d="M1 18v3h3c0-1.66-1.34-3-3-3zm0-4v2c2.76 0 5 2.24 5 5h2c0-3.87-3.13-7-7-7zm0-4v2a9 9 0 019 9h2c0-6.08-4.93-11-11-11zm20-7H3c-1.1 0-2 .9-2 2v3h2V5h18v14h-7v2h7c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2z" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" width="24" height="24">
      <path d="M21 3H3c-1.1 0-2 .9-2 2v3h2V5h18v14h-7v2h7c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM1 18v3h3c0-1.66-1.34-3-3-3zm0-4v2c2.76 0 5 2.24 5 5h2c0-3.87-3.13-7-7-7zm0-4v2a9 9 0 019 9h2c0-6.08-4.93-11-11-11z" />
    </svg>
  );
}
