# Ghi chú: gõ ngay khi bấm "+", xoá kèm Hoàn tác

Ngày 2026-10-27. Chủ dự án: "Làm hai việc còn lại cho Ghi chú (gõ được ngay khi bấm +, xoá kèm Hoàn tác), rồi phát hành 0.30.0." Chỉ trong module Notes.

## 1. Gõ ngay khi bấm "+"

Trước đây: bấm "+" thì Notes tạo ghi chú (3–17 giây khi Notes bận), xong mới mở và đặt con trỏ.

Nay: `NotesStore.newNote` mở ngay một **bản nháp** (`OpenNote` có id tạm `draft:<uuid>`, thế hệ mới, tài liệu rỗng hoặc tài liệu tạo lại), gọi `opened` để trang đặt con trỏ, rồi chờ Notes tạo ghi chú thật.

- Gõ trong lúc chờ: `edit` vẫn nhận, lần sửa nằm chờ (`pending`) nhưng `startSaving` không ghi bản nháp.
- Notes tạo xong: đọc ngày sửa của ghi chú mới làm mốc SaveGuard, đổi id của `open` và của lần sửa đang chờ sang id thật (giữ thế hệ, nên trình soạn không dựng lại, con trỏ và hoàn tác còn nguyên), nhớ thư mục, thêm vào gần đây, liệt kê lại, rồi ghi phần đã gõ.
- `flush` chờ việc tạo xong trước khi ghi, nên đổi sang ghi chú khác, rời trang hay thoát app (trong giới hạn 5 giây) đều không mất chữ đã gõ.
- Tạo thất bại: bản nháp ở lại với chữ đã gõ, trạng thái lỗi; dải thông báo có nút Chép.
- Độ an toàn của bản nháp như ghi chú mới đọc về: thiếu Full Disk Access (có cơ sở dữ liệu mà không đọc được) là chỉ xem; có ảnh mà không đặt tạm được là chỉ xem.
- Hàng đầu: trạng thái "Đang tạo…"; ẩn "Mở trong Notes" và "Xoá" cho tới khi có ghi chú thật. Tải lại không làm gì với bản nháp.

## 2. Xoá kèm Hoàn tác

Trước đây: Xoá mở thẻ hỏi "Xoá …?", bấm Xoá mới xoá.

Nay: Xoá (hàng đầu, nút trên dòng, menu chuột phải) xoá ngay. Trên danh sách hiện dải "Đã xoá "<tên>"" với nút **Hoàn tác** trong 10 giây (Esc đóng dải). Ghi chú rời danh sách và trình soạn ngay khi bấm, dải hiện ngay; Notes xoá ở nền (đo trên máy thật: 6 giây, liệt kê lại thêm 15 giây). Tên trên dải là dòng đầu đang gõ.

- Trước khi xoá, phần đang gõ dở của ghi chú đó được lưu (không còn bỏ đi), để Hoàn tác trả lại đủ.
- Store nhớ ghi chú vừa xoá: id, tên, thư mục (từ lần liệt kê). Hoàn tác gọi `NotesService.restore(_:to:)`: AppleScript `move note id … to folder id …`. Đã thử trên Notes thật (macOS 27): ghi chú từ "Đã xoá gần đây" về lại thư mục cũ, giữ id và nội dung; chỉ `container` của nó báo lỗi -1728, nên thư mục phải nhớ từ trước.
- Sau Hoàn tác: liệt kê lại; nếu không có ghi chú nào đang mở thì mở lại ghi chú đó.
- Không biết thư mục cũ (chưa từng được liệt kê) thì không có nút Hoàn tác.
- Thẻ hỏi xoá và `deletingID` bị bỏ.

## Kiểm chứng

- Test store với Notes giả (thêm thùng rác và `restore`): bản nháp mở trước khi Notes tạo xong; chữ gõ trong lúc chờ được ghi vào ghi chú mới; mở ghi chú khác trong lúc chờ vẫn ghi; tạo hỏng giữ chữ; tải lại không chạm bản nháp; thiếu Full Disk Access thì bản nháp chỉ xem; xoá lưu phần đang gõ; Hoàn tác trả ghi chú về thư mục và mở lại; không biết thư mục thì không Hoàn tác được.
- Test trang: chữ trạng thái "Đang tạo…"; Esc đóng dải Hoàn tác.
- Thử trên Notes thật trong thư mục "AraNotch-test": bấm +, gõ ngay, ghi chú có chữ; xoá rồi Hoàn tác.
