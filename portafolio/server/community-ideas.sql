
create table public.portfolio_ideas (
  id bigint generated always as identity primary key,
  request_id uuid not null unique,
  browser_id uuid not null,
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  created_at timestamptz not null default now(),
  hidden_at timestamptz
);
create index portfolio_ideas_visible_order_idx on public.portfolio_ideas(id desc) where hidden_at is null;
create index portfolio_ideas_browser_date_idx on public.portfolio_ideas(browser_id,created_at);
create table public.portfolio_idea_votes (
  idea_id bigint not null references public.portfolio_ideas(id) on delete cascade,
  browser_id uuid not null,
  primary key (idea_id,browser_id)
);
alter table public.portfolio_ideas enable row level security;
alter table public.portfolio_idea_votes enable row level security;
revoke all on public.portfolio_ideas,public.portfolio_idea_votes from public,anon,authenticated;
grant select,insert,update on public.portfolio_ideas to service_role;
grant select,insert,delete on public.portfolio_idea_votes to service_role;
grant usage on sequence public.portfolio_ideas_id_seq to service_role;

create function public.portfolio_ideas_list(p_browser uuid,p_before bigint)
returns table(id bigint,body text,created_at timestamptz,likes bigint,liked boolean)
language sql stable security invoker set search_path='' as $$
  select i.id,i.body,i.created_at,
    (select count(*) from public.portfolio_idea_votes v where v.idea_id=i.id),
    exists(select 1 from public.portfolio_idea_votes v where v.idea_id=i.id and v.browser_id=p_browser)
  from public.portfolio_ideas i
  where i.hidden_at is null and (p_before is null or i.id<p_before)
  order by i.id desc limit 21
$$;

create function public.portfolio_idea_publish(p_browser uuid,p_request uuid,p_body text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare idea_id bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_browser::text,184));
  select id into idea_id from public.portfolio_ideas where browser_id=p_browser and request_id=p_request;
  if found then return jsonb_build_object('id',idea_id); end if;
  if (select count(*) from public.portfolio_ideas where browser_id=p_browser and created_at>now()-interval '24 hours')>=3 then
    return jsonb_build_object('limited',true);
  end if;
  insert into public.portfolio_ideas(browser_id,request_id,body) values(p_browser,p_request,btrim(p_body)) returning id into idea_id;
  return jsonb_build_object('id',idea_id);
end;
$$;

create function public.portfolio_idea_vote(p_idea bigint,p_browser uuid,p_liked boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  perform 1 from public.portfolio_ideas where id=p_idea and hidden_at is null for update;
  if not found then return jsonb_build_object('missing',true); end if;
  if p_liked then
    insert into public.portfolio_idea_votes(idea_id,browser_id) values(p_idea,p_browser) on conflict do nothing;
  else
    delete from public.portfolio_idea_votes where idea_id=p_idea and browser_id=p_browser;
  end if;
  return jsonb_build_object('liked',p_liked,'likes',(select count(*) from public.portfolio_idea_votes where idea_id=p_idea));
end;
$$;

revoke execute on function public.portfolio_ideas_list(uuid,bigint),public.portfolio_idea_publish(uuid,uuid,text),public.portfolio_idea_vote(bigint,uuid,boolean) from public,anon,authenticated;
grant execute on function public.portfolio_ideas_list(uuid,bigint),public.portfolio_idea_publish(uuid,uuid,text),public.portfolio_idea_vote(bigint,uuid,boolean) to service_role;
