import { useGameState } from '../lib/useGameState.js';
import { errorMessage } from '../lib/errors.js';
import { go } from '../lib/router.js';
import { Spinner } from './ui.jsx';
import Lobby from './Lobby.jsx';
import GameScreen from './GameScreen.jsx';

export default function GameRoute({ id }) {
  const { state, error, refresh } = useGameState(id);

  if (!state && error) {
    return (
      <main className="page narrow">
        <h1>Can't open this game</h1>
        <div className="card stack">
          <p>{errorMessage(error)}</p>
          <p className="muted small-text">
            If this is your game on a new device, use Join Game with the code and your original name to take your seat back.
          </p>
          <button className="btn primary" onClick={() => go('/join')}>Join Game</button>
          <button className="btn" onClick={refresh}>Try again</button>
        </div>
      </main>
    );
  }
  if (!state) return <Spinner label="Opening game…" />;

  return state.game.status === 'lobby'
    ? <Lobby state={state} refresh={refresh} />
    : <GameScreen state={state} refresh={refresh} />;
}
