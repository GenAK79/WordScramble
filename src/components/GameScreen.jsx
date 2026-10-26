import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../lib/api.js';
import { errorMessage } from '../lib/errors.js';
import { key } from '../lib/premium.js';
import { analyzeMove } from '../lib/scoring.js';
import {
  assignBlank, dropOnRack, hasUnassignedBlank, placeOnCell,
  recall, recallAll, shuffleSlots, stagedPlacements
} from '../lib/rackModel.js';
import { useRack } from '../lib/useRack.js';
import Board from './Board.jsx';
import Rack from './Rack.jsx';
import {
  BlankPicker, ChallengeDialog, describeMove, MoveLog, PassDialog, ResultsDialog, SwapDialog
} from './Dialogs.jsx';
import { Modal, PlayerDot, useApp } from './ui.jsx';

const isTyping = (t) => t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable);

// What's under a screen point: a rack slot or a board cell.
function hitTest(x, y) {
  for (const el of document.elementsFromPoint(x, y)) {
    const d = el.getAttribute && el.getAttribute('data-drop');
    if (!d) continue;
    if (d.startsWith('rack:')) return { type: 'rack', index: Number(d.slice(5)) };
    if (d.startsWith('cell:')) {
      const [r, c] = d.slice(5).split(',').map(Number);
      return { type: 'cell', r, c };
    }
  }
  return null;
}

export default function GameScreen({ state, refresh }) {
  const { notify } = useApp();
  const { game, players, board: boardArr, moves, my_rack: serverRack, final_racks: finalRacks } = state;
  const meId = state.me;
  const me = players.find((p) => p.id === meId);
  const isHost = game.host_player_id === meId;
  const byId = useMemo(() => Object.fromEntries(players.map((p) => [p.id, p])), [players]);
  const finished = game.status === 'finished';
  const closing = game.status === 'closing';
  const myTurn = game.status === 'active' && game.turn_seat === me.seat;
  const turnPlayer = players.find((p) => p.seat === game.turn_seat);

  const boardMap = useMemo(
    () => new Map(boardArr.map((t) => [key(t.r, t.c), { letter: t.l, blank: t.b, seq: t.s }])),
    [boardArr]
  );
  const [slots, setSlots] = useRack(game.id, serverRack, boardMap);

  const lastMove = moves[0] ?? null;
  const openChallenge = lastMove && lastMove.status === 'challenged' ? lastMove : null;
  const lastPlayMove = moves.find((m) => m.kind === 'play' && m.status !== 'reverted');
  const canChallenge =
    !finished && lastMove && lastMove.kind === 'play' && lastMove.status === 'standing' && lastMove.player_id !== meId;

  const [busy, setBusy] = useState(false);
  const [dialog, setDialog] = useState(null);        // 'swap' | 'pass' | 'log' | 'menu'
  const [blankFor, setBlankFor] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [drag, setDrag] = useState(null);
  const [zoomed, setZoomed] = useState(false);
  const [resultsOpen, setResultsOpen] = useState(true);
  const slotsRef = useRef(slots);
  slotsRef.current = slots;

  // ---- live preview of the staged move -----------------------------------
  const staged = useMemo(() => stagedPlacements(slots), [slots]);
  const unassigned = hasUnassignedBlank(slots);
  const analysis = useMemo(() => {
    if (staged.length === 0 || unassigned) return null;
    return analyzeMove(boardMap, staged.map(({ r, c, letter, blank }) => ({ r, c, letter, blank })));
  }, [staged, unassigned, boardMap]);

  // ---- actions --------------------------------------------------------------
  const run = useCallback(async (fn) => {
    setBusy(true);
    try {
      const r = await fn();
      await refresh();
      return r;
    } catch (e) {
      notify(errorMessage(e), 'error');
      refresh().catch(() => {});
      return undefined;
    } finally {
      setBusy(false);
    }
  }, [notify, refresh]);

  const play = async () => {
    if (!analysis?.ok) return;
    const tiles = staged.map(({ r, c, letter, blank }) => ({ r, c, letter, blank }));
    const res = await run(() => api.playMove(game.id, tiles));
    if (res) {
      const words = res.words.map((w) => w.word).join(', ');
      notify(`${words} — ${res.score} points${res.bingo ? ' (bingo! +50)' : ''}`, 'good');
    }
  };
  const pass = async () => { setDialog(null); await run(() => api.passTurn(game.id)); };
  const swap = async (letters) => { const ok = await run(() => api.swapTiles(game.id, letters)); if (ok !== undefined) setDialog(null); };
  const challenge = () => run(() => api.challenge(game.id));
  const vote = (accept) => run(() => api.vote(game.id, accept));
  const finalize = () => run(() => api.finalize(game.id));
  const hostSkip = async () => {
    setDialog(null);
    const r = await run(() => api.hostSkip(game.id));
    if (r) notify({ skipped: 'Turn skipped.', challenge_accepted: 'Words accepted.', finished: 'Game finished.' }[r.action] ?? 'Done.');
  };

  const shuffle = useCallback(() => setSlots((s) => shuffleSlots(s)), [setSlots]);
  const recallTiles = () => { setSlots((s) => recallAll(s)); setSelectedId(null); };

  // ---- placing tiles (drag or tap) -------------------------------------------
  const placeAt = useCallback((id, r, c) => {
    if (boardMap.has(key(r, c))) return;
    const before = slotsRef.current.find((e) => e && e.id === id);
    setSlots((s) => placeOnCell(s, id, r, c));
    if (before && before.letter === '?' && !before.cell) setBlankFor(id);
  }, [boardMap, setSlots]);

  const dropTile = useCallback((id, hit) => {
    if (!hit) { setSlots((s) => recall(s, id)); return; }
    if (hit.type === 'rack') setSlots((s) => dropOnRack(s, id, hit.index));
    else placeAt(id, hit.r, hit.c);
  }, [placeAt, setSlots]);

  const tapTile = useCallback((id) => {
    const e = slotsRef.current.find((x) => x && x.id === id);
    if (!e) return;
    if (e.cell) { setSlots((s) => recall(s, id)); return; }
    setSelectedId((cur) => (cur === id ? null : id));
  }, [setSlots]);

  const onCellTap = (r, c) => {
    if (selectedId == null) return;
    placeAt(selectedId, r, c);
    setSelectedId(null);
  };

  const onTilePress = (e, entry) => {
    if (finished) return;
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    const sx = e.clientX, sy = e.clientY;
    let moved = false;
    const label = entry.letter === '?' ? (entry.assigned || '') : entry.letter;
    const onMove = (ev) => {
      if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 7) return;
      moved = true;
      setDrag({ id: entry.id, letter: label, blank: entry.letter === '?', x: ev.clientX, y: ev.clientY, over: hitTest(ev.clientX, ev.clientY) });
    };
    const cleanup = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onCancel);
    };
    const onUp = (ev) => {
      cleanup();
      if (!moved) { tapTile(entry.id); return; }
      const hit = hitTest(ev.clientX, ev.clientY);
      setDrag(null);
      dropTile(entry.id, hit);
    };
    const onCancel = () => { cleanup(); setDrag(null); };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onCancel);
  };

  // ---- space bar shuffles ----------------------------------------------------
  const modalOpen = !!(dialog || blankFor || openChallenge || (finished && resultsOpen));
  useEffect(() => {
    const onKey = (e) => {
      if (e.code !== 'Space' || isTyping(e.target) || modalOpen || finished) return;
      e.preventDefault();
      if (e.type === 'keydown' && !e.repeat) shuffle();
    };
    window.addEventListener('keydown', onKey);
    window.addEventListener('keyup', onKey);
    return () => { window.removeEventListener('keydown', onKey); window.removeEventListener('keyup', onKey); };
  }, [modalOpen, finished, shuffle]);

  useEffect(() => {
    document.title = myTurn ? '▶ Your turn · Word Scramble' : 'Word Scramble';
    return () => { document.title = 'Word Scramble'; };
  }, [myTurn]);

  // ---- drag preview ------------------------------------------------------------
  const rackPreview = drag && drag.over?.type === 'rack' ? dropOnRack(slots, drag.id, drag.over.index) : slots;
  const overKey = drag && drag.over?.type === 'cell' ? key(drag.over.r, drag.over.c) : null;
  const overIndex = drag && drag.over?.type === 'rack' ? drag.over.index : null;

  // ---- status line ----------------------------------------------------------------
  let status;
  if (finished) status = 'Game over';
  else if (closing) status = `${byId[lastPlayMove?.player_id]?.name ?? 'A player'} has gone out`;
  else if (unassigned) status = 'Choose a letter for the blank tile';
  else if (analysis?.ok) {
    status = `${analysis.words.map((w) => w.word).join(' + ')} · ${analysis.total} pts${analysis.bingo ? ' · bingo!' : ''}`;
  } else if (analysis && staged.length > 0) status = errorMessage({ code: analysis.error });
  else if (myTurn) status = 'Your turn — drag tiles onto the board';
  else status = `Waiting for ${turnPlayer?.name ?? '…'}`;

  const inPlay = !finished && !closing;
  const canPlay = myTurn && analysis?.ok && !unassigned && !busy;
  const moverOfLast = lastMove?.player_id === meId;

  return (
    <div className="game">
      <section className="scores" aria-label="Scores">
        {players.map((p) => (
          <div key={p.id} className={`pchip ${inPlay && p.seat === game.turn_seat ? 'turn' : ''} ${p.id === meId ? 'me' : ''}`}>
            <PlayerDot index={p.seat} />
            <span className="pname">{p.name}</span>
            <span className="pscore">{p.score}</span>
          </div>
        ))}
        <div className="bag" title="Tiles left in the bag">Bag {game.bag_count}</div>
      </section>

      <Board
        boardMap={boardMap}
        slots={slots}
        lastSeq={lastPlayMove?.seq}
        overKey={overKey}
        zoomed={zoomed}
        onCellTap={onCellTap}
        onTilePress={onTilePress}
        draggingId={drag?.id}
      />

      <div className={`statusbar ${myTurn ? 'mine' : ''} ${analysis?.ok ? 'ok' : ''}`} role="status">{status}</div>

      {canChallenge && !closing && (
        <div className="banner">
          <span>{describeMove(lastMove, byId)}</span>
          <button className="btn small" disabled={busy} onClick={challenge}>Challenge</button>
        </div>
      )}
      {closing && !openChallenge && (
        <div className="banner closing">
          <span>
            {moverOfLast
              ? 'You went out! Waiting for the others to confirm or challenge.'
              : `${byId[lastMove?.player_id]?.name ?? 'A player'} played their last tiles. Challenge, or finish the game.`}
          </span>
          {!moverOfLast && (
            <span className="row tight">
              {canChallenge && <button className="btn small" disabled={busy} onClick={challenge}>Challenge</button>}
              <button className="btn small primary" disabled={busy} onClick={finalize}>Finish game</button>
            </span>
          )}
          {isHost && moverOfLast && <button className="btn small" disabled={busy} onClick={hostSkip}>Host: finish game</button>}
        </div>
      )}

      <Rack
        slots={rackPreview}
        selectedId={selectedId}
        draggingId={drag?.id}
        overIndex={overIndex}
        onTilePress={onTilePress}
      />

      <div className="controls">
        <button className="btn" onClick={shuffle} disabled={finished} title="Shuffle (space bar)">⤮ Shuffle</button>
        <button className="btn" onClick={recallTiles} disabled={staged.length === 0}>↩ Recall</button>
        <button className="btn" onClick={() => setDialog('swap')} disabled={!myTurn || busy || game.bag_count < 7}>⇄ Swap</button>
        <button className="btn" onClick={() => setDialog('pass')} disabled={!myTurn || busy}>Pass</button>
        <button className="btn primary play" onClick={play} disabled={!canPlay}>
          {analysis?.ok ? `Play ${analysis.total}` : 'Play'}
        </button>
      </div>

      <div className="subcontrols">
        <button className="btn ghost small" onClick={() => setDialog('log')}>Moves</button>
        <button className="btn ghost small" onClick={() => setZoomed((z) => !z)}>{zoomed ? 'Fit board' : 'Zoom board'}</button>
        {isHost && inPlay && <button className="btn ghost small" onClick={() => setDialog('menu')}>Host tools</button>}
        {finished && !resultsOpen && <button className="btn ghost small" onClick={() => setResultsOpen(true)}>Results</button>}
        <span className="code-tag" title="Game code">{game.code}</span>
      </div>

      {drag && (
        <div className={`tile drag-ghost ${drag.blank ? 'blank' : ''}`} style={{ left: drag.x, top: drag.y }} aria-hidden="true">
          <span className="l">{drag.letter}</span>
        </div>
      )}

      {blankFor != null && (
        <BlankPicker
          onPick={(l) => { setSlots((s) => assignBlank(s, blankFor, l)); setBlankFor(null); }}
          onCancel={() => { setSlots((s) => recall(s, blankFor)); setBlankFor(null); }}
        />
      )}
      {dialog === 'swap' && <SwapDialog slots={slots} busy={busy} onSwap={swap} onClose={() => setDialog(null)} />}
      {dialog === 'pass' && <PassDialog busy={busy} onPass={pass} onClose={() => setDialog(null)} />}
      {dialog === 'log' && <MoveLog moves={moves} players={players} onClose={() => setDialog(null)} />}
      {dialog === 'menu' && (
        <Modal title="Host tools" onClose={() => setDialog(null)}>
          <p>Use these if a player has gone away and the game is stuck.</p>
          <button className="btn" disabled={busy || !turnPlayer} onClick={hostSkip}>
            Skip {turnPlayer?.name}'s turn
          </button>
        </Modal>
      )}
      {openChallenge && (
        <ChallengeDialog
          move={openChallenge}
          players={players}
          meId={meId}
          isHost={isHost}
          busy={busy}
          onVote={vote}
          onHostAccept={hostSkip}
        />
      )}
      {finished && resultsOpen && (
        <ResultsDialog players={players} moves={moves} finalRacks={finalRacks} meId={meId} onClose={() => setResultsOpen(false)} />
      )}
    </div>
  );
}

