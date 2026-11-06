
alter table public.portfolio_media
  add column apk_size_bytes integer
  check (apk_size_bytes is null or (kind='apk' and apk_size_bytes between 41943041 and 104857600));

create function public.portfolio_publish_split_apk(
  p_slug text,p_upload uuid,p_size integer,p_caption text,p_position integer
) returns uuid
language plpgsql security invoker set search_path='' as $$
declare
  part_bytes constant integer:=33554432;
  apk_path text;
  apk_id uuid;
begin
  if p_slug is null or p_slug !~ '^[a-z][a-z0-9-]{0,79}$'
    or p_upload is null or p_size is null or p_size not between 41943041 and 104857600 then
    raise exception 'APK dividido inválido';
  end if;
  apk_path:=p_slug||'/apk/'||p_upload::text||'.apk';
  if exists (
    select 1
    from pg_catalog.generate_series(0,(p_size-1)/part_bytes) as part(number)
    left join storage.objects o on o.bucket_id='portfolio-public'
      and o.name=apk_path||'.part-'||part.number::text||'.apk'
    where o.id is null or (o.metadata->>'size')::bigint is distinct from
      least(part_bytes,p_size-part.number*part_bytes)::bigint
  ) then
    return null;
  end if;
  insert into public.portfolio_media(app_slug,kind,object_path,caption,sort_order,apk_size_bytes)
    values(p_slug,'apk',apk_path,left(coalesce(p_caption,''),200),
           greatest(0,least(1000000,coalesce(p_position,0))),p_size)
    on conflict(object_path) do nothing;
  select id into apk_id from public.portfolio_media
    where object_path=apk_path and apk_size_bytes=p_size;
  return apk_id;
end;
$$;

revoke execute on function public.portfolio_publish_split_apk(text,uuid,integer,text,integer) from public,anon,authenticated;
grant execute on function public.portfolio_publish_split_apk(text,uuid,integer,text,integer) to service_role;
