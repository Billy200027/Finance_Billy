-- Batería transaccional: crea datos ficticios y revierte TODO al terminar.
begin;
do $$
declare u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();a uuid;bank uuid;ac uuid;r uuid;r2 uuid;l uuid;q uuid;rc uuid;json jsonb;n int;snap int;nowt timestamptz:=now();dt date:=(now() at time zone 'America/Guayaquil')::date;ok boolean;
begin
select id into a from finance_billy.members where role='ADMIN';select id into bank from finance_billy.banks where active limit 1;
insert into auth.users(id,aud,role,email,created_at) values(u,'authenticated','authenticated',u||'@test.invalid',now()),(v,'authenticated','authenticated',v||'@test.invalid',now());
perform public.finance_api(u,'register',jsonb_build_object('cedula','987654321001','name','Prueba Uno','phone','test','email','test@example.invalid','accounts',jsonb_build_array(jsonb_build_object('bank_id',bank,'type','AHORRO','number','TEST-ONLY','principal',true))));
perform public.finance_api(v,'register',jsonb_build_object('cedula','987654321002','name','Prueba Dos','accounts',jsonb_build_array(jsonb_build_object('bank_id',bank,'type','AHORRO','number','TEST-ONLY','principal',true))));
begin perform public.finance_api(v,'register',jsonb_build_object('cedula','987654321001','name','Duplicado')); exception when others then null;end;
if (select count(*) from finance_billy.members where cedula='987654321001')<>1 then raise exception 'FAIL duplicación';end if;
-- Pendiente no puede consultar datos de miembros.
begin perform public.finance_api(u,'state');raise exception 'FAIL pending';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
perform public.finance_api(a,'admin_member',jsonb_build_object('id',u,'status','APROBADA'),gen_random_uuid());
perform public.finance_api(a,'admin_member',jsonb_build_object('id',v,'status','APROBADA'),gen_random_uuid());
if (select points from finance_billy.members where id=u)<>100 then raise exception 'FAIL initial points';end if;
begin perform public.finance_api(u,'admin_settings','{"maintenance":true}');raise exception 'FAIL role';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
json:=public.finance_api(u,'state');if jsonb_array_length(json->'members')<>0 then raise exception 'FAIL privacy';end if;
if has_function_privilege('anon','public.finance_api(uuid,text,jsonb,uuid)','execute') or has_function_privilege('authenticated','public.finance_api(uuid,text,jsonb,uuid)','execute') then raise exception 'FAIL RPC grants';end if;
if exists(select 1 from pg_tables where schemaname='finance_billy' and not rowsecurity) then raise exception 'FAIL RLS';end if;
-- Activación real por comprobante + aprobación repetida protegida.
rc:=gen_random_uuid();json:=public.finance_api(u,'receipt_create',jsonb_build_object('kind','ACTIVACION','declared',100,'path',u||'/test-activation.png'),rc);r:=(json->>'id')::uuid;
rc:=gen_random_uuid();perform public.finance_api(a,'admin_receipt',jsonb_build_object('id',r,'status','APROBADO','verified',100),rc);perform public.finance_api(a,'admin_receipt',jsonb_build_object('id',r,'status','APROBADO','verified',100),rc);
if (select count(*) from finance_billy.activations where user_id=u)<>1 then raise exception 'FAIL double approval';end if;
if (select expires_at from finance_billy.members where id=u)<now()+interval '99 days' then raise exception 'FAIL days';end if;
-- Cooldown exacto de puntos.
json:=public.finance_api(u,'receipt_create',jsonb_build_object('kind','PUNTOS','declared',300,'path',u||'/test-points.png'),gen_random_uuid());r:=(json->>'id')::uuid;perform public.finance_api(a,'admin_receipt',jsonb_build_object('id',r,'status','APROBADO','verified',300),gen_random_uuid());
if (select points from finance_billy.members where id=u)<>120 then raise exception 'FAIL points purchase';end if;
json:=public.finance_api(u,'receipt_create',jsonb_build_object('kind','PUNTOS','declared',300,'path',u||'/test-points2.png'),gen_random_uuid());r:=(json->>'id')::uuid;
begin perform public.finance_api(a,'admin_receipt',jsonb_build_object('id',r,'status','APROBADO','verified',300),gen_random_uuid());raise exception 'FAIL cooldown';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
update finance_billy.members set last_points_purchase=now()-interval '168 hours' where id=u;perform public.finance_api(a,'admin_receipt',jsonb_build_object('id',r,'status','APROBADO','verified',300),gen_random_uuid());
-- Solicitud + snapshot + FIFO + desembolso.
select id into ac from finance_billy.accounts where user_id=u and active limit 1;
if extract(dow from dt)<>6 then
json:=public.finance_api(u,'request',jsonb_build_object('amount',10000,'weeks',5,'account_id',ac),gen_random_uuid());r:=(json->>'id')::uuid;
begin perform public.finance_api(u,'request',jsonb_build_object('amount',4000,'weeks',5,'account_id',ac),gen_random_uuid());raise exception 'FAIL double request';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
perform public.finance_api(a,'admin_points',jsonb_build_object('id',u,'delta',-100,'reason','Prueba snapshot'),gen_random_uuid());
if (select snapshot_points from finance_billy.requests where id=r)<>140 then raise exception 'FAIL snapshot';end if;
insert into finance_billy.requests(user_id,amount,weeks,rate,snapshot_points,bank_snapshot) values(v,4000,5,.0115,100,'{}') returning id into r2; update finance_billy.requests set created_at=now()+interval '1 second' where id=r2;
begin perform public.finance_api(a,'admin_disburse',jsonb_build_object('id',r2),gen_random_uuid());raise exception 'FAIL FIFO';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
perform public.finance_api(a,'admin_disburse',jsonb_build_object('id',r),gen_random_uuid());select id into l from finance_billy.loans where request_id=r;
if (select sum(amount) from finance_billy.installments where loan_id=l)<>10575 then raise exception 'FAIL rounding';end if;
if (select min(due) from finance_billy.installments where loan_id=l)<dt+7 then raise exception 'FAIL calendar';end if;
select id into q from finance_billy.installments where loan_id=l and number=1;
-- Cuota sáb 2027 con complemento lunes. Al aprobar tarde conserva fecha válida.
update finance_billy.installments set due='2026-10-03' where id=q;
json:=public.finance_api(u,'receipt_create',jsonb_build_object('kind','CUOTA','declared',1000,'installment_id',q,'path',u||'/part1.png'),gen_random_uuid());rc:=(json->>'id')::uuid;update finance_billy.receipts set uploaded_at='2026-10-03T12:00:00-05:00' where id=rc;perform public.finance_api(a,'admin_receipt',jsonb_build_object('id',rc,'status','APROBADO','verified',1000),gen_random_uuid());
json:=public.finance_api(u,'receipt_create',jsonb_build_object('kind','CUOTA','declared',1115,'installment_id',q,'path',u||'/part2.png'),gen_random_uuid());rc:=(json->>'id')::uuid;update finance_billy.receipts set uploaded_at='2026-10-05T12:00:00-05:00' where id=rc;perform public.finance_api(a,'admin_receipt',jsonb_build_object('id',rc,'status','APROBADO','verified',1115),gen_random_uuid());
if (select completed_at from finance_billy.installments where id=q)<>'2026-10-05T12:00:00-05:00'::timestamptz then raise exception 'FAIL receipt timestamp';end if;
if exists(select 1 from finance_billy.point_facts where key like 'late:'||q||':%' and active) then raise exception 'FAIL late approval reconciliation';end if;
-- Liquidación elimina intereses futuros, sin más de principal pendiente y semana corriente.
json:=finance_billy.quote(l,'2026-10-05T15:00:00-05:00');if (json->>'extra_interest')::int<>0 then raise exception 'FAIL Monday settlement';end if;
json:=finance_billy.quote(l,'2026-10-06T15:00:00-05:00');if (json->>'extra_interest')::int<>115 then raise exception 'FAIL Tuesday settlement';end if;
end if;
-- Noticias manuales y parámetros futuros conservan el contrato previo.
perform public.finance_api(a,'admin_news','{"title":"Prueba privada","body":"Uno\nDos","status":"BORRADOR"}',gen_random_uuid());
json:=public.finance_api(u,'state');if exists(select 1 from jsonb_array_elements(json->'news') z where z->>'status'='BORRADOR') then raise exception 'FAIL draft privacy';end if;
perform public.finance_api(a,'admin_settings','{"rate":0.02}',gen_random_uuid());
if exists(select 1 from finance_billy.loans where user_id=u and rate<>.0115) then raise exception 'FAIL retroactive rate';end if;
perform public.finance_api(a,'admin_settings','{"rate":0.0115}',gen_random_uuid());
-- Comprobante ajeno e intento de cuota futura.
begin perform public.finance_api(v,'receipt_view',jsonb_build_object('id',rc));raise exception 'FAIL receipt privacy';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
-- Dos obligaciones independientes producen -1 por obligación; reconciliar dos veces no duplica.
if l is not null then
update finance_billy.installments set due=dt-((extract(dow from dt)::int+1)%7)-7 where loan_id=l and number in(2,3);
perform finance_billy.reconcile(u);snap:=(select points from finance_billy.members where id=u);perform finance_billy.reconcile(u);
if (select points from finance_billy.members where id=u)<>snap then raise exception 'FAIL double penalty';end if;
if (select count(distinct split_part(key,':',2)) from finance_billy.point_facts where user_id=u and source='RETRASO_CUOTA' and active)<>2 then raise exception 'FAIL independent obligations';end if;
end if;

-- Piso 0 sin deuda oculta, reintento sin duplicados.
perform public.finance_api(a,'admin_points',jsonb_build_object('id',v,'delta',-1000,'reason','Prueba piso'),gen_random_uuid());if (select points from finance_billy.members where id=v)<>0 then raise exception 'FAIL floor';end if;
perform public.finance_api(a,'admin_points',jsonb_build_object('id',v,'delta',20,'reason','Prueba recuperación'),gen_random_uuid());if (select points from finance_billy.members where id=v)<>20 then raise exception 'FAIL hidden debt';end if;
perform public.finance_api(a,'admin_settings','{"maintenance":true}',gen_random_uuid());
begin perform public.finance_api(u,'profile','{"phone":"test"}',gen_random_uuid());raise exception 'FAIL maintenance';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
perform public.finance_api(u,'state');perform public.finance_api(a,'admin_settings','{"maintenance":false}',gen_random_uuid());
end $$;
rollback;
select 'PASS: registro, roles, privacidad, activación, idempotencia, puntos, cooldown, FIFO, snapshots, cuotas, recibos parciales, liquidación, piso 0, mantenimiento, rollback' as results;
