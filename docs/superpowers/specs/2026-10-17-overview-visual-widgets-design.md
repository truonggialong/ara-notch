# AraNotch — Widget hình ảnh cho Tổng quan, đợt 1 — Thiết kế

Ngày: 2026-10-17 · Dựa trên: `2026-10-16-overview-widgets-design.md` (Tổng quan kiểu widget, bản 0.25.0)

## Mục tiêu

Chủ dự án muốn đa dạng hoá widget: mỗi tính năng có nhiều kiểu widget khác hẳn nhau, mỗi kiểu là một ô riêng, nên một tính năng có thể có nhiều ô trên Tổng quan. Các widget mới ưu tiên thiết kế, không ưu tiên hiện thông tin bằng chữ: vòng, cung, ảnh, chấm màu, biểu tượng; chữ chỉ còn một con số khi thật cần.

Các lựa chọn của chủ dự án (2026-10-16 và 2026-10-17):

- Hướng: nhiều kiểu cho mỗi tính năng (không phải nhiều giao diện cho cùng một ô).
- Đợt 1 gồm 8 kiểu: Ảnh bìa, Đồng hồ ngày, Đĩa thời gian, Chồng thẻ, Bảng màu, Vòng giới hạn, Vòng thiết bị, Nút lớn. 15 kiểu còn lại của bản vẽ (bản vẽ có 23 kiểu; lúc hỏi tôi đếm nhầm là 22) (Đĩa xoay, Sóng nhạc, Loa, Tháng chấm, Dải thời gian, Cuộc họp tới, Vòng, Nhiều đĩa, Lưới ảnh, Copy Stack, Chấm phiên, Cột dùng, Pin lớn, Bậc âm lượng, Dải công cụ) để đợt sau.
- 7 ô hiện có giữ nguyên.
- Cách làm: mỗi kiểu mới là một ô riêng trong danh sách ô, như 7 ô cũ.

## Phạm vi

Trong phạm vi: 8 kiểu với cỡ, hình và cú bấm như dưới đây; cỡ cho phép theo từng kiểu; Nút lớn là một kiểu cho mỗi công cụ; mức pin thiết bị Bluetooth cho Vòng thiết bị; danh sách chip "Thêm ô" xếp theo tính năng.

Ngoài phạm vi: 15 kiểu của đợt sau; vẽ lại 7 ô cũ; một kiểu xuất hiện hai lần; nút đổi kiểu trên ô; tuỳ chọn riêng của từng ô.

## Mô hình (`NotchCore`)

### Kiểu ô

`OverviewWidget` thêm các trường hợp sau (giá trị lưu trong ngoặc):

| Kiểu | Giá trị lưu | Thuộc tính năng | Cỡ cho phép |
|---|---|---|---|
| Ảnh bìa | `albumArt` | Nhạc | nhỏ, lớn |
| Đồng hồ ngày | `dayClock` | Lịch | nhỏ, lớn |
| Đĩa thời gian | `timerDisc` | Hẹn giờ | nhỏ, lớn |
| Chồng thẻ | `clipStack` | Clipboard | nhỏ, lớn |
| Bảng màu | `colorPalette` | Clipboard | rộng, lớn |
| Vòng giới hạn | `usageRings` | Agent | nhỏ, lớn |
| Vòng thiết bị | `deviceRings` | Máy | rộng, lớn |
| Nút lớn, một kiểu mỗi công cụ | `tool.capture`, `tool.scroll`, `tool.text`, `tool.color`, `tool.translate`, `tool.panel`, `tool.library`, `tool.note` | Công cụ | nhỏ |

7 ô cũ giữ ba cỡ.

- `OverviewWidget.feature`: tính năng của kiểu (`media`, `calendar`, `timer`, `clipboard`, `agents`, `device`, `tools`), dùng cho màu, biểu tượng và thứ tự chip.
- `OverviewWidget.sizes`: các cỡ cho phép, từ nhỏ tới lớn.
- Mỗi kiểu vẫn nhiều nhất một lần trong bố cục; hai kiểu khác nhau của cùng một tính năng đặt cạnh nhau được.

### Thay đổi các phép tính

- `resized`: chỉ đi vòng qua các cỡ cho phép của kiểu đó (nhỏ → lớn → nhỏ với Ảnh bìa; rộng → lớn → rộng với Bảng màu); nút cỡ chỉ hiện khi kiểu có hơn một cỡ.
- `adding`: thêm ở cỡ nhỏ nhất cho phép của kiểu.
- `arrangement(from:)`: một mục có cỡ không cho phép thì lấy cỡ nhỏ nhất cho phép của kiểu, không bỏ mục.
- `showsAddTile` và `editingRows` giữ nguyên ý nghĩa: ô "Thêm ô" xuất hiện khi còn ít nhất một kiểu thêm được.
- Định dạng lưu `"<kiểu>:<cỡ>"` giữ nguyên; không có bước chuyển dữ liệu.

## Tám kiểu

Các kiểu hình ảnh không có dòng tên. Cả ô là hình vẽ, nền thẻ như các ô khác, màu theo tính năng (Nhạc trời, Lịch mù tạt, Hẹn giờ bạc hà, Clipboard đào, Agent tử đinh hương, Máy xô thơm). Tên kiểu hiện khi rê chuột và đọc được bằng VoiceOver.

| Kiểu | Nhỏ / rộng | Lớn | Bấm |
|---|---|---|---|
| Ảnh bìa | Ảnh bìa phủ kín ô, nút phát tròn ở góc dưới phải | Như nhỏ, thêm hai vạch tên bài và ca sĩ trên dải mờ ở đáy | Phát hoặc tạm dừng. Chưa có gì phát: biểu tượng nốt nhạc, bấm mở trang Nhạc |
| Đồng hồ ngày | Vòng 24 giờ, mỗi sự kiện có giờ của hôm nay là một cung, kim đỏ chỉ bây giờ | Như nhỏ, thêm chấm cho lời nhắc có giờ và vạch 0, 6, 12, 18 giờ | Mở trang Lịch. Chưa có quyền: vòng trống, bấm mở trang Lịch |
| Đĩa thời gian | Mặt đĩa, phần màu là thời gian còn lại của bộ đếm sắp hết nhất, thu dần theo giây | Như nhỏ, thêm số phút còn lại ở dưới | Tạm dừng hoặc tiếp tục; đã xong thì xoá. Không có bộ đếm: dấu + trong vòng nét đứt, bấm mở trang Hẹn giờ |
| Chồng thẻ | Ba thẻ xếp lệch, thẻ trên cùng là clip mới nhất, màu theo loại | Thẻ lớn hơn, thẻ trên cùng hiện ảnh thu nhỏ với clip ảnh, ba vạch với clip chữ | Dán clip trên cùng. Clip của bảng khoá không bao giờ hiện |
| Bảng màu | Tối đa 5 chấm màu (rộng), màu mới nhất có viền | Tối đa 10 chấm, hai hàng | Chép lại màu đó (như chép từ trang Clipboard). Chưa chép màu nào: các chấm trống nét đứt |
| Vòng giới hạn | Vòng ngoài là cửa sổ 5 giờ của Claude, vòng trong của Codex; số phần trăm của Claude ở giữa | Như nhỏ, thêm vạch mỏng cửa sổ 7 ngày bên ngoài mỗi vòng | Mở trang Agent; rê chuột: giờ đặt lại. Vòng nào chưa có số thì xám |
| Vòng thiết bị | Một vòng mỗi thiết bị: Mac trước, rồi thiết bị Bluetooth đang nối; vòng là pin, biểu tượng thiết bị ở giữa (rộng: tối đa 4) | Tối đa 8, hai hàng | Không làm gì; rê chuột: tên thiết bị và phần trăm |
| Nút lớn | Một nút tròn lớn màu công cụ, biểu tượng trắng ở giữa | — | Chạy công cụ (notch đóng trước, như trang Công cụ) |

Trong chế độ sửa, các kiểu hình ảnh có nút bỏ và nút cỡ như ô cũ; nội dung không nhận bấm.

## Pin thiết bị Bluetooth

- macOS liệt kê mức pin của thiết bị Apple qua `system_profiler SPBluetoothDataType -json` (đã thấy trên máy chủ dự án: hộp sạc, tai trái, tai phải của AirPods) mà không cần quyền mới.
- `SystemEventsCore` thêm bộ đọc thuần: từ JSON đó ra danh sách thiết bị đang nối với tên, loại (theo `BluetoothDeviceKind` sẵn có) và mức pin. Thiết bị có pin trái và phải thì lấy mức thấp hơn; hộp sạc không tính. Thiết bị không có mức pin thì vòng xám.
- `SystemEventsFeature` chạy lệnh đó ở nền khi trang Tổng quan đang hiện và có ô Vòng thiết bị, rồi mỗi 2 phút; lệnh lỗi hay chậm quá 5 giây thì giữ kết quả cũ.
- Pin của Mac lấy từ phần đọc pin sẵn có.

## Đồng hồ ngày: vị trí trên vòng

`CalendarCore` thêm hàm thuần đổi một thời điểm trong ngày thành góc trên vòng 24 giờ (0 giờ ở trên cùng, theo chiều kim đồng hồ) và một sự kiện thành cung (cắt ở 0 giờ và 24 giờ nếu sự kiện bắt đầu hôm trước hay kết thúc hôm sau). Sự kiện cả ngày không vẽ.

## Thêm ô

- Chip trong danh sách "Thêm ô" xếp theo tính năng (Nhạc, Lịch, Hẹn giờ, Clipboard, Agent, Máy, Công cụ), trong mỗi tính năng ô cũ trước, kiểu mới sau; mỗi chip mang màu và biểu tượng của tính năng.
- Chip của Nút lớn ghi tên công cụ, biểu tượng công cụ.
- Kiểu có cỡ nhỏ nhất là rộng chỉ có chip khi còn chỗ cho một ô rộng.

## Lỗi và trường hợp biên

- Ảnh bìa khi ứng dụng nhạc không có ảnh: nền màu trời với biểu tượng ứng dụng đang phát.
- Đồng hồ ngày với hơn 12 sự kiện: vẽ đủ, cung chồng nhau thì mờ hơn.
- Bảng màu: màu trùng nhau chỉ hiện một lần.
- Vòng thiết bị khi Bluetooth tắt hay không có thiết bị: chỉ vòng của Mac; Mac không có pin: biểu tượng ổ điện, vòng đầy.
- Một kiểu lưu trong bố cục mà bản sau bỏ đi: bỏ qua khi đọc, như hiện nay.

## Kiểm thử

Tự động:

- `NotchCoreTests`: cỡ cho phép của từng kiểu; `resized` đi vòng chỉ qua cỡ cho phép và trả `nil` cho Nút lớn; `adding` ở cỡ nhỏ nhất cho phép; `arrangement(from:)` sửa cỡ không cho phép; `showsAddTile` với kiểu chỉ có cỡ rộng khi chỉ còn chỗ cho ô nhỏ; mọi kiểu có tính năng và tên.
- `CalendarCoreTests`: góc của 0, 6, 12, 18 giờ; cung của sự kiện qua nửa đêm; sự kiện cả ngày không có cung.
- `SystemEventsCoreTests`: đọc JSON mẫu của `system_profiler` (AirPods trái, phải, hộp; chuột có một mức pin; thiết bị không có mức pin; thiết bị không nối bị bỏ).
- `Scripts/test.sh` toàn bộ.

Ảnh chụp (bản thử với `--overview-arrangement`): từng kiểu ở mỗi cỡ cho phép, có và không có dữ liệu, tiếng Anh và tiếng Việt; chế độ sửa với danh sách chip xếp theo tính năng.

Thử tay (chủ dự án): bấm từng kiểu, thêm và bỏ, đổi cỡ.
