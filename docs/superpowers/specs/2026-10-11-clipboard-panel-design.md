# AraNotch — Panel clipboard và bàn phím (mảng 2b) — Thiết kế

Ngày: 2026-10-11 · Dựa trên: `2026-10-11-clipboard-core-design.md`

## Mục tiêu

Nhấn ⌘⇧C ở bất kỳ app nào để mở một panel lịch sử clipboard cạnh con trỏ, chọn mục bằng bàn phím và dán mà không cần chạm chuột.

## Phạm vi

Trong phạm vi:

- Phím tắt toàn cục ⌘⇧C bật tắt panel; tắt được trong Cài đặt.
- Panel nổi 560×380: ô tìm kiếm, danh sách dọc bên trái, khung xem trước lớn bên phải.
- Bàn phím trong panel: ↑ ↓ chọn mục, Return dán, ⌘Return chỉ sao chép, ⌘⌫ xoá, ⌘1…⌘9 dán mục thứ n, Esc đóng (nếu ô tìm kiếm có chữ thì Esc xoá chữ trước).
- Bàn phím trên trang notch khi ô tìm kiếm đang nhận phím: ← → chọn thẻ khi ô tìm kiếm rỗng, cùng các phím Return, ⌘Return, ⌘⌫, ⌘1…⌘9, Esc như trên.
- Thẻ và dòng đang chọn được tô nổi; mục đang chọn luôn được cuộn vào tầm nhìn.
- Panel đóng khi dán, khi nhấn Esc, khi bấm ra ngoài hoặc khi mất tiêu điểm.

Ngoài phạm vi:

- 2c: tô màu code, tiêu đề và ảnh xem trước của liên kết, văn bản có định dạng.
- Mảng 11: tự chọn phím tắt khác, ghim panel luôn mở.

## Lưu ý về phím tắt

⌘⇧C trùng với phím tắt của một số app (ví dụ mở công cụ soi phần tử trong trình duyệt). Khi AraNotch đang chạy và phím tắt được bật, AraNotch nhận phím này trước. Vì vậy có công tắc trong Cài đặt.

## Thêm vào `ClipboardCore`

Toàn bộ quy tắc bàn phím và vị trí là logic thuần, kiểm thử được.

### `ClipSelection`

Giữ `selectedID` của mục đang chọn trong một danh sách id có thứ tự.

- `sync(with ids:)`: giữ nguyên lựa chọn nếu id còn trong danh sách; nếu không thì chọn phần tử đầu; danh sách rỗng thì không chọn gì.
- `moveNext(in:)`, `movePrevious(in:)`: dừng ở hai đầu, không xoay vòng. Khi chưa chọn gì thì chọn phần tử đầu.
- `select(index:in:)`: chọn theo vị trí; vị trí ngoài phạm vi thì bỏ qua và trả về sai.
- `index(in:)`: vị trí của mục đang chọn.

### `ClipPanelKeyMap`

Đổi một lần nhấn phím thành lệnh. Đầu vào: mã phím, tổ hợp phím bổ trợ (`KeyModifiers`: command, shift, option, control), hướng danh sách (`vertical` cho panel, `horizontal` cho notch) và ô tìm kiếm có rỗng không. Đầu ra là `ClipPanelCommand`:

| Phím | Lệnh |
|---|---|
| ↓ (dọc), → (ngang, ô tìm kiếm rỗng) | `moveNext` |
| ↑ (dọc), ← (ngang, ô tìm kiếm rỗng) | `movePrevious` |
| Return, Enter bàn phím số | `paste` |
| ⌘Return | `copy` |
| ⌘⌫ | `delete` |
| ⌘1…⌘9 | `pasteIndex(0…8)` |
| Esc, ô tìm kiếm có chữ | `clearSearch` |
| Esc, ô tìm kiếm rỗng | `close` |
| mọi phím khác | `passThrough` (để ô tìm kiếm xử lý) |

Phím mũi tên kèm bất kỳ phím bổ trợ nào là `passThrough`, để các phím tắt soạn thảo như ⌥← vẫn hoạt động. ← → ở hướng dọc và ↑ ↓ ở hướng ngang là `passThrough`.

### `PanelPlacement`

`frame(size:near:in:)` trả về khung panel: góc trên trái của panel đặt lệch con trỏ 12 điểm sang phải và xuống dưới, rồi bị dịch vào trong vùng hiển thị của màn hình nếu tràn. Nếu panel lớn hơn vùng hiển thị thì bám góc trên trái của vùng đó.

### Cài đặt

Thêm `clipboard.hotKeyEnabled` (Bool, mặc định bật) vào `ClipboardSettingsStore`.

## Thêm vào `ClipboardFeature`

- `HotKey`: đăng ký phím tắt toàn cục bằng Carbon `RegisterEventHotKey`, không cần quyền hệ thống. Ghi log nếu đăng ký thất bại.
- `ClipboardPanel`: `NSPanel` không kích hoạt app nhưng nhận phím, nổi trên các cửa sổ thường, hiện trên mọi Space.
- `ClipboardPanelView`: ô tìm kiếm, danh sách dòng (biểu tượng loại, đoạn trích, app nguồn, nhãn ⌘1…⌘9 cho chín dòng đầu), khung xem trước (toàn văn cuộn được, ảnh vừa khung, ô màu lớn kèm mã, danh sách đường dẫn, URL).
- `KeyCommandRouter`: một bộ theo dõi phím cục bộ; phím nhấn trong panel hoặc trong notch được đổi qua `ClipPanelKeyMap` rồi thực hiện. Lệnh `passThrough` trả sự kiện lại cho ô tìm kiếm.
- `ClipboardController`: thêm `togglePanel()`, lựa chọn dùng chung cho notch và panel, và công tắc phím tắt theo Cài đặt.

Dán từ panel: ghi mục vào clipboard, đóng panel (tiêu điểm tự về app đang dùng), chờ 0,08 giây rồi gửi ⌘V nếu có quyền Trợ năng.

## Trường hợp biên

| Tình huống | Xử lý |
|---|---|
| Nhấn ⌘⇧C khi panel đang mở | Đóng panel |
| Danh sách rỗng hoặc tìm không ra | Return, ⌘Return, ⌘⌫ không làm gì |
| ⌘7 khi chỉ có 3 mục | Không làm gì |
| Mục đang chọn bị xoá | Chọn mục đầu danh sách |
| Gõ tìm kiếm làm mục đang chọn biến mất | Chọn mục đầu của kết quả |
| Con trỏ sát mép phải hoặc mép dưới màn hình | Panel được dịch vào trong |
| Phím tắt đã bị app khác chiếm trước | Ghi log, panel vẫn mở được bằng cách khác trong tương lai; không báo lỗi cho người dùng ở vòng này |

## Kiểm thử

Kiểm thử đơn vị cho `ClipSelection`, `ClipPanelKeyMap`, `PanelPlacement` và khoá cài đặt mới.

Kiểm chứng trên app thật do Claude làm, không cần điều khiển máy: tham số `--show-clipboard-panel` mở panel khi khởi động; tham số `--send-keys` đưa các lần nhấn phím giả vào hàng đợi sự kiện của chính app (không gửi ra hệ thống), đi qua đúng đường xử lý phím thật; rồi app tự vẽ panel ra ảnh.

Cần người dùng tự thử: nhấn ⌘⇧C thật ở app khác, dán vào app đó, bấm ra ngoài để đóng.

## Tiêu chí hoàn thành

1. `Scripts/test.sh` qua toàn bộ.
2. Panel hiện đúng danh sách, mục chọn và khung xem trước cho từng loại.
3. Chuỗi phím giả ↓ ↓ đổi mục chọn sang dòng thứ ba; ⌘⌫ xoá mục đang chọn; gõ tìm kiếm rồi Esc xoá chữ, Esc lần nữa đóng panel.
4. Đăng ký phím tắt trả về thành công trong log; tắt công tắc thì huỷ đăng ký.
