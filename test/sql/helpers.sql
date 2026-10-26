-- Test harness part 2: assertion and game-building helpers (load after schema.sql).
drop schema if exists t cascade;
create schema t;
grant usage on schema t to anon, authenticated;

-- Switch the simulated signed-in user (1..9).
create function t.u(n int) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', ('00000000-0000-0000-0000-00000000000' || n)::text, false);
end $$;

create function t.eq(p_name text, p_actual anyelement, p_expected anyelement) returns void
language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL %: expected %, got %', p_name, p_expected, p_actual;
  end if;
  raise notice 'ok - %', p_name;
end $$;

-- Assert that a statement fails with exactly this error message.
create function t.fails(p_name text, p_sql text, p_msg text) returns void
language plpgsql as $$
declare got text;
begin
  begin
    execute p_sql;
    raise exception 'FAIL %: expected error %, but statement succeeded', p_name, p_msg;
  exception when others then
    got := sqlerrm;
    if got like 'FAIL %' then raise; end if;
  end;
  if got is distinct from p_msg then
    raise exception 'FAIL %: expected error %, got %', p_name, p_msg, got;
  end if;
  raise notice 'ok - %', p_name;
end $$;

-- Build play_move input. Lowercase = blank tile, '.' = square already on board.
create function t.pm(r int, c int, dir text, w text) returns jsonb language plpgsql as $$
declare i int; ch text; o jsonb := '[]'; rr int; cc int;
begin
  for i in 1..length(w) loop
    ch := substr(w, i, 1);
    continue when ch = '.';
    rr := r + case when dir = 'v' then i - 1 else 0 end;
    cc := c + case when dir = 'h' then i - 1 else 0 end;
    o := o || jsonb_build_array(jsonb_build_object('r', rr, 'c', cc, 'letter', upper(ch), 'blank', ch = lower(ch)));
  end loop;
  return o;
end $$;

-- n-player game, users 1..n, started, seat 0 to move.
create function t.new_game(n int) returns uuid language plpgsql as $$
declare g uuid; v_code text; i int;
begin
  perform t.u(1);
  g := (public.create_game('P1', n) ->> 'id')::uuid;
  select code into v_code from public.games where id = g;
  for i in 2..n loop
    perform t.u(i);
    perform public.join_game(v_code, 'P' || i);
  end loop;
  perform t.u(1);
  perform public.start_game(g);
  update public.games set turn_seat = 0 where id = g;
  return g;
end $$;

create function t.set_rack(g uuid, p_seat int, letters text) returns void language plpgsql as $$
declare arr text[] := array_fill(''::text, array[9]); i int;
begin
  for i in 1..length(letters) loop arr[i] := substr(letters, i, 1); end loop;
  update public.racks set tiles = arr
   where player_id = (select id from public.players where game_id = g and public.players.seat = p_seat);
end $$;

create function t.set_bag(g uuid, letters text) returns void language plpgsql as $$
begin
  update public.game_secrets set bag = case when letters = '' then '{}'::text[] else regexp_split_to_array(letters, '') end where game_id = g;
  update public.games set bag_count = length(letters) where id = g;
end $$;

create function t.rack(g uuid, p_seat int) returns text language sql stable as $$
  select coalesce(string_agg(x, '' order by x), '')
    from public.racks r join public.players p on p.id = r.player_id,
         unnest(public._rack_letters(r.tiles)) x
   where p.game_id = g and p.seat = p_seat;
$$;

create function t.bag(g uuid) returns text language sql stable as $$
  select coalesce(string_agg(x, '' order by x), '') from public.game_secrets, unnest(bag) x where game_id = g;
$$;

create function t.score(g uuid, p_seat int) returns int language sql stable as $$
  select score from public.players where game_id = g and public.players.seat = p_seat;
$$;

create function t.gcol(g uuid) returns public.games language sql stable as $$
  select * from public.games where id = g;
$$;
