begin;
do $test$
declare a uuid; u uuid:=gen_random_uuid(); k uuid:=gen_random_uuid(); adjustment_id uuid; result jsonb; n bigint; before_data jsonb;
begin
select user_id into a from finance_billy.summary_owner where id=1;
before_data:=jsonb_build_object('loans',(select jsonb_agg(to_jsonb(x)) from finance_billy.loans x),'receipts',(select jsonb_agg(to_jsonb(x)) from finance_billy.receipts x),'installments',(select jsonb_agg(to_jsonb(x)) from finance_billy.installments x));
insert into auth.users(id,aud,role,email,created_at) values(u,'authenticated','authenticated',u||'@test.invalid',now());
insert into finance_billy.members(id,cedula,name,role,status) values(u,'999999998888777','Prueba resumen','USUARIO','APROBADA');
begin
 perform public.finance_api(u,'admin_summary','{"category":"INGRESO","amount":100,"reason":"No autorizado"}',gen_random_uuid());
 raise exception 'FAIL otro usuario pudo ajustar';
exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
result:=public.finance_api(u,'state');
if (result->>'summary_owner')::boolean or jsonb_array_length(result->'summary_adjustments')<>0 then raise exception 'FAIL privacidad';end if;
result:=public.finance_api(a,'admin_summary','{"category":"INTERES","amount":123,"reason":"Prueba temporal"}',k);
adjustment_id:=(result->>'id')::uuid;
perform public.finance_api(a,'admin_summary','{"category":"INTERES","amount":123,"reason":"Prueba temporal"}',k);
if (select count(*) from finance_billy.summary_adjustments where key=k)<>1 then raise exception 'FAIL idempotencia';end if;
perform public.finance_api(a,'admin_summary',jsonb_build_object('reversal_of',adjustment_id,'reason','Reversión temporal'),gen_random_uuid());
if (select sum(amount) from finance_billy.summary_adjustments where key=k or reversal_of=(result->>'id')::uuid)<>0 then raise exception 'FAIL neto reversión';end if;
begin
 perform public.finance_api(a,'admin_summary',jsonb_build_object('reversal_of',adjustment_id,'reason','Repetida'),gen_random_uuid());
 raise exception 'FAIL doble reversión';
exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
begin perform public.finance_api(a,'admin_summary','{"category":"INTERES","amount":1,"reason":""}',gen_random_uuid());raise exception 'FAIL motivo';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
begin perform public.finance_api(a,'admin_summary','{"category":"INVALIDO","amount":1,"reason":"Prueba"}',gen_random_uuid());raise exception 'FAIL categoría';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
begin perform public.finance_api(a,'admin_summary','{"category":"INTERES","amount":1.5,"reason":"Prueba"}',gen_random_uuid());raise exception 'FAIL centavos';exception when others then if sqlerrm like 'FAIL%' then raise;end if;end;
perform public.finance_api(a,'admin_summary','{"category":"INGRESO","total":77777,"reason":"Total exacto temporal"}',gen_random_uuid());
select (select coalesce(sum(verified),0) from finance_billy.receipts where status='APROBADO')+coalesce(sum(amount),0) into n from finance_billy.summary_adjustments where category not in ('EGRESO','GASTO','RETIRO');
if n<>77777 then raise exception 'FAIL total exacto %',n;end if;
if before_data<>jsonb_build_object('loans',(select jsonb_agg(to_jsonb(x)) from finance_billy.loans x),'receipts',(select jsonb_agg(to_jsonb(x)) from finance_billy.receipts x),'installments',(select jsonb_agg(to_jsonb(x)) from finance_billy.installments x)) then raise exception 'FAIL registros originales cambiados';end if;
if has_table_privilege('anon','finance_billy.summary_adjustments','SELECT') or has_table_privilege('authenticated','finance_billy.summary_adjustments','INSERT') or has_function_privilege('anon','finance_billy.adjust_summary(uuid,jsonb,uuid)','EXECUTE') then raise exception 'FAIL permisos';end if;
end $test$;
rollback;
select 'OK: permisos, propietario, idempotencia, reversión, validación, total exacto y conservación de originales; datos de prueba revertidos' as resultado;
