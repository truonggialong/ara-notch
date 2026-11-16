# Vorssaint 3.4.4 so với Ara Notch (2026-11-16)

Nguồn: `~/Downloads/vorssaint-utils-3.4.4.zip`, mã nguồn Swift (GPL-3.0-or-later), chỉ đọc mã, không chạy app.
Lần học trước (3.4.3, 2026-11-09) đã cho ra nhóm 1 (đã duyệt), C1–C5 và D1–D11 (chờ duyệt).

Ghi chú về công cụ: gói này là mã nguồn, không có tệp app đã dựng, nên plugin REA (dùng cho tệp nhị phân, gói app) không cần dùng; phân tích bằng cách đọc mã trực tiếp.

## Các trang notch của Vorssaint và Ara Notch

| Trang Vorssaint | Ara Notch |
|---|---|
| controls (nút nhanh) | Có: trang Công cụ |
| music, lyrics, equalizer | Có (lời bài hát có); thiếu hàng chờ phát, xáo trộn |
| clipboard, files, captures, scratchpad, calendar, timer, agents | Có (Clipboard, Tệp, Chụp, Ghi chú, Lịch, Hẹn giờ, Agent) |
| mixer (âm lượng từng app) | Không — khó, cần macOS 14.2+ |
| system (CPU, RAM, pin, mạng) | Không → N3 |
| notifications (sao thông báo macOS) | Không — khó, đọc Trung tâm thông báo qua Trợ năng, dễ vỡ |
| camera (soi gương) | Không → N5 |
| downloads (tiến độ tải) | Không → N4 |
| watch (canh một vùng màn hình) | Không → N6 |
| keep awake ở notch đóng | Không → N2 |
| đếm ngược sự kiện ở notch đóng | Chỉ có báo 10 giây → N1 |
| notch trên màn hình khoá | Không — không đề xuất (dựa vào cửa sổ trên màn hình khoá, rủi ro) |

## Đề xuất

Tính năng: N1 đếm ngược tới cuộc họp, N2 giữ máy thức, N3 trang Hệ thống, N4 tiến độ tải xuống, N5 soi gương camera, N6 canh chừng một vùng.

Giao diện mới (thêm vào C1–C5, D1–D11):
- U1 mép cuộn mờ dần (`NotchScrollEdgeFade`).
- U2 trang thấp cuộn ngang, đủ chỗ thì xếp hàng đều (`NotchRail`).
- U3 đổi hoạt động ở cánh qua màu đen (`NotchFadeThrough`).
- U4 sửa từ 3.4.4: huỷ cú bấm khi thông báo đổi trước lúc nhả chuột; vuốt ngang qua thanh trượt không đổi mức; thanh trượt chạm được hai đầu.

## Tệp tham khảo trong mã Vorssaint

- `UI/Notch/NotchComponents.swift`: kiểu nút, số lăn, rail, hàng trên cạnh camera, nền kính.
- `UI/Notch/NotchQuickAccessView.swift`: nút tròn nhỏ giọt ra từ notch.
- `Services/Notch/NotchSupport.swift`: danh sách trang, phím tắt, cỡ từng trang.
- `Services/Notch/NotchDownloadService.swift`: `Progress.addSubscriber(forFileURL:)`.
- `Services/Notch/NotchWatchSupport.swift`: luật canh (đổi, đứng yên, có chữ, đạt số).
- `Services/Notch/NotchCalendarSupport.swift`: đếm ngược 15/30/60/120 phút.

Giấy phép GPL-3.0 cùng họ với Ara Notch, nên có thể chép mã kèm ghi nguồn; tên và nhận diện của Vorssaint thì không dùng.
