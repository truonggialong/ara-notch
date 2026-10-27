# Trang Ghi chú: hai cột tinh gọn (phương án A)

Ngày 2026-10-27. Chủ dự án chọn phương án A từ ba bản vẽ (A hai cột tinh gọn, B danh sách thu được, C một cột chuyển màn), kèm cả bảy thay đổi. Chỉ đổi giao diện trong module Notes; dữ liệu ghi vào Notes không đổi.

## Mục đích

Trên notch, Ghi chú dùng để ghi nhanh, tìm và liếc một ghi chú, sửa vài dòng. Bố cục phải cho thấy ghi chú đã lưu chưa, đưa mọi hành động ra nút nhìn thấy được, và để chữ là thứ nổi nhất trang.

## Bảy thay đổi

1. **Trạng thái lưu** trên đầu trình soạn: "Đã lưu", "Đang lưu…", "Chỉ xem", "Chưa lưu" (xung đột, lỗi), "Đã bị xoá", "Đang tải…". Một hàm thuần `NoteEditorHeader.status(open:state:isReloading:)` quyết định chữ, có test.
2. **Nút cho mọi hành động**: đầu trình soạn có nút "Mở trong Notes" và "Xoá" (thẻ hỏi xoá vẫn hiện trên danh sách như trước). Rê chuột lên một dòng của danh sách thì hiện nút xoá ở cuối dòng. Menu chuột phải giữ nguyên.
3. **Thanh định dạng chìm vào khung trình soạn**: không còn viên thuốc trắng; là một hàng nút trong suốt ở đầu khung, ngăn với chữ bằng một đường mảnh. Nhóm kiểu đoạn trước (kiểu đoạn, danh sách chấm, khối mã, ảnh), nhóm kiểu chữ sau (đậm, nghiêng, gạch dưới, gạch ngang, mã, liên kết). Nút đang bật sáng màu nhấn. Ghi chú không sửa được thì ẩn hẳn thanh này; dải lý do vẫn nói vì sao.
4. **Nút "+" màu nhấn**, cỡ thường (28 pt), là nút đặc duy nhất của trang.
5. **Thư mục thành tiêu đề của danh sách**: hàng trên chỉ còn ô tìm và "+". Ngay trên danh sách là dòng "Tất cả ghi chú 75 ▾" (tên thư mục đang xem và số ghi chú); bấm vào mở bảng chọn thư mục như trước.
6. **Trình soạn dễ đọc hơn**: lề chữ 12 × 10 pt (trước 4 × 6), giãn dòng thêm 3 pt, dòng đầu là đoạn thường thì hiện cỡ 16 (đơn cách 15) thay vì 13. Chỉ là cách hiển thị: kiểu đoạn nằm trong thuộc tính riêng, và việc đọc lại tài liệu từ chữ bỏ qua cỡ chữ, nên Notes nhận đúng như trước. Cỡ dòng đầu được chỉnh trong `textStorage(_:didProcessEditing:)` cho các đoạn vừa sửa, đoạn đầu và đoạn thứ hai, nên gõ Return, dán, hoàn tác, đổi kiểu đều đúng cỡ.
7. **Danh sách hẹp hơn**: 30% bề ngang (trước 38%), trình soạn rộng thêm.

Đầu trình soạn còn có thư mục của ghi chú (chip) và giờ sửa (`openedAt`).

## Không làm (để sau, chủ dự án quyết)

- Gõ được ngay khi bấm "+" trước khi Notes tạo xong.
- Xoá kèm "Hoàn tác" thay cho thẻ hỏi.
- Nút thu danh sách (phương án B).

## Kiểm chứng

- Test: chữ trạng thái cho từng trạng thái; dòng đầu cỡ 16 và tài liệu đọc lại không đổi; Return ở cuối dòng đầu cho dòng mới cỡ thường; đậm trên dòng đầu giữ cỡ 16; giãn dòng có trên mọi kiểu đoạn.
- `Scripts/test-module.sh Notes`, `Scripts/test.sh`, `swift build`.
- Chạy app thật, chụp trang Ghi chú (danh sách, ghi chú sửa được, ghi chú chỉ xem, bảng chọn thư mục).
