# Storageku · Sistem Manajemen Stok Gudang

Aplikasi web untuk mencatat stok barang kebutuhan pokok. Database memakai **Supabase**, sedangkan halaman aplikasinya dipasang di **GitHub Pages**. Keduanya gratis, dan aplikasi bisa dibuka dari laptop, tablet, maupun HP.

Isi paket:

| File | Fungsi |
|---|---|
| `index.html` | Aplikasi Storageku (seluruh tampilan & logika) |
| `schema.sql` | Struktur database, aturan keamanan, dan fungsi transaksi |
| `README.md` | Panduan ini |

---

## Langkah 1 · Buat project Supabase

1. Daftar atau masuk di **https://supabase.com**, lalu klik **New project**.
2. Isi nama project (misalnya `storageku`), buat **Database Password**, dan simpan password itu.
3. Pilih region **Southeast Asia (Singapore)** agar aplikasi cepat diakses dari Indonesia.
4. Tunggu 1–2 menit sampai project siap.

## Langkah 2 · Siapkan database

1. Di menu kiri, buka **SQL Editor**, lalu klik **New query**.
2. Buka file `schema.sql`, salin seluruh isinya, lalu tempel ke editor.
3. Klik **Run**. Hasilnya harus *Success*.

Skrip ini membuat tabel barang, transaksi, pengguna, dan pengaturan. Skrip ini juga memasang aturan berikut:

- Stok **tidak bisa negatif** dan **hanya berubah lewat transaksi**.
- Transaksi dari beberapa perangkat sekaligus aman, karena baris barang dikunci saat diproses.
- **Operator** hanya bisa mencatat transaksi dan melihat data. **Admin** punya akses penuh.
- Perubahan data langsung tampil di semua perangkat (real-time).

Skrip ini aman dijalankan ulang bila ada pembaruan.

## Langkah 3 · Atur login (Authentication)

Buka **Authentication → Sign In / Providers → Email**:

- **Confirm email**: matikan agar karyawan bisa langsung mendaftar tanpa membuka email konfirmasi. Kalau dibiarkan menyala, setiap pendaftar harus mengklik tautan di email dulu.
- Pastikan **Enable Email provider** menyala.

Catatan: layanan email bawaan Supabase hanya bisa mengirim sedikit email per jam. Ini cukup untuk tim kecil. Untuk "Lupa kata sandi" yang lebih andal, atur SMTP sendiri di **Authentication → Emails → SMTP Settings**.

## Langkah 4 · Ambil URL & kunci API

Buka **Project Settings → API** (pada tampilan baru: **Project Settings → API Keys** dan **Data API**). Salin dua nilai ini:

- **Project URL**, contoh `https://abcdefghijkl.supabase.co`
- Kunci **anon public** (`eyJhbGciOi…`) **atau** **publishable** (`sb_publishable_…`)

> ⚠️ **Jangan pernah** memakai kunci **service_role** atau **secret**. Kunci anon/publishable aman ditaruh di aplikasi karena data tetap dilindungi aturan keamanan (RLS) dari `schema.sql`.

Buka `index.html` dengan Notepad atau VS Code, cari baris berikut di bagian atas `<script>`, lalu isi:

```js
const SUPABASE_URL = 'https://abcdefghijkl.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOi...';
```

Kalau dibiarkan kosong, aplikasi akan menampilkan form **Hubungkan ke Supabase**, dan setiap perangkat harus mengisinya sekali. Mengisi langsung di file lebih praktis untuk banyak karyawan.

## Langkah 5 · Pasang di GitHub Pages

1. Masuk ke **https://github.com**, lalu klik **New repository**. Beri nama, misalnya `storageku`, dan pilih **Public**. GitHub Pages gratis hanya untuk repository publik.
2. Klik **uploading an existing file**. Unggah `index.html`, `schema.sql`, dan `README.md`, lalu klik **Commit changes**.
3. Buka **Settings → Pages**. Pada *Build and deployment*, pilih **Deploy from a branch**, branch **main**, folder **/ (root)**, lalu klik **Save**.
4. Tunggu 1–2 menit. Alamat aplikasi akan muncul, misalnya `https://namaanda.github.io/storageku/`.

Repository publik berarti **kode** aplikasi bisa dilihat orang lain. **Data gudang tetap aman** di Supabase dan hanya bisa dibuka oleh akun yang sudah disetujui admin.

## Langkah 6 · Daftarkan alamat aplikasi di Supabase

Buka **Authentication → URL Configuration**:

- **Site URL**: isi alamat GitHub Pages Anda, misalnya `https://namaanda.github.io/storageku/`.
- **Redirect URLs**: tambahkan alamat yang sama.

Langkah ini diperlukan agar tautan konfirmasi email dan "Lupa kata sandi" kembali ke aplikasi Anda.

## Langkah 7 · Mulai pakai

1. Buka alamat aplikasi, lalu klik **Daftar akun baru**. **Pendaftar pertama otomatis menjadi Admin.**
2. Karyawan membuka alamat yang sama dan mendaftar sendiri. Akun mereka berstatus **Menunggu persetujuan**.
3. Admin membuka **Manajemen Pengguna**, lalu klik **Setujui**. Peran bisa diubah menjadi Admin atau Operator.
4. Di HP, buka menu browser lalu pilih **Tambahkan ke Layar Utama** agar terasa seperti aplikasi.

Akun juga bisa ditambahkan dari Supabase: **Authentication → Users → Invite user**. Akun undangan muncul di Storageku sebagai menunggu persetujuan.

Setelah semua karyawan terdaftar, pendaftaran bisa ditutup di **Authentication → Sign In / Providers → Allow new users to sign up**. Ini opsional.

---

## Memindahkan data dari Storageku versi claude.ai

1. Di versi claude.ai, buka **Backup & Pemulihan**, lalu klik **Unduh Cadangan**.
2. Di versi Supabase, masuk sebagai Admin, buka **Backup & Pemulihan → Pulihkan Data**, lalu pilih file tadi.

Barang dan seluruh riwayat transaksi ikut pindah. Akun login lama tidak ikut pindah, jadi setiap orang perlu mendaftar ulang dengan email.

## Hal yang perlu diketahui (paket gratis Supabase)

- **Project dijeda setelah 7 hari tanpa aktivitas.** Datanya tetap aman. Untuk mengaktifkannya lagi, buka dashboard Supabase lalu klik **Restore project**. Gudang yang dipakai setiap hari tidak akan terkena.
- **Tidak ada backup otomatis.** Unduh cadangan secara rutin dari menu **Backup & Pemulihan**, misalnya setiap akhir pekan.
- Kapasitas database **500 MB**. Data stok berbentuk teks, jadi kapasitas ini cukup untuk ratusan ribu transaksi.
- Jika aplikasi dipakai untuk operasional penting yang harus selalu menyala, pertimbangkan paket **Pro**.

## Mengatasi masalah

| Pesan / gejala | Penyebab & solusi |
|---|---|
| "Database belum disiapkan" | `schema.sql` belum dijalankan. Ulangi Langkah 2. |
| "Kunci API Supabase tidak valid" | URL atau kunci salah salin. Ulangi Langkah 4. |
| "Email belum dikonfirmasi" | Buka email konfirmasi, atau matikan **Confirm email** (Langkah 3). |
| Akun selalu "Menunggu persetujuan" | Admin perlu klik **Setujui** di Manajemen Pengguna. |
| "Profil … belum ada" | Akun dibuat sebelum `schema.sql` dijalankan. Hapus akun itu di Authentication → Users, lalu daftar ulang. |
| Tautan lupa sandi membuka halaman yang salah | Isi Site URL dan Redirect URLs (Langkah 6). |
| Perubahan dari HP lain tidak langsung muncul | Periksa internet. Indikator di pojok kiri bawah menunjukkan status real-time, dan data disegarkan otomatis saat tersambung kembali. |
