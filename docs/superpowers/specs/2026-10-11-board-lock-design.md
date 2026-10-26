# AraNotch — Khoá board bằng mật mã (mảng 3b) — Thiết kế

Ngày: 2026-10-11 · Dựa trên: `2026-10-11-boards-design.md`

## Mục tiêu

Người dùng khoá một board bằng mật mã. Nội dung của board bị khoá được mã hoá trên đĩa và không hiện ở đâu cho tới khi nhập đúng mật mã.

## Cảnh báo cho người dùng

Không có cách khôi phục mật mã. Quên mật mã thì nội dung trong các board bị khoá không đọc lại được.

## Mô hình

- **Két (vault):** một mật mã dùng chung cho mọi board bị khoá. Ba trạng thái: chưa thiết lập, đang khoá, đang mở.
- **Board bị khoá:** board có cờ `is_locked`.
- **Mục trong két:** mọi mục được ghim vào một board bị khoá. Mục trong két được mã hoá, chỉ thuộc về board bị khoá, và không xuất hiện trong lịch sử chung ("Tất cả"), kể cả khi két đang mở.

## Mật mã và khoá

- Một khoá dữ liệu ngẫu nhiên 256 bit mã hoá nội dung bằng AES-GCM.
- Khoá dữ liệu được bọc bằng một khoá suy ra từ mật mã qua PBKDF2-HMAC-SHA256, 600 000 vòng, muối ngẫu nhiên 16 byte. Nhờ vậy đổi mật mã không phải mã hoá lại nội dung.
- Kho chỉ lưu muối, số vòng và khoá dữ liệu đã bọc. Mật mã và khoá dữ liệu không bao giờ được ghi ra đĩa; khoá dữ liệu chỉ nằm trong bộ nhớ khi két đang mở.
- Mật mã dài tối thiểu 4 ký tự.

## Cái gì được mã hoá

Với mỗi mục trong két: văn bản, tiêu đề liên kết, và nội dung mọi tệp đi kèm (ảnh, RTF, HTML, ảnh xem trước liên kết). Tên tệp và mã băm nội dung được thay bằng giá trị suy ra từ khoá, để không so được với nội dung thường.

Không được mã hoá (siêu dữ liệu): loại mục, tên app nguồn, thời điểm, kích thước, tên và biểu tượng board, số mục trong board.

## Hành vi của kho (`ClipboardCore`, lược đồ phiên bản 5)

| Thao tác | Hành vi |
|---|---|
| `createVault(passcode:)` | Chỉ khi chưa thiết lập. Mật mã quá ngắn bị từ chối. Sau khi tạo, két ở trạng thái mở |
| `unlockVault(passcode:)` | Sai mật mã ném `wrongPasscode` |
| `lockVault()` | Xoá khoá khỏi bộ nhớ |
| `changeVaultPasscode(from:to:)` | Cần đúng mật mã cũ; nội dung không bị mã hoá lại |
| `setBoardLocked(id:true)` | Cần két đang mở. Mọi mục của board thành mục trong két và bị gỡ khỏi các board không khoá |
| `setBoardLocked(id:false)` | Cần két đang mở. Mục không còn thuộc board bị khoá nào được giải mã về lịch sử thường |
| Ghim vào board bị khoá | Cần két đang mở; mục thành mục trong két |
| Bỏ ghim khỏi board bị khoá | Cần két đang mở; mục trở về lịch sử thường nếu không còn ở board bị khoá nào khác |
| `items()` | Không bao giờ gồm mục trong két |
| `items(inBoard:)` với board bị khoá | Két đang khoá: ném `vaultLocked`. Két đang mở: trả mục đã giải mã |
| Đọc ảnh, định dạng, ảnh xem trước của mục trong két | Két đang khoá: không có gì. Két đang mở: dữ liệu đã giải mã |
| Xoá board bị khoá | Cần két đang mở; các mục trở về lịch sử thường |
| Xoá một mục trong két | Luôn được phép; xoá cả tệp |

Khi một mục trở về lịch sử thường mà lịch sử đã có một mục cùng nội dung, hai mục được gộp làm một.

Sao chép lại nội dung trùng với một mục trong két tạo ra một mục thường mới trong lịch sử; mục trong két không bị đụng tới.

Mở kho lên thì két luôn ở trạng thái khoá. Kho phiên bản 1 đến 4 được nâng lên 5.

## Giao diện (`ClipboardFeature`)

- Chip của board bị khoá có biểu tượng ổ khoá (mở hoặc đóng theo trạng thái két).
- Chọn một board bị khoá khi két đang khoá: hàng trên cùng đổi thành hàng nhập mật mã. Đúng thì mở két và hiện board; sai thì báo lỗi.
- Chuột phải vào chip (trên trang notch): "Khoá board…" hoặc "Bỏ khoá board". Lần đầu khoá sẽ yêu cầu đặt mật mã (nhập hai lần).
- Két tự khoá lại sau 5 phút kể từ lần mở gần nhất. Khi két khoá mà đang xem một board bị khoá thì quay về "Tất cả".
- Hàng nhập mật mã hiện ở cả trang notch và panel nổi. Return để xác nhận, Esc để huỷ.

## Giới hạn đã biết

- Không giới hạn số lần thử mật mã; sức chống dò chỉ dựa vào PBKDF2 và độ dài mật mã.
- Nội dung đã từng nằm trong lịch sử thường trước khi bị khoá có thể còn sót trong các trang trống của tệp SQLite cho tới khi tệp được dọn; vòng này chạy `VACUUM` sau mỗi lần khoá board để giảm việc đó.
- Khi két đang mở, khoá dữ liệu nằm trong bộ nhớ của app.

## Kiểm thử

Kiểm thử đơn vị cho phần mật mã (bọc và mở khoá, sai mật mã, phát hiện dữ liệu bị sửa) và cho mọi dòng của bảng hành vi, gồm cả việc đọc thẳng tệp SQLite và tệp trong `blobs/` để xác nhận không còn nội dung thường.

Kiểm chứng trên app thật: khoá một board bằng chuột và bàn phím thật, mở lại app, nhập sai rồi đúng mật mã.

## Tiêu chí hoàn thành

1. `Scripts/test.sh` qua toàn bộ.
2. Sau khi khoá board, tìm chuỗi nội dung trong tệp kho và trong `blobs/` không thấy.
3. Mở lại app: board bị khoá không hiện nội dung cho tới khi nhập đúng mật mã.
