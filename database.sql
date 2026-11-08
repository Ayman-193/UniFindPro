-- UniFind PostgreSQL / Supabase setup. Run once in Supabase SQL Editor.
-- Uses auth.uid() and RLS to enforce ownership. Never expose service_role keys.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role text not null default 'user' check (role in ('user','admin')),
 created_at timestamptz not null default now()
);

create or replace function public.create_user_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,role) values (new.id,'user') on conflict (id) do nothing;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.create_user_profile();
insert into public.profiles(id) select id from auth.users on conflict (id) do nothing;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin');
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create table if not exists public.reports (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 type text not null check (type in ('lost','found')),
 category text not null check (category in ('Electronics','Accessories','Documents','Bags','Clothing','Other')),
 name text not null check (char_length(trim(name)) between 1 and 70),
 location text not null check (char_length(trim(location)) between 1 and 100),
 item_date date not null check (item_date <= current_date),
 description text not null check (char_length(trim(description)) between 1 and 1000),
 image_path text,
 status text not null default 'open' check (status in ('open','resolved')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint valid_image_path check (image_path is null or image_path ~ ('^' || user_id::text || '/[0-9a-f-]{36}[.](jpg|png|webp)$'))
);
create index if not exists reports_created_idx on public.reports(created_at desc);
create index if not exists reports_filters_idx on public.reports(status,type,category);

create table if not exists public.claims (
 id uuid primary key default gen_random_uuid(),
 report_id uuid not null references public.reports(id) on delete cascade,
 claimant_id uuid not null references auth.users(id) on delete cascade,
 message text not null check (char_length(trim(message)) between 15 and 1000),
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 unique(report_id,claimant_id)
);
create index if not exists claims_report_idx on public.claims(report_id);

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at=now(); return new; end $$;
drop trigger if exists reports_touch on public.reports;
create trigger reports_touch before update on public.reports for each row execute procedure public.touch_updated_at();

-- Prevent non-admins from changing report owner or immutable report fields on UPDATE.
create or replace function public.protect_report_update() returns trigger
language plpgsql set search_path = '' as $$
begin
 if not public.is_admin() and (new.user_id is distinct from old.user_id or new.type is distinct from old.type or new.category is distinct from old.category or new.name is distinct from old.name or new.location is distinct from old.location or new.item_date is distinct from old.item_date or new.description is distinct from old.description or new.image_path is distinct from old.image_path or new.created_at is distinct from old.created_at) then
  raise exception 'Only report status may be changed';
 end if;
 return new;
end $$;
drop trigger if exists protect_report_fields on public.reports;
create trigger protect_report_fields before update on public.reports for each row execute procedure public.protect_report_update();

-- Claimants cannot alter messages, owners, or report references.
create or replace function public.protect_claim_update() returns trigger
language plpgsql set search_path = '' as $$
begin
 if new.report_id is distinct from old.report_id or new.claimant_id is distinct from old.claimant_id or new.message is distinct from old.message or new.created_at is distinct from old.created_at then
  raise exception 'Claim identity and evidence cannot be changed';
 end if;
 return new;
end $$;
drop trigger if exists protect_claim_fields on public.claims;
create trigger protect_claim_fields before update on public.claims for each row execute procedure public.protect_claim_update();

alter table public.profiles enable row level security;
alter table public.reports enable row level security;
alter table public.claims enable row level security;

-- Profiles: a user can see their own role; no browser-based role changes.
drop policy if exists "Read own profile" on public.profiles;
create policy "Read own profile" on public.profiles for select to authenticated using (id=(select auth.uid()));

-- Reports: publicly readable, only signed-in owners can create, edit status or delete.
drop policy if exists "Public read reports" on public.reports;
create policy "Public read reports" on public.reports for select to anon,authenticated using (true);
drop policy if exists "Create own reports" on public.reports;
create policy "Create own reports" on public.reports for insert to authenticated with check (user_id=(select auth.uid()) and status='open');
drop policy if exists "Owner or admin update reports" on public.reports;
create policy "Owner or admin update reports" on public.reports for update to authenticated using (user_id=(select auth.uid()) or public.is_admin()) with check (user_id=(select auth.uid()) or public.is_admin());
drop policy if exists "Owner or admin delete reports" on public.reports;
create policy "Owner or admin delete reports" on public.reports for delete to authenticated using (user_id=(select auth.uid()) or public.is_admin());

-- Claims are private to claimant, report owner, and admin.
drop policy if exists "Private claim read" on public.claims;
create policy "Private claim read" on public.claims for select to authenticated using (claimant_id=(select auth.uid()) or public.is_admin() or exists(select 1 from public.reports r where r.id=report_id and r.user_id=(select auth.uid())));
drop policy if exists "Create claim for another owner" on public.claims;
create policy "Create claim for another owner" on public.claims for insert to authenticated with check (claimant_id=(select auth.uid()) and status='pending' and exists(select 1 from public.reports r where r.id=report_id and r.user_id<>(select auth.uid()) and r.status='open'));
drop policy if exists "Report owner or admin review claims" on public.claims;
create policy "Report owner or admin review claims" on public.claims for update to authenticated using (public.is_admin() or exists(select 1 from public.reports r where r.id=report_id and r.user_id=(select auth.uid()))) with check (public.is_admin() or exists(select 1 from public.reports r where r.id=report_id and r.user_id=(select auth.uid())));

-- Images are public by design. Store NO sensitive details in photos.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('report-images','report-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "Public view report photos" on storage.objects;
create policy "Public view report photos" on storage.objects for select to anon,authenticated using (bucket_id='report-images');
drop policy if exists "Upload photos into own folder" on storage.objects;
create policy "Upload photos into own folder" on storage.objects for insert to authenticated with check (bucket_id='report-images' and (storage.foldername(name))[1]=(select auth.uid())::text and lower(storage.extension(name)) in ('jpg','png','webp'));
drop policy if exists "Delete photos in own folder" on storage.objects;
create policy "Delete photos in own folder" on storage.objects for delete to authenticated using (bucket_id='report-images' and ((storage.foldername(name))[1]=(select auth.uid())::text or public.is_admin()));

-- Optional: grant admin role only from SQL Editor after account creation:
-- update public.profiles set role='admin' where id=(select id from auth.users where email='admin@example.com');
