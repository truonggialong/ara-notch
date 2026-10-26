# AraNotch — Bộ widget mới cho Tổng quan — Thiết kế

Ngày: 2026-10-18 · Dựa trên: `2026-10-16-overview-widgets-design.md` (lưới, cỡ, chế độ sửa), `2026-10-17-overview-visual-widgets-design.md` (đợt widget hình ảnh, được thay thế)

## Mục tiêu

Chủ dự án gửi hai ảnh mẫu "macOS | Custom Widget" (Kawsar Ahmed) và yêu cầu làm một bộ widget mới học theo cách thiết kế đó: hiển thị tối ưu, dễ quan sát, dễ dùng nhờ màu tương phản. Về cỡ: có thu nhỏ và phóng to; mỗi cỡ là một cách hiển thị khác nhau, nhưng không theo hướng "to hơn thì nhiều thông tin hơn": cỡ nhỏ đã đủ thông tin, cỡ to hơn chi tiết hơn, cỡ to nhất chi tiết hơn và nhiều hơn.

Điều rút ra từ ảnh mẫu: một con số chính thật to; nhãn nhỏ ở trên, con số ở giữa, số phụ có nhãn ở dưới; một màu nhấn mỗi ô cho thanh tiến độ, thanh chia khúc, nút tròn, chip trạng thái ở góc phải; hình chỉ bổ trợ, chữ và số luôn có.

Các lựa chọn của chủ dự án (2026-10-18):

- Bộ mới thay cả 15 kiểu hiện có (7 ô chữ và 8 ô hình ảnh của bản 0.26.0 chưa phát hành).
- Toàn thẻ tối trên notch đen; tương phản nằm ở màu nhấn.
- Màu nhấn: màu trang hiện có, làm đậm và sáng hơn; khi cần chú ý thì chuyển cam đỏ.
- Một kiểu cho mỗi tính năng, ba cỡ thật khác nhau: Nhạc, Lịch, Hẹn giờ, Clipboard, Agent, Máy, Công cụ.
- Hai đợt bản vẽ (trong cuộc trò chuyện) được duyệt "đúng hướng"; cách làm dưới đây được duyệt.

## Phạm vi

Trong phạm vi: 7 ô mới, mỗi ô ba cỡ; bộ thành phần dùng chung; màu nhấn và quy tắc cảnh báo; chuyển bố cục đã lưu sang bộ mới; bỏ 15 kiểu hình ảnh.

Ngoài phạm vi: thẻ sáng; nút đổi sáng/tối; ô cho tính năng chưa có ô (Tệp, Dịch); đổi lưới, cách đổi cỡ, kéo thả, chế độ sửa.

## Mô hình (`NotchCore`)

- `OverviewWidget` chỉ còn `media, calendar, timer, clipboard, tools, agents, device`, mỗi kiểu ba cỡ `[.small, .wide, .large]`. Bỏ `albumArt, dayClock, timerDisc, clipStack, colorPalette, usageRings, deviceRings, tool.*`, cùng `isVisual` và `toolID`.
- `OverviewGrid.arrangement(from:)` đọc giá trị cũ: `albumArt` → `media`, `dayClock` → `calendar`, `timerDisc` → `timer`, `clipStack` và `colorPalette` → `clipboard`, `usageRings` → `agents`, `deviceRings` → `device`, `tool.<bất kỳ>` → `tools`; giữ cỡ đã lưu (cả ba cỡ đều hợp lệ); kiểu đã có trong danh sách thì bỏ mục sau (giữ mục đầu). Giá trị lạ vẫn bị bỏ như nay.
- `OverviewAlert` (mới): các hàm thuần cho biết lúc nào dùng màu cảnh báo:
  - `battery(percent:isCharging:)`: đúng khi không sạc và `percent <= 20`.
  - `usage(percent:)`: đúng khi `percent >= 90`.
  - `timer(remaining:isFinished:)`: đúng khi đã hết giờ hoặc `remaining < 60` giây.
  - `agents(waiting:)`: đúng khi `waiting > 0`.

## Bộ thành phần dùng chung (`NotchShell/Design`)

| Thành phần | Mô tả |
|---|---|
| `AraWidget` | Thẻ tối `#1E1E1E`, bo 14, lề 9 × 11; nhận `hue` (màu nhấn của tính năng), tên (chú giải và VoiceOver), hành động khi bấm cả ô (tuỳ chọn) |
| `AraWidgetHeader` | Dòng trên: nhãn nhỏ màu chữ phụ `#9A9A9A` bên trái, chip trạng thái bên phải |
| `AraStatusChip` | Chip bo tròn, nền là màu nhấn tối, chữ là màu nhấn; dạng cảnh báo dùng cam đỏ |
| `AraBigValue` | Con số chính, chữ đậm vừa, cỡ 24 (nhỏ), 26 (rộng), tuỳ ô ở cỡ lớn |
| `AraTrackBar` | Thanh tiến độ cao 5 trên nền `#333`, có thể có nhiều đoạn (dải giờ) và một vạch "bây giờ" |
| `AraSegmentBar` | Thanh chia 5 khúc (pin) |
| `AraRoundButton` | Nút tròn 26: dạng chính nền màu nhấn chữ tối, dạng phụ nền `#2A2A2A` |
| `AraStatRow` | Hàng 2–3 số phụ, mỗi số có nhãn |

Màu nhấn (`AraPalette.vivid(_ hue:)`): Nhạc `#4FA8FF`, Lịch `#FFC23D`, Hẹn giờ `#2EE6A6`, Clipboard `#FF8A5B`, Agent `#A98BFF`, Máy `#9BE15D`; cảnh báo `AraPalette.alert` `#FF5A1F`. Công cụ: mỗi công cụ một màu (bảng `NotchTool.looks`, dùng bản vivid). Chữ chính `#F2F2F2`, chữ phụ `#9A9A9A`. Mọi chữ có cỡ tối thiểu 10,5 × `araScale`.

## Bảy ô

Nhỏ đã đủ thông tin; rộng chi tiết hơn; lớn chi tiết hơn và nhiều mục hơn. Bấm vào chỗ trống của ô (không phải nút) mở trang của tính năng.

### Nhạc
- Nhỏ: ảnh bìa nhỏ, tên bài, ca sĩ; thanh tiến độ; nút phát/dừng tròn màu nhấn.
- Rộng: ảnh lớn hơn, tên bài, "ca sĩ · ứng dụng"; ba nút (lùi, phát/dừng, tới); thanh tiến độ có giờ đã chạy và giờ còn lại.
- Lớn: ảnh 78; nhãn "Đang phát", chip tên ứng dụng; tên bài, ca sĩ; dòng lời bài hát đang hát (khi bật lời); thanh tiến độ có giờ; ba nút; loa đang phát và mức âm lượng.
- Chưa phát gì: nhãn "Đang phát", "Chưa có gì đang phát", các nút mở nhanh ứng dụng nhạc (rộng, lớn).

### Lịch
- Nhỏ: nhãn "Tiếp theo", chip "còn 40′"; giờ việc kế tiếp to (14:00); tên việc.
- Rộng: "Tiếp theo · còn 40′", giờ to và tên việc trên một dòng; chip số việc còn lại hôm nay; dải giờ cả ngày với các việc là đoạn màu nhấn và vạch "bây giờ" cam đỏ.
- Lớn: "Hôm nay · thứ, ngày", chip số việc; tới 6 dòng: sự kiện có vạch màu, giờ, tên, nút "Tham gia" khi có link họp hoặc thời lượng; lời nhắc có vòng tròn bấm để xong; dải giờ ở đáy.
- Không còn việc: "Hôm nay · không còn việc"; chưa có quyền: nút xin quyền như trang Lịch.
- Số việc và việc kế tiếp lấy từ `DaySummary`, `NextUp`; vị trí trên dải giờ từ `DayRing.fraction`.

### Hẹn giờ
- Nhỏ: nhãn "Hẹn giờ", chip trạng thái ("Đang chạy", "Tạm dừng", "Hết giờ"); thời gian còn lại to; thanh tiến độ. Bấm ô: dừng hoặc chạy tiếp.
- Rộng: "tên · độ dài", thời gian to; nút +1′, nút dừng/chạy, nút huỷ; thanh tiến độ.
- Lớn: chip "n đang chạy"; tới 4 bộ đếm, mỗi bộ tên, thời gian, thanh; hàng mức sẵn và nút "+ Mới".
- Không có bộ đếm: nhãn "Hẹn giờ", các mức sẵn (nhỏ: 2, rộng: 3, lớn: 4 và "+ Mới").
- Cảnh báo (`OverviewAlert.timer`): số và thanh cam đỏ.

### Clipboard
- Nhỏ: nhãn "Mới chép", thời gian; tên ngắn của mục mới nhất (hai dòng); "Bấm để dán". Bấm ô: dán mục đó.
- Rộng: "Clipboard · hôm nay", chip số mục hôm nay; ba thẻ mới nhất theo màu loại, bấm thẻ để dán.
- Lớn: như rộng nhưng sáu thẻ có thời gian chép; hàng chấm màu đã chép (`ColorPalette.recent`), bấm chấm để chép lại.
- Mục của bảng khoá không bao giờ hiện.

### Agent
- Nhỏ: nhãn "Agent", chip "n chờ bạn" (cam đỏ) khi có; số phiên to; thanh "Claude" 5 giờ với phần trăm.
- Rộng: hai phiên đầu (chấm trạng thái, tên, trạng thái), chip "+n"; thanh "Claude 5 giờ".
- Lớn: "Agent · n phiên", chip chờ bạn; tới 5 phiên với trạng thái và thời gian; Claude và Codex: thanh 5 giờ, thanh mảnh 7 ngày, giờ đặt lại.
- Chưa có phiên: "Chưa có agent nào chạy" và thanh Claude nếu có số.
- Cảnh báo: phiên chờ bạn (chấm, chip), mức dùng từ 90%.

### Máy
- Nhỏ: nhãn "Pin · Mac", chip giờ còn lại; phần trăm to; thanh chia 5 khúc.
- Rộng: phần trăm to "Pin · còn ~4 giờ", chip "Đang sạc" khi sạc; thanh âm lượng và tên loa đang phát.
- Lớn: "Pin và thiết bị"; một hàng mỗi thiết bị: Mac, các thiết bị Bluetooth đang nối (`BluetoothBatteryReader`), mỗi hàng biểu tượng, tên, thanh, phần trăm; hàng âm lượng.
- Mac không có pin: "Điện lưới". Cảnh báo pin thấp từng hàng.

### Công cụ
- Nhỏ: bốn công cụ hay dùng (chụp vùng, đọc chữ, lấy màu, dịch), nút tròn màu và tên ngắn.
- Rộng: bốn công cụ, tên đầy đủ.
- Lớn: tám công cụ, hai hàng.

## Dọn dẹp

Bỏ các tệp và mã của bản hình ảnh không còn dùng: `AlbumArtTile`, `TimerDiscTile`, `DayClockTile`, `ClipStackTile`, `ColorPaletteTile`, `UsageRingsTile`, `DeviceRingsTile`, `BigToolTile`, `AraVisualTile`, các chuỗi `overview.tile.<kiểu hình ảnh>` và `overview.caption.*` không còn dùng. Giữ `DayRing`, `DaySummary`, `NextUp`, `ColorPalette`, `BluetoothBatteries`, `BluetoothBatteryReader`, `AgentHeadline`, `UsageMeter.resetText`.

## Kiểm thử

Tự động:
- `NotchCoreTests`: chuyển từng kiểu cũ sang kiểu mới, giữ cỡ; mục trùng bỏ mục sau; 7 kiểu đều ba cỡ; các test lưới hiện có vẫn qua (sửa những test dùng kiểu đã bỏ).
- `NotchCoreTests`: bốn hàm `OverviewAlert` với giá trị biên (20%, 21%, đang sạc; 89%, 90%; 59 giây, 60 giây, hết giờ; 0 và 1 phiên chờ).
- `Scripts/test.sh` toàn bộ.

Ảnh chụp: 7 ô × 3 cỡ, có và không có dữ liệu, tiếng Việt và tiếng Anh, một ảnh có cảnh báo (pin thấp không có thật thì chụp hàng thiết bị Bluetooth hoặc dùng bộ đếm sắp hết).

Thử tay qua trợ năng: bấm các nút của từng ô ở từng cỡ, chế độ sửa đổi cỡ đủ ba cỡ.
