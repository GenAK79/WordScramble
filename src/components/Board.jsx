import { memo } from 'react';
import { BOARD_SIZE, CENTER, PREMIUM, key } from '../lib/premium.js';
import { tileValue } from '../lib/tiles.js';

const LABEL = { TW: '3W', DW: '2W', TL: '3L', DL: '2L' };

function Tile({ letter, blank, className = '', ...rest }) {
  return (
    <div className={`tile ${blank ? 'blank' : ''} ${className}`} {...rest}>
      <span className="l">{letter}</span>
      {!blank && <span className="v">{tileValue(letter)}</span>}
    </div>
  );
}

function Board({ boardMap, slots, lastSeq, overKey, zoomed, onCellTap, onTilePress, draggingId }) {
  const staged = new Map();
  for (const e of slots) if (e && e.cell) staged.set(key(e.cell.r, e.cell.c), e);

  const cells = [];
  for (let r = 0; r < BOARD_SIZE; r++) {
    for (let c = 0; c < BOARD_SIZE; c++) {
      const k = key(r, c);
      const prem = PREMIUM.get(k);
      const placed = boardMap.get(k);
      const pending = staged.get(k);
      const isCenter = r === CENTER && c === CENTER;
      cells.push(
        <div
          key={k}
          className={`cell ${prem ? prem : ''} ${overKey === k ? 'over' : ''}`}
          data-drop={`cell:${r},${c}`}
          onClick={() => onCellTap(r, c)}
        >
          {!placed && !pending && (isCenter ? <span className="star">★</span> : prem && <span className="plabel">{LABEL[prem]}</span>)}
          {placed && (
            <Tile letter={placed.letter} blank={placed.blank} className={placed.seq === lastSeq ? 'last' : ''} />
          )}
          {pending && (
            <Tile
              letter={pending.letter === '?' ? pending.assigned || '?' : pending.letter}
              blank={pending.letter === '?'}
              className={`staged ${draggingId === pending.id ? 'dragging' : ''}`}
              onPointerDown={(e) => onTilePress(e, pending)}
            />
          )}
        </div>
      );
    }
  }

  return (
    <div className={`board-scroll ${zoomed ? 'zoomed' : ''}`}>
      <div className="board" role="grid" aria-label="Game board">{cells}</div>
    </div>
  );
}

export default memo(Board);
export { Tile };
