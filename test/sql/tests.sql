-- Word Scramble: database logic tests. Each DO block is an independent scenario.
-- Run via test/run-sql-tests.sh (needs psql and a scratch Postgres 14+).

-- =====================================================================
-- 1. Static data
-- =====================================================================
do $$
begin
  perform t.eq('premium: 8 TW',  (select count(*)::int from public.premium_squares where kind='TW'), 8);
  perform t.eq('premium: 17 DW', (select count(*)::int from public.premium_squares where kind='DW'), 17);
  perform t.eq('premium: 12 TL', (select count(*)::int from public.premium_squares where kind='TL'), 12);
  perform t.eq('premium: 24 DL', (select count(*)::int from public.premium_squares where kind='DL'), 24);
  -- every premium square has its 4-way mirror (board is symmetric)
  perform t.eq('premium: symmetric', (
    select count(*)::int from public.premium_squares a
     where not exists (select 1 from public.premium_squares b
                        where b.row_no = a.col_no and b.col_no = a.row_no and b.kind = a.kind)
        or not exists (select 1 from public.premium_squares b
                        where b.row_no = 14 - a.row_no and b.col_no = a.col_no and b.kind = a.kind)), 0);
  perform t.eq('bag: 100 tiles', cardinality(public._new_bag()), 100);
  perform t.eq('bag: total face value 187',
    (select sum(public.tile_value(x))::int from unnest(public._new_bag()) x), 187);
  perform t.eq('bag: 2 blanks', (select count(*)::int from unnest(public._new_bag()) x where x = '?'), 2);
end $$;

-- =====================================================================
-- 2. Lobby, start, privacy of state
-- =====================================================================
do $$
declare g uuid; v_code text; s jsonb; s2 jsonb;
begin
  perform t.u(1);
  g := (public.create_game('Alex', 3) ->> 'id')::uuid;
  select code into v_code from public.games where id = g;
  perform t.eq('create: 5-char code', v_code ~ '^[A-HJ-NP-Z2-9]{5}$', true);
  perform t.fails('create: bad count', $q$select public.create_game('A', 5)$q$, 'INVALID_PLAYER_COUNT');
  perform t.fails('create: empty name', $q$select public.create_game('  ', 3)$q$, 'INVALID_NAME');

  perform t.u(2);
  s := public.peek_game(lower(v_code));
  perform t.eq('peek: host name', s ->> 'host_name', 'Alex');
  perform t.eq('peek: not member', (s ->> 'is_member')::boolean, false);
  perform t.eq('peek: id hidden', s -> 'id', 'null'::jsonb);
  perform public.join_game(v_code, 'Bea');
  perform t.fails('start: host only', format($q$select public.start_game(%L)$q$, g), 'HOST_ONLY');
  perform t.u(1);
  perform t.u(3);
  perform t.fails('join: name taken', format($q$select public.join_game(%L, 'bea')$q$, v_code), 'NAME_TAKEN');
  perform t.fails('state: stranger', format($q$select public.get_state(%L)$q$, g), 'NOT_A_PLAYER');
  perform public.join_game(v_code, 'Cy');
  perform t.u(4);
  perform t.fails('join: full', format($q$select public.join_game(%L, 'Di')$q$, v_code), 'GAME_FULL');

  perform t.u(1);
  perform public.start_game(g);
  perform t.eq('start: active', (select status from public.games where id = g), 'active');
  perform t.eq('start: bag 100-21', (select bag_count from public.games where id = g), 79);
  perform t.eq('start: bag secret matches', (select cardinality(bag) from public.game_secrets where game_id = g), 79);
  perform t.eq('start: racks 7 tiles each', (select count(*)::int from public.racks r, lateral unnest(public._rack_letters(r.tiles)) x where r.game_id = g), 21);
  perform t.eq('start: racks 9 slots', (select min(cardinality(tiles)) from public.racks where game_id = g), 9);

  s := public.get_state(g);
  perform t.eq('state: my_rack has 9 slots', jsonb_array_length(s -> 'my_rack'), 9);
  perform t.eq('state: no bag key', s ? 'bag', false);
  perform t.eq('state: bag count public', (s -> 'game' ->> 'bag_count')::int, 79);
  perform t.eq('state: players have no racks', (s -> 'players' -> 0) ? 'tiles', false);
  perform t.u(2);
  s2 := public.get_state(g);
  perform t.eq('state: own rack only',
    s2 -> 'my_rack',
    (select to_jsonb(tiles) from public.racks r join public.players p on p.id = r.player_id where p.game_id = g and p.seat = 1));
  perform t.u(6);
  perform t.fails('join: after start', format($q$select public.join_game(%L, 'Late')$q$, v_code), 'GAME_STARTED');
end $$;

-- A lone host cannot start.
do $$
declare g uuid;
begin
  perform t.u(1);
  g := (public.create_game('Solo', 2) ->> 'id')::uuid;
  perform t.fails('start: need 2 players', format($q$select public.start_game(%L)$q$, g), 'NEED_MORE_PLAYERS');
end $$;

-- =====================================================================
-- 3. Placement rules and scoring
-- =====================================================================
do $$
declare g uuid; r jsonb;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'HELLOXY');
  perform t.set_bag(g, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');

  perform t.u(2);
  perform t.fails('move: not your turn', format($q$select public.play_move(%L, t.pm(7,3,'h','HELLO'))$q$, g), 'NOT_YOUR_TURN');
  perform t.u(1);
  perform t.fails('move: must cover centre', format($q$select public.play_move(%L, t.pm(3,3,'h','HELLO'))$q$, g), 'MUST_COVER_CENTER');
  perform t.fails('move: tile not in rack', format($q$select public.play_move(%L, t.pm(7,3,'h','HELLZ'))$q$, g), 'TILE_NOT_IN_RACK');
  perform t.fails('move: blank not in rack', format($q$select public.play_move(%L, t.pm(7,3,'h','HELLo'))$q$, g), 'TILE_NOT_IN_RACK');
  perform t.fails('move: gap', format($q$select public.play_move(%L, '[{"r":7,"c":3,"letter":"H"},{"r":7,"c":5,"letter":"L"},{"r":7,"c":7,"letter":"O"}]'::jsonb)$q$, g), 'GAP_IN_WORD');
  perform t.fails('move: not in line', format($q$select public.play_move(%L, '[{"r":7,"c":7,"letter":"H"},{"r":8,"c":8,"letter":"E"}]'::jsonb)$q$, g), 'NOT_IN_LINE');
  perform t.fails('move: single first tile', format($q$select public.play_move(%L, '[{"r":7,"c":7,"letter":"H"}]'::jsonb)$q$, g), 'NO_WORD');
  perform t.fails('move: off board', format($q$select public.play_move(%L, '[{"r":7,"c":15,"letter":"H"}]'::jsonb)$q$, g), 'INVALID_MOVE');
  perform t.fails('move: bad letter', format($q$select public.play_move(%L, '[{"r":7,"c":7,"letter":"h"}]'::jsonb)$q$, g), 'INVALID_MOVE');
  perform t.fails('move: duplicate square', format($q$select public.play_move(%L, '[{"r":7,"c":7,"letter":"H"},{"r":7,"c":7,"letter":"E"}]'::jsonb)$q$, g), 'SQUARE_OCCUPIED');
  perform t.eq('move: failed attempts changed nothing', (select move_seq from public.games where id = g), 0);

  -- HELLO row 7 cols 3-7: H on DL(7,3)=8, E, L, L, O on centre DW => (8+1+1+1+1)*2 = 24
  r := public.play_move(g, t.pm(7,3,'h','HELLO'));
  perform t.eq('HELLO score 24', (r ->> 'score')::int, 24);
  perform t.eq('HELLO words', r -> 'words', '[{"word":"HELLO","score":24}]'::jsonb);
  perform t.eq('HELLO bingo no', (r ->> 'bingo')::boolean, false);
  perform t.eq('HELLO player score', t.score(g, 0), 24);
  perform t.eq('HELLO rack refilled with ABCDE', t.rack(g, 0), 'ABCDEXY');
  perform t.eq('HELLO bag count', (select bag_count from public.games where id = g), 21);
  perform t.eq('HELLO board tiles', (select count(*)::int from public.board_tiles where game_id = g), 5);
  perform t.eq('HELLO turn passes', (select turn_seat from public.games where id = g), 1);

  -- seat 1: WORLD down column 7 through the O: W4+O1+R1+L1+D2 = 9, no premiums on new squares
  perform t.set_rack(g, 1, 'WRLDQZK');
  perform t.u(2);
  perform t.fails('move: not connected', format($q$select public.play_move(%L, t.pm(0,0,'h','WRLD'))$q$, g), 'NOT_CONNECTED');
  perform t.fails('move: occupied square', format($q$select public.play_move(%L, t.pm(7,7,'h','W'))$q$, g), 'SQUARE_OCCUPIED');
  r := public.play_move(g, t.pm(6,7,'v','W.RLD'));
  perform t.eq('WORLD score 9', (r ->> 'score')::int, 9);
  perform t.eq('WORLD words', r -> 'words', '[{"word":"WORLD","score":9}]'::jsonb);

  -- seat 0: BAR along row 8 using existing R at (8,7). Cross words LB and LA.
  --   BAR = B3 + A(DL at 8,6)=2 + R1 = 6 ; LB = 1+3 = 4 ; LA = 1+2 = 3 ; total 13
  perform t.set_rack(g, 0, 'BAQXZJK');
  perform t.u(1);
  r := public.play_move(g, t.pm(8,5,'h','BA.'));
  perform t.eq('BAR total 13', (r ->> 'score')::int, 13);
  perform t.eq('BAR forms 3 words', jsonb_array_length(r -> 'words'), 3);
  perform t.eq('BAR words', r -> 'words', '[{"word":"BAR","score":6},{"word":"LB","score":4},{"word":"LA","score":3}]'::jsonb);
  perform t.eq('running score', t.score(g, 0), 24 + 13);
end $$;

-- Single tile forms words both ways; premium squares only count when newly covered.
do $$
declare g uuid; r jsonb;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'ABQQQQQ');
  perform t.set_bag(g, 'ZZZZZZZZZZ');
  -- AB at (7,7),(7,8): (1+3)*2 = 8 (centre DW)
  r := public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.eq('AB score 8', (r ->> 'score')::int, 8);
  -- seat 1 places one tile below B at (8,8): word "BE" vertical only. (8,8) is DL: E 1*2 -> B3+2=5
  perform t.set_rack(g, 1, 'EQQQQQQ');
  perform t.u(2);
  r := public.play_move(g, t.pm(8,8,'h','E'));
  perform t.eq('single tile scores vertical word with DL', (r ->> 'score')::int, 5);
  perform t.eq('single tile words', r -> 'words', '[{"word":"BE","score":5}]'::jsonb);
  -- the centre DW must not apply again: extend AB to ABS using existing tiles: S at (7,9): 1+3+1 = 5
  perform t.set_rack(g, 0, 'SQQQQQQ');
  perform t.u(1);
  r := public.play_move(g, t.pm(7,9,'h','S'));
  perform t.eq('premium not reused (ABS = 5)', (r ->> 'score')::int, 5);
  -- single tile with no neighbours in line but touching diagonally only is not connected
  perform t.set_rack(g, 1, 'QQQQQQQ');
  perform t.u(2);
  perform t.fails('diagonal is not connected', format($q$select public.play_move(%L, t.pm(9,9,'h','Q'))$q$, g), 'NOT_CONNECTED');
end $$;

-- Bingo + blank: all 7 tiles earn 50, blank scores 0.
do $$
declare g uuid; r jsonb;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'RETAIN?');
  perform t.set_bag(g, 'ABCDEFGHIJ');
  r := public.play_move(g, t.pm(7,4,'h','RETAINs'));
  -- RETAIN(1 each)=6, blank S=0, centre DW at (7,7)=A => 6*2 = 12, +50 bingo
  perform t.eq('bingo total', (r ->> 'score')::int, 62);
  perform t.eq('bingo flag', (r ->> 'bingo')::boolean, true);
  perform t.eq('bingo word score', (r -> 'words' -> 0 ->> 'score')::int, 12);
  perform t.eq('bingo rack redrawn', t.rack(g, 0), 'ABCDEFG');
  perform t.eq('blank stored as blank on board',
    (select is_blank from public.board_tiles where game_id = g and row_no = 7 and col_no = 10), true);
end $$;

-- =====================================================================
-- 4. Challenges and votes (3 players)
-- =====================================================================
do $$
declare g uuid; r jsonb; bag_before text; rack_before text; v jsonb;
begin
  g := t.new_game(3);
  perform t.set_rack(g, 0, 'ZQAAAAA');
  bag_before := null;
  perform t.u(1);
  rack_before := t.rack(g, 0);
  select t.bag(g) into bag_before;
  r := public.play_move(g, t.pm(7,7,'h','ZQ'));
  perform t.eq('ZQ scored (10+10)*2', (r ->> 'score')::int, 40);
  perform t.eq('bag shrank by 2', (select bag_count from public.games where id = g), 77);

  perform t.fails('challenge: own move', format($q$select public.challenge_move(%L)$q$, g), 'CANNOT_CHALLENGE_OWN_MOVE');
  perform t.u(2);
  perform public.challenge_move(g);
  perform t.eq('challenge opens', (select status from public.moves where game_id = g and seq = 1), 'challenged');
  perform t.fails('challenge: already open', format($q$select public.challenge_move(%L)$q$, g), 'CHALLENGE_OPEN');
  perform t.fails('play blocked during challenge', format($q$select public.play_move(%L, t.pm(8,7,'h','Q'))$q$, g), 'CHALLENGE_OPEN');
  perform t.fails('pass blocked during challenge', format($q$select public.pass_turn(%L)$q$, g), 'CHALLENGE_OPEN');

  perform t.u(1);
  perform t.fails('mover cannot vote', format($q$select public.cast_vote(%L, true)$q$, g), 'MOVER_CANNOT_VOTE');
  perform t.u(2);
  perform t.fails('challenger cannot vote (accept)', format($q$select public.cast_vote(%L, true)$q$, g), 'CHALLENGER_CANNOT_VOTE');
  perform t.fails('challenger cannot vote (reject)', format($q$select public.cast_vote(%L, false)$q$, g), 'CHALLENGER_CANNOT_VOTE');
  perform t.eq('challenger attempts left the challenge open', (select status from public.moves where game_id = g and seq = 1), 'challenged');
  perform t.eq('challenger attempts recorded no votes', (select count(*)::int from public.challenge_votes), 0);
  perform t.u(3);
  v := public.cast_vote(g, false);
  perform t.eq('juror reject undoes the play', v ->> 'result', 'reverted');
  perform t.eq('move marked reverted', (select status from public.moves where game_id = g and seq = 1), 'reverted');
  perform t.eq('board cleared', (select count(*)::int from public.board_tiles where game_id = g), 0);
  perform t.eq('score removed', t.score(g, 0), 0);
  perform t.eq('rack restored', t.rack(g, 0), rack_before);
  perform t.eq('bag restored (same tiles)', t.bag(g), bag_before);
  perform t.eq('bag count restored', (select bag_count from public.games where id = g), 79);
  perform t.eq('mover loses turn: next player is up', (select turn_seat from public.games where id = g), 1);
  perform t.eq('reverted play counts as scoreless', (select scoreless_turns from public.games where id = g), 1);
  perform t.fails('no open challenge any more', format($q$select public.cast_vote(%L, true)$q$, g), 'NO_OPEN_CHALLENGE');
  perform t.fails('reverted move cannot be re-challenged', format($q$select public.challenge_move(%L)$q$, g), 'ALREADY_RESOLVED');

  -- seat 1 now plays a valid word and everyone accepts
  perform t.set_rack(g, 1, 'ABQQQQQ');
  perform t.u(2);
  r := public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.eq('AB scored 8', (r ->> 'score')::int, 8);
  perform t.u(3);
  perform public.challenge_move(g);
  perform t.u(1);
  v := public.cast_vote(g, true);
  perform t.eq('3 players: the one juror accepting upholds', v ->> 'result', 'upheld');
  perform t.eq('move upheld', (select status from public.moves where game_id = g and seq = 2), 'upheld');
  perform t.eq('score kept', t.score(g, 1), 8);
  perform t.eq('turn goes on to seat 2', (select turn_seat from public.games where id = g), 2);
  perform t.fails('upheld word cannot be challenged again', format($q$select public.challenge_move(%L)$q$, g), 'ALREADY_RESOLVED');

  -- window closes once the next player acts
  perform t.u(3);
  perform public.pass_turn(g);
  perform t.u(1);
  perform t.fails('window closed after next move', format($q$select public.challenge_move(%L)$q$, g), 'NOTHING_TO_CHALLENGE');
end $$;

-- Challenge window only covers the latest play; non-plays cannot be challenged.
do $$
declare g uuid;
begin
  g := t.new_game(2);
  perform t.u(1);
  perform public.pass_turn(g);
  perform t.u(2);
  perform t.fails('cannot challenge a pass', format($q$select public.challenge_move(%L)$q$, g), 'NOTHING_TO_CHALLENGE');
end $$;

-- 2-player challenge: nobody else exists, so the challenger is the sole voter.
do $$
declare g uuid; v jsonb;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'ABQQQQQ');
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.u(1);
  perform t.fails('no vote possible without an open challenge', format($q$select public.cast_vote(%L, true)$q$, g), 'NO_OPEN_CHALLENGE');
  perform t.u(2);
  perform public.challenge_move(g);
  perform t.u(1);
  perform t.fails('2 players: mover cannot vote on challenge', format($q$select public.cast_vote(%L, true)$q$, g), 'MOVER_CANNOT_VOTE');
  perform t.u(2);
  v := public.cast_vote(g, true);
  perform t.eq('2 players: challenger accepts -> upheld', v ->> 'result', 'upheld');
end $$;

-- 4 players: challenger and mover are excluded, the two others must both accept.
do $$
declare g uuid; v jsonb;
begin
  g := t.new_game(4);
  perform t.set_rack(g, 0, 'ABQQQQQ');
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.u(2);
  perform public.challenge_move(g);
  perform t.fails('4 players: challenger cannot vote', format($q$select public.cast_vote(%L, true)$q$, g), 'CHALLENGER_CANNOT_VOTE');
  perform t.u(3);
  v := public.cast_vote(g, true);
  perform t.eq('4 players: first juror accepts -> pending', v ->> 'result', 'pending');
  perform t.u(4);
  v := public.cast_vote(g, true);
  perform t.eq('4 players: both jurors accept -> upheld', v ->> 'result', 'upheld');
end $$;

do $$
declare g uuid; v jsonb;
begin
  g := t.new_game(4);
  perform t.set_rack(g, 0, 'ABQQQQQ');
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.u(2);
  perform public.challenge_move(g);
  perform t.u(3);
  perform public.cast_vote(g, true);
  perform t.u(4);
  v := public.cast_vote(g, false);
  perform t.eq('4 players: one juror rejecting undoes the play', v ->> 'result', 'reverted');
end $$;

-- Host can force-accept a stalled vote (4 players so a vote can be left pending).
do $$
declare g uuid; v jsonb;
begin
  g := t.new_game(4);
  perform t.set_rack(g, 0, 'ABQQQQQ');
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.u(2);
  perform public.challenge_move(g);
  perform t.u(3);
  perform public.cast_vote(g, true);
  perform t.u(2);
  perform t.fails('non-host cannot force', format($q$select public.host_skip(%L)$q$, g), 'HOST_ONLY');
  perform t.u(1);
  v := public.host_skip(g);
  perform t.eq('host accepts stalled challenge', v ->> 'action', 'challenge_accepted');
  perform t.eq('move upheld by host', (select status from public.moves where game_id = g and seq = 1), 'upheld');
end $$;

-- =====================================================================
-- 5. Pass, swap, skip, rack order
-- =====================================================================
do $$
declare g uuid; before_rack text; r_after text;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'ABCDEFG');
  perform t.set_bag(g, repeat('Z', 30));
  perform t.u(1);
  perform t.fails('swap: letter not in rack', format($q$select public.swap_tiles(%L, array['Q'])$q$, g), 'TILE_NOT_IN_RACK');
  perform t.fails('swap: empty', format($q$select public.swap_tiles(%L, array[]::text[])$q$, g), 'INVALID_SWAP');
  perform public.swap_tiles(g, array['A','B']);
  perform t.eq('swap: rack now has Z Z', t.rack(g, 0), 'CDEFGZZ');
  perform t.eq('swap: bag count unchanged', (select bag_count from public.games where id = g), 30);
  perform t.eq('swap: bag has A,B returned', (select count(*)::int from public.game_secrets, unnest(bag) x where game_id = g and x in ('A','B')), 2);
  perform t.eq('swap: turn passed', (select turn_seat from public.games where id = g), 1);
  perform t.eq('swap: scoreless', (select scoreless_turns from public.games where id = g), 1);
  perform t.set_bag(g, 'ABCDEF');
  perform t.u(2);
  perform t.fails('swap: bag too small', format($q$select public.swap_tiles(%L, array[%L])$q$, g, substr(t.rack(g,1),1,1)), 'BAG_TOO_SMALL');
end $$;

do $$
declare g uuid;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'ABCDEFG');
  perform t.u(1);
  perform t.fails('rack order: different tiles', format($q$select public.save_rack_order(%L, array['A','','B','','C','D','E','F','Q'])$q$, g), 'INVALID_RACK');
  perform t.fails('rack order: tile missing', format($q$select public.save_rack_order(%L, array['','G','','F','E','','D','C','B'])$q$, g), 'INVALID_RACK');
  perform t.fails('rack order: wrong length', format($q$select public.save_rack_order(%L, array['A','B'])$q$, g), 'INVALID_RACK');
end $$;

do $$
declare g uuid; s jsonb;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'ABCDEFG');
  perform t.u(1);
  perform public.save_rack_order(g, array['','G','','F','E','A','D','C','B']);
  s := public.get_state(g);
  perform t.eq('rack order persisted with gaps', s -> 'my_rack', '["","G","","F","E","A","D","C","B"]'::jsonb);
end $$;

do $$
declare g uuid; v jsonb;
begin
  g := t.new_game(3);
  perform t.u(2);
  perform t.fails('skip: host only', format($q$select public.host_skip(%L)$q$, g), 'HOST_ONLY');
  perform t.u(1);
  v := public.host_skip(g);   -- seat 0 is up (host themself)
  perform t.eq('skip action', v ->> 'action', 'skipped');
  perform t.eq('skip advances turn', (select turn_seat from public.games where id = g), 1);
  perform t.eq('skip is not a scoreless turn', (select scoreless_turns from public.games where id = g), 0);
  perform t.eq('skip recorded for the skipped player', (select player_id from public.moves where game_id = g and kind = 'skip'),
               (select id from public.players where game_id = g and seat = 0));
end $$;

-- =====================================================================
-- 6. End of game
-- =====================================================================
do $$
declare g uuid; s jsonb;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'AB');     -- 1 + 3 = 4
  perform t.set_rack(g, 1, 'Q');      -- 10
  perform t.u(1);
  perform public.pass_turn(g); perform t.u(2);
  perform public.pass_turn(g); perform t.u(1);
  perform public.pass_turn(g); perform t.u(2);
  perform public.pass_turn(g); perform t.u(1);
  perform public.pass_turn(g);
  perform t.eq('5 passes: still active', (select status from public.games where id = g), 'active');
  perform t.u(2);
  perform public.pass_turn(g);
  perform t.eq('6 scoreless turns end the game', (select status from public.games where id = g), 'finished');
  perform t.eq('rack penalty p0', t.score(g, 0), -4);
  perform t.eq('rack penalty p1', t.score(g, 1), -10);
  s := public.get_state(g);
  perform t.eq('final racks revealed', jsonb_typeof(s -> 'final_racks'), 'object');
  perform t.fails('no moves after finish', format($q$select public.pass_turn(%L)$q$, g), 'GAME_NOT_ACTIVE');
end $$;

-- Going out: closing window, finalise gives rack totals to the player who went out.
do $$
declare g uuid;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'AB');
  perform t.set_rack(g, 1, 'QZ');          -- 20
  perform t.set_bag(g, '');
  perform t.u(1);
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.eq('out: status closing', (select status from public.games where id = g), 'closing');
  perform t.eq('out: out_seat', (select out_seat from public.games where id = g), 0);
  perform t.fails('out: mover cannot finalise', format($q$select public.finalize_game(%L)$q$, g), 'MOVER_CANNOT_FINALIZE');
  perform t.fails('out: nobody can play on', format($q$select public.pass_turn(%L)$q$, g), 'GAME_NOT_ACTIVE');
  perform t.u(2);
  perform public.finalize_game(g);
  perform t.eq('out: finished', (select status from public.games where id = g), 'finished');
  perform t.eq('out: winner bonus 8 + 20', t.score(g, 0), 28);
  perform t.eq('out: loser penalty', t.score(g, 1), -20);
end $$;

-- Challenge while closing: reject reopens the game; accept ends it.
do $$
declare g uuid;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'AB');
  perform t.set_rack(g, 1, 'QZ');
  perform t.set_bag(g, '');
  perform t.u(1);
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.u(2);
  perform public.challenge_move(g);
  perform t.fails('closing: finalise blocked by open challenge', format($q$select public.finalize_game(%L)$q$, g), 'CHALLENGE_OPEN');
  perform public.cast_vote(g, false);
  perform t.eq('closing+reject: game active again', (select status from public.games where id = g), 'active');
  perform t.eq('closing+reject: rack restored', t.rack(g, 0), 'AB');
  perform t.eq('closing+reject: score removed', t.score(g, 0), 0);
  perform t.eq('closing+reject: turn with other player', (select turn_seat from public.games where id = g), 1);
end $$;

do $$
declare g uuid;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'AB');
  perform t.set_rack(g, 1, 'QZ');
  perform t.set_bag(g, '');
  perform t.u(1);
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  perform t.u(2);
  perform public.challenge_move(g);
  perform public.cast_vote(g, true);
  perform t.eq('closing+accept: game finished', (select status from public.games where id = g), 'finished');
  perform t.eq('closing+accept: bonus applied', t.score(g, 0), 28);
end $$;

-- Host can end a stalled closing game.
do $$
declare g uuid; v jsonb;
begin
  g := t.new_game(2);
  perform t.set_rack(g, 0, 'AB');
  perform t.set_bag(g, '');
  perform public.play_move(g, t.pm(7,7,'h','AB'));
  v := public.host_skip(g);
  perform t.eq('host finishes closing game', v ->> 'action', 'finished');
end $$;

-- =====================================================================
-- 7. Rejoin, rename, my_games, cleanup
-- =====================================================================
do $$
declare g uuid; v_code text; l jsonb;
begin
  g := t.new_game(2);
  select code into v_code from public.games where id = g;
  perform t.u(5);                                  -- Bea comes back on a fresh anonymous session
  perform t.fails('rejoin needs confirmation', format($q$select public.join_game(%L, 'p2')$q$, v_code), 'NAME_TAKEN');
  perform public.join_game(v_code, 'p2', true);
  perform t.eq('rejoin: new session has the seat', (select user_id::text from public.players where game_id = g and seat = 1), '00000000-0000-0000-0000-000000000005');
  perform t.eq('rejoin: keeps rack', jsonb_array_length(public.get_state(g) -> 'my_rack'), 9);
  perform t.u(2);
  perform t.fails('rejoin: old session locked out', format($q$select public.get_state(%L)$q$, g), 'NOT_A_PLAYER');

  perform t.u(1);
  perform public.rename_player('Alexandra');
  perform t.eq('rename applies to games', (select name from public.players where game_id = g and seat = 0), 'Alexandra');
  perform t.fails('rename: collision', $q$select public.rename_player('P2')$q$, 'NAME_TAKEN');
  l := public.my_games();
  perform t.eq('my_games lists the game', (select count(*)::int from jsonb_array_elements(l) e where e ->> 'code' = v_code), 1);
end $$;

do $$
declare g uuid;
begin
  g := t.new_game(2);
  update public.games set last_activity = now() - interval '31 days' where id = g;
  perform t.eq('cleanup removes idle games', public.cleanup_inactive_games() >= 1, true);
  perform t.eq('cleanup cascades', (select count(*)::int from public.racks where game_id = g), 0);
end $$;

-- =====================================================================
-- 8. Privileges: what a signed-in browser client can and cannot touch
-- =====================================================================
do $$
declare g uuid; n int;
begin
  g := t.new_game(2);
  perform t.u(1);

  set local role authenticated;
  perform t.fails('client cannot read racks', $q$select * from public.racks$q$, 'permission denied for table racks');
  perform t.fails('client cannot read the bag', $q$select * from public.game_secrets$q$, 'permission denied for table game_secrets');
  perform t.fails('client cannot read moves', $q$select * from public.moves$q$, 'permission denied for table moves');
  perform t.fails('client cannot read players', $q$select * from public.players$q$, 'permission denied for table players');
  perform t.fails('client cannot write games', $q$update public.games set status = 'finished'$q$, 'permission denied for table games');
  perform t.fails('client cannot call internals', $q$select public._finish_game(gen_random_uuid(), null)$q$, 'permission denied for function _finish_game');
  perform t.fails('client cannot run cleanup', $q$select public.cleanup_inactive_games()$q$, 'permission denied for function cleanup_inactive_games');
  select count(*)::int into n from public.games;     -- RLS: only games the user is in
  reset role;
  perform t.eq('RLS: member sees only their games', n, (select count(*)::int from public.games g2 join public.players p on p.game_id = g2.id where p.user_id = '00000000-0000-0000-0000-000000000001'));

  perform t.u(9);
  set local role authenticated;
  select count(*)::int into n from public.games;
  reset role;
  perform t.eq('RLS: stranger sees no games', n, 0);

  set local role anon;
  perform t.fails('anon cannot call the API', $q$select public.create_game('X', 2)$q$, 'permission denied for function create_game');
  reset role;
end $$;

select 'ALL SQL TESTS PASSED' as result;
