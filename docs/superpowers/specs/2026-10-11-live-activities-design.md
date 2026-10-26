# AraNotch — Thông báo hệ thống trên notch (mảng 5a) — Thiết kế

Ngày: 2026-10-11 · Dựa trên: `2026-10-11-notch-shell-design.md`

## Mục tiêu

Khi notch đang đóng, nó nở sang hai bên trong vài giây để báo một sự kiện của máy: cắm hoặc rút sạc, pin yếu, pin đầy, bật tắt Caps Lock, mất mạng.

## Phạm vi

Trong phạm vi:

- Cơ chế "hoạt động trực tiếp" của khung notch: một nội dung bên trái và một nội dung bên phải notch, hiện có thời hạn, có mức ưu tiên và hàng đợi.
- Ba nguồn sự kiện, đều không cần quyền hệ thống: nguồn điện và pin, Caps Lock, kết nối mạng.
- Mục "Thông báo" trong Cài đặt: ba công tắc, mặc định bật.

Ngoài phạm vi (5b): thiết bị Bluetooth, thay HUD âm lượng và độ sáng, hẹn giờ nhanh, kiểu hiển thị chi tiết.

## Hoạt động trực tiếp trong khung notch

### `LiveActivityQueue` (`NotchCore`, logic thuần)

Quyết định hoạt động nào đang hiện. Mỗi yêu cầu có `id`, `priority` (số lớn hơn là quan trọng hơn) và `duration`.

- `present(_:at:)`:
  - Chưa có gì đang hiện: hiện ngay, hết hạn sau `duration`.
  - Cùng `id` với cái đang hiện: thay nội dung và tính lại thời hạn từ lúc này.
  - Ưu tiên cao hơn hoặc bằng cái đang hiện: thay thế ngay; cái bị thay không quay lại.
  - Ưu tiên thấp hơn: vào hàng chờ. Hàng chờ giữ tối đa 3 yêu cầu; yêu cầu cùng `id` trong hàng bị thay bằng bản mới; khi đầy thì bỏ yêu cầu có ưu tiên thấp nhất (nếu bằng nhau thì bỏ cái cũ nhất).
- `advance(to:)`: khi cái đang hiện hết hạn, lấy yêu cầu ưu tiên cao nhất trong hàng chờ (bằng nhau thì cái vào trước), hết hạn sau `duration` tính từ lúc đó. Hàng rỗng thì không hiện gì.
- `dismiss(id:)`: bỏ một yêu cầu, dù đang hiện hay đang chờ.
- `current`: yêu cầu đang hiện; `nextDeadline`: thời điểm cần gọi `advance` lần tới.

### Hình học

`NotchGeometry.compactRect(sideWidth:)`: hình chữ nhật cao bằng notch, rộng `closedRect.width + 2 × sideWidth`, căn giữa theo notch, bám mép trên. Bề rộng mỗi bên mặc định 92 điểm.

### Hiển thị

- `NotchLiveActivity`: `id`, `priority`, `duration`, view bên trái, view bên phải.
- `NotchController.present(_:)` và `dismissActivity(id:)`.
- Hoạt động chỉ hiện khi notch đóng. Mở notch thì ẩn; đóng lại mà chưa hết hạn thì hiện tiếp.
- Hình đen nở từ kích thước notch sang `compactRect` bằng cùng hiệu ứng lò xo; nội dung hai bên mờ dần vào.
- Cửa sổ vẫn bỏ qua chuột khi notch đóng, nên hoạt động không chặn thanh menu và không bấm được.

## Nguồn sự kiện (`SystemEventsCore`, logic thuần)

### `PowerEventDetector`

Nhận các `PowerSnapshot` liên tiếp (`isOnAC`, `isCharging`, `percent` 0…100, hoặc không có pin) và phát `PowerEvent`:

- `pluggedIn(percent)`: `isOnAC` chuyển từ sai sang đúng.
- `unplugged(percent)`: chuyển từ đúng sang sai.
- `low(percent)`: khi đang dùng pin và phần trăm xuống tới 20 hoặc thấp hơn, và lần nữa khi tới 10 hoặc thấp hơn. Mỗi ngưỡng chỉ báo một lần cho tới khi cắm sạc lại.
- `full`: khi đang cắm sạc và phần trăm đạt 100, một lần cho mỗi lần cắm.
- Ảnh chụp đầu tiên không phát gì (không báo trạng thái lúc khởi động), trừ khi máy đang dùng pin và đã ở dưới ngưỡng: khi đó báo `low` một lần.
- Máy không có pin: không phát gì.

### `CapsLockDetector`

Phát `on` hoặc `off` khi trạng thái đổi so với lần đọc trước. Lần đọc đầu không phát gì.

### `ConnectivityDebouncer`

Nhận `update(isOnline:at:)` và `advance(to:)`:

- Mất kết nối liên tục 3 giây mới phát `offline`, để Wi-Fi chập chờn không gây phiền.
- Có lại kết nối sau khi đã báo `offline` thì phát `online` ngay.
- Có lại trước 3 giây thì không phát gì.
- Trạng thái lúc khởi động không phát gì, trừ khi máy đang mất mạng: báo `offline` sau 3 giây.

### Cài đặt

`alerts.power`, `alerts.capsLock`, `alerts.network`: Bool, mặc định bật.

## Theo dõi thật (`SystemEventsFeature`)

- `PowerMonitor`: đọc bằng IOKit `IOPSCopyPowerSourcesInfo`, nhận thông báo thay đổi qua `IOPSNotificationCreateRunLoopSource`.
- `CapsLockMonitor`: đọc `NSEvent.modifierFlags` mỗi 0,3 giây. Theo dõi phím toàn cục cần quyền Trợ năng, nên dùng cách đọc định kỳ.
- `NetworkMonitor`: `NWPathMonitor`.
- `SystemEventsController`: nối ba nguồn với `NotchController.present`, tôn trọng ba công tắc.

Nội dung từng hoạt động:

| Sự kiện | Bên trái | Bên phải | Thời hạn | Ưu tiên |
|---|---|---|---|---|
| Cắm sạc | biểu tượng pin có tia sét | phần trăm | 3 giây | 2 |
| Rút sạc | biểu tượng pin | phần trăm | 3 giây | 2 |
| Pin yếu | biểu tượng pin 25%, màu đỏ | phần trăm, màu đỏ | 5 giây | 3 |
| Pin đầy | biểu tượng pin đầy, màu xanh lá | "100%" | 3 giây | 2 |
| Caps Lock | biểu tượng Caps Lock | "BẬT" hoặc "TẮT" | 1,5 giây | 1 |
| Mất mạng | biểu tượng Wi-Fi gạch chéo, màu cam | "Mất mạng" | 4 giây | 3 |
| Có mạng lại | biểu tượng Wi-Fi | "Đã kết nối" | 2 giây | 2 |

## Trường hợp biên

| Tình huống | Xử lý |
|---|---|
| Nhiều sự kiện dồn dập | Hàng đợi theo ưu tiên; Caps Lock bật tắt liên tục chỉ làm mới cùng một hoạt động |
| Notch đang mở khi sự kiện tới | Hoạt động vẫn tính giờ; chỉ hiện nếu notch đóng lại trước khi hết hạn |
| Phần trăm pin dao động quanh ngưỡng | Mỗi ngưỡng chỉ báo một lần cho tới lần cắm sạc sau |
| Máy bàn không có pin | Không có thông báo nguồn |
| Tắt một công tắc khi hoạt động loại đó đang hiện | Hoạt động đó bị gỡ ngay |

## Kiểm thử

Kiểm thử đơn vị: `LiveActivityQueue`, `compactRect`, `PowerEventDetector`, `CapsLockDetector`, `ConnectivityDebouncer`, cài đặt.

Kiểm chứng trên app thật do Claude làm: tham số `--simulate-events` đưa sự kiện giả qua đúng bộ điều khiển (không đụng trạng thái thật của máy) rồi app tự vẽ notch ra ảnh; log ghi trạng thái pin và mạng thật đọc được lúc khởi động.

Cần người dùng tự thử: cắm rút sạc thật, nhấn Caps Lock thật, tắt Wi-Fi thật.

## Tiêu chí hoàn thành

1. `Scripts/test.sh` qua toàn bộ.
2. Mỗi sự kiện trong bảng hiện đúng nội dung hai bên notch trong ảnh tự vẽ.
3. App đọc được trạng thái pin và mạng thật của máy.
4. Tắt công tắc thì sự kiện loại đó không hiện.
