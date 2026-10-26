# AraNotch — Tô màu code và văn bản có định dạng (mảng 2c) — Thiết kế

Ngày: 2026-10-11 · Dựa trên: `2026-10-11-clipboard-core-design.md`, `2026-10-11-clipboard-panel-design.md`

## Mục tiêu

Đoạn code đã sao chép được nhận ra và tô màu trong bản xem trước. Văn bản có định dạng (chữ đậm, bảng, màu) giữ nguyên định dạng khi dán lại từ lịch sử.

## Phạm vi

Trong phạm vi:

- Nhận diện code và tô màu, xử lý hoàn toàn trên máy, áp dụng cho khung xem trước của panel và thẻ trên notch.
- Lưu kèm dữ liệu RTF và HTML của mục văn bản; khi dán hoặc sao chép lại thì ghi cả văn bản thường lẫn dữ liệu định dạng.
- Nâng lược đồ kho lên phiên bản 2, tự chuyển dữ liệu từ phiên bản 1.

Ngoài phạm vi:

- Xem trước liên kết (tiêu đề, ảnh). Việc này cần tải trang từ mạng cho mỗi liên kết được sao chép; tự động tải có thể kích hoạt liên kết dùng một lần (đăng nhập, huỷ đăng ký). Cần chủ dự án quyết định mặc định bật hay tắt trước khi làm.
- Tuỳ chọn "dán dạng văn bản thường".
- Bộ lọc `@code`.

## Tô màu code (`ClipboardCore`)

Code không phải là một loại mục mới. Mục vẫn là `text`; việc nhận diện diễn ra lúc hiển thị, nên không đụng tới lược đồ hay mã băm.

### `CodeDetector.looksLikeCode(_:)`

Xét tối đa 4 000 ký tự đầu. Trả về đúng khi một trong các điều sau đúng:

- Văn bản (sau khi bỏ khoảng trắng hai đầu) bắt đầu bằng `{` hoặc `[`, có từ hai dòng trở lên và là JSON hợp lệ.
- Bắt đầu bằng `<` và có chứa `</` hoặc `/>` (HTML, XML).
- Có một dòng mở đầu bằng động từ SQL viết hoa (`SELECT`, `INSERT`, `UPDATE`, `CREATE`, `DELETE`) và văn bản có từ đi kèm tương ứng (`FROM`, `INTO`, `SET`, `TABLE`, `FROM`). Chỉ nhận chữ hoa, để câu văn như "Select a file from the list" không bị nhận nhầm.
- Có ít nhất một dòng mở đầu bằng từ khoá khai báo (`func`, `def`, `class`, `import`, `from`, `const`, `let`, `var`, `function`, `return`, `public`, `private`, `struct`, `enum`, `interface`, `package`, `using`, `fn`, `#include`) **và** có ít nhất hai dấu hiệu cú pháp khác nhau trong số: `{`, `}`, `=>`, `->`, `==`, `!=`, `()`, `);`, `=` có khoảng trắng hai bên, một dòng kết thúc bằng `;`, bằng `:` hoặc bằng `)`.
- Có từ ba dòng không rỗng trở lên, ít nhất 60% số dòng kết thúc bằng `;`, `{`, `}`, `,` hoặc `)`, và có ít nhất một dòng kết thúc bằng `;`, `{` hoặc `}`. Điều kiện sau cùng loại trừ địa chỉ nhiều dòng kết thúc bằng dấu phẩy.

Văn xuôi, liên kết, mã màu và một từ đơn phải cho kết quả sai.

### `CodeTokenizer.tokenize(_:)`

Chia văn bản thành các `CodeToken` liên tiếp, phủ kín toàn bộ chuỗi (nối lại bằng đúng văn bản gốc). Loại token: `plain`, `keyword`, `string`, `comment`, `number`.

- Chú thích: `//` tới hết dòng; `/* … */`; `#` và `--` tới hết dòng khi đứng đầu dòng (sau khoảng trắng). `/*` không đóng thì kéo tới hết văn bản.
- Chuỗi: giữa `"`, `'` hoặc `` ` ``, tôn trọng dấu `\` thoát ký tự. Chuỗi không đóng thì dừng ở cuối dòng.
- Số: dãy chữ số, có thể có `.`, `_`, tiền tố `0x`, không đứng ngay sau ký tự định danh.
- Từ khoá: định danh nằm trong tập từ khoá chung của các ngôn ngữ phổ biến.
- Mọi thứ khác là `plain`.

Bộ tách không cần hiểu đúng ngữ pháp từng ngôn ngữ; mục tiêu là màu sắc hợp lý cho code thông dụng và không bao giờ làm hỏng hay mất ký tự.

### Hiển thị (`ClipboardFeature`)

Bảng màu theo tông One Dark: từ khoá `#C678DD`, chuỗi `#98C379`, chú thích `#7F848E`, số `#D19A66`, còn lại `#ABB2BF`. Phông đơn cách. Khung xem trước tô tối đa 20 000 ký tự đầu; thẻ trên notch tô đoạn trích.

## Văn bản có định dạng

### Mô hình và kho

- `ClipRichData`: `rtf: Data?`, `html: Data?`.
- `ClipboardStore.add` nhận thêm tham số `rich` (mặc định không có), chỉ dùng cho nội dung văn bản. Mỗi phần lớn hơn 2 000 000 byte bị bỏ; mục vẫn được lưu dạng văn bản thường.
- Dữ liệu được ghi thành tệp `<mã băm>.rtf` và `<mã băm>.html` trong `blobs/`; tên tệp lưu ở hai cột mới `rtf_blob`, `html_blob`.
- `ClipItem` thêm `rtfBlobName`, `htmlBlobName`. `ClipboardStore.richData(for:)` trả dữ liệu, hoặc `nil` nếu mục không có.
- Sao chép lại cùng văn bản: dữ liệu định dạng của mục được thay bằng của lần sao chép mới (kể cả thay bằng không có gì).
- Xoá, cắt bớt và xoá toàn bộ đều xoá các tệp này.

### Lược đồ phiên bản 2

Mở kho phiên bản 1 thì thêm hai cột bằng `ALTER TABLE` rồi đặt `user_version = 2`. Dữ liệu cũ giữ nguyên. Kho có phiên bản lớn hơn 2 vẫn bị từ chối.

### Đọc và ghi clipboard

- `PasteboardReader` đọc thêm `public.rtf` và `public.html` khi nội dung là văn bản.
- `PasteboardWriter` ghi văn bản thường kèm RTF và HTML nếu mục có.

## Trường hợp biên

| Tình huống | Xử lý |
|---|---|
| Văn bản rất dài | Nhận diện xét 4 000 ký tự đầu; tô màu tối đa 20 000 ký tự |
| Code có tiếng Việt hoặc emoji trong chuỗi và chú thích | Giữ nguyên, không lỗi |
| Tệp định dạng trong `blobs/` bị mất | `richData` trả phần còn lại; dán vẫn có văn bản thường |
| Dữ liệu định dạng quá lớn | Bỏ phần đó, vẫn lưu văn bản |
| Mục ảnh hoặc tệp kèm tham số `rich` | Bỏ qua `rich` |

## Kiểm thử

Kiểm thử đơn vị: `CodeDetector` (mẫu code của Swift, Python, JavaScript, JSON, HTML, SQL; mẫu không phải code gồm văn xuôi tiếng Việt và tiếng Anh, liên kết, mã màu, danh sách gạch đầu dòng), `CodeTokenizer` (từng loại token, tính phủ kín, các trường hợp không đóng), kho (lưu và đọc dữ liệu định dạng, thay khi trùng, xoá tệp, giới hạn kích thước, chuyển từ phiên bản 1).

Kiểm chứng trên app thật do Claude làm: ảnh panel và thẻ có code được tô màu; ghi RTF vào clipboard riêng, kiểm tra kho có tệp `.rtf`, rồi dùng phím giả ⌘Return để sao chép lại và kiểm tra clipboard riêng có đúng dữ liệu RTF đó.

## Tiêu chí hoàn thành

1. `Scripts/test.sh` qua toàn bộ.
2. Mẫu code trong dữ liệu mẫu được tô màu ở panel và ở thẻ notch; văn xuôi thì không.
3. RTF sao chép vào được lưu, và sao chép lại từ lịch sử trả đúng từng byte.
4. Kho phiên bản 1 mở được, giữ nguyên mục cũ, và báo phiên bản 2 sau khi mở.
