import { RACK_SLOTS } from '../lib/premium.js';
import { Tile } from './Board.jsx';

// 9 slots (7 tiles + room for gaps). Tiles are absolutely positioned by slot
// index and keyed by id, so re-ordering animates and neighbours "move out of the way".
export default function Rack({ slots, selectedId, draggingId, overIndex, onTilePress }) {
  return (
    <div className="rack" aria-label="Your tile rack">
      <div className="rack-slots">
        {Array.from({ length: RACK_SLOTS }, (_, i) => (
          <div key={i} className={`rack-slot ${overIndex === i ? 'over' : ''}`} data-drop={`rack:${i}`} />
        ))}
      </div>
      <div className="rack-tiles">
        {slots.map((e, i) =>
          e && !e.cell ? (
            <div
              key={e.id}
              className="rack-pos"
              style={{ left: `${(i * 100) / RACK_SLOTS}%`, width: `${100 / RACK_SLOTS}%` }}
            >
              <Tile
                letter={e.letter === '?' ? '' : e.letter}
                blank={e.letter === '?'}
                className={`rack-tile ${selectedId === e.id ? 'selected' : ''} ${draggingId === e.id ? 'dragging' : ''}`}
                onPointerDown={(ev) => onTilePress(ev, e)}
              />
            </div>
          ) : null
        )}
      </div>
    </div>
  );
}
