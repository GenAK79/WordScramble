import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildSlots, moveInRack, shuffleSlots, placeOnCell, recall, recallAll, dropOnRack,
  sameMultiset, stagedPlacements, assignBlank, hasUnassignedBlank, toServerOrder
} from '../src/lib/rackModel.js';

const letters = (slots) => slots.map((e) => (e ? e.letter : '.')).join('');
const rack = (s) => buildSlots([...s].map((c) => (c === '.' ? '' : c)).concat(Array(9).fill('')).slice(0, 9));

test('buildSlots makes 9 slots and keeps gaps', () => {
  const s = buildSlots(['A', '', 'B', '', '', '', '', '', 'C']);
  assert.equal(s.length, 9);
  assert.equal(letters(s), 'A.B.....C');
  assert.equal(new Set(s.filter(Boolean).map((e) => e.id)).size, 3);
});

test('moveInRack: empty target swaps, occupied target shifts neighbours', () => {
  assert.equal(letters(moveInRack(rack('ABC'), 0, 5)), '.BC..A...');   // other tiles stay put
  assert.equal(letters(moveInRack(rack('ABCDE'), 0, 3)), 'BCDAE....');  // B C D slide left
  assert.equal(letters(moveInRack(rack('ABCDE'), 4, 1)), 'AEBCD....');  // B C D slide right
  assert.equal(letters(moveInRack(rack('ABC'), 1, 1)), 'ABC......');
});

test('shuffle keeps the same tiles, packs left, leaves staged placeholders alone', () => {
  const s = rack('ABCDEFG');
  const staged = placeOnCell(s, s[2].id, 7, 7);                 // C staged on the board
  const out = shuffleSlots(staged, () => 0.3);
  assert.equal(out[2].id, s[2].id);                              // placeholder untouched
  assert.deepEqual(out.filter(Boolean).map((e) => e.letter).sort(), 'ABCDEFG'.split(''));
  assert.equal(out.filter((e, i) => i !== 2 && e).length, 6);
  assert.equal(out[7], null);
  assert.equal(out[8], null);
});

test('staging, swapping on the board, and recall', () => {
  let s = rack('ABC');
  const [a, b] = [s[0].id, s[1].id];
  s = placeOnCell(s, a, 7, 7);
  s = placeOnCell(s, b, 7, 8);
  assert.deepEqual(stagedPlacements(s).map((p) => [p.letter, p.r, p.c]), [['A', 7, 7], ['B', 7, 8]]);
  s = placeOnCell(s, a, 7, 8);                                   // A onto B's square: they swap
  assert.deepEqual(stagedPlacements(s).map((p) => [p.letter, p.c]), [['A', 8], ['B', 7]]);
  s = placeOnCell(rack('ABC'), s[0].id, 0, 0);                   // fresh rack tile onto an occupied square sends the old one home
  s = recall(s, s[0].id);
  assert.equal(stagedPlacements(s).length, 0);
  assert.equal(stagedPlacements(recallAll(placeOnCell(rack('AB'), 1, 0, 0))).length, 0);
});

test('dropOnRack returns a staged tile to a chosen slot', () => {
  let s = rack('ABCD');
  s = placeOnCell(s, s[3].id, 7, 7);                             // D staged
  s = dropOnRack(s, s[3].id, 0);                                 // back at slot 0, others shift right
  assert.equal(letters(s), 'DABC.....');
  assert.equal(stagedPlacements(s).length, 0);
});

test('blank tiles need a letter before they can be played', () => {
  let s = rack('A?');
  s = placeOnCell(s, s[1].id, 7, 7);
  assert.equal(hasUnassignedBlank(s), true);
  s = assignBlank(s, s[1].id, 'Q');
  assert.equal(hasUnassignedBlank(s), false);
  assert.deepEqual(stagedPlacements(s)[0], { r: 7, c: 7, letter: 'Q', blank: true, id: s[1].id });
  // moving an assigned blank to another square keeps its letter
  s = placeOnCell(s, s[1].id, 8, 8);
  assert.equal(hasUnassignedBlank(s), false);
});

test('sameMultiset and server order', () => {
  const s = rack('ABC');
  assert.equal(sameMultiset(s, ['C', '', 'B', 'A', '', '', '', '', '']), true);
  assert.equal(sameMultiset(s, ['C', 'B', 'D', '', '', '', '', '', '']), false);
  assert.deepEqual(toServerOrder(moveInRack(s, 0, 4)), ['', 'B', 'C', '', 'A', '', '', '', '']);
});
