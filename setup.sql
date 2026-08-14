-- StudyNotes Store: production security setup
-- Run this ONCE in Supabase SQL Editor.
-- IMPORTANT: After creating your admin auth account, insert its auth.users id
-- into public.admin_users (see the final INSERT example below).

alter table public.notes
  add column if not exists book_name text,
  add column if not exists class_name text,
  add column if not exists subject text,
  add column if not exists chapter_name text,
  add column if not exists cover_path text;

alter table public.notes alter column title set not null;

create table if not exists public.store_settings (
  id integer primary key default 1 check (id = 1),
  upi_id text,
  qr_path text,
  updated_at timestamptz default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  access_token uuid not null default gen_random_uuid() unique,
  note_id uuid not null references public.notes(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null default auth.uid(),
  utr_id text not null,
  proof_path text,
  status text not null default 'pending' check (status in ('pending','paid','rejected')),
  created_at timestamptz default now(),
  verified_at timestamptz
);

-- Only these user IDs are allowed to administer the store.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);

alter table public.notes enable row level security;
alter table public.store_settings enable row level security;
alter table public.orders enable row level security;
alter table public.admin_users enable row level security;

-- Security-definer check used by the website and RLS policies.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = auth.uid()
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- Students may see only published note metadata.
drop policy if exists "public read published notes" on public.notes;
create policy "public read published notes"
on public.notes for select
to anon, authenticated
using (published = true);

-- ONLY admins can create/update/delete notes.
drop policy if exists "authenticated manage notes" on public.notes;
drop policy if exists "admin manage notes" on public.notes;
create policy "admin manage notes"
on public.notes for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Public store needs the payment destination (UPI + public QR path).
drop policy if exists "public read store settings" on public.store_settings;
create policy "public read store settings"
on public.store_settings for select
to anon, authenticated
using (true);

-- ONLY admins can change payment settings.
drop policy if exists "admin manage store settings" on public.store_settings;
create policy "admin manage store settings"
on public.store_settings for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Buyers can submit payment requests. This is intentionally public.
drop policy if exists "users create orders" on public.orders;
create policy "users create orders"
on public.orders for insert
to anon, authenticated
with check (true);

-- ONLY admins can read/update payment requests.
drop policy if exists "authenticated read all orders" on public.orders;
drop policy if exists "admin read all orders" on public.orders;
create policy "admin read all orders"
on public.orders for select
to authenticated
using (public.is_admin());

drop policy if exists "authenticated update orders" on public.orders;
drop policy if exists "admin update orders" on public.orders;
create policy "admin update orders"
on public.orders for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Admin list itself is not directly readable from the browser.
-- The is_admin() security-definer function is the only check needed by the frontend.
drop policy if exists "admin users self read" on public.admin_users;
create policy "admin users self read"
on public.admin_users for select
to authenticated
using (user_id = auth.uid());

-- Storage buckets
insert into storage.buckets (id,name,public) values ('notes-pdfs','notes-pdfs',false)
on conflict (id) do nothing;
insert into storage.buckets (id,name,public) values ('notes-covers','notes-covers',true)
on conflict (id) do nothing;
insert into storage.buckets (id,name,public) values ('payment-qr','payment-qr',true)
on conflict (id) do nothing;
insert into storage.buckets (id,name,public) values ('payment-proofs','payment-proofs',false)
on conflict (id) do nothing;

-- ONLY admins may upload/delete note PDFs.
drop policy if exists "authenticated upload note pdf" on storage.objects;
drop policy if exists "admin upload note pdf" on storage.objects;
create policy "admin upload note pdf"
on storage.objects for insert to authenticated
with check (bucket_id = 'notes-pdfs' and public.is_admin());

drop policy if exists "authenticated delete note pdf" on storage.objects;
drop policy if exists "admin delete note pdf" on storage.objects;
create policy "admin delete note pdf"
on storage.objects for delete to authenticated
using (bucket_id = 'notes-pdfs' and public.is_admin());

-- Public cover images.
drop policy if exists "public read covers" on storage.objects;
create policy "public read covers"
on storage.objects for select to public
using (bucket_id = 'notes-covers');

drop policy if exists "authenticated upload covers" on storage.objects;
drop policy if exists "admin upload covers" on storage.objects;
create policy "admin upload covers"
on storage.objects for insert to authenticated
with check (bucket_id = 'notes-covers' and public.is_admin());

-- Public QR image.
drop policy if exists "public read qr" on storage.objects;
create policy "public read qr"
on storage.objects for select to public
using (bucket_id = 'payment-qr');

drop policy if exists "authenticated upload qr" on storage.objects;
drop policy if exists "admin upload qr" on storage.objects;
create policy "admin upload qr"
on storage.objects for insert to authenticated
with check (bucket_id = 'payment-qr' and public.is_admin());

-- Buyers may upload payment proof. They cannot read/delete other proofs.
drop policy if exists "anon upload proof" on storage.objects;
create policy "anon upload proof"
on storage.objects for insert to anon, authenticated
with check (bucket_id = 'payment-proofs');

-- Buyer can check only an order when they know the random access token kept in
-- their browser. This does not expose the PDF itself.
create or replace function public.check_order_status(p_order_id uuid, p_access_token uuid)
returns table(id uuid, status text, note_id uuid)
language sql
security definer
set search_path = public
as $$
  select o.id, o.status, o.note_id
  from public.orders o
  where o.id = p_order_id and o.access_token = p_access_token;
$$;
revoke all on function public.check_order_status(uuid,uuid) from public;
grant execute on function public.check_order_status(uuid,uuid) to anon, authenticated;

-- IMPORTANT: after your admin Auth user exists, add that user's UUID here.
-- Find it with:
-- select id, email from auth.users order by created_at desc;
-- Then run:
-- insert into public.admin_users(user_id) values ('YOUR-AUTH-USER-UUID')
-- on conflict (user_id) do nothing;

-- NOTE: notes-pdfs stays PRIVATE. Final production PDF delivery should use a
-- server/Edge Function to verify a paid order and return a short-lived signed URL.


-- ============================================================
-- PREVIOUS YEAR QUESTION PAPERS - SECURE ACCESS CODE
-- Students cannot read the table or storage bucket directly.
-- They must first provide the Access Code. PDF delivery is handled
-- by the Supabase Edge Function included in this ZIP.
-- ============================================================

create table if not exists public.previous_year_papers (
  id uuid primary key default gen_random_uuid(),
  exam_name text,
  year integer not null check (year between 2000 and 2100),
  class_name text,
  subject text not null,
  title text not null,
  pdf_path text not null,
  published boolean not null default true,
  created_at timestamptz default now()
);

alter table public.previous_year_papers enable row level security;

-- V2/V4 exam type support.
alter table public.previous_year_papers
add column if not exists exam_type text not null default 'अन्य';

-- Access-code hash table. Only one active code is kept.
create table if not exists public.previous_year_access (
  id integer primary key default 1 check (id=1),
  code_hash text not null,
  updated_at timestamptz default now()
);

alter table public.previous_year_access enable row level security;

-- Students never get direct SELECT on either table.
drop policy if exists "public read published previous papers" on public.previous_year_papers;
drop policy if exists "admin read previous papers" on public.previous_year_papers;
create policy "admin read previous papers"
on public.previous_year_papers for select to authenticated
using (public.is_admin());

drop policy if exists "admin manage previous papers" on public.previous_year_papers;
create policy "admin manage previous papers"
on public.previous_year_papers for all
 to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "admin read access code" on public.previous_year_access;
create policy "admin read access code"
on public.previous_year_access for select to authenticated
using (public.is_admin());

-- SHA-256 helper used only inside security-definer functions.
create or replace function public.sha256_hex(p_text text)
returns text
language plpgsql
immutable
as $$
begin
  return encode(digest(coalesce(p_text,''), 'sha256'), 'hex');
end;
$$;

-- Verify code without exposing the stored hash.
create or replace function public.verify_previous_year_access_code(p_code text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.previous_year_access
    where id=1 and code_hash = public.sha256_hex(p_code)
  );
$$;

revoke all on function public.verify_previous_year_access_code(text) from public;
grant execute on function public.verify_previous_year_access_code(text) to anon, authenticated;

-- Return papers only after the correct code is supplied.
create or replace function public.get_previous_year_papers(p_code text)
returns table(
  id uuid, exam_name text, exam_type text, year integer, class_name text,
  subject text, title text, published boolean, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select p.id,p.exam_name,p.exam_type,p.year,p.class_name,p.subject,p.title,p.published,p.created_at
  from public.previous_year_papers p
  where p.published=true
    and exists(
      select 1 from public.previous_year_access a
      where a.id=1 and a.code_hash=public.sha256_hex(p_code)
    )
  order by p.year desc,p.created_at desc;
$$;

revoke all on function public.get_previous_year_papers(text) from public;
grant execute on function public.get_previous_year_papers(text) to anon, authenticated;

-- Admin-only function to set/replace the code. Plain code is never stored.
create or replace function public.set_previous_year_access_code(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    return false;
  end if;
  if length(trim(coalesce(p_code,''))) < 4 then
    return false;
  end if;
  insert into public.previous_year_access(id,code_hash,updated_at)
  values(1,public.sha256_hex(trim(p_code)),now())
  on conflict (id) do update set code_hash=excluded.code_hash, updated_at=now();
  return true;
end;
$$;

revoke all on function public.set_previous_year_access_code(text) from public;
grant execute on function public.set_previous_year_access_code(text) to authenticated;

-- IMPORTANT: create your first code after setup, while logged in as admin:
-- select public.set_previous_year_access_code('YOUR-CODE-HERE');

-- Private storage bucket: no public URL access.
insert into storage.buckets (id,name,public)
values ('previous-year-papers','previous-year-papers',false)
on conflict (id) do update set public=false;

drop policy if exists "public read previous paper pdfs" on storage.objects;
drop policy if exists "admin upload previous paper pdfs" on storage.objects;
create policy "admin upload previous paper pdfs"
on storage.objects for insert to authenticated
with check (bucket_id='previous-year-papers' and public.is_admin());

drop policy if exists "admin delete previous paper pdfs" on storage.objects;
create policy "admin delete previous paper pdfs"
on storage.objects for delete to authenticated
using (bucket_id='previous-year-papers' and public.is_admin());

grant insert, update, delete on table public.previous_year_papers to authenticated;
revoke select on table public.previous_year_papers from anon;
grant select on table public.previous_year_papers to authenticated;

