# AraNotch — Khung notch (mảng 1) — Thiết kế

Ngày: 2026-10-11 · Lộ trình tổng: `2026-10-11-aranotch-roadmap.md`

## Mục tiêu

Một app chạy nền hiển thị một hình đen trùng khít notch. Khi rê chuột hoặc bấm vào notch, hình đó nở ra thành một bảng chứa các trang. Mọi mảng tính năng sau này chỉ cần đăng ký một trang vào khung này.

## Phạm vi

Trong phạm vi:

- App dạng agent (không có icon Dock), có icon trên thanh menu với hai mục: mở Cài đặt và Thoát.
- Hình notch đóng trùng khít notch vật lý. Trên màn hình không có notch, dùng một notch ảo đặt giữa mép trên.
- Mở khi rê chuột (có độ trễ chỉnh được) hoặc khi bấm. Đóng khi con trỏ rời bảng (có độ trễ ân hạn) hoặc khi bấm ra ngoài.
- Hiệu ứng lò xo khi đóng mở, rung phản hồi khi mở.
- Hệ thống trang: đăng ký trang, thanh tab ở đầu bảng, chuyển trang bằng bấm tab hoặc vuốt ngang hai ngón trên hàng đầu bảng (phần còn lại để trang tự cuộn nội dung của mình).
- Hai trang tạm để kiểm chứng khung: Chào mừng và Thông tin.
- Cửa sổ Cài đặt với mục Chung: bật tắt mở khi rê chuột, độ trễ rê chuột, bật tắt rung.
- Giao diện tiếng Anh và tiếng Việt.

Ngoài phạm vi (thuộc mảng khác trong lộ trình):

- Điều hướng bằng bàn phím và việc notch nhận tiêu điểm bàn phím: làm ở mảng 2, nơi đầu tiên cần đến.
- Nội dung hiển thị khi notch đang đóng (nhạc, pin): mảng 4 và 5.
- Kiểu Pill hoàn chỉnh, tuỳ chọn nhiều màn hình, vuốt xuống để mở, ẩn khi quay màn hình: mảng 11.
- Khởi động cùng máy, icon app, ký Developer ID: mảng 12.

## Kiến trúc

Một package SwiftPM, ba target:

| Target | Loại | Trách nhiệm | Phụ thuộc |
|---|---|---|---|
| `NotchCore` | thư viện | Logic thuần, không có giao diện: hình học, máy trạng thái, danh sách trang, cài đặt, bộ gom cử chỉ vuốt | Foundation, CoreGraphics |
| `NotchShell` | thư viện | Cửa sổ, theo dõi con trỏ, view SwiftUI của notch, bộ điều khiển | `NotchCore`, AppKit, SwiftUI |
| `AraNotch` | chương trình | Khởi động app, icon thanh menu, cửa sổ Cài đặt, hai trang tạm | `NotchShell` |

Toàn bộ quy tắc hành vi nằm trong `NotchCore` để kiểm thử được mà không cần màn hình hay cửa sổ thật.

## Thành phần trong `NotchCore`

### `ScreenDescriptor`

Mô tả một màn hình bằng số liệu thuần: `frame` (toạ độ toàn cục, gốc ở góc dưới trái), `safeAreaTop`, `auxLeftWidth`, `auxRightWidth` (bề rộng hai vùng không bị che ở hai bên notch, `nil` nếu không có notch), `menuBarHeight`.

### `NotchGeometry`

Tạo từ một `ScreenDescriptor`.

- `hasPhysicalNotch`: đúng khi `safeAreaTop > 0` và có đủ hai bề rộng phụ.
- `closedRect`:
  - Có notch: rộng `frame.width - auxLeftWidth - auxRightWidth`, cao `safeAreaTop`, bám mép trên, bắt đầu tại `frame.minX + auxLeftWidth`.
  - Không có notch: rộng 180, cao bằng `menuBarHeight` (tối thiểu 24), căn giữa mép trên.
- `openRect(size:)`: căn giữa theo `closedRect.midX`, bám mép trên, bị kẹp lại trong `frame` theo chiều ngang.
- `hoverRect`: `closedRect` nới thêm 4 điểm về mọi phía. Phần nới lên trên vượt ra ngoài màn hình để con trỏ chạm mép trên vẫn được tính là bên trong.
- `openHitRect(size:)`: `openRect` cao thêm 4 điểm lên trên, cùng lý do.

Trên máy phát triển (màn hình 1512×982 điểm) notch đo được rộng 185, cao 32.

### `NotchStateMachine`

Bốn trạng thái: `closed`, `hoverPending`, `open`, `closePending`. Thuộc tính `openOnHover`. Hàm `handle(event)` trả về danh sách hiệu ứng cần thực hiện.

| Trạng thái | Sự kiện | Trạng thái mới | Hiệu ứng |
|---|---|---|---|
| `closed` | con trỏ vào, `openOnHover` bật | `hoverPending` | hẹn giờ rê chuột |
| `closed` | bấm bên trong | `open` | đã mở |
| `hoverPending` | con trỏ ra | `closed` | huỷ giờ rê chuột |
| `hoverPending` | hết giờ rê chuột | `open` | đã mở |
| `hoverPending` | bấm bên trong | `open` | huỷ giờ rê chuột, đã mở |
| `open` | con trỏ ra | `closePending` | hẹn giờ đóng |
| `open` | bấm bên ngoài | `closed` | đã đóng |
| `closePending` | con trỏ vào | `open` | huỷ giờ đóng |
| `closePending` | hết giờ đóng | `closed` | đã đóng |
| `closePending` | bấm bên ngoài | `closed` | huỷ giờ đóng, đã đóng |
| `open`, `closePending` | buộc đóng | `closed` | huỷ giờ đóng (nếu có), đã đóng |
| `hoverPending` | buộc đóng | `closed` | huỷ giờ rê chuột |
| `closed` | buộc mở | `open` | đã mở |
| `hoverPending` | buộc mở | `open` | huỷ giờ rê chuột, đã mở |
| `closePending` | buộc mở | `open` | huỷ giờ đóng |

"Buộc mở" (mở bằng lệnh, không phải bằng con trỏ) giữ bảng mở dù con trỏ đang ở nơi khác: sự kiện "con trỏ ra" bị bỏ qua cho tới khi con trỏ đã vào bảng một lần. Bấm bên ngoài vẫn đóng ngay. Trạng thái giữ này mất khi bảng đóng.

Mọi cặp trạng thái và sự kiện không có trong bảng thì giữ nguyên trạng thái và không có hiệu ứng. Nhờ vậy một bộ hẹn giờ cũ bắn muộn không gây sai lệch.

"Bên trong" được bộ điều khiển tính theo trạng thái hiện tại: dùng `hoverRect` khi `closed` hoặc `hoverPending`, dùng `openHitRect` khi `open` hoặc `closePending`.

### `PageRegistry`

Danh sách có thứ tự các `PageDescriptor` (`id`, `titleKey`, `symbolName`) và `selectedID`.

- `register`: thêm vào cuối; bỏ qua nếu trùng `id`; trang đầu tiên tự được chọn.
- `select(id)`: bỏ qua nếu `id` không tồn tại.
- `selectNext`, `selectPrevious`: xoay vòng ở hai đầu; không làm gì khi có ít hơn hai trang.

### `ShellSettingsStore`

Đọc và ghi vào một `UserDefaults` được truyền vào.

| Khoá | Kiểu | Mặc định | Ràng buộc |
|---|---|---|---|
| `shell.openOnHover` | Bool | bật | |
| `shell.hoverDelay` | Double (giây) | 0,10 | kẹp trong 0 đến 0,5 |
| `shell.hapticsEnabled` | Bool | bật | |

Độ trễ đóng cố định 0,25 giây, không đưa ra Cài đặt.

### `SwipeAccumulator`

Cộng dồn độ dịch ngang của một cử chỉ cuộn trên trackpad. Khi tổng vượt 40 điểm thì phát đúng một lần `next` (vuốt sang trái) hoặc `previous` (vuốt sang phải) cho mỗi cử chỉ. Tự đặt lại khi cử chỉ bắt đầu, kết thúc hoặc bị huỷ. Bỏ qua cử chỉ mà độ dịch dọc lớn hơn độ dịch ngang.

## Thành phần trong `NotchShell`

### `NotchPanel`

`NSPanel` không viền, không kích hoạt app, nền trong suốt, không bóng. Mức cửa sổ nằm trên thanh menu. Hiện trên mọi Space và trên app toàn màn hình, không tham gia chuyển cửa sổ.

Khung cửa sổ luôn bằng `openRect` và không đổi kích thước khi đóng mở. Khi notch đóng, cửa sổ bỏ qua mọi sự kiện chuột nên không cản thao tác với thanh menu. Khi mở, cửa sổ nhận sự kiện chuột.

### `PointerMonitor`

Gói các bộ theo dõi sự kiện toàn cục và cục bộ của `NSEvent` cho: di chuyển chuột, kéo chuột trái, nhấn chuột trái, cuộn. Báo về vị trí con trỏ theo toạ độ toàn cục. Không cần quyền Trợ năng.

### `NotchController`

Giữ `NotchPanel`, `NotchStateMachine`, `PointerMonitor`, `ShellSettings` và các bộ hẹn giờ. Đổi sự kiện con trỏ thành sự kiện của máy trạng thái, rồi thực hiện hiệu ứng trả về.

- Chọn màn hình: màn hình đầu tiên có notch; nếu không có thì màn hình chính. Tính lại khi cấu hình màn hình thay đổi.
- Lưới an toàn: khi trạng thái khác `closed`, một bộ hẹn giờ 15 lần mỗi giây đọc vị trí con trỏ và gửi lại cho máy trạng thái. Việc này đảm bảo notch không bị kẹt ở trạng thái mở nếu hệ thống bỏ sót một sự kiện chuột. Khi `closed` thì không có bộ hẹn giờ nào chạy.
- API công khai: `start()`, `register(page:)`, `open()`, `close()`, `selectPage(id:)`, và `onOpenSettings` để app gắn hành động của nút bánh răng.

### View

- `NotchShape`: hình đen có hai góc dưới bo tròn và hai "tai" lõm ở mép trên, bán kính đổi mượt giữa hai trạng thái.
- `NotchRootView`: vẽ hình, hàng đầu bảng và nội dung trang đang chọn. Hàng đầu bảng cao bằng notch: các nút tab nằm bên trái notch, nút bánh răng nằm bên phải, phần giữa để trống cho notch vật lý. Nội dung chỉ hiện khi mở.
- `NotchPage`: một `PageDescriptor` kèm hàm tạo view.

Notch luôn dùng nền đen chữ sáng, không theo giao diện sáng tối của hệ thống.

## Thành phần trong `AraNotch`

- `AppDelegate`: đặt app ở chế độ phụ trợ, tạo cài đặt, bộ điều khiển, icon thanh menu, đăng ký hai trang tạm.
- `StatusItemController`: icon thanh menu và menu.
- `SettingsWindowController` và `SettingsView`: cửa sổ Cài đặt, chia thành các tab (`SettingsTab`). App ghép tab Chung của khung notch với mỗi tab do một mảng tính năng cung cấp. `show(tabID:)` mở thẳng một tab; id không tồn tại thì giữ tab hiện tại.
- `WelcomePage`, `AboutPage`: trang tạm. Trang Thông tin hiện phiên bản và kích thước notch đo được, dùng làm công cụ chẩn đoán. Cả hai sẽ bị thay khi có trang thật.
- Tham số dòng lệnh dùng cho kiểm thử tự động: `--open-on-launch` mở notch ngay khi khởi động, `--show-settings` mở cửa sổ Cài đặt ngay khi khởi động (kèm `--settings-tab <id>` để chọn tab). `--select-page <id>` chọn trang khi khởi động. `--snapshot-dir <thư mục>` cho app tự vẽ các cửa sổ đang hiện của chính nó ra file PNG sau 1,5 giây; việc này không cần quyền ghi màn hình và không nhìn thấy app khác.

## Bản địa hoá

Chuỗi hiển thị nằm trong `Resources/en.lproj/Localizable.strings` và `Resources/vi.lproj/Localizable.strings`. Script build chép chúng vào `Contents/Resources` của app, và code tra chuỗi từ bundle chính. Tiếng Anh là ngôn ngữ gốc.

## Build và chạy

- `Scripts/build-app.sh [debug|release]`: chạy `swift build`, dựng `build/AraNotch.app` (file thực thi, `Info.plist` với `LSUIElement`, thư mục ngôn ngữ), ký ad-hoc.
- `Scripts/run.sh`: tắt bản đang chạy, build rồi mở app.

## Trường hợp biên

| Tình huống | Xử lý |
|---|---|
| Không có màn hình nào | Không tạo cửa sổ; tạo lại khi có thông báo đổi cấu hình màn hình |
| Rút hoặc cắm màn hình ngoài | Tính lại hình học, buộc đóng, đặt lại khung cửa sổ |
| Thanh menu tự ẩn (`menuBarHeight` bằng 0) | Notch ảo cao tối thiểu 24 |
| Bộ hẹn giờ bắn sau khi trạng thái đã đổi | Máy trạng thái bỏ qua |
| Giá trị cài đặt ngoài khoảng cho phép | Kẹp về khoảng hợp lệ khi đọc và khi ghi |
| Hệ thống bỏ sót sự kiện chuột | Lưới an toàn 15 lần mỗi giây khi notch không đóng |

## Kiểm thử

Kiểm thử đơn vị bằng Swift Testing cho toàn bộ `NotchCore`:

- `NotchGeometry`: màn hình có notch, không có notch, màn hình phụ có gốc toạ độ khác 0, kẹp `openRect` trong màn hình, thanh menu tự ẩn.
- `NotchStateMachine`: từng dòng của bảng chuyển trạng thái, và các sự kiện phải bị bỏ qua.
- `PageRegistry`: đăng ký, trùng `id`, chọn, xoay vòng, danh sách rỗng và một phần tử.
- `ShellSettingsStore`: mặc định, ghi rồi đọc lại, kẹp giá trị.
- `SwipeAccumulator`: ngưỡng, chỉ phát một lần mỗi cử chỉ, đặt lại, bỏ qua cuộn dọc.

Kiểm chứng trên app thật do Claude tự làm: build, chạy, kiểm tra cửa sổ tồn tại đúng vị trí, rồi chụp màn hình các trạng thái đóng, mở, chuyển trang và cửa sổ Cài đặt.

## Tiêu chí hoàn thành

1. `swift test` chạy qua toàn bộ.
2. `Scripts/build-app.sh` tạo ra app chạy được, không có icon Dock, có icon thanh menu.
3. Notch đóng không nhìn thấy được trên máy có notch và không cản thao tác với thanh menu.
4. Rê chuột vào notch thì bảng mở ra; đưa chuột ra ngoài thì bảng đóng lại.
5. Chuyển được giữa hai trang tạm bằng tab.
6. Thay đổi trong Cài đặt có hiệu lực ngay và còn nguyên sau khi mở lại app.
