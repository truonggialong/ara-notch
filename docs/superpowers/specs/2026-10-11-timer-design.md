# AraNotch — Hẹn giờ (mảng 9a) — Thiết kế

Ngày: 2026-10-11 · Dựa trên: `2026-10-11-notch-shell-design.md`, `2026-10-11-live-activities-design.md`

## Mục tiêu

Đặt một bộ đếm ngược ngay trên notch, rồi quên nó đi: khi notch đóng, thời gian còn lại hiện bên cạnh notch; khi hết giờ, notch báo và phát âm thanh.

## Phạm vi

Trong phạm vi: một bộ đếm ngược duy nhất; các mức sẵn 5, 15, 25, 45 phút và số phút tuỳ chọn (1 đến 180); tạm dừng, tiếp tục, huỷ; hiển thị bên notch khi đang đếm; báo hết giờ; tab Hẹn giờ trong Cài đặt với công tắc âm thanh.

Ngoài phạm vi: nhiều bộ đếm cùng lúc; phân loại Task, Reminder, Break; cảnh báo toàn màn hình; đọc bộ đếm của app Clock; giữ bộ đếm qua lần mở lại app.

## `TimerCore` (logic thuần)

### `CountdownTimer`

Trạng thái: `idle`, `running(endsAt:)`, `paused(remaining:)`, `finished`.

| Hàm | Hành vi |
|---|---|
| `start(duration:at:)` | Bắt đầu đếm, từ bất kỳ trạng thái nào. Thời lượng bị kẹp trong 1 giây đến 3 giờ |
| `pause(at:)` | Chỉ có tác dụng khi đang đếm; giữ lại phần còn lại |
| `resume(at:)` | Chỉ có tác dụng khi đang tạm dừng |
| `cancel()` | Về `idle` |
| `tick(at:)` | Khi đang đếm và đã tới giờ: chuyển sang `finished` và trả về đúng, đúng một lần |
| `remaining(at:)` | Phần còn lại, không bao giờ âm; 0 khi `idle` hoặc `finished` |
| `progress(at:)` | Phần đã trôi qua, 0…1 |

### `TimerFormat.clock(_:)`

Làm tròn lên tới giây: `59.2` → `1:00`, `1499` → `24:59`, `3900` → `1:05:00`, `0` → `0:00`.

### `TimerSettingsStore`

`timer.minutes` (Int, mặc định 25, kẹp 1…180), `timer.sound` (Bool, mặc định bật).

## `TimerFeature`

- Trang "Hẹn giờ" trên notch. Lúc rảnh: bốn nút mức sẵn, bộ chọn số phút và nút Bắt đầu. Lúc đang đếm: đồng hồ lớn, thanh tiến độ, nút Tạm dừng và Huỷ. Lúc tạm dừng: Tiếp tục và Huỷ. Lúc hết giờ: thông báo và nút Đặt lại.
- Bộ hẹn giờ 1 giây một lần chỉ chạy khi đang đếm.
- Khi đang đếm: một hoạt động trực tiếp (ưu tiên 1) hiện biểu tượng đồng hồ bên trái và thời gian còn lại bên phải, được làm mới mỗi giây. Thông báo hệ thống có ưu tiên cao hơn sẽ tạm che nó.
- Khi hết giờ: hoạt động ưu tiên 3 trong 6 giây ("Hết giờ"), và âm thanh hệ thống nếu công tắc bật.

## Kiểm thử

Kiểm thử đơn vị cho `CountdownTimer`, `TimerFormat`, `TimerSettingsStore`. Kiểm chứng trên app thật: tham số `--timer <giây>` bắt đầu đếm khi khởi động; ảnh trang và ảnh notch đóng lúc đang đếm; chờ hết giờ và xác nhận hoạt động "Hết giờ"; thử bấm nút bằng chuột thật.

## Tiêu chí hoàn thành

1. `Scripts/test.sh` qua toàn bộ.
2. Bắt đầu, tạm dừng, tiếp tục, huỷ đều chạy bằng chuột thật.
3. Notch đóng hiện thời gian còn lại và giảm dần; hết giờ thì báo.
