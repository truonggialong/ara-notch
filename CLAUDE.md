# AraNotch — cách làm việc

Ứng dụng notch cho macOS, Swift Package (SwiftPM), chia module theo tính năng. Trả lời chủ dự án bằng tiếng Việt.

## Làm việc theo module

- Trước mọi việc với mã, đọc `Modules/README.md` (bản đồ module, luật ranh giới, quy trình sửa lỗi), rồi sổ của module liên quan `Modules/<Module>/README.md`.
- Repo này không dùng graphify (đã bỏ ngày 2026-10-26). Không chạy `graphify` ở đây, kể cả khi hướng dẫn chung trong `~/CLAUDE.md` nói khác.
- Sửa lỗi trong đúng module chứa lỗi, theo 5 bước ở `Modules/README.md`: tìm module, tái hiện bằng test trong module đó, sửa trong module đó, kiểm chứng, ghi sổ. Không sửa cục bộ ở module khác để che lỗi.
- Đổi giao diện công khai mà module khác dùng (hàm `public`, khoá lưu UserDefaults, case của `ShortcutAction`): báo chủ dự án trước.

## Lệnh

- `Scripts/check-modules.sh`: kiểm tra ranh giới module.
- `Scripts/test-module.sh <Module>`: test của một module.
- `Scripts/test.sh`: ranh giới và toàn bộ test. Không gọi `swift test` trực tiếp.
- `swift build`: build cả target app (`swift test` không build nó).
- `Scripts/build-app.sh`, rồi mở bằng `open build/AraNotch.app`. Không chạy thẳng tệp trong `Contents/MacOS`.

## Sau mỗi việc

Cập nhật sổ module (nhật ký sửa lỗi, giới hạn, tệp, API), `docs/project/FEATURES.md` khi có tính năng mới, và thêm một vòng vào `docs/project/HISTORY.md`.

## GitHub

- `origin` là repo công khai `truonggialong/ara-notch`, và `main` ở máy nối tiếp `origin/main`. Lịch sử cũ trước ngày 2026-10-26 chỉ nằm trong nhánh `archive/full-history` ở máy. Không đẩy nhánh đó lên.
- Commit mang tên module ở đầu: `Clipboard: …`, `Platform: …`; việc trên nhiều module hoặc tài liệu chung thì dùng `App: …`, `Docs: …`. Tác giả là "The Arawo company".
- `README.md` ở gốc là trang giới thiệu trên GitHub: cập nhật nó trong commit, không sửa qua API.
- Đẩy lên `origin` là việc công khai: hỏi chủ dự án trước, trừ khi họ đã cho phép. Không bao giờ force-push. Mẫu khoá giả trong test phải ghép từ nhiều phần, vì GitHub chặn chuỗi trông như khoá thật.
