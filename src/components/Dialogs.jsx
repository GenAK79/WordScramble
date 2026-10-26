import { useState } from 'react';
import { LETTERS } from '../lib/tiles.js';
import { go } from '../lib/router.js';
import { Modal, PlayerDot } from './ui.jsx';
import { Tile } from './Board.jsx';

const collins = (w) => `https://www.collinsdictionary.com/dictionary/english/${encodeURIComponent(w.toLowerCase())}`;

export function describeMove(m, byId) {
  const who = byId[m.player_id]?.name ?? 'Someone';
  switch (m.kind) {
    case 'play': {
      const words = (m.words ?? []).map((w) => w.word).join(', ');
      return `${who} played ${words} for ${m.score}`;
    }
    case 'pass': return `${who} passed`;
    case 'swap': return `${who} swapped ${m.info?.count ?? ''} tile${m.info?.count === 1 ? '' : 's'}`;
    case 'skip': return `${who} was skipped by the host`;
    case 'end': return 'Game over';
    default: return '';
  }
}

export function WordLinks({ words }) {
  return (
    <ul className="word-links">
      {words.map((w, i) => (
        <li key={i}>
          <strong>{w.word}</strong>
          <a href={collins(w.word)} target="_blank" rel="noopener noreferrer">Look up in Collins ↗</a>
        </li>
      ))}
    </ul>
  );
}

export function BlankPicker({ onPick, onCancel }) {
  return (
    <Modal title="Which letter is the blank?" onClose={onCancel}>
      <div className="letter-grid">
        {LETTERS.map((l) => (
          <button key={l} className="btn letter" onClick={() => onPick(l)}>{l}</button>
        ))}
      </div>
    </Modal>
  );
}

export function SwapDialog({ slots, busy, onSwap, onClose }) {
  const [picked, setPicked] = useState(new Set());
  const rackTiles = slots.filter((e) => e && !e.cell);
  const toggle = (id) => setPicked((s) => {
    const n = new Set(s);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });
  const chosen = rackTiles.filter((e) => picked.has(e.id));
  return (
    <Modal title="Swap tiles" onClose={onClose}>
      <p>Choose the tiles to swap. You'll lose your turn.</p>
      <div className="swap-row">
        {rackTiles.map((e) => (
          <button key={e.id} className={`swap-tile ${picked.has(e.id) ? 'picked' : ''}`} onClick={() => toggle(e.id)} aria-pressed={picked.has(e.id)}>
            <Tile letter={e.letter === '?' ? '' : e.letter} blank={e.letter === '?'} />
          </button>
        ))}
      </div>
      <div className="row">
        <button className="btn primary" disabled={chosen.length === 0 || busy} onClick={() => onSwap(chosen.map((e) => e.letter))}>
          Swap {chosen.length || ''} tile{chosen.length === 1 ? '' : 's'}
        </button>
        <button className="btn" onClick={onClose}>Cancel</button>
      </div>
    </Modal>
  );
}

export function PassDialog({ busy, onPass, onClose }) {
  return (
    <Modal title="Pass your turn?" onClose={onClose}>
      <p>You won't score this turn. Six scoreless turns in a row end the game.</p>
      <div className="row">
        <button className="btn primary" disabled={busy} onClick={onPass}>Pass</button>
        <button className="btn" onClick={onClose}>Cancel</button>
      </div>
    </Modal>
  );
}

// Everyone except the mover votes. Unanimous accept keeps the play; any reject undoes it.
export function ChallengeDialog({ move, players, meId, isHost, busy, onVote, onHostAccept }) {
  const byId = Object.fromEntries(players.map((p) => [p.id, p]));
  const mover = byId[move.player_id];
  const challenger = byId[move.challenge_by];
  const voters = players.filter((p) => p.id !== move.player_id);
  const myVote = move.votes?.[meId];
  const canVote = meId !== move.player_id && myVote === undefined;
  return (
    <Modal title="Word challenged">
      <p><strong>{challenger?.name}</strong> challenged <strong>{mover?.name}</strong>'s play. Check the words, then vote.</p>
      <WordLinks words={move.words ?? []} />
      <p className="muted small-text">
        Every player except {mover?.name} votes. The play stays only if everyone accepts; otherwise the tiles go back and {mover?.name} loses the turn.
      </p>
      <ul className="vote-list">
        {voters.map((p) => {
          const v = move.votes?.[p.id];
          return (
            <li key={p.id}>
              <PlayerDot index={p.seat} /> {p.name}{p.id === meId ? ' (you)' : ''}
              <span className={`vote ${v === undefined ? 'wait' : v ? 'yes' : 'no'}`}>
                {v === undefined ? 'waiting…' : v ? 'accepts' : 'rejects'}
              </span>
            </li>
          );
        })}
      </ul>
      {canVote && (
        <div className="row">
          <button className="btn primary" disabled={busy} onClick={() => onVote(true)}>Accept words</button>
          <button className="btn danger" disabled={busy} onClick={() => onVote(false)}>Reject words</button>
        </div>
      )}
      {!canVote && meId === move.player_id && <p className="muted">Waiting for the other players to vote…</p>}
      {!canVote && meId !== move.player_id && <p className="muted">Your vote is in. Waiting for the others…</p>}
      {isHost && (
        <button className="btn ghost small" disabled={busy} onClick={onHostAccept}>
          Host: accept the words (for absent players)
        </button>
      )}
    </Modal>
  );
}

export function MoveLog({ moves, players, onClose }) {
  const byId = Object.fromEntries(players.map((p) => [p.id, p]));
  return (
    <Modal title="Moves" onClose={onClose} wide>
      {moves.length === 0 && <p className="muted">No moves yet.</p>}
      <ol className="move-log" reversed>
        {moves.map((m) => (
          <li key={m.seq} className={m.status === 'reverted' ? 'reverted' : ''}>
            {m.player_id && <PlayerDot index={byId[m.player_id]?.seat ?? 0} />}
            <span>{describeMove(m, byId)}</span>
            {m.status === 'challenged' && <em className="badge warn">challenged</em>}
            {m.status === 'upheld' && <em className="badge ok">challenge failed</em>}
            {m.status === 'reverted' && <em className="badge bad">undone</em>}
          </li>
        ))}
      </ol>
    </Modal>
  );
}

export function ResultsDialog({ players, moves, finalRacks, meId, onClose }) {
  const ranked = [...players].sort((a, b) => b.score - a.score);
  const top = ranked[0]?.score;
  const end = moves.find((m) => m.kind === 'end');
  const delta = Object.fromEntries((end?.info?.adjustments ?? []).map((a) => [a.player_id, a.delta]));
  return (
    <Modal title="Game over" onClose={onClose}>
      <ol className="results">
        {ranked.map((p, i) => (
          <li key={p.id} className={p.score === top ? 'winner' : ''}>
            <span className="rank">{p.score === top ? '🏆' : i + 1}</span>
            <span className="rname"><PlayerDot index={p.seat} /> {p.name}{p.id === meId ? ' (you)' : ''}</span>
            <span className="rscore">{p.score}</span>
            {delta[p.id] !== undefined && delta[p.id] !== 0 && (
              <span className="muted small-text rdelta">
                {delta[p.id] > 0 ? '+' : ''}{delta[p.id]} end of game
                {finalRacks?.[p.id]?.length ? ` · left: ${finalRacks[p.id].map((l) => (l === '?' ? '_' : l)).join('')}` : ''}
              </span>
            )}
          </li>
        ))}
      </ol>
      <div className="row">
        <button className="btn primary" onClick={() => go('/')}>Home</button>
        <button className="btn" onClick={onClose}>View board</button>
      </div>
    </Modal>
  );
}
