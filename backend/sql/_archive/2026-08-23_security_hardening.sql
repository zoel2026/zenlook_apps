-- ============================================================================
-- Security hardening (2026-08-23)
--
-- Fix 4 celah yang ditemukan saat audit:
--   1. Requester bisa self-accept permintaan pertemanan
--      (policy friendships_update_involved mengizinkan kedua pihak UPDATE).
--   2. Receiver bisa memanipulasi pesan masuk lewat UPDATE
--      (content/sender_id tidak dilindungi, hanya read_at yang semestinya).
--   3. Tidak ada cek pertemanan saat INSERT pesan -> siapa pun bisa DM siapa pun.
--   4. Username duplikat membuat signup gagal dengan error mentah Postgres.
--
-- Semua statement idempotent — aman dijalankan berulang kali.
-- Jalankan: Supabase Dashboard > SQL Editor > New query > paste > Run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Hanya PENERIMA (friend_id) yang boleh mengubah status friendship.
--    Requester membatalkan request lewat DELETE (sudah diizinkan policy lama).
-- ---------------------------------------------------------------------------
drop policy if exists "friendships_update_involved" on public.friendships;
create policy "friendships_update_involved"
    on public.friendships for update
    using (auth.uid() = friend_id)
    with check (auth.uid() = friend_id);

-- ---------------------------------------------------------------------------
-- 2. Guard trigger messages: receiver hanya boleh mengisi read_at.
--    RLS tidak bisa membatasi per kolom, jadi kita kunci lewat trigger.
-- ---------------------------------------------------------------------------
create or replace function public.messages_update_guard()
returns trigger
language plpgsql
as $$
declare
    jwt_role text;
begin
    -- service_role (server-side, trusted) boleh lewat
    jwt_role := coalesce(
        current_setting('request.jwt.claims', true)::json ->> 'role', '');
    if jwt_role = 'service_role' then
        return new;
    end if;

    if auth.uid() is null or new.receiver_id <> auth.uid() then
        raise exception 'Hanya penerima yang boleh memperbarui pesan';
    end if;

    if new.sender_id   is distinct from old.sender_id
       or new.receiver_id is distinct from old.receiver_id
       or new.content     is distinct from old.content
       or new.created_at  is distinct from old.created_at then
        raise exception 'Hanya kolom read_at yang boleh diubah';
    end if;

    return new;
end;
$$;

drop trigger if exists messages_update_guard on public.messages;
create trigger messages_update_guard
    before update on public.messages
    for each row execute procedure public.messages_update_guard();

-- ---------------------------------------------------------------------------
-- 3. Pesan hanya boleh dikirim ke teman yang sudah accepted.
-- ---------------------------------------------------------------------------
drop policy if exists "messages_insert_own" on public.messages;
create policy "messages_insert_own"
    on public.messages for insert
    with check (
        auth.uid() = sender_id
        and exists (
            select 1 from public.friendships f
            where f.status = 'accepted'
              and ((f.user_id = sender_id and f.friend_id = receiver_id)
                or (f.friend_id = sender_id and f.user_id = receiver_id))
        )
    );

-- ---------------------------------------------------------------------------
-- 4. handle_new_user tahan bencina:
--    - username kosong/invalid -> digenerate otomatis
--    - username duplikat       -> diberi suffix acak (signup tetap sukses)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    base_username text;
    candidate     text;
begin
    base_username := lower(regexp_replace(
        coalesce(new.raw_user_meta_data ->> 'username', ''),
        '[^a-z0-9_]', '', 'g'
    ));

    if base_username is null or length(base_username) < 3 then
        base_username := 'user';
    end if;
    base_username := left(base_username, 24);

    candidate := base_username;
    while exists (select 1 from public.profiles where username = candidate) loop
        candidate := base_username || '_' || substr(md5(random()::text), 1, 4);
    end loop;

    insert into public.profiles (id, email, username, full_name, phone, avatar_url)
    values (
        new.id,
        new.email,
        candidate,
        new.raw_user_meta_data ->> 'full_name',
        nullif(new.raw_user_meta_data ->> 'phone', ''),
        new.raw_user_meta_data ->> 'avatar_url'
    )
    on conflict (id) do nothing;

    return new;
end;
$$;
