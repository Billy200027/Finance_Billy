-- Install after push.sql and after storing FINANCE_PUSH_WORKER_KEY in
-- Edge Function secrets and the matching finance_push_worker_key in Vault.
-- Never commit either secret value.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('finance-billy-push','* * * * *',$cron$
 select net.http_post(
  url:='https://ulylpdeutafjuuevdllz.supabase.co/functions/v1/finance-push',
  headers:=jsonb_build_object('Content-Type','application/json','x-finance-worker',
   (select decrypted_secret from vault.decrypted_secrets where name='finance_push_worker_key')),
  body:='{}'::jsonb,timeout_milliseconds:=15000);
$cron$);
