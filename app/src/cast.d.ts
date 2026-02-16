// Minimal type stubs for Google Cast SDK globals

declare namespace cast {
  namespace framework {
    class CastContext {
      static getInstance(): CastContext;
      setOptions(options: {
        receiverApplicationId: string;
        autoJoinPolicy: string;
      }): void;
      requestSession(): Promise<void>;
      endCurrentSession(stopCasting: boolean): void;
      getCurrentSession(): CastSession | null;
      addEventListener(type: string, listener: (event: any) => void): void;
    }

    class CastSession {
      getSessionObj(): { receiver: { friendlyName: string } };
      sendMessage(namespace: string, message: string): Promise<void>;
    }

    enum SessionState {
      NO_SESSION = 'NO_SESSION',
      SESSION_STARTING = 'SESSION_STARTING',
      SESSION_STARTED = 'SESSION_STARTED',
      SESSION_START_FAILED = 'SESSION_START_FAILED',
      SESSION_ENDING = 'SESSION_ENDING',
      SESSION_ENDED = 'SESSION_ENDED',
      SESSION_RESUMED = 'SESSION_RESUMED',
    }

    enum CastContextEventType {
      SESSION_STATE_CHANGED = 'sessionstatechanged',
    }
  }
}

declare namespace chrome.cast {
  enum AutoJoinPolicy {
    ORIGIN_SCOPED = 'origin_scoped',
  }
}

interface Window {
  __onGCastApiAvailable?: (isAvailable: boolean) => void;
  cast?: typeof cast;
  chrome?: { cast?: typeof chrome.cast };
}
