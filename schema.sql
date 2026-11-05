-- VIBE ROOM schema. Run in Supabase SQL Editor as project owner.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default 'Viber' check (char_length(nickname) between 1 and 24),
  avatar_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  description text,
  invite_code text not null unique,
  max_members integer not null check (max_members between 2 and 100),
  owner_id uuid not null references auth.users(id),
  room_image text,
  created_at timestamptz not null default now()
);
create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(room_id,user_id)
);
create table if not exists public.tracks (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  youtube_url text not null,
  youtube_id text not null check (char_length(youtube_id)=11),
  title text not null,
  channel text not null,
  thumbnail text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references public.tracks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  score integer not null check (score between 0 and 10),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(track_id,user_id)
);
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references public.tracks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists room_members_user_idx on public.room_members(user_id);
create index if not exists tracks_room_created_idx on public.tracks(room_id,created_at desc);
create index if not exists ratings_track_idx on public.ratings(track_id);
create index if not exists comments_track_idx on public.comments(track_id,created_at);

create or replace function public.is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.room_members where room_id=p_room_id and user_id=auth.uid()); $$;
create or replace function public.is_track_room_member(p_track_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.tracks t join public.room_members m on m.room_id=t.room_id where t.id=p_track_id and m.user_id=auth.uid()); $$;

create or replace function public.create_room(p_name text,p_description text,p_max_members integer,p_invite_code text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare new_id uuid;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 if p_max_members < 2 or p_max_members > 100 then raise exception '방 인원은 2~100명으로 설정해 주세요.'; end if;
 insert into public.rooms(name,description,max_members,invite_code,owner_id)
 values(trim(p_name),nullif(trim(p_description),''),p_max_members,upper(p_invite_code),auth.uid()) returning id into new_id;
 insert into public.room_members(room_id,user_id) values(new_id,auth.uid());
 return new_id;
end; $$;

create or replace function public.join_room(p_invite_code text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare r public.rooms%rowtype; member_count integer;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 select * into r from public.rooms where invite_code=upper(trim(p_invite_code)) for update;
 if not found then raise exception '초대 코드가 올바르지 않습니다.'; end if;
 if exists(select 1 from public.room_members where room_id=r.id and user_id=auth.uid()) then return r.id; end if;
 select count(*) into member_count from public.room_members where room_id=r.id;
 if member_count >= r.max_members then raise exception '방 정원이 가득 찼습니다.'; end if;
 insert into public.room_members(room_id,user_id) values(r.id,auth.uid());
 return r.id;
end; $$;

create or replace function public.leave_room(p_room_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 delete from public.room_members where room_id=p_room_id and user_id=auth.uid();
 -- Room, tracks, ratings and comments remain in the database. Rejoining restores access.
end; $$;

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.tracks enable row level security;
alter table public.ratings enable row level security;
alter table public.comments enable row level security;

create policy "profiles readable by authenticated users" on public.profiles for select to authenticated using (true);
create policy "users create own profile" on public.profiles for insert to authenticated with check (id=auth.uid());
create policy "users update own profile" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());

create policy "room visible to members" on public.rooms for select to authenticated using (public.is_room_member(id));
create policy "room owner updates room" on public.rooms for update to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid());
create policy "members visible to room members" on public.room_members for select to authenticated using (public.is_room_member(room_id));

create policy "tracks visible to room members" on public.tracks for select to authenticated using (public.is_room_member(room_id));
create policy "members add tracks" on public.tracks for insert to authenticated with check (user_id=auth.uid() and public.is_room_member(room_id));
create policy "owners delete own tracks" on public.tracks for delete to authenticated using (user_id=auth.uid() and public.is_room_member(room_id));

create policy "ratings visible to room members" on public.ratings for select to authenticated using (public.is_track_room_member(track_id));
create policy "members rate others tracks" on public.ratings for insert to authenticated with check (
 user_id=auth.uid() and public.is_track_room_member(track_id)
 and exists(select 1 from public.tracks t where t.id=track_id and t.user_id<>auth.uid())
);
create policy "users update own ratings on others tracks" on public.ratings for update to authenticated using (
 user_id=auth.uid() and exists(select 1 from public.tracks t where t.id=track_id and t.user_id<>auth.uid())
) with check (user_id=auth.uid());
create policy "users delete own ratings" on public.ratings for delete to authenticated using (user_id=auth.uid());

create policy "comments visible to room members" on public.comments for select to authenticated using (public.is_track_room_member(track_id));
create policy "members comment in room" on public.comments for insert to authenticated with check (user_id=auth.uid() and public.is_track_room_member(track_id));
create policy "authors update own comments" on public.comments for update to authenticated using (user_id=auth.uid() and public.is_track_room_member(track_id)) with check (user_id=auth.uid());
create policy "authors delete own comments" on public.comments for delete to authenticated using (user_id=auth.uid() and public.is_track_room_member(track_id));

-- Keep updated_at current for edits.
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;
drop trigger if exists ratings_touch_updated_at on public.ratings;
create trigger ratings_touch_updated_at before update on public.ratings for each row execute function public.touch_updated_at();
drop trigger if exists comments_touch_updated_at on public.comments;
create trigger comments_touch_updated_at before update on public.comments for each row execute function public.touch_updated_at();

-- Enable Realtime for live room updates (ignore if already added).
do $$ begin
 alter publication supabase_realtime add table public.tracks;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
 alter publication supabase_realtime add table public.ratings;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
 alter publication supabase_realtime add table public.comments;
exception when duplicate_object then null; when undefined_object then null; end $$;
