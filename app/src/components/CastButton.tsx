import { useEffect } from 'preact/hooks';
import { castState, initCast, requestCast, stopCast } from '../services/cast';
import { IconCast } from './Icons';

export function CastButton() {
  useEffect(() => {
    initCast();
  }, []);

  const { available, connected, loading } = castState.value;

  if (loading || !available) return null;

  return (
    <button
      class={`cast-btn${connected ? ' connected' : ''}`}
      onClick={connected ? stopCast : requestCast}
      aria-label={connected ? 'Disconnect Chromecast' : 'Cast to TV'}
    >
      <IconCast connected={connected} />
    </button>
  );
}
