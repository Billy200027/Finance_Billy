-- Finance Billy 3.1: sin planes. No modifica las tablas del proyecto anterior.
create schema if not exists finance_billy;
revoke all on schema finance_billy from public,anon,authenticated;
grant usage on schema finance_billy to service_role;
create table finance_billy.settings(id int primary key check(id=1), value jsonb not null);
insert into finance_billy.settings values(1,'{"maintenance":false,"activation_days":100,"activation_price":100,"points_price":300,"points_amount":20,"cooldown_hours":168,"loan_min":4000,"loan_min_weeks":5,"loan_max_weeks":20,"rate":0.0115}');
create table finance_billy.members(id uuid primary key references auth.users(id), cedula text unique not null check(cedula ~ '^[0-9]{6,15}$'),name text not null,phone text not null default '',email text not null default '',role text not null default 'USUARIO' check(role in ('ADMIN','USUARIO')),status text not null default 'PENDIENTE' check(status in ('PENDIENTE','APROBADA','RECHAZADA','BLOQUEADA')),created_at timestamptz not null default now(),approved_at timestamptz,expires_at timestamptz,points int not null default 0 check(points>=0),force_password boolean not null default false,last_points_purchase timestamptz);
create unique index only_one_fb_admin on finance_billy.members(role) where role='ADMIN';
create table finance_billy.banks(id uuid primary key default gen_random_uuid(),name text not null unique,active boolean not null default true);
insert into finance_billy.banks(name) values('Banco Pichincha'),('Banco Guayaquil'),('Banco del Pacífico'),('Produbanco'),('Banco Bolivariano'),('Cooperativa / otro');
create table finance_billy.accounts(id uuid primary key default gen_random_uuid(),user_id uuid not null references finance_billy.members(id),bank_id uuid not null references finance_billy.banks(id),type text not null check(type in ('AHORRO','CORRIENTE')),number text not null,principal boolean not null default true,active boolean not null default true);
create index fb_accounts_user on finance_billy.accounts(user_id);
create table finance_billy.requests(id uuid primary key default gen_random_uuid(),user_id uuid not null references finance_billy.members(id),created_at timestamptz not null default now(),status text not null default 'PENDIENTE',amount int not null check(amount>0),weeks int not null check(weeks>0),rate numeric not null,snapshot_points int not null,bank_snapshot jsonb not null,reason text,disbursed_at timestamptz,reference text);
create unique index fb_one_request on finance_billy.requests(user_id) where status in ('PENDIENTE','APROBADA_PENDIENTE_DESEMBOLSO');
create index fb_queue on finance_billy.requests(created_at,id) where status in ('PENDIENTE','APROBADA_PENDIENTE_DESEMBOLSO');
create table finance_billy.loans(id uuid primary key default gen_random_uuid(),request_id uuid unique not null references finance_billy.requests(id),user_id uuid not null references finance_billy.members(id),amount int not null,weeks int not null,rate numeric not null,total int not null,status text not null default 'ACTIVO',disbursed_at timestamptz not null,settled_at timestamptz);
create unique index fb_one_active_loan on finance_billy.loans(user_id) where status='ACTIVO';
create index fb_loans_user on finance_billy.loans(user_id);
create table finance_billy.installments(id uuid primary key default gen_random_uuid(),loan_id uuid not null references finance_billy.loans(id),user_id uuid not null references finance_billy.members(id),number int not null,due date not null,amount int not null,principal int not null,interest int not null,verified int not null default 0,completed_at timestamptz,status text not null default 'PENDIENTE',unique(loan_id,number));
create index fb_installments_user_due on finance_billy.installments(user_id,due);
create table finance_billy.receipts(id uuid primary key default gen_random_uuid(),user_id uuid not null references finance_billy.members(id),kind text not null check(kind in ('CUOTA','ACTIVACION','PUNTOS','LIQUIDACION')),installment_id uuid references finance_billy.installments(id),loan_id uuid references finance_billy.loans(id),declared int not null check(declared>0),verified int not null default 0,path text unique not null,uploaded_at timestamptz not null default now(),checked_at timestamptz,status text not null default 'PENDIENTE',reason text,quote jsonb,key uuid unique not null);
create index fb_receipts_user on finance_billy.receipts(user_id,uploaded_at desc);
create table finance_billy.activations(id uuid primary key default gen_random_uuid(),user_id uuid not null references finance_billy.members(id),receipt_id uuid unique not null references finance_billy.receipts(id),starts_at timestamptz not null,ends_at timestamptz not null);
create table finance_billy.point_facts(key text primary key,user_id uuid not null references finance_billy.members(id),at timestamptz not null,delta int not null,source text not null,active boolean not null default true,seq bigint generated always as identity);
create index fb_facts_user_at on finance_billy.point_facts(user_id,at,key);
create table finance_billy.point_movements(id uuid primary key default gen_random_uuid(),user_id uuid not null references finance_billy.members(id),at timestamptz not null default now(),source text not null,requested int not null,applied int not null,before int not null,after int not null,reference text);
create index fb_movements_user on finance_billy.point_movements(user_id,at desc);
create table finance_billy.news(id uuid primary key default gen_random_uuid(),title text not null,body text not null,status text not null default 'PUBLICADO',created_at timestamptz not null default now());
create table finance_billy.audit(id bigint generated always as identity primary key,at timestamptz not null default now(),actor uuid,action text not null,target text,payload jsonb);
create table finance_billy.operations(key uuid primary key,user_id uuid not null,action text not null,result jsonb not null);
create table finance_billy.throttle(key text primary key,start_at timestamptz not null default now(),hits int not null default 1);
-- Todas las tablas son privadas. RLS añade una segunda barrera sin políticas públicas.
do $$ declare t record; begin for t in select tablename from pg_tables where schemaname='finance_billy' loop execute format('alter table finance_billy.%I enable row level security',t.tablename); end loop; end $$;

create function finance_billy.reconcile(p_user uuid,p_now timestamptz default now()) returns void language plpgsql security invoker set search_path='' as $$
declare m finance_billy.members; q finance_billy.installments; d date; lastdate date; ev record; bal int:=0; old int; until_day date; today date:=(p_now at time zone 'America/Guayaquil')::date;
begin
 select * into m from finance_billy.members where id=p_user for update; if m.approved_at is null then return; end if;
 -- No se generan penalidades para administrador fuera del flujo de miembro.
 if m.role='USUARIO' then
 for d in select generate_series((m.approved_at at time zone 'America/Guayaquil')::date,today-1,'1 day')::date loop
 if not exists(select 1 from finance_billy.activations a where a.user_id=p_user and a.starts_at<(d+1)::timestamp at time zone 'America/Guayaquil' and a.ends_at>=(d+1)::timestamp at time zone 'America/Guayaquil') then
 insert into finance_billy.point_facts values('inactive:'||p_user||':'||d,p_user,(d+1)::timestamp at time zone 'America/Guayaquil',-1,'INACTIVIDAD',true) on conflict do nothing;
 end if; end loop; end if;
 update finance_billy.point_facts f set active=false where f.user_id=p_user and exists(select 1 from finance_billy.installments z where z.user_id=p_user and z.status='CANCELADA' and f.key like 'late:'||z.id||':%');
 for q in select * from finance_billy.installments where user_id=p_user and status<>'CANCELADA' loop
 until_day:=least(today,coalesce((q.completed_at at time zone 'America/Guayaquil')::date,today));
 update finance_billy.point_facts set active=false where key like 'late:'||q.id||':%' and at>=(until_day+1)::timestamp at time zone 'America/Guayaquil';
 if until_day>=q.due+3 then
 for d in select generate_series(q.due+3,until_day,'1 day')::date loop
 insert into finance_billy.point_facts values('late:'||q.id||':'||d,p_user,d::timestamp at time zone 'America/Guayaquil',-1,'RETRASO_CUOTA',true) on conflict(key) do update set active=true;
 end loop; end if;
 if q.completed_at is not null then
 insert into finance_billy.point_facts values('reward:'||q.id,p_user,q.completed_at,case when (q.completed_at at time zone 'America/Guayaquil')::date<=q.due then 2 when (q.completed_at at time zone 'America/Guayaquil')::date=q.due+1 then 1 else 0 end,'PUNTUALIDAD',true) on conflict(key) do update set at=excluded.at,delta=excluded.delta;
 end if;
 end loop;
 for ev in select * from finance_billy.point_facts where user_id=p_user and active order by at,seq loop bal:=greatest(0,bal+ev.delta); end loop;
 old:=m.points; if old<>bal then
 insert into finance_billy.point_movements(user_id,source,requested,applied,before,after,reference) values(p_user,'CONCILIACION',bal-old,bal-old,old,bal,'Historial conciliado: aprobaciones, puntualidad e inactividad');
 update finance_billy.members set points=bal where id=p_user;
 end if;
end $$;
create function finance_billy.quote(p_loan uuid,p_now timestamptz default now()) returns jsonb language plpgsql security invoker set search_path='' as $$
declare l finance_billy.loans; principal_left int; due_interest int; extra int:=0; latest_due date; today date:=(p_now at time zone 'America/Guayaquil')::date;
begin
 select * into l from finance_billy.loans where id=p_loan and status='ACTIVO'; if not found then raise exception 'Préstamo no activo'; end if;
 select coalesce(sum(principal),0),coalesce(sum(case when due<=today then interest else 0 end),0) into principal_left,due_interest from finance_billy.installments where loan_id=p_loan and status<>'PAGADA';
 select max(due) into latest_due from finance_billy.installments where loan_id=p_loan and due<=today;
 -- Si ya hay cuota exigible impaga, su interés ya está incluido; no se añade dos veces.
 if not exists(select 1 from finance_billy.installments where loan_id=p_loan and due<=today and status<>'PAGADA') and extract(dow from today) between 2 and 5 and exists(select 1 from finance_billy.installments where loan_id=p_loan and due>today and status<>'PAGADA') then extra:=round(l.amount*l.rate); end if;
 return jsonb_build_object('loan_id',p_loan,'principal',principal_left,'due_interest',due_interest,'extra_interest',extra,'credit',coalesce((select sum(verified) from finance_billy.installments where loan_id=p_loan and status<>'PAGADA'),0),'total',greatest(0,principal_left+due_interest+extra-coalesce((select sum(verified) from finance_billy.installments where loan_id=p_loan and status<>'PAGADA'),0)),'at',p_now,'date',today);
end $$;

create function public.finance_throttle(p_key text,p_limit int default 20) returns boolean language plpgsql security definer set search_path='' as $$
declare n int;begin
 insert into finance_billy.throttle(key) values(p_key) on conflict(key) do update set hits=case when finance_billy.throttle.start_at<now()-interval '15 minutes' then 1 else finance_billy.throttle.hits+1 end,start_at=case when finance_billy.throttle.start_at<now()-interval '15 minutes' then now() else finance_billy.throttle.start_at end returning hits into n;
 return n<=p_limit;
end $$;
revoke all on function public.finance_throttle(text,int) from public,anon,authenticated;
grant execute on function public.finance_throttle(text,int) to service_role;

create or replace function public.finance_api(p_user uuid,p_action text,p_data jsonb default '{}',p_key uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare m finance_billy.members; target finance_billy.members; cfg jsonb; res jsonb:='{}'; r finance_billy.requests; l finance_billy.loans; q finance_billy.installments; rec finance_billy.receipts; first_id uuid; amount int; weeks int; total int; normal int; princ int; i int; first_due date; d date; expiry timestamptz; startt timestamptz; quote jsonb; target_id uuid; currentpoints int; delta int; vtime timestamptz; mt int; uid uuid; today date:=(now() at time zone 'America/Guayaquil')::date;
begin
 perform pg_advisory_xact_lock(hashtext('finance-billy-v31'));
 select value into cfg from finance_billy.settings where id=1;
 if p_key is not null then select result into res from finance_billy.operations where key=p_key and user_id=p_user and action=p_action; if found then return res; end if; end if; res:='{}'::jsonb;
 if p_action='register' then
 if exists(select 1 from finance_billy.members where id=p_user) then return '{}'::jsonb; end if;
 if length(trim(p_data->>'name'))<5 then raise exception 'Escribe tu nombre completo'; end if;
 insert into finance_billy.members(id,cedula,name,phone,email) values(p_user,p_data->>'cedula',trim(p_data->>'name'),coalesce(p_data->>'phone',''),coalesce(p_data->>'email',''));
 insert into finance_billy.accounts(user_id,bank_id,type,number,principal) select p_user,(a->>'bank_id')::uuid,a->>'type',a->>'number',coalesce((a->>'principal')::boolean,false) from jsonb_array_elements(p_data->'accounts') a;
 if (select count(*) from finance_billy.accounts where user_id=p_user) not between 1 and 2 or exists(select 1 from finance_billy.accounts a join finance_billy.banks b on b.id=a.bank_id where user_id=p_user and (not b.active or length(a.number)<3)) then raise exception 'Debes registrar una o dos cuentas bancarias válidas'; end if;
 return jsonb_build_object('status','PENDIENTE');
 end if;
 if p_action='public' then return jsonb_build_object('banks',(select jsonb_agg(to_jsonb(b)) from finance_billy.banks b where active)); end if;
 select * into m from finance_billy.members where id=p_user for update; if not found then raise exception 'Cuenta no registrada'; end if;
 if p_action='status' then return jsonb_build_object('member',to_jsonb(m)); end if;
 if m.status<>'APROBADA' then raise exception 'Tu cuenta todavía no está aprobada o está bloqueada'; end if;
 if m.force_password and p_action not in ('password_changed','state') then raise exception 'Primero cambia tu contraseña temporal'; end if;
 if m.role<>'ADMIN' and coalesce((cfg->>'maintenance')::boolean,false) and p_action not in ('state','quote','receipt_view','password_changed') then raise exception 'Estamos en mantenimiento: puedes consultar, pero no realizar cambios'; end if;
 if p_action like 'admin_%' and m.role<>'ADMIN' then raise exception 'Acceso reservado al administrador'; end if;
 perform finance_billy.reconcile(p_user); select * into m from finance_billy.members where id=p_user;
 if p_action='state' then
 if m.role='ADMIN' then for uid in select id from finance_billy.members where approved_at is not null loop perform finance_billy.reconcile(uid); end loop; end if;
 res:=jsonb_build_object('member',(select to_jsonb(x)||jsonb_build_object('days',greatest(0,ceil(extract(epoch from (x.expires_at-now()))/86400))) from finance_billy.members x where id=p_user),'settings',cfg,
 'banks',coalesce((select jsonb_agg(to_jsonb(b) order by name) from finance_billy.banks b),'[]'),
 'accounts',coalesce((select jsonb_agg(to_jsonb(a)) from finance_billy.accounts a where (m.role='ADMIN' or user_id=p_user) and active),'[]'),
 'requests',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('position',(select count(*) from finance_billy.requests y where y.status in ('PENDIENTE','APROBADA_PENDIENTE_DESEMBOLSO') and (y.created_at,y.id)<=(x.created_at,x.id))) order by created_at) from finance_billy.requests x where m.role='ADMIN' or user_id=p_user),'[]'),
 'loans',coalesce((select jsonb_agg(to_jsonb(x) order by disbursed_at desc) from finance_billy.loans x where m.role='ADMIN' or user_id=p_user),'[]'),
 'installments',coalesce((select jsonb_agg(to_jsonb(x) order by due,number) from finance_billy.installments x where m.role='ADMIN' or user_id=p_user),'[]'),
 'receipts',coalesce((select jsonb_agg(to_jsonb(x) order by uploaded_at desc) from finance_billy.receipts x where m.role='ADMIN' or user_id=p_user),'[]'),
 'movements',coalesce((select jsonb_agg(to_jsonb(x) order by at desc) from finance_billy.point_movements x where m.role='ADMIN' or user_id=p_user),'[]'),
 'news',coalesce((select jsonb_agg(to_jsonb(x) order by created_at desc) from finance_billy.news x where m.role='ADMIN' or status='PUBLICADO'),'[]'),
 'members',case when m.role='ADMIN' then coalesce((select jsonb_agg(to_jsonb(x) order by created_at desc) from finance_billy.members x),'[]') else '[]'::jsonb end,
 'audit',case when m.role='ADMIN' then coalesce((select jsonb_agg(to_jsonb(x) order by at desc) from (select * from finance_billy.audit order by id desc limit 200) x),'[]') else '[]'::jsonb end);
 return res;
 elsif p_action='request' then
 if m.expires_at is null or m.expires_at<=now() then raise exception 'Activa tus días antes de solicitar un préstamo'; end if;
 if extract(dow from today)=6 then raise exception 'Las solicitudes se reciben de domingo a viernes'; end if;
 if exists(select 1 from finance_billy.loans where user_id=p_user and status='ACTIVO') or exists(select 1 from finance_billy.requests where user_id=p_user and status in ('PENDIENTE','APROBADA_PENDIENTE_DESEMBOLSO')) then raise exception 'Ya tienes un préstamo activo o una solicitud en espera'; end if;
 amount:=(p_data->>'amount')::int; weeks:=(p_data->>'weeks')::int;
 if amount<(cfg->>'loan_min')::int or amount%500<>0 or amount>500*floor(m.points/5.0) or weeks<(cfg->>'loan_min_weeks')::int or weeks>(cfg->>'loan_max_weeks')::int then raise exception 'Revisa el monto, tus puntos y el plazo permitido'; end if;
 if not exists(select 1 from finance_billy.accounts where id=(p_data->>'account_id')::uuid and user_id=p_user and active) then raise exception 'Selecciona tu cuenta bancaria'; end if;
 insert into finance_billy.requests(user_id,amount,weeks,rate,snapshot_points,bank_snapshot) select p_user,amount,weeks,(cfg->>'rate')::numeric,m.points,to_jsonb(a)||jsonb_build_object('bank_name',b.name) from finance_billy.accounts a join finance_billy.banks b on b.id=a.bank_id where a.id=(p_data->>'account_id')::uuid returning id into first_id;
 res:=jsonb_build_object('id',first_id);
 elsif p_action in ('cancel_request','admin_request','admin_disburse') then
 select * into r from finance_billy.requests where id=(p_data->>'id')::uuid for update;
 if not found or r.status not in ('PENDIENTE','APROBADA_PENDIENTE_DESEMBOLSO') then raise exception 'La solicitud ya fue procesada'; end if;
 if p_action='cancel_request' then
 if r.user_id<>p_user then raise exception 'Solicitud ajena'; end if;
 insert into finance_billy.point_facts values('cancel:'||r.id,p_user,now(),-3,'CANCELACION',true);
 update finance_billy.requests set status='CANCELADA',reason='Cancelación del miembro' where id=r.id; perform finance_billy.reconcile(p_user);
 elsif p_action='admin_request' then
 if p_data->>'status' not in ('RECHAZADA','APROBADA_PENDIENTE_DESEMBOLSO','CANCELADA_ADMIN') then raise exception 'Estado inválido'; end if;
 if p_data->>'status'<>'APROBADA_PENDIENTE_DESEMBOLSO' and length(trim(coalesce(p_data->>'reason','')))<3 then raise exception 'El motivo es obligatorio'; end if;
 if p_data->>'status'='APROBADA_PENDIENTE_DESEMBOLSO' and r.id<>(select id from finance_billy.requests where status in ('PENDIENTE','APROBADA_PENDIENTE_DESEMBOLSO') order by created_at,id limit 1) then raise exception 'Respeta la primera solicitud de la cola FIFO'; end if;
 update finance_billy.requests set status=p_data->>'status',reason=p_data->>'reason' where id=r.id;
 else
 if r.id<>(select id from finance_billy.requests where status in ('PENDIENTE','APROBADA_PENDIENTE_DESEMBOLSO') order by created_at,id limit 1) then raise exception 'Primero desembolsa la solicitud inicial de la cola'; end if;
 total:=r.amount+round(r.amount*r.rate*r.weeks);normal:=round(total::numeric/r.weeks);princ:=round(r.amount::numeric/r.weeks);
 d:=today+7;first_due:=d+((6-extract(dow from d)::int+7)%7);
 insert into finance_billy.loans(request_id,user_id,amount,weeks,rate,total,disbursed_at) values(r.id,r.user_id,r.amount,r.weeks,r.rate,total,now()) returning id into first_id;
 for i in 1..r.weeks loop
 mt:=case when i=r.weeks then total-normal*(r.weeks-1) else normal end;amount:=case when i=r.weeks then r.amount-princ*(r.weeks-1) else princ end;
 insert into finance_billy.installments(loan_id,user_id,number,due,amount,principal,interest) values(first_id,r.user_id,i,first_due+7*(i-1),mt,amount,mt-amount);
 end loop;
 update finance_billy.requests set status='DESEMBOLSADA',disbursed_at=now(),reference=p_data->>'reference' where id=r.id;
 end if;
 elsif p_action='quote' then
 select * into l from finance_billy.loans where id=(p_data->>'loan_id')::uuid and (user_id=p_user or m.role='ADMIN'); if not found then raise exception 'Préstamo no encontrado'; end if;
 return finance_billy.quote(l.id);
 elsif p_action='receipt_create' then
 if exists(select 1 from finance_billy.receipts where key=p_key and user_id=p_user) then return '{}'::jsonb; end if;
 amount:=(p_data->>'declared')::int; if amount<=0 then raise exception 'Monto inválido'; end if;
 if p_data->>'kind'='CUOTA' then
 select * into q from finance_billy.installments where id=(p_data->>'installment_id')::uuid and user_id=p_user and status in ('PENDIENTE','PARCIAL');
 if not found or q.id<>(select id from finance_billy.installments where loan_id=q.loan_id and status in ('PENDIENTE','PARCIAL') order by number limit 1) then raise exception 'Selecciona la cuota pendiente más antigua'; end if;
 if amount>q.amount-q.verified then raise exception 'El monto supera el pendiente; no se distribuye automáticamente'; end if;
 elsif p_data->>'kind'='LIQUIDACION' then
 select * into l from finance_billy.loans where id=(p_data->>'loan_id')::uuid and user_id=p_user and status='ACTIVO';if not found then raise exception 'Préstamo no encontrado';end if; quote:=finance_billy.quote(l.id);
 if amount<>(quote->>'total')::int then raise exception 'El monto debe coincidir con la cotización total';end if;
 elsif p_data->>'kind'='ACTIVACION' then if amount<>(cfg->>'activation_price')::int then raise exception 'Cada activación requiere el monto exacto';end if;
 elsif p_data->>'kind'='PUNTOS' then if amount<>(cfg->>'points_price')::int then raise exception 'Compra de puntos: monto exacto';end if;
 else raise exception 'Concepto inválido'; end if;
 if p_data->>'kind' in ('ACTIVACION','PUNTOS') then quote:=cfg; end if;
 if p_data->>'path' not like p_user::text||'/%' then raise exception 'Archivo ajeno';end if;
 insert into finance_billy.receipts(user_id,kind,installment_id,loan_id,declared,path,key,quote) values(p_user,p_data->>'kind',q.id,coalesce(l.id,q.loan_id),amount,p_data->>'path',p_key,quote) returning id into first_id;res:=jsonb_build_object('id',first_id);
 elsif p_action='receipt_view' then
 select * into rec from finance_billy.receipts where id=(p_data->>'id')::uuid and (user_id=p_user or m.role='ADMIN');if not found then raise exception 'Comprobante no encontrado';end if;return jsonb_build_object('path',rec.path);
 elsif p_action='admin_receipt' then
 select * into rec from finance_billy.receipts where id=(p_data->>'id')::uuid for update;if not found or rec.status<>'PENDIENTE' then raise exception 'Este comprobante ya fue revisado';end if;
 if p_data->>'status'='RECHAZADO' then
 if length(trim(coalesce(p_data->>'reason','')))<3 then raise exception 'Escribe el motivo del rechazo';end if;update finance_billy.receipts set status='RECHAZADO',checked_at=now(),reason=p_data->>'reason' where id=rec.id;
 else
 amount:=(p_data->>'verified')::int;if amount<=0 then raise exception 'Registra el monto verificado';end if;
 select * into target from finance_billy.members where id=rec.user_id for update;
 if rec.kind='CUOTA' then
 select * into q from finance_billy.installments where id=rec.installment_id for update;
 if q.status not in ('PENDIENTE','PARCIAL') or amount>q.amount-q.verified then raise exception 'El importe excede el saldo o la cuota está cerrada';end if;
 if q.id<>(select id from finance_billy.installments where loan_id=q.loan_id and status in ('PENDIENTE','PARCIAL') order by number limit 1) then raise exception 'Verifica primero la cuota más antigua';end if;
 if q.verified+amount=q.amount then
 select greatest(rec.uploaded_at,coalesce(max(uploaded_at),rec.uploaded_at)) into vtime from finance_billy.receipts where installment_id=q.id and status='APROBADO';
 update finance_billy.installments set verified=q.amount,status='PAGADA',completed_at=vtime where id=q.id;
 else update finance_billy.installments set verified=verified+amount,status='PARCIAL' where id=q.id;end if;
 if not exists(select 1 from finance_billy.installments where loan_id=q.loan_id and status<>'PAGADA') then update finance_billy.loans set status='COMPLETADO',settled_at=now() where id=q.loan_id;end if;
 elsif rec.kind='ACTIVACION' then
 if amount<>(rec.quote->>'activation_price')::int then raise exception 'Monto de activación incorrecto';end if;
 startt:=greatest(now(),coalesce(target.expires_at,now()));expiry:=startt+make_interval(days=>(rec.quote->>'activation_days')::int);
 insert into finance_billy.activations(user_id,receipt_id,starts_at,ends_at) values(rec.user_id,rec.id,startt,expiry);update finance_billy.members set expires_at=expiry where id=rec.user_id;
 elsif rec.kind='PUNTOS' then
 if amount<>(rec.quote->>'points_price')::int then raise exception 'Monto de compra incorrecto';end if;
 if target.last_points_purchase is not null and now()<target.last_points_purchase+make_interval(hours=>(rec.quote->>'cooldown_hours')::int) then raise exception 'Aún no han transcurrido las 168 horas desde la aprobación anterior';end if;
 insert into finance_billy.point_facts values('purchase:'||rec.id,rec.user_id,now(),(rec.quote->>'points_amount')::int,'COMPRA_PUNTOS',true);update finance_billy.members set last_points_purchase=now() where id=rec.user_id;
 else
 select * into l from finance_billy.loans where id=rec.loan_id and status='ACTIVO' for update;if not found then raise exception 'Préstamo no activo';end if;
 quote:=finance_billy.quote(l.id,rec.uploaded_at);
 if amount<>(quote->>'total')::int or quote->>'total'<>rec.quote->>'total' then raise exception 'La cotización cambió: revisa los pagos y solicita un comprobante corregido';end if;
 for q in select * from finance_billy.installments where loan_id=l.id and status<>'PAGADA' order by number loop
 if q.due<=(rec.uploaded_at at time zone 'America/Guayaquil')::date then update finance_billy.installments set status='PAGADA',verified=q.amount,completed_at=rec.uploaded_at where id=q.id;else update finance_billy.installments set status='CANCELADA' where id=q.id;end if;
 end loop;
 update finance_billy.loans set status='LIQUIDADO',settled_at=now() where id=l.id;
 end if;
 update finance_billy.receipts set status='APROBADO',verified=amount,checked_at=now(),reason=p_data->>'reason' where id=rec.id;perform finance_billy.reconcile(rec.user_id);
 end if;
 elsif p_action='admin_member' then
 select * into target from finance_billy.members where id=(p_data->>'id')::uuid for update;if not found or target.role='ADMIN' then raise exception 'Miembro no disponible';end if;
 if p_data->>'status' not in ('APROBADA','RECHAZADA','BLOQUEADA') then raise exception 'Estado inválido';end if;
 if p_data->>'status'='APROBADA' and target.approved_at is null then
 insert into finance_billy.point_facts values('initial:'||target.id,target.id,now(),100,'APROBACION',true);update finance_billy.members set approved_at=now() where id=target.id;
 end if;update finance_billy.members set status=p_data->>'status' where id=target.id;perform finance_billy.reconcile(target.id);
 elsif p_action='admin_points' then
 target_id:=(p_data->>'id')::uuid;delta:=(p_data->>'delta')::int;
 if length(trim(coalesce(p_data->>'reason','')))<3 or abs(delta)>100000 then raise exception 'Motivo obligatorio y ajuste razonable';end if;
 insert into finance_billy.point_facts values('manual:'||p_key,target_id,now(),delta,'AJUSTE_MANUAL',true);perform finance_billy.reconcile(target_id);
 elsif p_action='profile' then
 update finance_billy.members set phone=coalesce(p_data->>'phone',phone),email=coalesce(p_data->>'email',email) where id=p_user;
 if p_data ? 'accounts' then
 if jsonb_array_length(p_data->'accounts') not between 1 and 2 then raise exception 'Debes conservar una o dos cuentas';end if;
 update finance_billy.accounts set active=false where user_id=p_user;
 insert into finance_billy.accounts(user_id,bank_id,type,number,principal) select p_user,(a->>'bank_id')::uuid,a->>'type',a->>'number',coalesce((a->>'principal')::boolean,false) from jsonb_array_elements(p_data->'accounts') a;
 if exists(select 1 from finance_billy.accounts a join finance_billy.banks b on b.id=a.bank_id where user_id=p_user and a.active and (not b.active or length(a.number)<3)) then raise exception 'Cuenta bancaria inválida';end if;
 end if;
 elsif p_action='admin_news' then
 if p_data ? 'id' then update finance_billy.news set title=coalesce(p_data->>'title',title),body=coalesce(p_data->>'body',body),status=coalesce(p_data->>'status',status) where id=(p_data->>'id')::uuid;
 else if length(trim(p_data->>'title'))<3 or length(trim(p_data->>'body'))<3 then raise exception 'Completa el título y el contenido';end if;insert into finance_billy.news(title,body,status) values(p_data->>'title',p_data->>'body',coalesce(p_data->>'status','PUBLICADO'));end if;
 elsif p_action='admin_bank' then
 if p_data ? 'id' then update finance_billy.banks set name=coalesce(p_data->>'name',name),active=coalesce((p_data->>'active')::boolean,active) where id=(p_data->>'id')::uuid;
 else insert into finance_billy.banks(name) values(trim(p_data->>'name'));end if;
 elsif p_action='admin_settings' then
 res:=cfg||p_data;
 if (res->>'activation_days')::int<1 or (res->>'activation_price')::int<1 or (res->>'points_price')::int<1 or (res->>'points_amount')::int<1 or (res->>'cooldown_hours')::int<1 or (res->>'loan_min')::int<500 or (res->>'loan_min')::int%500<>0 or (res->>'loan_min_weeks')::int<1 or (res->>'loan_max_weeks')::int<(res->>'loan_min_weeks')::int or (res->>'rate')::numeric not between 0 and 1 then raise exception 'Parámetros incoherentes';end if;
 insert into finance_billy.audit(actor,action,payload) values(p_user,'CONFIGURACION_ANTERIOR',cfg);update finance_billy.settings set value=res where id=1;
 elsif p_action='admin_password_flag' then
 if (p_data->>'id')::uuid=p_user then raise exception 'Usa el cambio personal de contraseña';end if;
 if not exists(select 1 from finance_billy.members where id=(p_data->>'id')::uuid and role='USUARIO') then raise exception 'Miembro no encontrado';end if; update finance_billy.members set force_password=true where id=(p_data->>'id')::uuid; delete from auth.sessions where user_id=(p_data->>'id')::uuid;
 elsif p_action='password_changed' then update finance_billy.members set force_password=false where id=p_user;
 elsif p_action='admin_correct_date' then
 if length(trim(coalesce(p_data->>'reason','')))<3 then raise exception 'Motivo obligatorio';end if;
 select * into q from finance_billy.installments where id=(p_data->>'id')::uuid and status='PAGADA';if not found then raise exception 'Cuota no pagada';end if;
 vtime:=(p_data->>'at')::timestamptz;if vtime>now() then raise exception 'No puede ser una fecha futura';end if;
 insert into finance_billy.audit(actor,action,target,payload) values(p_user,'FECHA_ANTERIOR',q.id::text,to_jsonb(q));update finance_billy.installments set completed_at=vtime where id=q.id;perform finance_billy.reconcile(q.user_id);
 else raise exception 'Acción no disponible';
 end if;
 insert into finance_billy.audit(actor,action,target,payload) values(p_user,p_action,coalesce(p_data->>'id',p_data->>'loan_id'),p_data);
 if p_key is not null then insert into finance_billy.operations values(p_key,p_user,p_action,res);end if;
 return res;
end $$;
revoke all on function public.finance_api(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.finance_api(uuid,text,jsonb,uuid) to service_role;
revoke all on all tables in schema finance_billy from public,anon,authenticated;
grant all on all tables in schema finance_billy to service_role;
grant usage,select on all sequences in schema finance_billy to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('finance-billy','finance-billy',false,5242880,array['image/jpeg','image/png']) on conflict(id) do nothing;

create function public.finance_session_valid(p_user uuid,p_session uuid) returns boolean language sql security definer set search_path='' as $$ select exists(select 1 from auth.sessions where id=p_session and user_id=p_user) $$;
revoke all on function public.finance_session_valid(uuid,uuid) from public,anon,authenticated;
grant execute on function public.finance_session_valid(uuid,uuid) to service_role;
