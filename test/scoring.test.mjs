// Client scoring mirror: must agree with the database on the same scenarios
// (see test/sql/tests.sql), and the premium maps must be identical.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { analyzeMove } from '../src/lib/scoring.js';
import { PREMIUM, key } from '../src/lib/premium.js';
import { tileValue } from '../src/lib/tiles.js';

// lowercase = blank, '.' = square already on the board (skipped)
function pm(r, c, dir, w) {
  const out = [];
  [...w].forEach((ch, i) => {
    if (ch === '.') return;
    out.push({
      r: r + (dir === 'v' ? i : 0),
      c: c + (dir === 'h' ? i : 0),
      letter: ch.toUpperCase(),
      blank: ch === ch.toLowerCase()
    });
  });
  return out;
}
const commit = (board, placements) => {
  for (const p of placements) board.set(key(p.r, p.c), { letter: p.letter, blank: p.blank });
};

test('premium squares match the SQL seed exactly', () => {
  const sql = readFileSync(new URL('../supabase/schema.sql', import.meta.url), 'utf8');
  const block = sql.slice(sql.indexOf('insert into public.premium_squares'), sql.indexOf('on conflict do nothing'));
  const fromSql = new Map();
  for (const m of block.matchAll(/\((\d+),(\d+),'(TW|DW|TL|DL)'\)/g)) fromSql.set(key(+m[1], +m[2]), m[3]);
  assert.equal(fromSql.size, 61);
  assert.deepEqual([...PREMIUM].sort(), [...fromSql].sort());
});

test('tile values total 187 over the standard distribution', () => {
  const dist = { A:9,B:2,C:2,D:4,E:12,F:2,G:3,H:2,I:9,J:1,K:1,L:4,M:2,N:6,O:8,P:2,Q:1,R:6,S:4,T:6,U:4,V:2,W:2,X:1,Y:2,Z:1 };
  let total = 0, count = 2;
  for (const [l, n] of Object.entries(dist)) { total += tileValue(l) * n; count += n; }
  assert.equal(count, 100);
  assert.equal(total, 187);
  assert.equal(tileValue('?'), 0);
});

test('scoring scenarios agree with the database tests', () => {
  const board = new Map();

  let r = analyzeMove(board, pm(7, 3, 'h', 'HELLO'));
  assert.deepEqual(r, { ok: true, total: 24, words: [{ word: 'HELLO', score: 24 }], bingo: false });
  commit(board, pm(7, 3, 'h', 'HELLO'));

  r = analyzeMove(board, pm(6, 7, 'v', 'W.RLD'));
  assert.equal(r.total, 9);
  commit(board, pm(6, 7, 'v', 'W.RLD'));

  r = analyzeMove(board, pm(8, 5, 'h', 'BA.'));
  assert.equal(r.total, 13);
  assert.deepEqual(r.words, [
    { word: 'BAR', score: 6 }, { word: 'LB', score: 4 }, { word: 'LA', score: 3 }
  ]);
});

test('single tile, premium not reused, bingo with blank', () => {
  const b = new Map();
  commit(b, pm(7, 7, 'h', 'AB'));
  let r = analyzeMove(b, pm(8, 8, 'h', 'E'));
  assert.deepEqual(r.words, [{ word: 'BE', score: 5 }]);
  commit(b, pm(8, 8, 'h', 'E'));
  r = analyzeMove(b, pm(7, 9, 'h', 'S'));
  assert.equal(r.total, 5);

  const empty = new Map();
  r = analyzeMove(empty, pm(7, 4, 'h', 'RETAINs'));
  assert.equal(r.total, 62);
  assert.equal(r.bingo, true);
  assert.equal(r.words[0].score, 12);
});

test('rejections mirror server error codes', () => {
  const empty = new Map();
  assert.equal(analyzeMove(empty, pm(3, 3, 'h', 'HELLO')).error, 'MUST_COVER_CENTER');
  assert.equal(analyzeMove(empty, [{ r: 7, c: 7, letter: 'H' }]).error, 'NO_WORD');
  assert.equal(analyzeMove(empty, [
    { r: 7, c: 3, letter: 'H' }, { r: 7, c: 5, letter: 'L' }, { r: 7, c: 7, letter: 'O' }
  ]).error, 'GAP_IN_WORD');
  assert.equal(analyzeMove(empty, [
    { r: 7, c: 7, letter: 'H' }, { r: 8, c: 8, letter: 'E' }
  ]).error, 'NOT_IN_LINE');

  const b = new Map();
  commit(b, pm(7, 7, 'h', 'AB'));
  assert.equal(analyzeMove(b, pm(0, 0, 'h', 'WRLD')).error, 'NOT_CONNECTED');
  assert.equal(analyzeMove(b, pm(9, 9, 'h', 'Q')).error, 'NOT_CONNECTED');
  assert.equal(analyzeMove(b, pm(7, 7, 'h', 'W')).error, 'SQUARE_OCCUPIED');
  assert.equal(analyzeMove(b, []).error, 'INVALID_MOVE');
});
