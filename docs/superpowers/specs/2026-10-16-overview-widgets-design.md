# AraNotch — Tổng quan kiểu widget — Thiết kế

Ngày: 2026-10-16 · Dựa trên: vòng P (trang Tổng quan, 0.3.0), vòng R (Tổng quan bảy ô, 0.5.0), `2026-10-11-notch-shell-design.md`

## Mục tiêu

Chủ dự án muốn tự sắp xếp trang Tổng quan như widget của macOS: chọn ô nào hiện, ở đâu, cỡ nào, và sắp xếp ngay trên notch. Hiện nay bảy ô đứng cố định trong ba cột, chỉ bật tắt được trong Cài đặt.

Các lựa chọn của chủ dự án (2026-10-16):

- Mục tiêu: tự sắp xếp như widget (không phải thêm ô mới hay đổi nội dung theo ngữ cảnh).
- Sửa ngay trên notch, không trong Cài đặt.
- Lưới 4 cột, ba cỡ ô: nhỏ 1×1, rộng 2×1, lớn 2×2.
- Khi ô không vừa hai hàng, notch dài thêm hàng (chiều rộng không đổi).
- Cách làm: danh sách có thứ tự, ô tự dồn vào chỗ trống đầu tiên vừa nó.
- Bố cục mặc định giữ đúng chiều cao hiện nay (hai hàng), Công cụ nhanh mặc định tắt.

## Phạm vi

Trong phạm vi: mô hình bố cục và cách xếp trong `NotchCore`; lưu bố cục và chuyển từ `hiddenOverviewWidgets`; bảy ô hiện có, mỗi ô ba cỡ; chế độ sửa trên notch (bỏ ô, đổi cỡ, kéo đổi chỗ, thêm ô); notch dài theo số hàng; Cài đặt có nút Đặt lại bố cục.

Ngoài phạm vi: ô mới (ghi chú, thời tiết, CPU...); một tính năng xuất hiện hai lần; để trống ô ở giữa lưới; nhiều màn Tổng quan; nội dung đổi theo ngữ cảnh; sửa bố cục trong Cài đặt; nút mũi tên dời chỗ thay cho kéo.

## `NotchCore` (logic thuần)

### Kiểu dữ liệu

| Kiểu | Nội dung |
|---|---|
| `OverviewWidget` | Giữ nguyên: `media, calendar, timer, clipboard, tools, agents, device` |
| `OverviewTileSize` | `small` (1×1), `wide` (2×1), `large` (2×2); có `columns`, `rows`, `next` (nhỏ → rộng → lớn → nhỏ) |
| `OverviewItem` | `widget` và `size` |
| `OverviewPlacement` | `item`, `column`, `row` (ô trên cùng bên trái) |
| `OverviewArrangement` | Danh sách `OverviewItem` theo thứ tự; mỗi `widget` nhiều nhất một lần |

### `OverviewGrid`

Hằng số: 4 cột; ít nhất 2 hàng; nhiều nhất 4 hàng (16 ô nhỏ).

| Hàm | Hành vi |
|---|---|
| `place(_ items:)` | Đặt từng ô theo thứ tự vào chỗ trống đầu tiên vừa nó, quét từ trái sang phải rồi từ trên xuống. Ô nhỏ phía sau được dồn lên lấp chỗ trống mà ô rộng để lại. Trả về các `OverviewPlacement` và số hàng dùng tới (ít nhất 2) |
| `fits(_ items:)` | Đúng khi `place` không cần quá 4 hàng |
| `resized(_ items:, widget:)` | Đổi cỡ của một ô sang cỡ kế tiếp; nếu cỡ mới không vừa thì bỏ qua cỡ đó và thử cỡ sau nữa; trả về `nil` khi chỉ còn đúng cỡ đang có (nút cỡ báo "Hết chỗ") |
| `moved(_ items:, widget:, to index:)` | Đưa một ô tới vị trí `index` trong danh sách |
| `adding(_ items:, widget:)` | Thêm ô ở cỡ nhỏ vào cuối; `nil` khi đã có ô đó hoặc không còn chỗ |
| `removing(_ items:, widget:)` | Bỏ ô khỏi danh sách |
| `sheetHeight(rows:)` | `nil` cho 2 hàng (tờ thường); từ 3 hàng là chiều cao tờ thường cộng (số hàng − 2) × (chiều cao hàng + khoảng cách giữa ô). Chiều cao hàng lấy từ trang hiện nay: hai hàng chia đều chiều cao vùng trang |

### Lưu trữ

- Khoá mới `shell.overviewArrangement`: mảng chuỗi `"<widget>:<size>"`, ví dụ `["media:wide", "calendar:wide", "timer:small"]`.
- Khi đọc: bỏ chuỗi không hợp lệ, bỏ `widget` trùng (giữ lần đầu), rồi bỏ các ô cuối danh sách cho tới khi vừa 4 hàng.
- Khi khoá mới chưa có: dựng bố cục mặc định, bỏ những ô có trong `shell.hiddenOverviewWidgets`. Khoá cũ chỉ được đọc cho lần chuyển này và không ghi nữa.
- Khoá mới có nhưng là mảng rỗng nghĩa là chủ dự án đã bỏ mọi ô; không dựng lại mặc định.

### Bố cục mặc định

`media:wide, calendar:wide, timer:small, agents:small, clipboard:small, device:small` — vừa đúng hai hàng. `tools` mặc định tắt (đã có trang Công cụ riêng).

`OverviewLayout.columns(hidden:)`, `fills(_:in:)`, mảng `arrangement` và `growing` bị bỏ; `widgets(hidden:)` được thay bằng bố cục đã lưu. `pageID` và `orderWithOverview(_:)` giữ nguyên.

## Ba cỡ cho mỗi ô

`AraOverviewTile` (NotchShell/Design) nhận cỡ của ô qua một giá trị environment mới `\.araTileSize`; trang Tổng quan đặt giá trị này cho từng ô. Mỗi tính năng tự vẽ ba dạng; trang chỉ đặt ô vào lưới, như quyết định của vòng P.

| Ô | Nhỏ 1×1 | Rộng 2×1 | Lớn 2×2 |
|---|---|---|---|
| Nhạc | Ảnh bìa, tên bài, nút phát/tạm dừng | Ảnh, tên, ca sĩ, ba nút (như nay) | Ảnh lớn, tên, ca sĩ, thanh tiến độ, ba nút, dòng lời bài hát đang hát (khi bật lời bài hát) |
| Hôm nay | Việc kế tiếp và thời gian còn lại ("còn 12′") | Ba dòng sự kiện và lời nhắc (như nay) | Sáu dòng, nút Tham gia cho sự kiện có link họp, bấm vòng tròn để đánh dấu xong lời nhắc |
| Hẹn giờ | Bộ đếm sắp hết nhất, bấm để tạm dừng; chưa có thì một mức sẵn | Đồng hồ, +1′, tạm dừng; chưa có thì ba mức sẵn (như nay) | Tới bốn bộ đếm, mỗi bộ có +1′ và tạm dừng; chưa có thì các mức sẵn |
| Clipboard | Clip mới nhất, bấm để dán | Ba thẻ nhỏ (như nay) | Sáu thẻ, hai hàng ba thẻ |
| Agent | Một chấm gộp và một dòng ("1 chờ bạn", "2 đang chạy") | Hai phiên (như nay) | Năm phiên và vạch giới hạn của Claude và Codex |
| Máy | Pin phần trăm và mức âm lượng | Thanh pin và thanh âm lượng (như nay) | Pin, âm lượng, đầu ra âm thanh đang dùng, thiết bị Bluetooth đang nối* |
| Công cụ | Bốn nút tròn nhỏ, 2 × 2 | Bốn nút một hàng (như nay) | Mọi công cụ của trang Công cụ, hai hàng |

\* Hiện app chỉ nhận sự kiện nối và ngắt Bluetooth. Nếu không đọc được danh sách thiết bị đang nối mà không cần quyền mới, dòng này bị bỏ và ghi vào phần giới hạn.

Ô nhỏ chỉ có icon trên dòng tên (không có chữ) để đủ chỗ cho nội dung; bấm icon vẫn mở trang của tính năng. Ô rộng và ô lớn giữ dòng tên như nay.

## Sửa trên notch

### Vào và ra

- Khi trang Tổng quan đang hiện, hàng tab có thêm nút bút chì, cạnh nút ghim và nút Cài đặt. Menu chuột phải của mọi ô có mục "Sửa bố cục".
- Trong chế độ sửa nút bút chì thành nút Xong. Bấm Xong, bấm ra ngoài notch hoặc sang trang khác thì thoát chế độ sửa.
- Mỗi thay đổi được lưu ngay; không có Huỷ.

### Trong chế độ sửa

- Notch được giữ mở bằng `setKeepsOpen(true, forPage: "overview")`, như bộ chọn ngày của trang Lịch.
- Nội dung ô không nhận cú bấm (không dán, không dừng nhạc); các ô rung nhẹ.
- Góc trên bên trái mỗi ô: nút − bỏ ô.
- Góc dưới bên phải mỗi ô: nút cỡ, đổi vòng nhỏ → rộng → lớn theo `resized`. Khi không còn cỡ nào vừa, nút lắc và hiện "Hết chỗ".
- Kéo một ô (SwiftUI `DragGesture` trong notch, không dùng kéo thả của hệ thống): các ô khác dồn lại ngay theo vị trí sẽ thả, notch dài ra hoặc ngắn lại theo số hàng. Thả ra ngoài lưới thì ô về chỗ cũ.
- Cuối lưới là ô "+ Thêm ô" (khi còn chỗ cho một ô nhỏ và còn tính năng đang tắt). Bấm thì hiện các tính năng đang tắt thành chip mang màu trang của chúng; bấm một chip để thêm ô ở cỡ nhỏ. Ô "+ Thêm ô" chiếm một ô nhỏ và được tính vào số hàng trong lúc sửa, nên notch có thể dài thêm một hàng trong chế độ sửa rồi ngắn lại khi thoát.

### Trang trống

Khi không còn ô nào, trang hiện trạng thái trống có nút "+ Thêm ô", bấm vào là vào chế độ sửa với danh sách chip mở sẵn.

## Chiều cao notch

`OverviewPage` báo `OverviewGrid.sheetHeight(rows:)` qua `NotchController.setSheetHeight(_:forPage:)` mỗi khi số hàng đổi, kể cả trong lúc kéo. Trần 80% chiều cao màn hình của `PageHeight` vẫn áp dụng.

## Cài đặt

Trong Cài đặt › Trang notch, hàng chip bật tắt ô Tổng quan (`settings.overview`) được thay bằng một dòng "Sắp xếp các ô ngay trên notch: bấm nút bút chì trên trang Tổng quan" và nút "Đặt lại bố cục" (trả về bố cục mặc định). Tìm kiếm trong Cài đặt vẫn tìm được mục này.

## Lỗi và trường hợp biên

- Dữ liệu lưu hỏng: xử lý như phần Lưu trữ, không bao giờ làm app dừng.
- Một tính năng chưa tạo được ô (ví dụ tính năng đó tắt hẳn): chỗ của nó vẫn giữ trong bố cục, ô hiện trống với tên tính năng, để bố cục không nhảy.
- Cỡ notch 100% đến 150%: lưới tính trên tờ gốc 640 × 200 rồi phóng theo `araScale`, như mọi trang khác.
- Màn hình không có tai thỏ và kiểu viên thuốc: không có gì khác.

## Kiểm thử

Tự động (`NotchCoreTests`):

- `place`: thứ tự, dồn ô nhỏ vào chỗ trống, số hàng tối thiểu 2, các bố cục mẫu.
- `fits`, `resized` (bỏ qua cỡ không vừa, trả `nil`), `moved`, `adding` (trùng, hết chỗ), `removing`.
- `sheetHeight` cho 2, 3, 4 hàng.
- Lưu trữ: đọc chuỗi hợp lệ, chuỗi hỏng, trùng, quá chỗ, mảng rỗng; chuyển từ `hiddenOverviewWidgets`; bố cục mặc định vừa hai hàng.

Ảnh chụp: bảy ô ở ba cỡ, tiếng Anh và tiếng Việt, với dữ liệu thật của máy; trang ở 2, 3 và 4 hàng; chế độ sửa.

Thử tay trên notch thật: vào và ra chế độ sửa, bỏ ô, đổi cỡ tới "Hết chỗ", kéo đổi chỗ, thêm ô, Đặt lại bố cục; notch không tự đóng trong lúc sửa; bố cục còn nguyên sau khi mở lại app.
