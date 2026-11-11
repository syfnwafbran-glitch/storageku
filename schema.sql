-- =====================================================================
--  STORAGEKU · Skema database Supabase
--  Jalankan seluruh isi file ini sekali di Supabase: SQL Editor → New query → Run.
--  Aman dijalankan ulang (memakai IF NOT EXISTS / CREATE OR REPLACE).
-- =====================================================================

-- ---------- Tabel ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  name        text not null,
  role        text not null default 'operator' check (role in ('admin','operator')),
  active      boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.settings (
  id           int primary key default 1 check (id = 1),
  categories   text[] not null default array['Beras & Biji-bijian','Minyak & Lemak','Gula & Tepung','Bumbu Dapur','Mi Instan','Telur & Susu','Minuman','Makanan Kaleng','Kebutuhan Rumah Tangga'],
  units        text[] not null default array['pcs','dus','kg','liter','karung','pak','botol','sak','kaleng','lusin'],
  last_backup  timestamptz,
  last_restore timestamptz,
  updated_at   timestamptz not null default now()
);
insert into public.settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.items (
  id          uuid primary key default gen_random_uuid(),
  sku         text not null,
  name        text not null check (char_length(name) between 2 and 100),
  category    text not null,
  unit        text not null,
  buy         numeric(14,2) not null check (buy >= 0),
  sell        numeric(14,2) check (sell >= 0),
  stock       numeric(14,2) not null default 0 check (stock >= 0),   -- stok tidak pernah negatif
  min         numeric(14,2) not null default 0 check (min >= 0),
  location    text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists items_sku_unique on public.items (upper(sku));

create table if not exists public.transactions (
  id            bigint generated always as identity primary key,
  date          date not null,
  ts            timestamptz not null default now(),
  type          text not null check (type in ('in','out')),
  item_id       uuid references public.items(id) on delete set null,
  sku           text,
  name          text,
  unit          text,
  category      text,
  qty           numeric(14,2) not null check (qty > 0),
  stock_before  numeric(14,2) not null,
  stock_after   numeric(14,2) not null check (stock_after >= 0),
  party         text not null,
  note          text not null default '',
  user_id       uuid references public.profiles(id) on delete set null,
  user_name     text
);
create index if not exists transactions_ts_idx on public.transactions (ts desc);
create index if not exists transactions_item_idx on public.transactions (item_id);

-- ---------- Fungsi bantu peran ----------
create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin');
$$;

-- ---------- Profil otomatis saat pendaftaran ----------
-- Pendaftar pertama otomatis menjadi Admin aktif. Pendaftar berikutnya menjadi Operator
-- nonaktif dan baru bisa memakai aplikasi setelah disetujui Admin.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_first boolean;
begin
  perform pg_advisory_xact_lock(424242);
  select not exists (select 1 from public.profiles) into v_first;
  insert into public.profiles (id, email, name, role, active)
  values (new.id, new.email,
          coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)),
          case when v_first then 'admin' else 'operator' end,
          v_first);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Penjaga aturan ----------
-- Stok hanya boleh berubah melalui fungsi transaksi (bukan edit langsung).
create or replace function public.guard_item_stock() returns trigger
language plpgsql as $$
begin
  if new.stock is distinct from old.stock and coalesce(current_setting('storageku.allow_stock', true), '') <> '1' then
    raise exception 'Stok hanya dapat berubah melalui transaksi barang masuk/keluar.';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists items_guard_stock on public.items;
create trigger items_guard_stock before update on public.items
  for each row execute function public.guard_item_stock();

-- Selalu harus ada minimal satu admin aktif; email & id profil tidak boleh diubah.
create or replace function public.guard_profiles() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.id := old.id; new.email := old.email; new.created_at := old.created_at;
  if old.role = 'admin' and old.active and (new.role <> 'admin' or not new.active) then
    if not exists (select 1 from public.profiles where role = 'admin' and active and id <> old.id) then
      raise exception 'Harus ada minimal satu admin aktif.';
    end if;
  end if;
  if old.id = auth.uid() and (new.role <> old.role or new.active <> old.active) then
    raise exception 'Anda tidak dapat mengubah peran atau status akun sendiri.';
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profiles();

-- ---------- Row Level Security ----------
alter table public.profiles     enable row level security;
alter table public.settings     enable row level security;
alter table public.items        enable row level security;
alter table public.transactions enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_active());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings for select to authenticated using (public.is_active());
drop policy if exists settings_update on public.settings;
create policy settings_update on public.settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists items_select on public.items;
create policy items_select on public.items for select to authenticated using (public.is_active());
drop policy if exists items_update on public.items;
create policy items_update on public.items for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists items_delete on public.items;
create policy items_delete on public.items for delete to authenticated using (public.is_admin());
-- Tidak ada policy INSERT untuk items dan tidak ada policy tulis untuk transactions:
-- keduanya hanya bisa diisi lewat fungsi RPC di bawah, yang memeriksa peran & stok.

drop policy if exists transactions_select on public.transactions;
create policy transactions_select on public.transactions for select to authenticated using (public.is_active());

-- ---------- RPC: catat transaksi (atomik, mengunci baris barang) ----------
create or replace function public.record_transaction(
  p_item uuid, p_type text, p_qty numeric, p_date date, p_party text, p_note text default ''
) returns public.transactions
language plpgsql security definer set search_path = public as $$
declare v_prof public.profiles; v_item public.items; v_after numeric; v_t public.transactions;
begin
  select * into v_prof from public.profiles where id = auth.uid() and active;
  if not found then raise exception 'Akun Anda belum aktif atau tidak memiliki akses.' using errcode = '42501'; end if;
  if p_type not in ('in','out') then raise exception 'Jenis transaksi tidak valid.'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'Jumlah harus lebih dari 0.'; end if;
  if round(p_qty, 2) <> p_qty then raise exception 'Jumlah maksimal 2 angka di belakang koma.'; end if;
  if p_date is null then raise exception 'Tanggal transaksi wajib diisi.'; end if;
  if p_date > current_date + 1 then raise exception 'Tanggal tidak boleh melebihi hari ini.'; end if;
  if char_length(trim(coalesce(p_party, ''))) < 2 then raise exception 'Supplier/tujuan wajib diisi (minimal 2 karakter).'; end if;
  if char_length(coalesce(p_note, '')) > 200 then raise exception 'Keterangan maksimal 200 karakter.'; end if;

  select * into v_item from public.items where id = p_item for update;   -- kunci baris: aman dari transaksi bersamaan
  if not found then raise exception 'Barang tidak ditemukan. Mungkin sudah dihapus.'; end if;

  v_after := case when p_type = 'in' then v_item.stock + p_qty else v_item.stock - p_qty end;
  if v_after < 0 then
    raise exception 'Stok tidak mencukupi. Stok tersedia % %, diminta % %.', v_item.stock, v_item.unit, p_qty, v_item.unit;
  end if;

  perform set_config('storageku.allow_stock', '1', true);
  update public.items set stock = v_after where id = p_item;
  perform set_config('storageku.allow_stock', '', true);

  insert into public.transactions (date, type, item_id, sku, name, unit, category, qty, stock_before, stock_after, party, note, user_id, user_name)
  values (p_date, p_type, v_item.id, v_item.sku, v_item.name, v_item.unit, v_item.category, p_qty, v_item.stock, v_after,
          trim(p_party), coalesce(trim(p_note), ''), v_prof.id, v_prof.name)
  returning * into v_t;
  return v_t;
end $$;

-- ---------- RPC: tambah barang (+ transaksi "Stok Awal") ----------
create or replace function public.create_item(p jsonb) returns public.items
language plpgsql security definer set search_path = public as $$
declare v_prof public.profiles; v_item public.items; v_stock numeric := coalesce((p->>'stock')::numeric, 0);
begin
  select * into v_prof from public.profiles where id = auth.uid() and active and role = 'admin';
  if not found then raise exception 'Hanya Admin yang dapat menambah barang.' using errcode = '42501'; end if;
  if v_stock < 0 then raise exception 'Stok awal tidak boleh negatif.'; end if;
  insert into public.items (sku, name, category, unit, buy, sell, stock, min, location)
  values (upper(trim(p->>'sku')), trim(p->>'name'), p->>'category', p->>'unit', (p->>'buy')::numeric,
          nullif(p->>'sell', '')::numeric, round(v_stock, 2), coalesce((p->>'min')::numeric, 0), trim(p->>'location'))
  returning * into v_item;
  if v_item.stock > 0 then
    insert into public.transactions (date, type, item_id, sku, name, unit, category, qty, stock_before, stock_after, party, note, user_id, user_name)
    values (coalesce((p->>'date')::date, current_date), 'in', v_item.id, v_item.sku, v_item.name, v_item.unit, v_item.category,
            v_item.stock, 0, v_item.stock, 'Stok Awal', 'Stok awal saat barang ditambahkan', v_prof.id, v_prof.name);
  end if;
  return v_item;
end $$;

-- ---------- RPC: kosongkan data gudang ----------
create or replace function public.wipe_data() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Hanya Admin yang dapat mengosongkan data.' using errcode = '42501'; end if;
  delete from public.transactions where true;
  delete from public.items where true;
end $$;

-- ---------- RPC: pulihkan dari cadangan ----------
-- p = { items:[...], transactions:[...], settings:{categories,units}, profiles:[{id,name,role,active}] }
create or replace function public.restore_backup(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n_items int; n_trx int;
begin
  if not public.is_admin() then raise exception 'Hanya Admin yang dapat memulihkan data.' using errcode = '42501'; end if;
  delete from public.transactions where true;
  delete from public.items where true;

  insert into public.items (id, sku, name, category, unit, buy, sell, stock, min, location, created_at, updated_at)
  select (x->>'id')::uuid, x->>'sku', x->>'name', x->>'category', x->>'unit', (x->>'buy')::numeric, nullif(x->>'sell','')::numeric,
         (x->>'stock')::numeric, coalesce((x->>'min')::numeric, 0), coalesce(x->>'location', '-'),
         coalesce((x->>'created_at')::timestamptz, now()), now()
  from jsonb_array_elements(coalesce(p->'items', '[]'::jsonb)) x;
  get diagnostics n_items = row_count;

  insert into public.transactions (date, ts, type, item_id, sku, name, unit, category, qty, stock_before, stock_after, party, note, user_id, user_name)
  select (x->>'date')::date, coalesce((x->>'ts')::timestamptz, now()), x->>'type',
         case when exists (select 1 from public.items i where i.id::text = x->>'item_id') then (x->>'item_id')::uuid end,
         x->>'sku', x->>'name', x->>'unit', x->>'category', (x->>'qty')::numeric, (x->>'stock_before')::numeric, (x->>'stock_after')::numeric,
         coalesce(x->>'party', '-'), coalesce(x->>'note', ''),
         case when exists (select 1 from public.profiles u where u.id::text = x->>'user_id') then (x->>'user_id')::uuid end,
         x->>'user_name'
  from jsonb_array_elements(coalesce(p->'transactions', '[]'::jsonb)) x
  order by coalesce((x->>'ts')::timestamptz, now());
  get diagnostics n_trx = row_count;

  if p ? 'settings' and jsonb_typeof(p->'settings'->'categories') = 'array' then
    update public.settings set
      categories = array(select jsonb_array_elements_text(p->'settings'->'categories')),
      units = coalesce(array(select jsonb_array_elements_text(p->'settings'->'units')), units),
      last_restore = now(), updated_at = now()
    where id = 1;
  else
    update public.settings set last_restore = now() where id = 1;
  end if;

  -- Peran & status pengguna dipulihkan hanya untuk akun yang masih ada.
  update public.profiles pr set name = coalesce(x->>'name', pr.name), role = coalesce(x->>'role', pr.role), active = coalesce((x->>'active')::boolean, pr.active)
  from jsonb_array_elements(coalesce(p->'profiles', '[]'::jsonb)) x
  where pr.id::text = x->>'id' and pr.id <> auth.uid();

  return jsonb_build_object('items', n_items, 'transactions', n_trx);
end $$;

-- ---------- Hak eksekusi fungsi ----------
revoke all on function public.record_transaction(uuid, text, numeric, date, text, text) from public, anon;
revoke all on function public.create_item(jsonb) from public, anon;
revoke all on function public.wipe_data() from public, anon;
revoke all on function public.restore_backup(jsonb) from public, anon;
grant execute on function public.record_transaction(uuid, text, numeric, date, text, text) to authenticated;
grant execute on function public.create_item(jsonb) to authenticated;
grant execute on function public.wipe_data() to authenticated;
grant execute on function public.restore_backup(jsonb) to authenticated;

-- ---------- Realtime: perubahan langsung tampil di semua perangkat ----------
do $$
declare t text;
begin
  foreach t in array array['items','transactions','profiles','settings'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
alter table public.items replica identity full;
alter table public.transactions replica identity full;
alter table public.profiles replica identity full;
