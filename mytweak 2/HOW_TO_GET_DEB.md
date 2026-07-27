# Hướng dẫn lấy file .deb thật qua GitHub Actions (miễn phí, không cần Mac)

Cách này để GitHub build hộ bạn trên cloud — bạn không cần cài gì trên máy
tính cá nhân, không cần Mac, không cần biết dùng Theos.

## Bước 1: Tạo tài khoản GitHub (nếu chưa có)
https://github.com/join

## Bước 2: Tạo repository mới
1. Vào https://github.com/new
2. Đặt tên bất kỳ, ví dụ `callvoicefx`, để **Private** cũng được.
3. Bấm "Create repository".

## Bước 3: Upload toàn bộ thư mục `mytweak/` (kèm `.github/`) lên repo đó
Cách dễ nhất không cần dòng lệnh:
1. Vào trang repo vừa tạo → "uploading an existing file" (hoặc kéo thả).
2. Kéo **toàn bộ nội dung** thư mục `mytweak` (bao gồm cả folder ẩn
   `.github`) vào khung upload. GitHub web đôi khi không nhận folder ẩn khi
   kéo thả — nếu vậy, dùng GitHub Desktop (app, dễ dùng, có kéo thả cả
   thư mục ẩn): https://desktop.github.com

## Bước 4: Chạy workflow
1. Vào tab **Actions** trên repo.
2. Chọn "Build CallVoiceFX .deb" ở cột bên trái.
3. Bấm nút **Run workflow** (màu xanh, góc phải) → Run workflow.
4. Đợi khoảng 2-4 phút, trang sẽ hiện dấu tick xanh nếu build thành công.

## Bước 5: Tải file .deb
1. Bấm vào lần chạy vừa xong (dòng có dấu tick xanh).
2. Kéo xuống mục **Artifacts** ở cuối trang → tải `CallVoiceFX-deb.zip`.
3. Giải nén ra sẽ thấy file `.deb` thật, copy vào điện thoại (AirDrop/Telegram
   Saved Messages/Files app) rồi cài bằng Filza hoặc Sileo/Zebra.

## Nếu bước "Build package" báo lỗi (dấu X đỏ)
Bấm vào bước đó để xem log lỗi cụ thể, copy đoạn lỗi gửi lại cho mình —
mình sẽ đọc log và sửa code hoặc sửa workflow theo đúng lỗi đó. Loại lỗi
hay gặp nhất với setup này là thiếu đúng phiên bản iOS SDK; nếu vậy chỉ
cần đổi số phiên bản SDK trong `build.yml` (dòng `iPhoneOS16.5.sdk`) sang
phiên bản có sẵn trong repo `theos/sdks`, mình có thể chỉnh giúp ngay khi
thấy log.
