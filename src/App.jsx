import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase, configured } from './lib/supabase.js';
import { api } from './lib/api.js';
import { errorMessage } from './lib/errors.js';
import { getName, saveName, validName } from './lib/storage.js';
import { go, useRoute } from './lib/router.js';
import { AppContext, Modal, Spinner, TileWord } from './components/ui.jsx';
import { Home, NewGame, JoinGame, Resume } from './components/Menu.jsx';
import GameRoute from './components/GameRoute.jsx';

function NameForm({ initial = '', onSubmit, submitLabel, busy }) {
  const [value, setValue] = useState(initial);
  return (
    <form className="stack" onSubmit={(e) => { e.preventDefault(); if (validName(value)) onSubmit(value.trim()); }}>
      <label className="field">
        <span>Your player name</span>
        <input
          autoFocus
          value={value}
          maxLength={20}
          onChange={(e) => setValue(e.target.value)}
          placeholder="e.g. Alex"
          autoComplete="nickname"
          autoCapitalize="words"
        />
      </label>
      <button className="btn primary" disabled={!validName(value) || busy}>{submitLabel}</button>
    </form>
  );
}

function NameGate({ onSave }) {
  return (
    <main className="page narrow">
      <TileWord word="WORD" size="lg" />
      <TileWord word="SCRAMBLE" size="lg" />
      <h1 className="center">Welcome!</h1>
      <p className="center muted">Pick the name your friends will see. You can change it any time.</p>
      <NameForm onSubmit={onSave} submitLabel="Let's play" />
    </main>
  );
}

function Notice({ title, children }) {
  return (
    <main className="page narrow">
      <TileWord word="WORD" size="lg" />
      <TileWord word="SCRAMBLE" size="lg" />
      <h1 className="center">{title}</h1>
      <div className="card stack">{children}</div>
    </main>
  );
}

export default function App() {
  const parts = useRoute();
  const [auth, setAuth] = useState({ status: configured ? 'loading' : 'unconfigured' });
  const [name, setNameState] = useState(getName);
  const [toast, setToast] = useState(null);
  const [editingName, setEditingName] = useState(false);
  const [renaming, setRenaming] = useState(false);

  useEffect(() => {
    if (!configured) return;
    let cancelled = false;
    (async () => {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (!session) {
          const { error } = await supabase.auth.signInAnonymously();
          if (error) throw error;
        }
        if (!cancelled) setAuth({ status: 'ready' });
      } catch (e) {
        if (!cancelled) setAuth({ status: 'error', message: e?.message || 'Sign-in failed' });
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const notify = useCallback((message, kind = 'info') => setToast({ message, kind, id: Date.now() }), []);
  useEffect(() => {
    if (!toast) return undefined;
    const t = setTimeout(() => setToast(null), 3800);
    return () => clearTimeout(t);
  }, [toast]);

  const firstName = useCallback((n) => { saveName(n); setNameState(n); }, []);

  const changeName = useCallback(async (n) => {
    setRenaming(true);
    try {
      await api.renamePlayer(n);      // updates every unfinished game; rejects duplicates
      saveName(n);
      setNameState(n);
      setEditingName(false);
    } catch (e) {
      notify(errorMessage(e), 'error');
    } finally {
      setRenaming(false);
    }
  }, [notify]);

  const ctx = useMemo(() => ({ name, notify }), [name, notify]);

  let body;
  if (auth.status === 'unconfigured') {
    body = (
      <Notice title="Setup needed">
        <p>This build has no Supabase connection. Set <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code> and rebuild — see the README.</p>
      </Notice>
    );
  } else if (auth.status === 'loading') {
    body = <Spinner label="Connecting…" />;
  } else if (auth.status === 'error') {
    body = (
      <Notice title="Can't sign in">
        <p>{auth.message}</p>
        <p className="muted">Make sure <strong>Anonymous sign-ins</strong> are enabled in Supabase (Authentication → Sign In / Providers).</p>
        <button className="btn" onClick={() => window.location.reload()}>Try again</button>
      </Notice>
    );
  } else if (!name) {
    body = <NameGate onSave={firstName} />;
  } else {
    const [section, arg] = parts;
    if (section === 'new') body = <NewGame />;
    else if (section === 'join') body = <JoinGame key={arg || 'x'} initialCode={arg} />;
    else if (section === 'resume') body = <Resume />;
    else if (section === 'game' && arg) body = <GameRoute key={arg} id={arg} />;
    else body = <Home />;
  }

  return (
    <AppContext.Provider value={ctx}>
      <div className="app">
        {auth.status === 'ready' && name && (
          <header className="topbar">
            <button className="btn ghost small" onClick={() => go('/')} aria-label="Home">⌂ Home</button>
            <button className="btn ghost small name-chip" onClick={() => setEditingName(true)} aria-label="Change your name">
              ✎ {name}
            </button>
          </header>
        )}
        {body}
        {editingName && (
          <Modal title="Change your name" onClose={() => setEditingName(false)}>
            <NameForm initial={name} onSubmit={changeName} submitLabel="Save name" busy={renaming} />
            <p className="muted small-text">Your name is updated in all your games that haven't finished.</p>
          </Modal>
        )}
        {toast && <div key={toast.id} className={`toast ${toast.kind}`} role="status">{toast.message}</div>}
      </div>
    </AppContext.Provider>
  );
}
