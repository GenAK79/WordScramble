import { useEffect, useState } from 'react';
import { api } from '../lib/api.js';
import { errorMessage } from '../lib/errors.js';
import { go } from '../lib/router.js';
import { Modal, Spinner, TileWord, useApp } from './ui.jsx';

export function Home() {
  const { name } = useApp();
  return (
    <main className="page narrow">
      <TileWord word="WORD" size="lg" />
      <TileWord word="SCRAMBLE" size="lg" />
      <p className="center muted">Playing as <strong>{name}</strong></p>
      <div className="stack big-buttons">
        <button className="btn primary big" onClick={() => go('/new')}>New Game</button>
        <button className="btn big" onClick={() => go('/resume')}>Resume Game</button>
        <button className="btn big" onClick={() => go('/join')}>Join Game</button>
      </div>
    </main>
  );
}

export function NewGame() {
  const { name, notify } = useApp();
  const [count, setCount] = useState(4);
  const [busy, setBusy] = useState(false);

  const create = async () => {
    setBusy(true);
    try {
      const g = await api.createGame(name, count);
      go(`/game/${g.id}`);
    } catch (e) {
      notify(errorMessage(e), 'error');
      setBusy(false);
    }
  };

  return (
    <main className="page narrow">
      <h1>New game</h1>
      <div className="card stack">
        <p>How many players in total, including you?</p>
        <div className="segmented" role="radiogroup" aria-label="Number of players">
          {[2, 3, 4].map((n) => (
            <button
              key={n}
              role="radio"
              aria-checked={count === n}
              className={count === n ? 'seg active' : 'seg'}
              onClick={() => setCount(n)}
            >{n}</button>
          ))}
        </div>
        <p className="muted">
          You'll get a game code and link to send to {count - 1} other {count - 1 === 1 ? 'player' : 'players'}.
          You can start as soon as at least one has joined.
        </p>
        <button className="btn primary big" onClick={create} disabled={busy}>
          {busy ? 'Creating…' : 'Create game'}
        </button>
      </div>
    </main>
  );
}

const cleanCode = (s) => s.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 5);

export function JoinGame({ initialCode = '' }) {
  const { name, notify } = useApp();
  const [code, setCode] = useState(cleanCode(initialCode));
  const [info, setInfo] = useState(null);
  const [lookupError, setLookupError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [confirmTakeover, setConfirmTakeover] = useState(false);

  useEffect(() => {
    setInfo(null);
    setLookupError(null);
    if (code.length !== 5) return undefined;
    let cancelled = false;
    api.peekGame(code)
      .then((r) => { if (!cancelled) setInfo(r); })
      .catch((e) => { if (!cancelled) setLookupError(errorMessage(e)); });
    return () => { cancelled = true; };
  }, [code]);

  const join = async (takeover = false) => {
    setBusy(true);
    try {
      const r = await api.joinGame(code, name, takeover);
      go(`/game/${r.id}`);
    } catch (e) {
      if (e.code === 'NAME_TAKEN' && !takeover) setConfirmTakeover(true);
      else notify(errorMessage(e), 'error');
      setBusy(false);
    }
  };

  const statusText = info && {
    lobby: 'Waiting for players to join',
    active: 'Game in progress',
    closing: 'Game in progress',
    finished: 'Finished'
  }[info.status];

  return (
    <main className="page narrow">
      <h1>Join game</h1>
      <div className="card stack">
        <label className="field">
          <span>Game code</span>
          <input
            className="code-input"
            value={code}
            onChange={(e) => setCode(cleanCode(e.target.value))}
            placeholder="ABCDE"
            inputMode="text"
            autoCapitalize="characters"
            autoComplete="off"
            autoCorrect="off"
            spellCheck="false"
            maxLength={5}
            autoFocus={!initialCode}
          />
        </label>
        {lookupError && <p className="error-text">{lookupError}</p>}
        {info && (
          <div className="info-box">
            <div><strong>{info.host_name}</strong>'s game</div>
            <div className="muted">{info.player_count} of {info.max_players} players · {statusText}</div>
          </div>
        )}
        {info?.is_member ? (
          <button className="btn primary big" onClick={() => go(`/game/${info.id}`)}>Open your game</button>
        ) : (
          <button className="btn primary big" onClick={() => join(false)} disabled={code.length !== 5 || busy || !!lookupError}>
            {busy ? 'Joining…' : `Join as ${name}`}
          </button>
        )}
        <p className="muted small-text">
          Playing already on another device? Enter the code and use your original name to take your seat back.
        </p>
      </div>
      {confirmTakeover && (
        <Modal title="Is that you?" onClose={() => setConfirmTakeover(false)}>
          <p>Someone called <strong>{name}</strong> is already in this game. If that was you (new device or cleared browser), you can take over that seat.</p>
          <div className="row">
            <button className="btn primary" onClick={() => { setConfirmTakeover(false); join(true); }}>Yes, that's me</button>
            <button className="btn" onClick={() => setConfirmTakeover(false)}>No, use another name</button>
          </div>
        </Modal>
      )}
    </main>
  );
}

const STATUS_LABEL = { lobby: 'Waiting for players', active: 'In progress', closing: 'In progress', finished: 'Finished' };

export function Resume() {
  const { notify } = useApp();
  const [games, setGames] = useState(null);

  useEffect(() => {
    let cancelled = false;
    api.myGames()
      .then((g) => { if (!cancelled) setGames(g); })
      .catch((e) => { if (!cancelled) { notify(errorMessage(e), 'error'); setGames([]); } });
    return () => { cancelled = true; };
  }, [notify]);

  if (!games) return <Spinner />;

  const open = games.filter((g) => g.status !== 'finished');
  const done = games.filter((g) => g.status === 'finished');

  const Row = ({ g }) => {
    const myTurn = g.status === 'active' && g.my_seat === g.turn_seat;
    return (
      <button className={`game-row${myTurn ? ' my-turn' : ''}`} onClick={() => go(`/game/${g.id}`)}>
        <span className="code-pill">{g.code}</span>
        <span className="game-row-main">
          <span>{STATUS_LABEL[g.status]} · {g.player_count}/{g.max_players} players</span>
          <span className="muted small-text">
            {g.status === 'lobby' && 'Not started yet'}
            {g.status === 'active' && (myTurn ? 'Your turn!' : `Waiting for ${g.turn_name ?? 'a player'}`)}
            {g.status === 'closing' && 'Finishing up'}
            {g.status === 'finished' && `You scored ${g.my_score}`}
          </span>
        </span>
        <span aria-hidden="true">›</span>
      </button>
    );
  };

  return (
    <main className="page narrow">
      <h1>Resume game</h1>
      {games.length === 0 && (
        <div className="card stack">
          <p>No games found on this device yet.</p>
          <p className="muted small-text">If you're expecting one, use Join Game with the code and your original name to take your seat back.</p>
          <button className="btn" onClick={() => go('/join')}>Join Game</button>
        </div>
      )}
      {open.length > 0 && <div className="stack">{open.map((g) => <Row key={g.id} g={g} />)}</div>}
      {done.length > 0 && (
        <>
          <h3 className="muted">Finished</h3>
          <div className="stack">{done.map((g) => <Row key={g.id} g={g} />)}</div>
        </>
      )}
    </main>
  );
}
