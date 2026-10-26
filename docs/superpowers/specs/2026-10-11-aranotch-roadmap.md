# AraNotch — Lộ trình sản phẩm

Ngày: 2026-10-11

## Mục tiêu

AraNotch là app macOS native biến notch của MacBook thành trung tâm tiện ích, phát hành cho người dùng khác. Sản phẩm tham chiếu là OneNotch (tryonenotch.com, v2.0.4).

## Quyết định của chủ dự án

| Câu hỏi | Trả lời |
|---|---|
| Mục đích | Phát hành thành sản phẩm cho người khác |
| Định vị | Bộ tính năng rộng như OneNotch, cạnh tranh bằng độ hoàn thiện hoặc giá |
| Vạch phát hành v1.0 | Gần ngang bằng toàn bộ tính năng OneNotch rồi mới phát hành |
| Cách làm việc | Claude tự viết code, tự quyết kỹ thuật, tự kiểm thử |

## Giả định do Claude tự chốt (sửa được)

- **Tên tạm:** AraNotch, lấy theo tên thư mục dự án. Bundle ID tạm `com.aranotch.app`.
- **Nền tảng:** macOS 15 trở lên, Apple silicon. Máy phát triển chạy macOS 27.0.1 nên macOS 15 và 26 chưa được kiểm thử thực tế.
- **Công nghệ:** Swift 6, SwiftUI và AppKit, build bằng Swift Package Manager. Máy chưa có Xcode; SwiftPM và Swift Testing đã được xác nhận chạy được chỉ với Command Line Tools.
- **Phân phối:** tải trực tiếp ngoài Mac App Store, vì sandbox của App Store chặn nhiều tính năng cốt lõi (dán vào app khác, sắp xếp cửa sổ).
- **Bản quyền:** tên, giao diện, hình ảnh và mã nguồn đều tự làm. Chỉ tham khảo ý tưởng tính năng đã công bố công khai của OneNotch.

## Các mảng công việc

Mỗi mảng có spec, kế hoạch và vòng triển khai riêng. Thứ tự dưới đây là thứ tự làm.

| # | Mảng | Nội dung chính | Phụ thuộc |
|---|---|---|---|
| 1 | Khung notch | Cửa sổ bám notch, mở khi rê chuột hoặc bấm, hiệu ứng, hệ thống trang, Cài đặt, icon thanh menu | Không |
| 2 | Clipboard cơ bản | Ghi lịch sử, lưu trữ, trang trên notch, tìm kiếm với bộ lọc `@`, bấm để dán, panel nổi ⌘⇧C, điều hướng bàn phím, quyền riêng tư, xem trước màu, link và code | 1 |
| 3 | Clipboard nâng cao | Board và ghim, khoá board bằng mật mã, Copy Stack, cửa sổ Library, công cụ sửa text, xuất và nhập, đồng bộ iCloud | 2 |
| 4 | Nhạc | Đang phát, điều khiển, nguồn phát, lời bài hát, sóng nhạc, màn hình khoá | 1 |
| 5 | Thông báo hệ thống | Pin, Bluetooth, Caps Lock, mất mạng, thay HUD âm lượng và độ sáng, hẹn giờ nhanh | 1 |
| 6 | AI agent | Theo dõi phiên Claude Code và Codex, duyệt quyền trên notch, hạn mức sử dụng, Clipboard MCP | 1, 2 |
| 7 | Chụp và chú thích | Các kiểu chụp, trình chú thích, OCR, chụp cuộn, Quick Access, lịch sử ảnh | 1 |
| 8 | Dịch và Smart Selection | Dịch nhanh ⌘⇧G, nhiều engine, từ điển, quy đổi tiền, đơn vị, múi giờ | 1 |
| 9 | Lịch và tập trung | Sự kiện, lời nhắc, nhắc họp, Focus Timer | 1 |
| 10 | Cửa sổ và file | Snap Zones, xử lý file kéo thả lên notch | 1 |
| 11 | Giao diện và nền tảng | Kiểu Pill hoàn chỉnh, tuỳ chọn nhiều màn hình, Liquid Glass, màu nhấn, ẩn khi quay màn hình, ẩn icon thanh menu, cử chỉ | 1 |
| 12 | Phát hành | Giấy phép Free và Pro, tự cập nhật, onboarding, đủ ngôn ngữ, ký Developer ID và notarize, website | Tất cả |

## Việc chỉ chủ dự án làm được

Claude không tạo tài khoản và không nhập thông tin thanh toán thay người dùng, nên các việc sau cần chủ dự án tự làm khi tới lúc:

- Đăng ký Apple Developer Program (99 USD mỗi năm). Bắt buộc để ký Developer ID, notarize và dùng iCloud. Cần trước mảng 3 (đồng bộ iCloud) và mảng 12.
- Tài khoản nhà cung cấp thanh toán để bán giấy phép (mảng 12).
- Chốt tên và nhận diện thương hiệu cuối cùng (trước mảng 12).
- Cài Xcode. Chưa bắt buộc cho mảng 1, nhưng cần khi làm iCloud, asset catalog và đo hiệu năng.

## Rủi ro đã biết

- **Đo bộ nhớ:** dùng `footprint -p <pid>` (con số `phys_footprint`, giống cột Memory của Activity Monitor). Con số RSS của `ps` gồm cả trang framework dùng chung nên cao hơn nhiều và không phản ánh bộ nhớ riêng của app. Ngày 2026-10-11: 33 MB khi rảnh, RSS 107 MB.

- **Thiếu Xcode:** với SDK macOS 27, `@State` của SwiftUI là macro và plugin của nó chỉ đi kèm Xcode. Khi chỉ có Command Line Tools, code phải dùng `ObservableObject` thay cho `@State`. Test cũng phải chạy qua `Scripts/test.sh` vì lỗi nạp plugin Swift Testing.

- **Khối lượng:** OneNotch cần 17 bản phát hành trong khoảng 3,5 tháng để tới trạng thái hiện tại và vẫn đang ra bản mới gần như hằng ngày.
- **Nhạc đang phát:** từ macOS 15.4 Apple hạn chế API riêng tư MediaRemote; mảng 4 cần khảo sát cách thay thế trước khi thiết kế.
- **macOS 27:** changelog OneNotch ghi nhận nhiều lỗi tương thích riêng trên macOS 27 (ẩn icon thanh menu, kéo panel nổi).
- **Chưa xem được video giới thiệu:** nội dung bài đăng đã đọc đủ, nhưng hình ảnh video chưa xem được vì khung trình duyệt bị ẩn khi nghiên cứu.
