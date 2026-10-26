-- Optional: delete games with no activity for 30 days, nightly.
-- First enable the extension: Database -> Extensions -> pg_cron.
create extension if not exists pg_cron;

select cron.schedule(
  'word-scramble-cleanup',
  '17 3 * * *',
  $$ select public.cleanup_inactive_games(); $$
);
