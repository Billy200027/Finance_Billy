-- Extensión incremental: no modifica préstamos, cuotas ni comprobantes.
create table finance_billy.summary_owner (
 id integer primary key check(id=1),
 user_id uuid not null unique references finance_billy.members(id)
);
do $$ begin
 if (select count(*) from finance_billy.members where role='ADMIN')<>1 then
 raise exception 'Debe existir un único propietario antes de instalar el resumen';
 end if;
 insert into finance_billy.summary_owner select 1,id from finance_billy.members where role='ADMIN';
end $$;
create table finance_billy.summary_adjustments(
 id uuid primary key default gen_random_uuid(),
 key uuid not null unique,
 actor uuid not null references finance_billy.members(id),
 at timestamptz not null default now(),
 category text not null check(category in ('EGRESO','INGRESO','INTERES','ACTIVACION','PUNTOS','OTRA_GANANCIA','GASTO','RETIRO')),
 amount bigint not null check(amount<>0 and abs(amount)<=100000000),
 reason text not null check(length(trim(reason)) between 3 and 500),
 reversal_of uuid unique references finance_billy.summary_adjustments(id)
);
alter table finance_billy.summary_owner enable row level security;
alter table finance_billy.summary_adjustments enable row level security;
revoke all on finance_billy.summary_owner,finance_billy.summary_adjustments from public,anon,authenticated;
create function finance_billy.adjust_summary(p_user uuid,p_data jsonb,p_key uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare a finance_billy.summary_adjustments; cat text; n bigint; base bigint; reason text:=trim(p_data->>'reason');
begin
 if not exists(select 1 from finance_billy.summary_owner o join finance_billy.members m on m.id=o.user_id where o.user_id=p_user and m.role='ADMIN' and m.status='APROBADA' and not m.force_password) then raise exception 'Solo el propietario puede ajustar este resumen';end if;
 if p_key is null then raise exception 'Falta identificador de operación';end if;
 select * into a from finance_billy.summary_adjustments where key=p_key;
 if found then return jsonb_build_object('id',a.id);end if;
 if reason is null or length(reason) not between 3 and 500 then raise exception 'Escribe un motivo de 3 a 500 caracteres';end if;
 if p_data ? 'reversal_of' then
 select * into a from finance_billy.summary_adjustments where id=(p_data->>'reversal_of')::uuid;
 if not found or a.reversal_of is not null or exists(select 1 from finance_billy.summary_adjustments where reversal_of=a.id) then raise exception 'Este ajuste no puede revertirse de nuevo';end if;
 cat:=a.category;n:=-a.amount;
 else
 cat:=p_data->>'category';
 if cat is null or cat not in ('EGRESO','INGRESO','INTERES','ACTIVACION','PUNTOS','OTRA_GANANCIA','GASTO','RETIRO') then raise exception 'Concepto inválido';end if;
 if p_data ? 'total' then
 if cat not in ('EGRESO','INGRESO') or (p_data->>'total') !~ '^[0-9]+$' then raise exception 'Total inválido';end if;
 n:=(p_data->>'total')::bigint;
 if n>100000000 then raise exception 'Total fuera de rango';end if;
 if cat='EGRESO' then
 select coalesce(sum(amount),0) into base from finance_billy.loans;
 select base+coalesce(sum(amount),0) into base from finance_billy.summary_adjustments where category in ('EGRESO','GASTO','RETIRO');
 else
 select coalesce(sum(verified),0) into base from finance_billy.receipts where status='APROBADO';
 select base+coalesce(sum(amount),0) into base from finance_billy.summary_adjustments where category not in ('EGRESO','GASTO','RETIRO');
 end if;
 n:=n-base;
 else
 if (p_data->>'amount') is null or (p_data->>'amount') !~ '^-?[0-9]+$' then raise exception 'Importe inválido';end if;
 n:=(p_data->>'amount')::bigint;
 end if;
 end if;
 if n=0 or abs(n)>100000000 then raise exception 'Importe no nulo, máximo un millón de dólares';end if;
 insert into finance_billy.summary_adjustments(key,actor,category,amount,reason,reversal_of)
 values(p_key,p_user,cat,n,reason,(p_data->>'reversal_of')::uuid) returning * into a;
 return jsonb_build_object('id',a.id);
end $$;
revoke all on function finance_billy.adjust_summary(uuid,jsonb,uuid) from public,anon,authenticated;

-- Conserva el RPC vigente y sus permisos; inserta únicamente estado y acción nuevos.
do $migration$
declare def text; needle text; replacement text;
begin
 def:=pg_get_functiondef('public.finance_api(uuid,text,jsonb,uuid)'::regprocedure);
 needle:=' return res;'||chr(10)||' elsif p_action=''request'' then';
 replacement:=' return res||jsonb_build_object(''summary_owner'',exists(select 1 from finance_billy.summary_owner where user_id=p_user),''summary_adjustments'',case when exists(select 1 from finance_billy.summary_owner where user_id=p_user) then coalesce((select jsonb_agg(to_jsonb(x) order by at desc,id) from finance_billy.summary_adjustments x),''[]''::jsonb) else ''[]''::jsonb end);'||chr(10)||' elsif p_action=''admin_summary'' then'||chr(10)||' res:=finance_billy.adjust_summary(p_user,p_data,p_key);'||chr(10)||' elsif p_action=''request'' then';
 if strpos(def,needle)=0 then raise exception 'RPC distinto al esperado; no se ha modificado';end if;
 execute replace(def,needle,replacement);
end $migration$;

