// Client-side mirror of the server's play_move() geometry + scoring.
// It only powers the live "this move would score N" preview and early hints;
// the database is the authority and re-validates every move.
import { PREMIUM, key, BOARD_SIZE, CENTER } from './premium.js';
import { tileValue } from './tiles.js';

const inBounds = (r, c) => r >= 0 && c >= 0 && r < BOARD_SIZE && c < BOARD_SIZE;

/**
 * @param {Map<string,{letter:string,blank:boolean}>} board  committed tiles keyed "r,c"
 * @param {{r:number,c:number,letter:string,blank:boolean}[]} placements  staged tiles
 * @returns {{ok:true,total:number,words:{word:string,score:number}[],bingo:boolean}
 *          |{ok:false,error:string}}
 */
export function analyzeMove(board, placements) {
  const n = placements.length;
  if (n < 1 || n > 7) return { ok: false, error: 'INVALID_MOVE' };

  const staged = new Map();
  for (const p of placements) {
    const k = key(p.r, p.c);
    if (!inBounds(p.r, p.c)) return { ok: false, error: 'INVALID_MOVE' };
    if (board.has(k) || staged.has(k)) return { ok: false, error: 'SQUARE_OCCUPIED' };
    staged.set(k, { letter: p.letter, blank: !!p.blank });
  }
  const at = (r, c) => (inBounds(r, c) ? staged.get(key(r, c)) ?? board.get(key(r, c)) ?? null : null);

  const rows = placements.map((p) => p.r);
  const cols = placements.map((p) => p.c);
  const minR = Math.min(...rows), maxR = Math.max(...rows);
  const minC = Math.min(...cols), maxC = Math.max(...cols);
  const sameRow = minR === maxR;
  const sameCol = minC === maxC;
  if (n > 1 && !sameRow && !sameCol) return { ok: false, error: 'NOT_IN_LINE' };
  if (n > 1) {
    if (sameRow) {
      for (let c = minC; c <= maxC; c++) if (!at(minR, c)) return { ok: false, error: 'GAP_IN_WORD' };
    } else {
      for (let r = minR; r <= maxR; r++) if (!at(r, minC)) return { ok: false, error: 'GAP_IN_WORD' };
    }
  }

  if (board.size === 0) {
    if (!staged.has(key(CENTER, CENTER))) return { ok: false, error: 'MUST_COVER_CENTER' };
  } else {
    const touches = placements.some((p) =>
      [[-1, 0], [1, 0], [0, -1], [0, 1]].some(([dr, dc]) => board.has(key(p.r + dr, p.c + dc)))
    );
    if (!touches) return { ok: false, error: 'NOT_CONNECTED' };
  }

  // Walk the full run through (r,c) in direction (dr,dc); score with premiums on new tiles only.
  const run = (r, c, dr, dc) => {
    while (at(r - dr, c - dc)) { r -= dr; c -= dc; }
    let word = '', sum = 0, mult = 1, len = 0;
    while (at(r, c)) {
      const t = at(r, c);
      word += t.letter;
      len++;
      let v = t.blank ? 0 : tileValue(t.letter);
      if (staged.has(key(r, c))) {
        const prem = PREMIUM.get(key(r, c));
        if (prem === 'DL') v *= 2;
        else if (prem === 'TL') v *= 3;
        else if (prem === 'DW') mult *= 2;
        else if (prem === 'TW') mult *= 3;
      }
      sum += v;
      r += dr; c += dc;
    }
    return { word, score: sum * mult, len };
  };

  const found = [];
  if (n === 1) {
    found.push(run(placements[0].r, placements[0].c, 0, 1));
    found.push(run(placements[0].r, placements[0].c, 1, 0));
  } else if (sameRow) {
    found.push(run(placements[0].r, placements[0].c, 0, 1));
    for (const p of placements) found.push(run(p.r, p.c, 1, 0));
  } else {
    found.push(run(placements[0].r, placements[0].c, 1, 0));
    for (const p of placements) found.push(run(p.r, p.c, 0, 1));
  }
  const words = found.filter((w) => w.len >= 2).map(({ word, score }) => ({ word, score }));
  if (words.length === 0) return { ok: false, error: 'NO_WORD' };

  const bingo = n === 7;
  const total = words.reduce((a, w) => a + w.score, 0) + (bingo ? 50 : 0);
  return { ok: true, total, words, bingo };
}
