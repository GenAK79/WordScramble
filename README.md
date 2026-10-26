# Word Scramble

A multiplayer tile-and-word game for 2–4 players. Static React app (GitHub Pages) + Supabase (Postgres, Auth, Realtime). Installable as a PWA.

Players join with a 5-character code. Play is live or asynchronous: every move is stored in Supabase, other players see it in real time, and you can come back to a game days later.

> "Scrabble" is a registered trademark. This project uses its own name, branding and artwork; only the green colour theme and the classic rules are shared.

---

## 1. Set up Supabase (about 5 minutes)

1. Create a project at <https://supabase.com>.
2. **Authentication → Sign In / Providers → enable "Allow anonymous sign-ins".** The app signs every player in anonymously.
3. **SQL Editor →** paste the whole of [`supabase/schema.sql`](supabase/schema.sql) and run it. It is safe to re-run.
4. **Project Settings → API:** note the *Project URL* and the *anon / publishable key*. (The key is designed to be public; the database enforces security — see below.)
5. Optional but recommended — auto-delete games idle for 30 days: **Database → Extensions → enable `pg_cron`**, then run [`supabase/cleanup.sql`](supabase/cleanup.sql).
6. Realtime: `schema.sql` adds the `games` table to the `supabase_realtime` publication. If you ever see "no live updates", check **Database → Replication / Publications** that `games` is ticked. (The app also polls every 15 s and on tab focus as a safety net.)

## 2. Run locally

```bash
npm install
cp .env.example .env.local      # fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm run dev
```

Commit the generated `package-lock.json`.

## 3. Deploy to GitHub Pages

1. Push this folder to a GitHub repository (default branch `main`).
2. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
3. **Settings → Secrets and variables → Actions → Variables tab →** add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
4. Push to `main`. The workflow in `.github/workflows/deploy.yml` runs the tests, builds, and publishes to `https://<user>.github.io/<repo>/`.

The app uses relative asset paths and hash routing (`#/join/ABCDE`), so no per-repository configuration or server rewrites are needed. Invitation links are generated from the address the host is playing on.

## 4. Tests

```bash
npm test            # client unit tests: scoring mirror, rack model, premium-square parity with the SQL
npm run test:sql    # database tests against a scratch Postgres 14+ (needs psql), see below
```

Database tests create and drop a throwaway database:

```bash
WS_TEST_PSQL="psql -h localhost -p 5432 -U postgres" npm run test:sql
```

They cover every rule listed in section 6 (placement, scoring with premium squares and blanks, bingo, challenge/vote/undo, end-game, rejoin) and the privilege model (clients cannot read racks, the bag or other tables).

---

## 5. How it is built

```
Browser (GitHub Pages)                    Supabase
  React + Vite PWA        ── RPC ──▶      Postgres functions (SECURITY DEFINER)
  anonymous Auth session  ◀─ Realtime ──  games row changes → client re-fetches get_state()
```

**Anti-cheat.** The browser only has the public key, so security lives in the database:

- Tables are locked down with row-level security and revoked privileges. The only direct read is a member's own `games` row (needed for Realtime).
- The shuffled **tile bag**, every **rack**, and the **tiles drawn on each move** live in tables no client can read.
- Every action is a function that checks it is your turn, that you own the tiles you play, the geometry (single line, no gaps, connected, centre on the first move) and computes the score **on the server**. The client's live score preview is only a convenience; the same scenarios are tested against both the client and the database so they agree.
- `get_state()` returns the board, scores, move history, and **only your own rack**.

**Identity.** Each browser gets an anonymous Supabase user; your display name is stored locally and can be changed at any time (it is updated in your unfinished games). Resume lists the games tied to your session. If you clear your browser or switch device, use **Join Game** with the game code and your original name to take your seat back (you are asked to confirm). Note this means anyone who knows the code *and* a player's name can claim that seat — appropriate for a game between friends, not for strangers.

## 6. Rules implemented

- 15×15 board, 100 tiles (98 letters + 2 blanks), standard tile values and premium squares; the centre star is a double-word square.
- Seven tiles per player; the first word must cover the centre; later words must connect.
- Premium squares only count for newly placed tiles. Blanks score 0 and need a letter chosen. Using all seven tiles scores a 50-point bonus.
- Pass, or swap 1–7 tiles (only while the bag holds at least 7). Six consecutive scoreless turns (passes, swaps, undone plays) end the game.
- The game ends when a player empties their rack with the bag empty. Everyone else loses the value of their remaining tiles and the player who went out gains the total.

### Word checking and challenges (no built-in dictionary)

Collins Scrabble Words and the Oxford dictionaries are licensed word lists, so none is bundled. Instead **players police words by challenge and vote**:

1. After a play, any *other* player can press **Challenge** until the next player acts.
2. The challenge screen lists the words formed with links to look each one up in Collins' online dictionary. (That is Collins' general dictionary, which is close to — but not identical with — the tournament Scrabble word list.)
3. **Every player except the one who played votes.** The word stands only if all accept; a single reject ends the vote and undoes the play.
4. Undone play: tiles return to the rack, any tiles drawn go back into the bag, the score is removed and the player loses that turn. There is no penalty for a failed challenge.
5. If the player who goes out is challenged and the word is rejected, the game resumes. Otherwise another player taps **Finish game** (or the challenge vote upholds the play), which applies the end-of-game scoring.

Two players: the single other player is the sole voter, so they decide after looking the word up.

If a player disappears, the **host** can skip their turn, accept a stalled vote (missing votes count as accept), or finish a game that is waiting on confirmations. Skipping is not counted as a scoreless turn.

## 7. Known limits (v1)

- No push notifications; turns are shown in the app (the browser tab title shows "▶ Your turn"). Resume lists games where it is your turn.
- Out of scope by design: chat, hints, stats, undo, spectators, history, timers.
- Supabase anonymous sign-ins have per-IP rate limits, and free-tier projects can pause after a period of inactivity; both are Supabase settings.
- Drag-and-drop uses pointer events (mouse and touch). Tap a rack tile, then tap a board square, works as an alternative; tap a placed tile to take it back.

## 8. Project layout

```
supabase/schema.sql      tables, RLS, privileges, game logic (functions)
supabase/cleanup.sql     optional pg_cron job (30-day idle cleanup)
src/lib/                 scoring mirror, rack model, API wrapper, router
src/components/          screens, board, rack, dialogs
test/                    client unit tests + SQL test suite
.github/workflows/       GitHub Pages deploy
```
