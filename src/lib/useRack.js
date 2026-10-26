import { useEffect, useRef, useState } from 'react';
import { api } from './api.js';
import { key } from './premium.js';
import { buildSlots, sameMultiset, toServerOrder } from './rackModel.js';

// Local, editable view of the server rack.
//  - Adopts the server rack whenever the set of tiles changes (after a play,
//    swap, undo...). Otherwise the local arrangement wins.
//  - Saves the player's tile order back to the server (debounced).
//  - Unstages tiles whose target square has since been taken.
export function useRack(gameId, serverRack, boardMap) {
  const [slots, setSlots] = useState(() => buildSlots(serverRack));
  const lastSaved = useRef(serverRack ? serverRack.join('|') : '');
  const serverKey = serverRack ? serverRack.join('|') : '';

  useEffect(() => {
    if (!serverRack) return;
    setSlots((prev) => {
      if (sameMultiset(prev, serverRack)) return prev;
      lastSaved.current = serverKey;
      return buildSlots(serverRack);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [serverKey]);

  useEffect(() => {
    setSlots((prev) =>
      prev.some((e) => e && e.cell && boardMap.has(key(e.cell.r, e.cell.c)))
        ? prev.map((e) => (e && e.cell && boardMap.has(key(e.cell.r, e.cell.c)) ? { ...e, cell: null, assigned: null } : e))
        : prev
    );
  }, [boardMap]);

  useEffect(() => {
    if (!serverRack) return undefined;
    const order = toServerOrder(slots);
    const orderKey = order.join('|');
    if (orderKey === lastSaved.current) return undefined;
    const t = setTimeout(async () => {
      try {
        await api.saveRackOrder(gameId, order);
        lastSaved.current = orderKey;
      } catch {
        /* non-critical: the arrangement just stays local until the next change */
      }
    }, 700);
    return () => clearTimeout(t);
  }, [slots, gameId, serverRack]);

  return [slots, setSlots];
}
