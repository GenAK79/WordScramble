import { useState } from 'react';
import { api } from '../lib/api.js';
import { errorMessage } from '../lib/errors.js';
import { inviteUrl } from '../lib/router.js';
import { PlayerDot, useApp } from './ui.jsx';

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Fallback for older/locked-down browsers
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }
}

export default function Lobby({ state, refresh }) {
  const { notify } = useApp();
  const { game, players, me } = state;
  const isHost = game.host_player_id === me;
  const host = players.find((p) => p.id === game.host_player_id);
  const [copied, setCopied] = useState(false);
  const [busy, setBusy] = useState(false);

  const message =
    `Join my game of Word Scramble!\nGame code: ${game.code}\nLink: ${inviteUrl(game.code)}`;

  const copy = async () => {
    const ok = await copyText(message);
    if (ok) {
      setCopied(true);
      setTimeout(() => setCopied(false), 2200);
    } else {
      notify("Couldn't copy — select the message and copy it manually.", 'error');
    }
  };

  const start = async () => {
    setBusy(true);
    try {
      await api.startGame(game.id);
      await refresh();
    } catch (e) {
      notify(errorMessage(e), 'error');
    } finally {
      setBusy(false);
    }
  };

  const slots = Array.from({ length: game.max_players }, (_, i) => players.find((p) => p.seat === i) ?? null);

  return (
    <main className="page narrow">
      <h1>Game lobby</h1>

      <div className="card stack">
        <div className="center">
          <div className="muted small-text">Game code</div>
          <div className="big-code" aria-label={`Game code ${game.code.split('').join(' ')}`}>{game.code}</div>
        </div>
        <pre className="invite" aria-label="Invitation message">{message}</pre>
        <button className="btn primary big" onClick={copy}>{copied ? '✓ Copied!' : 'Copy invitation'}</button>
        <p className="muted small-text center">Send this to your friends. They open the link (or tap Join Game and type the code).</p>
      </div>

      <div className="card stack">
        <h3>Players ({players.length}/{game.max_players})</h3>
        <ul className="player-list">
          {slots.map((p, i) => (
            <li key={i} className={p ? '' : 'empty'}>
              <PlayerDot index={i} />
              {p ? <span>{p.name}{p.id === me ? ' (you)' : ''}{p.id === game.host_player_id ? ' · host' : ''}</span> : <span>Waiting for player…</span>}
            </li>
          ))}
        </ul>
        {isHost ? (
          <>
            <button className="btn primary big" onClick={start} disabled={players.length < 2 || busy}>
              {busy ? 'Starting…' : `Start game with ${players.length} players`}
            </button>
            {players.length < 2 && <p className="muted small-text center">Waiting for at least one more player.</p>}
            {players.length >= 2 && players.length < game.max_players && (
              <p className="muted small-text center">Not everyone has joined — starting now closes the game to new players.</p>
            )}
          </>
        ) : (
          <p className="muted center">Waiting for {host?.name ?? 'the host'} to start the game…</p>
        )}
      </div>
    </main>
  );
}
