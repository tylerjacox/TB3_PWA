// Haptic + Audio feedback (PRD 10.6)
import { appData } from '../state';

let audioCtx: AudioContext | null = null;
let unlocked = false;

function getAudioCtx(): AudioContext {
  if (!audioCtx) audioCtx = new AudioContext();
  return audioCtx;
}

// iOS suspends AudioContext until resumed inside a user gesture.
// Call this once on first tap to unlock audio for the session.
function unlockAudioCtx() {
  if (unlocked) return;
  unlocked = true;
  const ctx = getAudioCtx();
  if (ctx.state === 'suspended') ctx.resume();
  // Play a silent buffer to fully unlock on iOS
  const buf = ctx.createBuffer(1, 1, ctx.sampleRate);
  const src = ctx.createBufferSource();
  src.buffer = buf;
  src.connect(ctx.destination);
  src.start();
}

if (typeof document !== 'undefined') {
  document.addEventListener('touchstart', unlockAudioCtx, { once: true });
  document.addEventListener('click', unlockAudioCtx, { once: true });
}

function vibrate(pattern: number | number[]) {
  const mode = appData.value.profile.soundMode;
  if (mode === 'off') return;
  if (navigator.vibrate) navigator.vibrate(pattern);
}

type ToneSpec = { freq: number; duration: number; delay: number; type?: OscillatorType };

function playTones(tones: ToneSpec[]) {
  const mode = appData.value.profile.soundMode;
  if (mode !== 'on') return;
  try {
    const ctx = getAudioCtx();
    if (ctx.state === 'suspended') ctx.resume();
    const now = ctx.currentTime;
    for (const t of tones) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      const start = now + t.delay / 1000;
      const dur = t.duration / 1000;
      osc.type = t.type ?? 'sine';
      osc.frequency.value = t.freq;
      gain.gain.setValueAtTime(0.15, start);
      gain.gain.exponentialRampToValueAtTime(0.001, start + dur);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(start);
      osc.stop(start + dur);
    }
  } catch { /* Audio may not be available */ }
}

export function feedbackSetComplete() {
  vibrate(50);
  playTones([
    { freq: 660, duration: 60, delay: 0 },
    { freq: 880, duration: 80, delay: 60 },
  ]);
}

export function feedbackExerciseComplete() {
  vibrate([50, 50, 50]);
  playTones([
    { freq: 784, duration: 100, delay: 0 },
    { freq: 1047, duration: 150, delay: 100 },
    { freq: 1319, duration: 200, delay: 250 },
  ]);
}

export function feedbackRestComplete() {
  vibrate([50, 50, 50, 50, 50]);
  playTones([
    { freq: 523, duration: 100, delay: 0 },
    { freq: 659, duration: 100, delay: 100 },
    { freq: 784, duration: 150, delay: 200 },
  ]);
  speak('Go');
}

export function feedbackUndo() {
  vibrate(150);
}

export function feedbackSessionComplete() {
  vibrate([150, 50, 50, 50, 150]);
  playTones([
    { freq: 523, duration: 150, delay: 0 },
    { freq: 659, duration: 150, delay: 150 },
    { freq: 784, duration: 200, delay: 300 },
  ]);
}

export function feedbackError() {
  vibrate([30, 30, 30]);
  playTones([{ freq: 220, duration: 100, delay: 0, type: 'square' }]);
}

// --- Voice Announcements ---

const speechAvailable = typeof window !== 'undefined' && 'speechSynthesis' in window;

export function isSpeechAvailable(): boolean {
  return speechAvailable;
}

function getSelectedVoice(): SpeechSynthesisVoice | null {
  const name = appData.value.profile.voiceName;
  if (!name) return null;
  const voices = speechSynthesis.getVoices();
  return voices.find((v) => v.name === name) ?? null;
}

export function getAvailableVoices(): SpeechSynthesisVoice[] {
  return speechSynthesis
    .getVoices()
    .filter((v) => v.lang.startsWith('en'))
    .sort((a, b) => a.name.localeCompare(b.name));
}

function speak(text: string) {
  if (!speechAvailable) return;
  if (!appData.value.profile.voiceAnnouncements) return;
  try {
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.rate = 1.1;
    const voice = getSelectedVoice();
    if (voice) u.voice = voice;
    speechSynthesis.speak(u);
  } catch { /* Speech may not be available */ }
}

export function speakTest(text: string, voiceName: string | null) {
  if (!speechAvailable) return;
  try {
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.rate = 1.1;
    if (voiceName) {
      const voice = speechSynthesis.getVoices().find((v) => v.name === voiceName);
      if (voice) u.voice = voice;
    }
    speechSynthesis.speak(u);
  } catch { /* Speech may not be available */ }
}

const MILESTONE_LABELS: Record<number, string> = {
  60: 'One minute',
  30: 'Thirty seconds',
  15: 'Fifteen seconds',
  5: '5', 4: '4', 3: '3', 2: '2', 1: '1',
};

export function feedbackVoiceMilestone(remainingMs: number): number | null {
  const sec = Math.ceil(remainingMs / 1000);
  const label = MILESTONE_LABELS[sec];
  if (label) {
    speak(label);
    return sec;
  }
  return null;
}
