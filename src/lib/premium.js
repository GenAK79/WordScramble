// Premium squares on the 15x15 board, as [row, col] pairs.
// Must match public.premium_squares in supabase/schema.sql (a test enforces this).
export const TW = [[0,0],[0,7],[0,14],[7,0],[7,14],[14,0],[14,7],[14,14]];
export const DW = [
  [1,1],[2,2],[3,3],[4,4],[1,13],[2,12],[3,11],[4,10],
  [13,1],[12,2],[11,3],[10,4],[13,13],[12,12],[11,11],[10,10],
  [7,7]
];
export const TL = [[1,5],[1,9],[5,1],[5,5],[5,9],[5,13],[9,1],[9,5],[9,9],[9,13],[13,5],[13,9]];
export const DL = [
  [0,3],[0,11],[2,6],[2,8],[3,0],[3,7],[3,14],[6,2],[6,6],[6,8],[6,12],[7,3],[7,11],
  [8,2],[8,6],[8,8],[8,12],[11,0],[11,7],[11,14],[12,6],[12,8],[14,3],[14,11]
];

export const key = (r, c) => `${r},${c}`;

export const PREMIUM = new Map();
for (const [r, c] of TW) PREMIUM.set(key(r, c), 'TW');
for (const [r, c] of DW) PREMIUM.set(key(r, c), 'DW');
for (const [r, c] of TL) PREMIUM.set(key(r, c), 'TL');
for (const [r, c] of DL) PREMIUM.set(key(r, c), 'DL');

export const BOARD_SIZE = 15;
export const CENTER = 7;
export const RACK_SLOTS = 9;
