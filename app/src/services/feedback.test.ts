import {
  feedbackSetComplete, feedbackExerciseComplete, feedbackRestComplete,
  feedbackUndo, feedbackSessionComplete, feedbackVoiceMilestone,
} from './feedback';
import { appData } from '../state';
import { createDefaultAppData } from '../types';

// Reset appData to defaults before each test
beforeEach(() => {
  appData.value = {
    ...createDefaultAppData(),
    profile: {
      ...createDefaultAppData().profile,
      soundMode: 'on',
      voiceAnnouncements: true,
    },
  };
  vi.clearAllMocks();
});

describe('feedbackSetComplete', () => {
  it('calls navigator.vibrate', () => {
    feedbackSetComplete();
    expect(navigator.vibrate).toHaveBeenCalledWith(50);
  });
});

describe('feedbackExerciseComplete', () => {
  it('calls navigator.vibrate with pattern', () => {
    feedbackExerciseComplete();
    expect(navigator.vibrate).toHaveBeenCalledWith([50, 50, 50]);
  });
});

describe('feedbackRestComplete', () => {
  it('calls navigator.vibrate with pattern', () => {
    feedbackRestComplete();
    expect(navigator.vibrate).toHaveBeenCalledWith([50, 50, 50, 50, 50]);
  });
});

describe('feedbackUndo', () => {
  it('calls navigator.vibrate', () => {
    feedbackUndo();
    expect(navigator.vibrate).toHaveBeenCalledWith(150);
  });
});

describe('feedbackSessionComplete', () => {
  it('calls navigator.vibrate with pattern', () => {
    feedbackSessionComplete();
    expect(navigator.vibrate).toHaveBeenCalledWith([150, 50, 50, 50, 150]);
  });
});

describe('soundMode off suppresses vibrate', () => {
  it('does not vibrate when soundMode is off', () => {
    appData.value = {
      ...appData.value,
      profile: { ...appData.value.profile, soundMode: 'off' },
    };
    feedbackSetComplete();
    expect(navigator.vibrate).not.toHaveBeenCalled();
  });
});

describe('feedbackVoiceMilestone', () => {
  it('returns 60 for ~60 seconds remaining', () => {
    // 60000ms → Math.ceil(60000/1000) = 60
    const result = feedbackVoiceMilestone(60000);
    expect(result).toBe(60);
  });

  it('returns 30 for ~30 seconds remaining', () => {
    const result = feedbackVoiceMilestone(30000);
    expect(result).toBe(30);
  });

  it('returns 15 for ~15 seconds remaining', () => {
    const result = feedbackVoiceMilestone(15000);
    expect(result).toBe(15);
  });

  it('returns 5 for ~5 seconds remaining', () => {
    const result = feedbackVoiceMilestone(5000);
    expect(result).toBe(5);
  });

  it('returns 1 for ~1 second remaining', () => {
    const result = feedbackVoiceMilestone(1000);
    expect(result).toBe(1);
  });

  it('returns null for non-milestone time (45s)', () => {
    const result = feedbackVoiceMilestone(45000);
    expect(result).toBeNull();
  });

  it('returns null for non-milestone time (10s)', () => {
    const result = feedbackVoiceMilestone(10000);
    expect(result).toBeNull();
  });
});
