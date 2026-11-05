
create table public.portfolio_media (
 id uuid primary key default gen_random_uuid(),
 app_slug text not null check (app_slug ~ '^[a-z][a-z0-9-]{0,79}$'),
 kind text not null check (kind in ('screenshot','logo','apk')),
 object_path text not null unique,
 caption text not null default '' check (char_length(caption)<=200),
 sort_order integer not null default 0,
 created_at timestamptz not null default now()
);
create index portfolio_media_app_order_idx on public.portfolio_media(app_slug,kind,sort_order,created_at);
alter table public.portfolio_media enable row level security;
revoke all on public.portfolio_media from public,anon,authenticated;
grant select on public.portfolio_media to anon,authenticated;
grant all on public.portfolio_media to service_role;
create policy portfolio_media_public_read on public.portfolio_media for select to anon,authenticated using (true);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('portfolio-public','portfolio-public',true,41943040,array['image/jpeg','image/png','image/webp','application/vnd.android.package-archive'])
on conflict(id) do nothing;
