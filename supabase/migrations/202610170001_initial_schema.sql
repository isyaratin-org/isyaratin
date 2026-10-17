begin;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '' check (char_length(full_name) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversations (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  location text not null default '' check (char_length(location) <= 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);

create table public.messages (
  id uuid primary key,
  conversation_id uuid not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  author text not null check (author in ('signer', 'partner')),
  source text not null check (source in ('typed', 'sign', 'voice')),
  content text not null check (char_length(btrim(content)) between 1 and 5000),
  created_at timestamptz not null default now(),
  foreign key (conversation_id, owner_id)
    references public.conversations(id, owner_id) on delete cascade
);

create index conversations_owner_updated_idx
  on public.conversations (owner_id, updated_at desc);
create index messages_owner_conversation_created_idx
  on public.messages (owner_id, conversation_id, created_at);

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

create policy profiles_select_own on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy profiles_update_own on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy conversations_select_own on public.conversations
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy conversations_insert_own on public.conversations
  for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy conversations_update_own on public.conversations
  for update to authenticated using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy conversations_delete_own on public.conversations
  for delete to authenticated using ((select auth.uid()) = owner_id);

create policy messages_select_own on public.messages
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy messages_insert_own on public.messages
  for insert to authenticated with check ((select auth.uid()) = owner_id);

-- Messages are append-only through the client. Conversation deletion cascades.
revoke all on public.profiles, public.conversations, public.messages from anon;
revoke all on public.profiles, public.conversations, public.messages from authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.conversations to authenticated;
grant select, insert on public.messages to authenticated;

create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120));
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

insert into public.profiles (id, full_name)
select id, left(coalesce(raw_user_meta_data ->> 'full_name', ''), 120)
from auth.users on conflict (id) do nothing;

-- Private assets are uploaded by an administrator, never with an admin key in the app.
insert into storage.buckets (id, name, public, file_size_limit)
values ('avatar-assets', 'avatar-assets', false, 52428800)
on conflict (id) do nothing;

create policy avatar_assets_read_authenticated on storage.objects
  for select to authenticated using (bucket_id = 'avatar-assets');

commit;
