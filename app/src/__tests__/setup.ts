import '@testing-library/jest-dom/vitest';

// Stub navigator.vibrate (not in jsdom)
Object.defineProperty(navigator, 'vibrate', {
  value: vi.fn(() => true),
  writable: true,
});

// Stub speechSynthesis (not in jsdom)
Object.defineProperty(window, 'speechSynthesis', {
  value: {
    speak: vi.fn(),
    cancel: vi.fn(),
    getVoices: vi.fn(() => []),
  },
  writable: true,
});

// Stub AudioContext (not in jsdom)
class MockAudioContext {
  state = 'running';
  currentTime = 0;
  sampleRate = 44100;
  resume = vi.fn();
  createOscillator = vi.fn(() => ({
    type: 'sine',
    frequency: { value: 0 },
    connect: vi.fn(),
    start: vi.fn(),
    stop: vi.fn(),
  }));
  createGain = vi.fn(() => ({
    gain: { setValueAtTime: vi.fn(), exponentialRampToValueAtTime: vi.fn() },
    connect: vi.fn(),
  }));
  createBuffer = vi.fn(() => ({}));
  createBufferSource = vi.fn(() => ({
    buffer: null,
    connect: vi.fn(),
    start: vi.fn(),
  }));
  destination = {};
}
(globalThis as any).AudioContext = MockAudioContext;
