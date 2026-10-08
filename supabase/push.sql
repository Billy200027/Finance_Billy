-- Private FCM routing. No user-supplied role or recipient is trusted.
create table if not exists finance_billy.push_devices (
 id uuid primary key, user_id uuid not null references finance_billy.members(id),
 session_id uuid not null, binding uuid not null, token text unique not null,
 updated_at timestamptz not null default now()
);
create table if not exists finance_billy.push_deliveries (
 id uuid primary key default gen_random_uuid(), event_id uuid not null,
 device_id uuid not null references finance_billy.push_devices(id) on delete cascade,
 user_id uuid not null, binding uuid not null, title text not null, body text not null, page text not null,
 created_at timestamptz not null default now(), next_at timestamptz not null default now(),
 attempts int not null default 0, lease uuid, lease_until timestamptz,
 status text not null default 'PENDING' check(status in ('PENDING','SENT','SKIPPED','FAILED')),
 error_code text, unique(event_id,device_id)
);
create index if not exists fb_push_pending on finance_billy.push_deliveries(next_at) where status='PENDING';
alter table finance_billy.push_devices enable row level security;
alter table finance_billy.push_deliveries enable row level security;
revoke all on finance_billy.push_devices,finance_billy.push_deliveries from public,anon,authenticated;

create or replace function public.finance_push_device(p_user uuid,p_session uuid,p_device uuid,p_binding uuid,p_token text,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.finance_session_valid(p_user,p_session) then raise exception 'Sesión revocada'; end if;
 if not p_enabled then
  delete from finance_billy.push_devices where id=p_device and user_id=p_user;
  return '{"ok":true}'::jsonb;
 end if;
 if not exists(select 1 from finance_billy.members where id=p_user and status='APROBADA' and not force_password) then raise exception 'Cuenta no habilitada'; end if;
 if p_binding is null or p_device is null or length(p_token) not between 30 and 4096 or p_token !~ '^[A-Za-z0-9_:\-]+$' then raise exception 'Dispositivo inválido'; end if;
 -- Possession of the native token permits replacing its old account association.
 delete from finance_billy.push_devices where token=p_token and id<>p_device;
 insert into finance_billy.push_devices(id,user_id,session_id,binding,token)
 values(p_device,p_user,p_session,p_binding,p_token)
 on conflict(id) do update set user_id=excluded.user_id,session_id=excluded.session_id,binding=excluded.binding,token=excluded.token,updated_at=now();
 return '{"ok":true}'::jsonb;
end $$;

create or replace function finance_billy.push_event() returns trigger language plpgsql security invoker set search_path='' as $$
declare audience text; recipient uuid; title text; body text; page text; event uuid:=gen_random_uuid();
begin
 if tg_table_name='news' then
  if new.status<>'PUBLICADO' then return new; end if;
  if tg_op='UPDATE' and old.status='PUBLICADO' then return new; end if;
  audience:='ALL'; title:='Nueva noticia'; body:='Hay una publicación nueva en Finance Billy.'; page:='Noticias';
 elsif tg_table_name='requests' then
  if tg_op='INSERT' then audience:='ADMIN'; title:='Nueva solicitud'; body:='Tienes una solicitud pendiente de revisión.'; page:='Solicitudes';
  elsif new.status='APROBADA_PENDIENTE_DESEMBOLSO' and old.status is distinct from new.status then
   audience:='USER'; recipient:=new.user_id; title:='Solicitud aprobada'; body:='Tu solicitud fue aprobada. Revisa su estado en Finance Billy.'; page:='Préstamos';
  else return new; end if;
 elsif tg_table_name='receipts' then
  audience:='ADMIN'; title:='Nuevo comprobante'; body:='Tienes un comprobante pendiente de revisión.'; page:='Comprobantes';
 end if;
 insert into finance_billy.push_deliveries(event_id,device_id,user_id,binding,title,body,page)
 select event,d.id,d.user_id,d.binding,title,body,page from finance_billy.push_devices d
 join finance_billy.members m on m.id=d.user_id
 where m.status='APROBADA' and not m.force_password and public.finance_session_valid(d.user_id,d.session_id)
 and (audience='ALL' or audience='ADMIN' and m.role='ADMIN' or audience='USER' and m.id=recipient);
 return new;
end $$;
drop trigger if exists fb_push_news on finance_billy.news;
create trigger fb_push_news after insert or update on finance_billy.news for each row execute function finance_billy.push_event();
drop trigger if exists fb_push_requests on finance_billy.requests;
create trigger fb_push_requests after insert or update on finance_billy.requests for each row execute function finance_billy.push_event();
drop trigger if exists fb_push_receipts on finance_billy.receipts;
create trigger fb_push_receipts after insert on finance_billy.receipts for each row execute function finance_billy.push_event();

create or replace function public.finance_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare batch uuid:=gen_random_uuid(); result jsonb;
begin
 update finance_billy.push_deliveries q set status='SKIPPED',error_code='INELIGIBLE'
 where q.status='PENDING' and (q.created_at<now()-interval '24 hours' or not exists(
 select 1 from finance_billy.push_devices d join finance_billy.members m on m.id=d.user_id
 where d.id=q.device_id and d.user_id=q.user_id and d.binding=q.binding and m.status='APROBADA'
 and not m.force_password and public.finance_session_valid(d.user_id,d.session_id)));
 with chosen as (
 select id from finance_billy.push_deliveries where status='PENDING' and next_at<=now()
 and (lease_until is null or lease_until<now()) order by created_at limit 50 for update skip locked
 ), leased as (
 update finance_billy.push_deliveries q set lease=batch,lease_until=now()+interval '2 minutes',attempts=attempts+1
 from chosen where q.id=chosen.id returning q.*
 ) select coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('token',d.token)),'[]') into result
 from leased l join finance_billy.push_devices d on d.id=l.device_id;
 return result;
end $$;
create or replace function public.finance_push_finish(p_id uuid,p_lease uuid,p_status text,p_code text default null,p_invalid boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare q finance_billy.push_deliveries;
begin
 select * into q from finance_billy.push_deliveries where id=p_id and lease=p_lease and status='PENDING' for update;
 if not found then return; end if;
 update finance_billy.push_deliveries set status=case when p_status='SENT' then 'SENT' when p_status='FAILED' or attempts>=6 then 'FAILED' else 'PENDING' end,
 error_code=left(p_code,80),next_at=now()+make_interval(secs=>least(3600,60*power(2,attempts)::int)),lease=null,lease_until=null where id=q.id;
 if p_invalid then delete from finance_billy.push_devices where id=q.device_id and binding=q.binding; end if;
end $$;
revoke all on function public.finance_push_device(uuid,uuid,uuid,uuid,text,boolean),public.finance_push_claim(),public.finance_push_finish(uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.finance_push_device(uuid,uuid,uuid,uuid,text,boolean),public.finance_push_claim(),public.finance_push_finish(uuid,uuid,text,text,boolean) to service_role;
revoke all on function finance_billy.push_event() from public,anon,authenticated;
