import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase.js';
import { api } from './api.js';

// Loads get_state() for a game and keeps it fresh:
//  - Supabase Realtime on the games row (bumped by every action)
//  - a slow poll as a safety net, and a refresh when the tab becomes visible
export function useGameState(gameId) {
  const [state, setState] = useState(null);
  const [error, setError] = useState(null);
  const alive = useRef(true);
  const inflight = useRef(false);
  const queued = useRef(false);

  const refresh = useCallback(async () => {
    if (inflight.current) { queued.current = true; return; }
    inflight.current = true;
    try {
      const s = await api.getState(gameId);
      if (alive.current) { setState(s); setError(null); }
    } catch (e) {
      if (alive.current) setError(e);
    } finally {
      inflight.current = false;
      if (queued.current) { queued.current = false; refresh(); }
    }
  }, [gameId]);

  useEffect(() => {
    alive.current = true;
    setState(null);
    setError(null);
    refresh();

    const channel = supabase
      .channel(`game-${gameId}`)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'games', filter: `id=eq.${gameId}` },
        () => refresh())
      .subscribe();

    const poll = setInterval(() => { if (!document.hidden) refresh(); }, 15000);
    const onVisible = () => { if (!document.hidden) refresh(); };
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('online', onVisible);

    return () => {
      alive.current = false;
      clearInterval(poll);
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('online', onVisible);
      supabase.removeChannel(channel);
    };
  }, [gameId, refresh]);

  return { state, error, refresh };
}
