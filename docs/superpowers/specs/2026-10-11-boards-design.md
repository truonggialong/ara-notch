# AraNotch — Board và ghim (mảng 3a) — Thiết kế

Ngày: 2026-10-11 · Dựa trên: các spec clipboard 2a đến 2d

## Mục tiêu

Người dùng ghim những mục hay dùng vào các board có tên. Mục đã ghim không bị mất khi lịch sử đầy hay khi xoá lịch sử.

## Phạm vi

Trong phạm vi:

- Tạo, đổi tên, đổi biểu tượng và xoá board.
- Ghim và bỏ ghim một mục vào một hay nhiều board, từ menu chuột phải của thẻ.
- Hàng chip board trên trang Clipboard của notch: "Tất cả", từng board kèm số mục, và nút thêm. Chọn một board thì chỉ hiện mục của board đó.
- Mục đã ghim được loại khỏi giới hạn số mục và không bị "Xoá lịch sử" xoá.
- Lược đồ kho phiên bản 4.

Ngoài phạm vi: khoá board bằng mật mã, kéo thả để ghim và sắp xếp, lọc theo board trong panel nổi, Copy Stack, cửa sổ Library (các vòng sau của mảng 3); giới hạn theo gói Free và Pro (mảng 12).

## Kho (`ClipboardCore`, lược đồ phiên bản 4)

Hai bảng mới:

- `boards(id, name, symbol, created_at)`
- `board_items(board_id, item_id, pinned_at)`, khoá chính là cặp (board, mục).

`ClipBoard`: `id`, `name`, `symbolName`, `itemCount`.

Giới hạn: tối đa 20 board; mỗi board tối đa 200 mục; tên board dài tối đa 40 ký tự.

| Hàm | Hành vi |
|---|---|
| `boards()` | Mọi board theo thứ tự tạo, kèm số mục |
| `createBoard(name:symbolName:at:)` | Tên được bỏ khoảng trắng hai đầu. Lỗi `invalidBoardName` nếu rỗng hoặc quá dài; `duplicateBoardName` nếu trùng tên (không phân biệt hoa thường); `tooManyBoards` nếu đã đủ 20 |
| `updateBoard(id:name:symbolName:)` | Cùng quy tắc tên; trùng với chính nó thì được |
| `deleteBoard(id:)` | Xoá board và các liên kết ghim; mục vẫn ở trong lịch sử, rồi lịch sử được cắt bớt theo giới hạn |
| `pin(itemID:toBoard:at:)` | Ghim; ghim lại mục đã ghim thì không đổi gì; lỗi `boardFull` khi board đã có 200 mục; mục hoặc board không tồn tại thì bỏ qua |
| `unpin(itemID:fromBoard:)` | Bỏ ghim; rồi lịch sử được cắt bớt theo giới hạn |
| `items(inBoard:)` | Mục của board, ghim gần nhất đứng đầu |
| `boardMembership()` | Bảng tra từ id mục sang tập id board chứa nó |

Thay đổi ở hành vi có sẵn:

- **Cắt bớt:** `maxItems` chỉ tính mục chưa ghim. Mục đã ghim không bao giờ bị cắt.
- **`deleteAll()`:** chỉ xoá mục chưa ghim cùng tệp của chúng. Mục đã ghim và các board còn nguyên.
- **`delete(id:)`:** xoá mục, kể cả khi đã ghim, và gỡ nó khỏi mọi board.
- Sao chép lại nội dung đã ghim: mục lên đầu lịch sử như thường, vẫn còn ghim.

Kho phiên bản 1 đến 3 được nâng lên 4; phiên bản lớn hơn bị từ chối.

## Giao diện (`ClipboardFeature`)

- Hàng trên cùng của trang Clipboard: ô tìm kiếm (hẹp lại) bên trái, hàng chip cuộn ngang bên phải.
- Chip đang chọn được tô nổi. Tìm kiếm áp dụng trong phạm vi board đang chọn.
- Nút thêm mở một hàng soạn ngay tại chỗ: sáu biểu tượng để chọn, ô nhập tên, nút Lưu và Huỷ. Lỗi tên hiện thành chữ đỏ. Chuột phải vào chip board: Đổi tên…, Xoá board.
- Chuột phải vào thẻ có thêm mục con "Ghim vào" liệt kê các board, có dấu tích ở board đang chứa mục; bấm để ghim hoặc bỏ ghim.
- Thẻ đã ghim có biểu tượng ghim nhỏ ở chân thẻ.
- Board rỗng hiện lời nhắc cách ghim.
- Nhãn nút trong Cài đặt đổi thành "Xoá lịch sử chưa ghim…".

Panel nổi có cùng hàng chip board ngay dưới ô tìm kiếm và liệt kê đúng board đang chọn; lựa chọn board dùng chung với trang notch. Dòng đã ghim có biểu tượng ghim, và chuột phải vào dòng có cùng menu Dán, Sao chép, Ghim vào, Xoá. Tạo, đổi tên và xoá board chỉ làm ở trang notch, nơi có hàng soạn; hàng chip trong panel không có nút thêm.

## Trường hợp biên

| Tình huống | Xử lý |
|---|---|
| Board đang chọn bị xoá | Quay về "Tất cả" |
| Mục bị xoá khi đang ghim | Biến khỏi mọi board |
| Giảm `maxItems` | Chỉ mục chưa ghim bị cắt |
| Tên board chỉ khác hoa thường hoặc khoảng trắng hai đầu | Coi là trùng |
| Ghim khi board đầy | Không ghim, ghi log |

## Kiểm thử

Kiểm thử đơn vị cho mọi hàm của kho ở trên, các thay đổi về cắt bớt và xoá, và nâng lược đồ từ phiên bản 3.

Kiểm chứng trên app thật do Claude làm: tham số `--seed-boards` tạo hai board và ghim vài mục mẫu; `--select-board <tên>`; `--edit-new-board` mở hàng soạn; rồi app tự vẽ trang ra ảnh. Mở lại app để xác nhận board còn nguyên. Mở một kho phiên bản 3 thật.

Cần người dùng tự thử: chuột phải để ghim, gõ tên board, bấm chip.

## Tiêu chí hoàn thành

1. `Scripts/test.sh` qua toàn bộ.
2. Trang Clipboard hiện hàng chip; chọn board chỉ hiện mục của board; thẻ đã ghim có biểu tượng ghim.
3. Mục đã ghim còn nguyên sau khi lịch sử vượt giới hạn và sau `deleteAll()`.
4. Kho phiên bản 3 mở được và lên phiên bản 4.
