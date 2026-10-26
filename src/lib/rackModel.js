// Pure model for the 9-slot rack and tiles staged on the board.
// A slot holds null or an entry { id, letter, cell, assigned }.
//   letter   'A'..'Z' or '?' (blank)
//   cell     null while in the rack, {r,c} while staged on the board
//            (the entry keeps its slot as an invisible placeholder)
//   assigned the letter a staged blank stands for
import { RACK_SLOTS } from './premium.js';

let nextId = 1;
const make = (letter) => ({ id: nextId++, letter, cell: null, assigned: null });

export function buildSlots(serverRack) {
  const out = Array(RACK_SLOTS).fill(null);
  (serverRack || []).forEach((l, i) => { if (l && i < RACK_SLOTS) out[i] = make(l); });
  return out;
}

export const isGhost = (e) => !!(e && e.cell);
const isFree = (e) => !e || isGhost(e);

export function sameMultiset(slots, serverRack) {
  const a = slots.filter(Boolean).map((e) => e.letter).sort().join('');
  const b = (serverRack || []).filter(Boolean).sort().join('');
  return a === b;
}

export const indexOfId = (slots, id) => slots.findIndex((e) => e && e.id === id);

// Move the tile at `from` to slot `to`. An empty target swaps places; an
// occupied target shifts the tiles in between out of the way.
export function moveInRack(slots, from, to) {
  if (from === to || from < 0 || to < 0) return slots;
  const a = [...slots];
  if (isFree(a[to])) {
    [a[from], a[to]] = [a[to], a[from]];
    return a;
  }
  const [x] = a.splice(from, 1);
  a.splice(to, 0, x);
  return a;
}

// Shuffle tiles that are physically in the rack, packing them to the left of
// the free slots. Tiles staged on the board keep their placeholder slots.
export function shuffleSlots(slots, rnd = Math.random) {
  const positions = slots.map((_, i) => i).filter((i) => !isGhost(slots[i]));
  const tiles = positions.map((i) => slots[i]).filter(Boolean);
  for (let i = tiles.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [tiles[i], tiles[j]] = [tiles[j], tiles[i]];
  }
  const out = [...slots];
  positions.forEach((p, k) => { out[p] = tiles[k] ?? null; });
  return out;
}

export function placeOnCell(slots, id, r, c) {
  const entry = slots.find((e) => e && e.id === id);
  if (!entry) return slots;
  const other = slots.find((e) => e && e.id !== id && e.cell && e.cell.r === r && e.cell.c === c);
  return slots.map((e) => {
    if (!e) return e;
    if (e.id === id) {
      return { ...e, cell: { r, c }, assigned: e.letter === '?' && entry.cell ? e.assigned : null };
    }
    if (other && e.id === other.id) {
      // dropping onto another staged tile swaps them (or sends it back to the rack)
      return entry.cell ? { ...e, cell: entry.cell } : { ...e, cell: null, assigned: null };
    }
    return e;
  });
}

export const recall = (slots, id) =>
  slots.map((e) => (e && e.id === id ? { ...e, cell: null, assigned: null } : e));

export const recallAll = (slots) =>
  slots.map((e) => (e && e.cell ? { ...e, cell: null, assigned: null } : e));

export function dropOnRack(slots, id, toIndex) {
  const from = indexOfId(slots, id);
  if (from < 0) return slots;
  return moveInRack(recall(slots, id), from, toIndex);
}

export const assignBlank = (slots, id, letter) =>
  slots.map((e) => (e && e.id === id ? { ...e, assigned: letter } : e));

export function stagedPlacements(slots) {
  return slots
    .filter((e) => e && e.cell)
    .map((e) => ({
      r: e.cell.r,
      c: e.cell.c,
      letter: e.letter === '?' ? e.assigned : e.letter,
      blank: e.letter === '?',
      id: e.id
    }));
}

export const hasUnassignedBlank = (slots) => slots.some((e) => e && e.cell && e.letter === '?' && !e.assigned);

// Letters of the rack in slot order ('' for empty); ghosts count (still in the rack server-side).
export const toServerOrder = (slots) => slots.map((e) => (e ? e.letter : ''));
