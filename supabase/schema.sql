-- =====================================================================
-- Word Scramble: database schema, security and game logic (v1)
--
-- Run this whole file once in the Supabase SQL editor.
-- It is safe to re-run: tables use IF NOT EXISTS, functions use
-- CREATE OR REPLACE.
--
-- Security model
--   * The browser only holds the public (anon/publishable) key and an
--     anonymous Supabase Auth session.
--   * No table is directly readable or writable by clients, except that
--     members may SELECT their own game row (needed for Realtime).
--   * The tile bag, every rack and the tiles drawn on each move live in
--     tables with no client access. They are only reachable through the
--     SECURITY DEFINER functions below, which validate every action.
--   * Players receive only their own rack, from get_state().
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
create table if not exists public.games (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique check (code ~ '^[A-Z0-9]{5}$'),
  status           text not null default 'lobby'
                   check (status in ('lobby','active','closing','finished')),
  max_players      int  not null check (max_players between 2 and 4),
  host_player_id   uuid,
  turn_seat        int,
  out_seat         int,                       -- seat that went out (status 'closing')
  bag_count        int  not null default 0,
  scoreless_turns  int  not null default 0,
  move_seq         int  not null default 0,
  version          bigint not null default 0, -- bumped on every change; drives Realtime
  created_at       timestamptz not null default now(),
  started_at       timestamptz,
  finished_at      timestamptz,
  last_activity    timestamptz not null default now()
);

create table if not exists public.players (
  id         uuid primary key default gen_random_uuid(),
  game_id    uuid not null references public.games(id) on delete cascade,
  user_id    uuid not null,                   -- current auth.uid() that controls this seat
  seat       int  not null check (seat between 0 and 3),
  name       text not null check (char_length(name) between 1 and 20),
  score      int  not null default 0,
  joined_at  timestamptz not null default now(),
  unique (game_id, seat),
  unique (game_id, user_id)
);
create unique index if not exists players_game_name_uq on public.players (game_id, lower(name));
create index if not exists players_user_idx on public.players (user_id);

-- Rack: always exactly 9 slots; '' = empty slot, '?' = blank tile.
create table if not exists public.racks (
  player_id uuid primary key references public.players(id) on delete cascade,
  game_id   uuid not null references public.games(id) on delete cascade,
  tiles     text[] not null
);

-- The face-down bag (already shuffled). Never exposed.
create table if not exists public.game_secrets (
  game_id uuid primary key references public.games(id) on delete cascade,
  bag     text[] not null
);

create table if not exists public.board_tiles (
  game_id   uuid not null references public.games(id) on delete cascade,
  row_no    int  not null check (row_no between 0 and 14),
  col_no    int  not null check (col_no between 0 and 14),
  letter    text not null check (letter ~ '^[A-Z]$'),
  is_blank  boolean not null default false,
  move_seq  int  not null,
  primary key (game_id, row_no, col_no)
);

create table if not exists public.moves (
  id             bigserial primary key,
  game_id        uuid not null references public.games(id) on delete cascade,
  seq            int  not null,
  player_id      uuid,                         -- null for the final 'end' record
  kind           text not null check (kind in ('play','pass','swap','skip','end')),
  placements     jsonb,
  words          jsonb,
  score          int  not null default 0,
  info           jsonb,
  status         text not null default 'standing'
                 check (status in ('standing','challenged','upheld','reverted')),
  challenge_by   uuid,
  prev_scoreless int  not null default 0,
  created_at     timestamptz not null default now(),
  unique (game_id, seq)
);

-- Tiles drawn on a move (needed to undo a rejected word). Never exposed.
create table if not exists public.move_secrets (
  move_id bigint primary key references public.moves(id) on delete cascade,
  drawn   text[] not null default '{}'
);

create table if not exists public.challenge_votes (
  move_id   bigint not null references public.moves(id) on delete cascade,
  player_id uuid   not null,
  accept    boolean not null,
  primary key (move_id, player_id)
);

create table if not exists public.premium_squares (
  row_no int not null,
  col_no int not null,
  kind   text not null check (kind in ('TW','DW','TL','DL')),
  primary key (row_no, col_no)
);

insert into public.premium_squares (row_no, col_no, kind) values
  -- triple word
  (0,0,'TW'),(0,7,'TW'),(0,14,'TW'),(7,0,'TW'),(7,14,'TW'),(14,0,'TW'),(14,7,'TW'),(14,14,'TW'),
  -- double word (centre star is a double word)
  (1,1,'DW'),(2,2,'DW'),(3,3,'DW'),(4,4,'DW'),(1,13,'DW'),(2,12,'DW'),(3,11,'DW'),(4,10,'DW'),
  (13,1,'DW'),(12,2,'DW'),(11,3,'DW'),(10,4,'DW'),(13,13,'DW'),(12,12,'DW'),(11,11,'DW'),(10,10,'DW'),
  (7,7,'DW'),
  -- triple letter
  (1,5,'TL'),(1,9,'TL'),(5,1,'TL'),(5,5,'TL'),(5,9,'TL'),(5,13,'TL'),
  (9,1,'TL'),(9,5,'TL'),(9,9,'TL'),(9,13,'TL'),(13,5,'TL'),(13,9,'TL'),
  -- double letter
  (0,3,'DL'),(0,11,'DL'),(2,6,'DL'),(2,8,'DL'),(3,0,'DL'),(3,7,'DL'),(3,14,'DL'),
  (6,2,'DL'),(6,6,'DL'),(6,8,'DL'),(6,12,'DL'),(7,3,'DL'),(7,11,'DL'),
  (8,2,'DL'),(8,6,'DL'),(8,8,'DL'),(8,12,'DL'),
  (11,0,'DL'),(11,7,'DL'),(11,14,'DL'),(12,6,'DL'),(12,8,'DL'),(14,3,'DL'),(14,11,'DL')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Row level security: lock every table down
-- ---------------------------------------------------------------------
alter table public.games           enable row level security;
alter table public.players         enable row level security;
alter table public.racks           enable row level security;
alter table public.game_secrets    enable row level security;
alter table public.board_tiles     enable row level security;
alter table public.moves           enable row level security;
alter table public.move_secrets    enable row level security;
alter table public.challenge_votes enable row level security;
alter table public.premium_squares enable row level security;

revoke all on public.games, public.players, public.racks, public.game_secrets,
              public.board_tiles, public.moves, public.move_secrets,
              public.challenge_votes, public.premium_squares
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------
create or replace function public._uid() returns uuid
language plpgsql stable set search_path = public, pg_temp as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'NOT_AUTHENTICATED'; end if;
  return v;
end $$;

create or replace function public._is_member(p_game uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.players p where p.game_id = p_game and p.user_id = auth.uid());
$$;

-- Members may read their own game row (this is what Realtime needs).
drop policy if exists games_member_select on public.games;
create policy games_member_select on public.games
  for select to authenticated using (public._is_member(id));
grant select on public.games to authenticated;

create or replace function public._me(p_game uuid) returns public.players
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare pl public.players;
begin
  select * into pl from public.players where game_id = p_game and user_id = public._uid();
  if not found then raise exception 'NOT_A_PLAYER'; end if;
  return pl;
end $$;

create or replace function public._lock_game(p_game uuid) returns public.games
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games;
begin
  select * into g from public.games where id = p_game for update;
  if not found then raise exception 'GAME_NOT_FOUND'; end if;
  return g;
end $$;

create or replace function public._touch(p_game uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.games set version = version + 1, last_activity = now() where id = p_game;
$$;

create or replace function public._player_count(p_game uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from public.players where game_id = p_game;
$$;

-- Face value of a tile ('?' blank = 0).
create or replace function public.tile_value(l text) returns int
language sql immutable as $$
  select case when l = '?' then 0
         else (array[1,3,3,2,1,4,2,4,1,8,5,1,3,1,1,3,10,1,1,1,1,4,4,8,4,10])[ascii(l) - 64] end;
$$;

create or replace function public._shuffle(p_arr text[]) returns text[]
language sql volatile as $$
  select coalesce(array_agg(x order by random()), '{}'::text[]) from unnest(p_arr) as x;
$$;

-- Standard English distribution: 98 letters + 2 blanks = 100 tiles.
create or replace function public._new_bag() returns text[]
language sql volatile as $$
  select public._shuffle(regexp_split_to_array(
      repeat('A',9)||repeat('B',2)||repeat('C',2)||repeat('D',4)||repeat('E',12)||
      repeat('F',2)||repeat('G',3)||repeat('H',2)||repeat('I',9)||repeat('J',1)||
      repeat('K',1)||repeat('L',4)||repeat('M',2)||repeat('N',6)||repeat('O',8)||
      repeat('P',2)||repeat('Q',1)||repeat('R',6)||repeat('S',4)||repeat('T',6)||
      repeat('U',4)||repeat('V',2)||repeat('W',2)||repeat('X',1)||repeat('Y',2)||
      repeat('Z',1)||repeat('?',2), ''));
$$;

-- Rack helpers (racks are 9-slot arrays; '' = empty slot)
create or replace function public._rack_letters(p_rack text[]) returns text[]
language sql immutable as $$
  select coalesce(array_agg(x order by o), '{}'::text[])
  from unnest(p_rack) with ordinality as t(x, o) where x <> '';
$$;

create or replace function public._rack_remove(p_rack text[], p_letters text[]) returns text[]
language plpgsql immutable as $$
declare v text[] := p_rack; l text; i int;
begin
  foreach l in array coalesce(p_letters, '{}'::text[]) loop
    i := array_position(v, l);
    if i is null then raise exception 'TILE_NOT_IN_RACK'; end if;
    v[i] := '';
  end loop;
  return v;
end $$;

create or replace function public._rack_add(p_rack text[], p_letters text[]) returns text[]
language plpgsql immutable as $$
declare v text[] := p_rack; l text; i int;
begin
  foreach l in array coalesce(p_letters, '{}'::text[]) loop
    i := array_position(v, ''::text);
    if i is null then raise exception 'RACK_FULL'; end if;
    v[i] := l;
  end loop;
  return v;
end $$;

-- Score one run of tiles starting from (p_row,p_col) in direction (dr,dc).
-- Only newly placed tiles trigger premium squares. Returns {word,score,len}.
create or replace function public._word_run(
  grid text[], isblank boolean[], isnew boolean[],
  p_row int, p_col int, dr int, dc int
) returns jsonb
language plpgsql stable set search_path = public, pg_temp as $$
declare
  rr int := p_row; cc int := p_col; idx int;
  w text := ''; s int := 0; wm int := 1; lv int; k text; len int := 0;
begin
  while rr - dr >= 0 and cc - dc >= 0 and grid[(rr - dr) * 15 + (cc - dc) + 1] <> '' loop
    rr := rr - dr; cc := cc - dc;
  end loop;
  while rr <= 14 and cc <= 14 and grid[rr * 15 + cc + 1] <> '' loop
    idx := rr * 15 + cc + 1;
    w := w || grid[idx];
    len := len + 1;
    lv := case when isblank[idx] then 0 else public.tile_value(grid[idx]) end;
    if isnew[idx] then
      select kind into k from public.premium_squares where row_no = rr and col_no = cc;
      if k = 'DL' then lv := lv * 2;
      elsif k = 'TL' then lv := lv * 3;
      elsif k = 'DW' then wm := wm * 2;
      elsif k = 'TW' then wm := wm * 3;
      end if;
    end if;
    s := s + lv;
    rr := rr + dr; cc := cc + dc;
  end loop;
  return jsonb_build_object('word', w, 'score', s * wm, 'len', len);
end $$;

-- ---------------------------------------------------------------------
-- Lobby: create / peek / join / rename / start
-- ---------------------------------------------------------------------
create or replace function public.create_game(p_name text, p_max int) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := public._uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text; v_game uuid; v_player uuid; i int; tries int := 0;
begin
  if char_length(v_name) not between 1 and 20 then raise exception 'INVALID_NAME'; end if;
  if p_max is null or p_max not between 2 and 4 then raise exception 'INVALID_PLAYER_COUNT'; end if;
  loop
    v_code := '';
    for i in 1..5 loop
      v_code := v_code || substr(v_chars, 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (select 1 from public.games where code = v_code);
    tries := tries + 1;
    if tries > 20 then raise exception 'CODE_GENERATION_FAILED'; end if;
  end loop;
  insert into public.games (code, max_players) values (v_code, p_max) returning id into v_game;
  insert into public.players (game_id, user_id, seat, name) values (v_game, v_uid, 0, v_name)
    returning id into v_player;
  update public.games set host_player_id = v_player where id = v_game;
  return jsonb_build_object('id', v_game, 'code', v_code);
end $$;

create or replace function public.peek_game(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare g public.games; v_member boolean;
begin
  perform public._uid();
  select * into g from public.games where code = upper(btrim(coalesce(p_code, '')));
  if not found then raise exception 'GAME_NOT_FOUND'; end if;
  v_member := public._is_member(g.id);
  return jsonb_build_object(
    'status', g.status,
    'max_players', g.max_players,
    'player_count', public._player_count(g.id),
    'host_name', (select name from public.players where id = g.host_player_id),
    'is_member', v_member,
    'id', case when v_member then g.id else null end);
end $$;

-- Join a game by code. If a player with the same name already exists, the
-- caller must pass p_takeover = true to claim that seat (this is how a
-- player rejoins from a new device / cleared browser).
create or replace function public.join_game(p_code text, p_name text, p_takeover boolean default false)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := public._uid();
  v_name text := btrim(coalesce(p_name, ''));
  g public.games; same public.players; n int;
begin
  if char_length(v_name) not between 1 and 20 then raise exception 'INVALID_NAME'; end if;
  select * into g from public.games where code = upper(btrim(coalesce(p_code, ''))) for update;
  if not found then raise exception 'GAME_NOT_FOUND'; end if;

  if exists (select 1 from public.players where game_id = g.id and user_id = v_uid) then
    return jsonb_build_object('id', g.id, 'code', g.code, 'rejoined', true);
  end if;

  select * into same from public.players where game_id = g.id and lower(name) = lower(v_name);
  if found then
    if not coalesce(p_takeover, false) then raise exception 'NAME_TAKEN'; end if;
    update public.players set user_id = v_uid where id = same.id;
    perform public._touch(g.id);
    return jsonb_build_object('id', g.id, 'code', g.code, 'rejoined', true);
  end if;

  if g.status <> 'lobby' then raise exception 'GAME_STARTED'; end if;
  n := public._player_count(g.id);
  if n >= g.max_players then raise exception 'GAME_FULL'; end if;
  insert into public.players (game_id, user_id, seat, name) values (g.id, v_uid, n, v_name);
  perform public._touch(g.id);
  return jsonb_build_object('id', g.id, 'code', g.code, 'rejoined', false);
end $$;

-- Change the caller's display name in every unfinished game they are in.
create or replace function public.rename_player(p_name text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := public._uid(); v_name text := btrim(coalesce(p_name, ''));
begin
  if char_length(v_name) not between 1 and 20 then raise exception 'INVALID_NAME'; end if;
  begin
    update public.players set name = v_name
     where user_id = v_uid and name <> v_name
       and game_id in (select id from public.games where status <> 'finished');
  exception when unique_violation then
    raise exception 'NAME_TAKEN';
  end;
  update public.games set version = version + 1
   where status <> 'finished' and id in (select game_id from public.players where user_id = v_uid);
end $$;

create or replace function public.start_game(p_game uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  g public.games; me public.players; pl record;
  v_bag text[]; v_rack text[]; n int;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  if g.host_player_id <> me.id then raise exception 'HOST_ONLY'; end if;
  if g.status <> 'lobby' then raise exception 'ALREADY_STARTED'; end if;
  n := public._player_count(g.id);
  if n < 2 then raise exception 'NEED_MORE_PLAYERS'; end if;

  v_bag := public._new_bag();
  for pl in select id from public.players where game_id = g.id order by seat loop
    v_rack := public._rack_add(array_fill(''::text, array[9]), v_bag[1:7]);
    v_bag := v_bag[8:cardinality(v_bag)];
    insert into public.racks (player_id, game_id, tiles) values (pl.id, g.id, v_rack);
  end loop;
  insert into public.game_secrets (game_id, bag) values (g.id, v_bag)
    on conflict (game_id) do update set bag = excluded.bag;

  update public.games
     set status = 'active', max_players = n, started_at = now(),
         turn_seat = floor(random() * n)::int, bag_count = cardinality(v_bag),
         version = version + 1, last_activity = now()
   where id = g.id;
end $$;

-- ---------------------------------------------------------------------
-- Turn actions
-- ---------------------------------------------------------------------

-- Finish the game and apply end-of-game rack adjustments.
-- p_out_seat: seat that went out (gets the others' rack totals), or null.
create or replace function public._finish_game(p_game uuid, p_out_seat int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  pl record; total_others int := 0; adj jsonb := '[]'::jsonb; out_id uuid; v_seq int;
begin
  for pl in
    select p.id, p.seat,
           coalesce((select sum(public.tile_value(x))::int
                       from unnest(public._rack_letters(r.tiles)) x), 0) as rv
      from public.players p join public.racks r on r.player_id = p.id
     where p.game_id = p_game
  loop
    if p_out_seat is not null and pl.seat = p_out_seat then
      out_id := pl.id;
      continue;
    end if;
    total_others := total_others + pl.rv;
    update public.players set score = score - pl.rv where id = pl.id;
    adj := adj || jsonb_build_array(jsonb_build_object('player_id', pl.id, 'delta', -pl.rv));
  end loop;
  if out_id is not null then
    update public.players set score = score + total_others where id = out_id;
    adj := adj || jsonb_build_array(jsonb_build_object('player_id', out_id, 'delta', total_others));
  end if;
  select move_seq + 1 into v_seq from public.games where id = p_game;
  insert into public.moves (game_id, seq, player_id, kind, info)
    values (p_game, v_seq, null, 'end', jsonb_build_object('adjustments', adj, 'out_seat', p_out_seat));
  update public.games
     set status = 'finished', finished_at = now(), move_seq = v_seq, out_seat = p_out_seat,
         version = version + 1, last_activity = now()
   where id = p_game;
end $$;

-- Record a pass / swap / skip and advance the turn.
create or replace function public._record_nonplay(
  p_game uuid, p_player uuid, p_kind text, p_info jsonb, p_scoreless boolean
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; n int; new_scoreless int;
begin
  select * into g from public.games where id = p_game;
  n := public._player_count(p_game);
  new_scoreless := g.scoreless_turns + case when p_scoreless then 1 else 0 end;
  insert into public.moves (game_id, seq, player_id, kind, info, prev_scoreless)
    values (p_game, g.move_seq + 1, p_player, p_kind, p_info, g.scoreless_turns);
  update public.games
     set move_seq = move_seq + 1, turn_seat = (g.turn_seat + 1) % n,
         scoreless_turns = new_scoreless, version = version + 1, last_activity = now()
   where id = p_game;
  if new_scoreless >= 6 then perform public._finish_game(p_game, null); end if;
end $$;

create or replace function public._assert_can_act(g public.games, me public.players) returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if g.status <> 'active' then raise exception 'GAME_NOT_ACTIVE'; end if;
  if g.turn_seat <> me.seat then raise exception 'NOT_YOUR_TURN'; end if;
  if exists (select 1 from public.moves where game_id = g.id and seq = g.move_seq and status = 'challenged') then
    raise exception 'CHALLENGE_OPEN';
  end if;
end $$;

create or replace function public.play_move(p_game uuid, p_tiles jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  g public.games; me public.players; rk public.racks;
  n int; i int; el jsonb; idx int;
  rs int[] := '{}'; cs int[] := '{}'; ls text[] := '{}'; bl boolean[] := '{}';
  grid text[] := array_fill(''::text, array[225]);
  isblank boolean[] := array_fill(false, array[225]);
  isnew boolean[] := array_fill(false, array[225]);
  b record; needed text[] := '{}'; v_rack text[];
  v_row boolean; v_col boolean; minr int; maxr int; minc int; maxc int;
  board_empty boolean; connected boolean := false; covers_center boolean := false;
  wl jsonb := '[]'::jsonb; w jsonb; total int := 0; bingo boolean := false;
  v_bag text[]; drawn text[]; take int; mv_id bigint; next_seat int; n_players int;
  v_out boolean; placements jsonb;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  perform public._assert_can_act(g, me);

  -- ---- parse input -------------------------------------------------
  if p_tiles is null or jsonb_typeof(p_tiles) <> 'array' then raise exception 'INVALID_MOVE'; end if;
  n := jsonb_array_length(p_tiles);
  if n < 1 or n > 7 then raise exception 'INVALID_MOVE'; end if;
  for i in 0..n - 1 loop
    el := p_tiles -> i;
    if jsonb_typeof(el) <> 'object'
       or coalesce(el ->> 'r', '') !~ '^\d{1,2}$' or coalesce(el ->> 'c', '') !~ '^\d{1,2}$'
       or coalesce(el ->> 'letter', '') !~ '^[A-Z]$'
       or coalesce(el ->> 'blank', 'false') not in ('true', 'false') then
      raise exception 'INVALID_MOVE';
    end if;
    if (el ->> 'r')::int > 14 or (el ->> 'c')::int > 14 then raise exception 'INVALID_MOVE'; end if;
    rs := array_append(rs, (el ->> 'r')::int);
    cs := array_append(cs, (el ->> 'c')::int);
    ls := array_append(ls, el ->> 'letter');
    bl := array_append(bl, coalesce(el ->> 'blank', 'false')::boolean);
  end loop;

  -- ---- load board, drop new tiles on it ------------------------------
  for b in select row_no, col_no, letter, is_blank from public.board_tiles where game_id = g.id loop
    idx := b.row_no * 15 + b.col_no + 1;
    grid[idx] := b.letter; isblank[idx] := b.is_blank;
  end loop;
  board_empty := not exists (select 1 from public.board_tiles where game_id = g.id);

  for i in 1..n loop
    idx := rs[i] * 15 + cs[i] + 1;
    if grid[idx] <> '' then raise exception 'SQUARE_OCCUPIED'; end if;
    grid[idx] := ls[i]; isblank[idx] := bl[i]; isnew[idx] := true;
    needed := array_append(needed, case when bl[i] then '?' else ls[i] end);
    if rs[i] = 7 and cs[i] = 7 then covers_center := true; end if;
  end loop;

  -- ---- rack ownership --------------------------------------------------
  select * into rk from public.racks where player_id = me.id for update;
  v_rack := public._rack_remove(rk.tiles, needed);   -- raises TILE_NOT_IN_RACK

  -- ---- geometry ---------------------------------------------------------
  select min(x), max(x) into minr, maxr from unnest(rs) x;
  select min(x), max(x) into minc, maxc from unnest(cs) x;
  v_row := (minr = maxr);
  v_col := (minc = maxc);
  if n > 1 and not (v_row or v_col) then raise exception 'NOT_IN_LINE'; end if;
  if n > 1 then
    if v_row then
      for i in minc..maxc loop
        if grid[minr * 15 + i + 1] = '' then raise exception 'GAP_IN_WORD'; end if;
      end loop;
    else
      for i in minr..maxr loop
        if grid[i * 15 + minc + 1] = '' then raise exception 'GAP_IN_WORD'; end if;
      end loop;
    end if;
  end if;

  if board_empty then
    if not covers_center then raise exception 'MUST_COVER_CENTER'; end if;
  else
    for i in 1..n loop
      if (rs[i] > 0  and grid[(rs[i] - 1) * 15 + cs[i] + 1] <> '' and not isnew[(rs[i] - 1) * 15 + cs[i] + 1])
      or (rs[i] < 14 and grid[(rs[i] + 1) * 15 + cs[i] + 1] <> '' and not isnew[(rs[i] + 1) * 15 + cs[i] + 1])
      or (cs[i] > 0  and grid[rs[i] * 15 + cs[i]     ] <> '' and not isnew[rs[i] * 15 + cs[i]     ])
      or (cs[i] < 14 and grid[rs[i] * 15 + cs[i] + 2] <> '' and not isnew[rs[i] * 15 + cs[i] + 2])
      then connected := true; end if;
    end loop;
    if not connected then raise exception 'NOT_CONNECTED'; end if;
  end if;

  -- ---- words formed and scoring ------------------------------------------
  if n = 1 then
    w := public._word_run(grid, isblank, isnew, rs[1], cs[1], 0, 1);
    if (w ->> 'len')::int >= 2 then wl := wl || jsonb_build_array(w); end if;
    w := public._word_run(grid, isblank, isnew, rs[1], cs[1], 1, 0);
    if (w ->> 'len')::int >= 2 then wl := wl || jsonb_build_array(w); end if;
  else
    if v_row then
      wl := wl || jsonb_build_array(public._word_run(grid, isblank, isnew, rs[1], cs[1], 0, 1));
    else
      wl := wl || jsonb_build_array(public._word_run(grid, isblank, isnew, rs[1], cs[1], 1, 0));
    end if;
    for i in 1..n loop
      if v_row then
        w := public._word_run(grid, isblank, isnew, rs[i], cs[i], 1, 0);
      else
        w := public._word_run(grid, isblank, isnew, rs[i], cs[i], 0, 1);
      end if;
      if (w ->> 'len')::int >= 2 then wl := wl || jsonb_build_array(w); end if;
    end loop;
  end if;
  if jsonb_array_length(wl) = 0 then raise exception 'NO_WORD'; end if;

  select coalesce(sum((e ->> 'score')::int), 0) into total from jsonb_array_elements(wl) e;
  select jsonb_agg(jsonb_build_object('word', e ->> 'word', 'score', (e ->> 'score')::int)) into wl
    from jsonb_array_elements(wl) e;
  if n = 7 then bingo := true; total := total + 50; end if;

  -- ---- apply -------------------------------------------------------------------
  select bag into v_bag from public.game_secrets where game_id = g.id for update;
  take := least(n, coalesce(cardinality(v_bag), 0));
  drawn := v_bag[1:take];
  v_bag := v_bag[take + 1:coalesce(cardinality(v_bag), 0)];
  v_rack := public._rack_add(v_rack, drawn);
  v_out := (cardinality(public._rack_letters(v_rack)) = 0);

  select jsonb_agg(jsonb_build_object('r', rs[k], 'c', cs[k], 'letter', ls[k], 'blank', bl[k]) order by k)
    into placements from generate_subscripts(rs, 1) k;

  insert into public.moves (game_id, seq, player_id, kind, placements, words, score, prev_scoreless)
    values (g.id, g.move_seq + 1, me.id, 'play', placements, wl, total, g.scoreless_turns)
    returning id into mv_id;
  insert into public.move_secrets (move_id, drawn) values (mv_id, drawn);
  insert into public.board_tiles (game_id, row_no, col_no, letter, is_blank, move_seq)
    select g.id, rs[k], cs[k], ls[k], bl[k], g.move_seq + 1 from generate_subscripts(rs, 1) k;

  update public.racks set tiles = v_rack where player_id = me.id;
  update public.game_secrets set bag = v_bag where game_id = g.id;
  update public.players set score = score + total where id = me.id;

  n_players := public._player_count(g.id);
  next_seat := (me.seat + 1) % n_players;
  update public.games
     set move_seq = g.move_seq + 1, turn_seat = next_seat, scoreless_turns = 0,
         bag_count = cardinality(v_bag),
         status = case when v_out then 'closing' else 'active' end,
         out_seat = case when v_out then me.seat else null end,
         version = version + 1, last_activity = now()
   where id = g.id;

  return jsonb_build_object('score', total, 'words', wl, 'bingo', bingo);
end $$;

create or replace function public.pass_turn(p_game uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me public.players;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  perform public._assert_can_act(g, me);
  perform public._record_nonplay(g.id, me.id, 'pass', null, true);
end $$;

create or replace function public.swap_tiles(p_game uuid, p_letters text[]) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  g public.games; me public.players; rk public.racks;
  v_bag text[]; v_rack text[]; drawn text[]; take int; l text;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  perform public._assert_can_act(g, me);
  take := coalesce(cardinality(p_letters), 0);
  if take < 1 or take > 7 then raise exception 'INVALID_SWAP'; end if;
  foreach l in array p_letters loop
    if l is null or l !~ '^[A-Z?]$' then raise exception 'INVALID_SWAP'; end if;
  end loop;
  select bag into v_bag from public.game_secrets where game_id = g.id for update;
  if cardinality(v_bag) < 7 then raise exception 'BAG_TOO_SMALL'; end if;
  select * into rk from public.racks where player_id = me.id for update;
  v_rack := public._rack_remove(rk.tiles, p_letters);
  drawn := v_bag[1:take];
  v_bag := public._shuffle(v_bag[take + 1:cardinality(v_bag)] || p_letters);
  v_rack := public._rack_add(v_rack, drawn);
  update public.racks set tiles = v_rack where player_id = me.id;
  update public.game_secrets set bag = v_bag where game_id = g.id;
  perform public._record_nonplay(g.id, me.id, 'swap', jsonb_build_object('count', take), true);
end $$;

-- Persist the owner's preferred tile arrangement (same tiles, new order).
create or replace function public.save_rack_order(p_game uuid, p_tiles text[]) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare me public.players; rk public.racks; x text;
begin
  me := public._me(p_game);
  select * into rk from public.racks where player_id = me.id for update;
  if not found then raise exception 'GAME_NOT_ACTIVE'; end if;
  if p_tiles is null or cardinality(p_tiles) <> 9 then raise exception 'INVALID_RACK'; end if;
  foreach x in array p_tiles loop
    if x !~ '^([A-Z?]|)$' then raise exception 'INVALID_RACK'; end if;
  end loop;
  if (select array_agg(t order by t) from unnest(public._rack_letters(p_tiles)) t)
     is distinct from
     (select array_agg(t order by t) from unnest(public._rack_letters(rk.tiles)) t) then
    raise exception 'INVALID_RACK';
  end if;
  update public.racks set tiles = p_tiles where player_id = me.id;
end $$;

-- ---------------------------------------------------------------------
-- Challenges
-- ---------------------------------------------------------------------

-- Undo a rejected play: tiles go back to the rack, drawn tiles back to the
-- bag, score removed. The turn stays with the next player (the mover loses
-- their turn). Counts as a scoreless turn.
create or replace function public._revert_move(p_game uuid, p_seq int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  mv public.moves; rk public.racks; v_drawn text[]; v_bag text[]; v_rack text[];
  played text[]; new_scoreless int;
begin
  select * into mv from public.moves where game_id = p_game and seq = p_seq for update;
  select drawn into v_drawn from public.move_secrets where move_id = mv.id;
  select * into rk from public.racks where player_id = mv.player_id for update;
  select bag into v_bag from public.game_secrets where game_id = p_game for update;
  select array_agg(case when (e ->> 'blank')::boolean then '?' else e ->> 'letter' end)
    into played from jsonb_array_elements(mv.placements) e;

  v_rack := public._rack_add(public._rack_remove(rk.tiles, v_drawn), played);
  v_bag := public._shuffle(v_bag || v_drawn);

  delete from public.board_tiles where game_id = p_game and move_seq = mv.seq;
  update public.racks set tiles = v_rack where player_id = mv.player_id;
  update public.game_secrets set bag = v_bag where game_id = p_game;
  update public.players set score = score - mv.score where id = mv.player_id;
  update public.moves set status = 'reverted' where id = mv.id;

  new_scoreless := mv.prev_scoreless + 1;
  update public.games
     set status = 'active', out_seat = null, bag_count = cardinality(v_bag),
         scoreless_turns = new_scoreless, version = version + 1, last_activity = now()
   where id = p_game;
  if new_scoreless >= 6 then perform public._finish_game(p_game, null); end if;
end $$;

-- A word stands: close the challenge and, if the mover had gone out, end the game.
create or replace function public._uphold_move(p_game uuid, p_seq int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games;
begin
  update public.moves set status = 'upheld' where game_id = p_game and seq = p_seq;
  select * into g from public.games where id = p_game;
  if g.status = 'closing' then
    perform public._finish_game(p_game, g.out_seat);
  else
    perform public._touch(p_game);
  end if;
end $$;

create or replace function public.challenge_move(p_game uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me public.players; mv public.moves;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  if g.status not in ('active', 'closing') then raise exception 'GAME_NOT_ACTIVE'; end if;
  select * into mv from public.moves where game_id = g.id and seq = g.move_seq;
  if not found or mv.kind <> 'play' then raise exception 'NOTHING_TO_CHALLENGE'; end if;
  if mv.player_id = me.id then raise exception 'CANNOT_CHALLENGE_OWN_MOVE'; end if;
  if mv.status = 'challenged' then raise exception 'CHALLENGE_OPEN'; end if;
  if mv.status <> 'standing' then raise exception 'ALREADY_RESOLVED'; end if;
  update public.moves set status = 'challenged', challenge_by = me.id where id = mv.id;
  perform public._touch(g.id);
end $$;

-- Every player except the mover votes. Unanimous accept = word stands.
-- Any reject ends the vote immediately and the play is undone.
create or replace function public.cast_vote(p_game uuid, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me public.players; mv public.moves; accepts int; result text;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  select * into mv from public.moves where game_id = g.id and seq = g.move_seq and status = 'challenged';
  if not found then raise exception 'NO_OPEN_CHALLENGE'; end if;
  if mv.player_id = me.id then raise exception 'MOVER_CANNOT_VOTE'; end if;
  if p_accept is null then raise exception 'INVALID_VOTE'; end if;
  begin
    insert into public.challenge_votes (move_id, player_id, accept) values (mv.id, me.id, p_accept);
  exception when unique_violation then
    raise exception 'ALREADY_VOTED';
  end;

  if not p_accept then
    perform public._revert_move(g.id, mv.seq);
    return jsonb_build_object('result', 'reverted');
  end if;
  select count(*)::int into accepts from public.challenge_votes where move_id = mv.id and accept;
  if accepts >= public._player_count(g.id) - 1 then
    perform public._uphold_move(g.id, mv.seq);
    return jsonb_build_object('result', 'upheld');
  end if;
  perform public._touch(g.id);
  return jsonb_build_object('result', 'pending');
end $$;

-- After a player goes out, any other player can close the game once they
-- are satisfied nobody wants to challenge.
create or replace function public.finalize_game(p_game uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me public.players; mv public.moves;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  if g.status <> 'closing' then raise exception 'GAME_NOT_CLOSING'; end if;
  select * into mv from public.moves where game_id = g.id and seq = g.move_seq;
  if mv.status = 'challenged' then raise exception 'CHALLENGE_OPEN'; end if;
  if mv.player_id = me.id then raise exception 'MOVER_CANNOT_FINALIZE'; end if;
  perform public._finish_game(g.id, g.out_seat);
end $$;

-- Host-only escape hatch for absent players:
--   * open challenge  -> the word is accepted (missing votes count as accept)
--   * game closing    -> finish the game
--   * otherwise       -> skip the current player's turn (not a scoreless turn)
create or replace function public.host_skip(p_game uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me public.players; mv public.moves; v_player uuid;
begin
  g := public._lock_game(p_game);
  me := public._me(p_game);
  if g.host_player_id <> me.id then raise exception 'HOST_ONLY'; end if;
  if g.status not in ('active', 'closing') then raise exception 'GAME_NOT_ACTIVE'; end if;
  select * into mv from public.moves where game_id = g.id and seq = g.move_seq;
  if found and mv.status = 'challenged' then
    perform public._uphold_move(g.id, mv.seq);
    return jsonb_build_object('action', 'challenge_accepted');
  end if;
  if g.status = 'closing' then
    perform public._finish_game(g.id, g.out_seat);
    return jsonb_build_object('action', 'finished');
  end if;
  select id into v_player from public.players where game_id = g.id and seat = g.turn_seat;
  perform public._record_nonplay(g.id, v_player, 'skip', jsonb_build_object('by_host', true), false);
  return jsonb_build_object('action', 'skipped');
end $$;

-- ---------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------
create or replace function public.get_state(p_game uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare g public.games; me public.players; res jsonb;
begin
  me := public._me(p_game);
  select * into g from public.games where id = p_game;
  if not found then raise exception 'GAME_NOT_FOUND'; end if;

  res := jsonb_build_object(
    'game', jsonb_build_object(
      'id', g.id, 'code', g.code, 'status', g.status, 'max_players', g.max_players,
      'host_player_id', g.host_player_id, 'turn_seat', g.turn_seat, 'out_seat', g.out_seat,
      'bag_count', g.bag_count, 'scoreless_turns', g.scoreless_turns,
      'move_seq', g.move_seq, 'version', g.version,
      'created_at', g.created_at, 'finished_at', g.finished_at),
    'me', me.id,
    'players', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'seat', p.seat, 'name', p.name, 'score', p.score,
               'rack_count', coalesce(cardinality(public._rack_letters(r.tiles)), 0)) order by p.seat), '[]'::jsonb)
        from public.players p left join public.racks r on r.player_id = p.id
       where p.game_id = g.id),
    'board', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'r', b.row_no, 'c', b.col_no, 'l', b.letter, 'b', b.is_blank, 's', b.move_seq)), '[]'::jsonb)
        from public.board_tiles b where b.game_id = g.id),
    'moves', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'seq', m.seq, 'player_id', m.player_id, 'kind', m.kind, 'score', m.score,
               'words', m.words, 'placements', m.placements, 'info', m.info,
               'status', m.status, 'challenge_by', m.challenge_by,
               'votes', (select coalesce(jsonb_object_agg(v.player_id, v.accept), '{}'::jsonb)
                           from public.challenge_votes v where v.move_id = m.id)
             ) order by m.seq desc), '[]'::jsonb)
        from (select * from public.moves where game_id = g.id order by seq desc limit 100) m),
    'my_rack', (select to_jsonb(tiles) from public.racks where player_id = me.id)
  );

  if g.status = 'finished' then
    res := res || jsonb_build_object('final_racks', (
      select coalesce(jsonb_object_agg(r.player_id, to_jsonb(public._rack_letters(r.tiles))), '{}'::jsonb)
        from public.racks r where r.game_id = g.id));
  end if;
  return res;
end $$;

create or replace function public.my_games() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_uid uuid := public._uid();
begin
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by t.last_activity desc)
    from (
      select g.id, g.code, g.status, g.max_players, g.last_activity, g.turn_seat,
             public._player_count(g.id) as player_count,
             (select name from public.players x where x.game_id = g.id and x.seat = g.turn_seat) as turn_name,
             p.seat as my_seat, p.score as my_score
        from public.players p join public.games g on g.id = p.game_id
       where p.user_id = v_uid
       order by g.last_activity desc limit 30) t
  ), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- Housekeeping: delete games idle for 30 days (not callable by clients).
-- Schedule with pg_cron, see supabase/cleanup.sql.
-- ---------------------------------------------------------------------
create or replace function public.cleanup_inactive_games() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  delete from public.games where last_activity < now() - interval '30 days';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Privileges: clients may only call the public API functions.
-- ---------------------------------------------------------------------
revoke all on function
  public._uid(), public._is_member(uuid), public._me(uuid), public._lock_game(uuid),
  public._touch(uuid), public._player_count(uuid), public._shuffle(text[]), public._new_bag(),
  public._rack_letters(text[]), public._rack_remove(text[], text[]), public._rack_add(text[], text[]),
  public._word_run(text[], boolean[], boolean[], int, int, int, int),
  public._finish_game(uuid, int), public._record_nonplay(uuid, uuid, text, jsonb, boolean),
  public._assert_can_act(public.games, public.players),
  public._revert_move(uuid, int), public._uphold_move(uuid, int),
  public.cleanup_inactive_games(), public.tile_value(text)
  from public, anon, authenticated;
grant execute on function public._is_member(uuid) to authenticated;  -- used by the games RLS policy

revoke all on function
  public.create_game(text, int), public.peek_game(text), public.join_game(text, text, boolean),
  public.rename_player(text), public.start_game(uuid), public.play_move(uuid, jsonb),
  public.pass_turn(uuid), public.swap_tiles(uuid, text[]), public.save_rack_order(uuid, text[]),
  public.challenge_move(uuid), public.cast_vote(uuid, boolean), public.finalize_game(uuid),
  public.host_skip(uuid), public.get_state(uuid), public.my_games()
  from public, anon, authenticated;
grant execute on function
  public.create_game(text, int), public.peek_game(text), public.join_game(text, text, boolean),
  public.rename_player(text), public.start_game(uuid), public.play_move(uuid, jsonb),
  public.pass_turn(uuid), public.swap_tiles(uuid, text[]), public.save_rack_order(uuid, text[]),
  public.challenge_move(uuid), public.cast_vote(uuid, boolean), public.finalize_game(uuid),
  public.host_skip(uuid), public.get_state(uuid), public.my_games()
  to authenticated;

-- ---------------------------------------------------------------------
-- Realtime: broadcast changes to the games row (drives live updates).
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'games') then
    alter publication supabase_realtime add table public.games;
  end if;
end $$;
