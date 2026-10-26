import { useEffect, useState } from 'react';

// Hash routing keeps the app working on GitHub Pages with no server config:
//   #/  #/new  #/join  #/join/ABCDE  #/resume  #/game/<uuid>
const read = () => window.location.hash.replace(/^#\/?/, '').split('/').filter(Boolean);

export function useRoute() {
  const [parts, setParts] = useState(read);
  useEffect(() => {
    const on = () => setParts(read());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return parts;
}

export const go = (path) => { window.location.hash = `#${path}`; };

// Absolute invitation link for a game code.
export function inviteUrl(code) {
  const base = window.location.href.split('#')[0];
  return `${base}#/join/${code}`;
}
