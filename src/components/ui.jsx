import { createContext, useContext, useEffect } from 'react';

export const AppContext = createContext(null);
export const useApp = () => useContext(AppContext);

export function Modal({ title, onClose, children, wide }) {
  useEffect(() => {
    if (!onClose) return undefined;
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={(e) => { if (e.target === e.currentTarget && onClose) onClose(); }}>
      <div className={`modal${wide ? ' wide' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <h2>{title}</h2>
          {onClose && <button className="icon-btn" onClick={onClose} aria-label="Close">✕</button>}
        </div>
        <div className="modal-body">{children}</div>
      </div>
    </div>
  );
}

export function Spinner({ label = 'Loading…' }) {
  return <div className="center-note"><div className="spinner" aria-hidden="true" />{label}</div>;
}

// Row of little tiles used for the logo.
export function TileWord({ word, size = 'md' }) {
  return (
    <div className={`tile-word ${size}`} aria-label={word}>
      {[...word].map((ch, i) => (ch === ' ' ? <span key={i} className="tw-gap" /> : <span key={i} className="tile mini">{ch}</span>))}
    </div>
  );
}

export function PlayerDot({ index }) {
  return <span className={`pdot p${index}`} aria-hidden="true" />;
}
