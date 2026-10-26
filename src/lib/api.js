import { supabase } from './supabase.js';
import { GameError } from './errors.js';

async function rpc(fn, args = {}) {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new GameError(error.message || 'UNKNOWN', error);
  return data;
}

export const api = {
  createGame: (name, maxPlayers) => rpc('create_game', { p_name: name, p_max: maxPlayers }),
  peekGame: (code) => rpc('peek_game', { p_code: code }),
  joinGame: (code, name, takeover = false) =>
    rpc('join_game', { p_code: code, p_name: name, p_takeover: takeover }),
  renamePlayer: (name) => rpc('rename_player', { p_name: name }),
  startGame: (game) => rpc('start_game', { p_game: game }),
  getState: (game) => rpc('get_state', { p_game: game }),
  myGames: () => rpc('my_games'),
  playMove: (game, tiles) => rpc('play_move', { p_game: game, p_tiles: tiles }),
  passTurn: (game) => rpc('pass_turn', { p_game: game }),
  swapTiles: (game, letters) => rpc('swap_tiles', { p_game: game, p_letters: letters }),
  saveRackOrder: (game, tiles) => rpc('save_rack_order', { p_game: game, p_tiles: tiles }),
  challenge: (game) => rpc('challenge_move', { p_game: game }),
  vote: (game, accept) => rpc('cast_vote', { p_game: game, p_accept: accept }),
  finalize: (game) => rpc('finalize_game', { p_game: game }),
  hostSkip: (game) => rpc('host_skip', { p_game: game })
};
