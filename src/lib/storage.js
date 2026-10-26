const NAME_KEY = 'wordscramble.playerName';

export function getName() {
  try { return (localStorage.getItem(NAME_KEY) || '').trim(); } catch { return ''; }
}

export function saveName(name) {
  try { localStorage.setItem(NAME_KEY, name); } catch { /* storage unavailable: name lives in memory only */ }
}

export const validName = (n) => n.trim().length >= 1 && n.trim().length <= 20;
