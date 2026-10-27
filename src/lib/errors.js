// Maps database error codes (RAISE EXCEPTION 'CODE') to friendly text.
const MESSAGES = {
  NOT_AUTHENTICATED: 'Your session has expired. Please reload the page.',
  NOT_A_PLAYER: "You're not a player in this game.",
  GAME_NOT_FOUND: "We couldn't find a game with that code.",
  GAME_FULL: 'That game is already full.',
  GAME_STARTED: 'That game has already started.',
  GAME_NOT_ACTIVE: "The game isn't in play right now.",
  GAME_NOT_CLOSING: "The game isn't waiting to finish.",
  ALREADY_STARTED: 'The game has already started.',
  NEED_MORE_PLAYERS: 'You need at least 2 players to start.',
  HOST_ONLY: 'Only the host can do that.',
  NAME_TAKEN: 'That name is already used in this game.',
  INVALID_NAME: 'Names must be 1–20 characters.',
  INVALID_PLAYER_COUNT: 'Choose 2, 3 or 4 players.',
  NOT_YOUR_TURN: "It's not your turn.",
  CHALLENGE_OPEN: 'A challenge is in progress — wait for the vote to finish.',
  INVALID_MOVE: 'That move is not valid.',
  SQUARE_OCCUPIED: 'A square is already taken.',
  TILE_NOT_IN_RACK: "You don't have those tiles.",
  NOT_IN_LINE: 'Tiles must all be in one row or one column.',
  GAP_IN_WORD: 'There are gaps between your tiles.',
  MUST_COVER_CENTER: 'The first word must cover the centre star.',
  NOT_CONNECTED: 'Your word must connect to tiles already on the board.',
  NO_WORD: 'Your tiles must form a word of at least two letters.',
  INVALID_SWAP: 'Choose 1–7 tiles to swap.',
  BAG_TOO_SMALL: 'You can only swap while 7 or more tiles remain in the bag.',
  INVALID_RACK: "Couldn't save the tile order.",
  NOTHING_TO_CHALLENGE: "There's no play to challenge right now.",
  CANNOT_CHALLENGE_OWN_MOVE: "You can't challenge your own play.",
  ALREADY_RESOLVED: 'That play has already been decided.',
  NO_OPEN_CHALLENGE: 'There is no open challenge.',
  MOVER_CANNOT_VOTE: "You can't vote on your own play.",
  CHALLENGER_CANNOT_VOTE: "You can't vote on your own challenge — the other players decide.",
  ALREADY_VOTED: "You've already voted.",
  MOVER_CANNOT_FINALIZE: 'Another player needs to confirm the end of the game.'
};

export class GameError extends Error {
  constructor(code, cause) {
    super(code);
    this.code = code;
    this.cause = cause;
  }
}

export function errorMessage(e) {
  const code = e?.code && MESSAGES[e.code] ? e.code : e?.message;
  if (MESSAGES[code]) return MESSAGES[code];
  if (e instanceof TypeError || /fetch|network/i.test(e?.message || '')) {
    return "Can't reach the server. Check your connection and try again.";
  }
  return 'Something went wrong. Please try again.';
}
