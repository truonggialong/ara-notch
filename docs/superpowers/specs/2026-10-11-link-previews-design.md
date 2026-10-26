# AraNotch — Xem trước liên kết (mảng 2d) — Thiết kế

Ngày: 2026-10-11 · Dựa trên: `2026-10-11-clipboard-rich-design.md`

## Mục tiêu

Liên kết đã sao chép hiện kèm tiêu đề trang và ảnh đại diện, thay vì chỉ là một dòng URL.

## Quyết định của chủ dự án

Tính năng **mặc định bật**, có công tắc trong Cài đặt để tắt (lựa chọn B ngày 2026-10-11). Chủ dự án đã được báo trước rằng việc tự tải trang có thể kích hoạt liên kết dùng một lần và cho trang web biết liên kết đã được sao chép.

## Phạm vi

Trong phạm vi:

- Sau khi một liên kết được ghi nhận từ clipboard, app tải trang đó một lần để lấy tiêu đề và ảnh đại diện, rồi lưu vào kho.
- Bộ lọc an toàn quyết định liên kết nào không bao giờ được tự tải.
- Thẻ notch, dòng và khung xem trước của panel hiện tiêu đề và ảnh khi có.
- Công tắc trong Cài đặt; tắt thì không có yêu cầu mạng nào.

Ngoài phạm vi: phát video YouTube, TikTok tại chỗ; làm mới bản xem trước đã lưu; tải lại khi lỗi.

## Bộ lọc an toàn (`LinkPreviewPolicy`, `ClipboardCore`)

`shouldFetch(_ url:)` trả về sai, tức không tải, khi:

- Lược đồ không phải `http` hoặc `https`, hoặc không có host.
- URL chứa tên đăng nhập hoặc mật khẩu.
- Host là `localhost`, kết thúc bằng `.local`, `.internal`, `.lan`, `.home`, không có dấu chấm, hoặc là địa chỉ IP (IPv4 hay IPv6). Liên kết tới thiết bị trong mạng nội bộ có thể thực hiện hành động khi được mở.
- Cổng khác 80 và 443.
- Đường dẫn chứa một trong các từ (không phân biệt hoa thường): `unsubscribe`, `confirm`, `verify`, `activate`, `reset`, `magic`, `login`, `logout`, `signin`, `signout`, `auth`, `oauth`, `token`, `invite`, `delete`, `remove`, `cancel`, `approve`, `accept`, `decline`, `callback`, `authenticate`, `authorize`, `authorization`, `verification`, `confirmation`, `activation`. So khớp theo từ nguyên vẹn (tách ở mọi ký tự không phải chữ hay số), nên `/authors/` không bị nhầm với `auth`.
- Tham số truy vấn có tên chứa một trong: `token`, `code`, `key`, `secret`, `signature`, `sig`, `auth`, `password`, `otp`, `session`, `ticket`, `nonce`. Cũng so theo từ nguyên vẹn: `access_token` bị chặn, `keyword` thì không.

Bộ lọc này giảm rủi ro chứ không loại bỏ hẳn: một liên kết dùng một lần không có dấu hiệu nào ở trên vẫn sẽ được tải.

## Đọc trang (`LinkMetadataParser`, `ClipboardCore`)

`parse(html:baseURL:)` trả về `LinkMetadata` gồm `title` và `imageURL`, cả hai có thể thiếu.

- Tiêu đề: `og:title`, rồi `twitter:title`, rồi thẻ `<title>`. Giải mã thực thể HTML (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`, `&apos;`, `&nbsp;`, dạng số thập phân và thập lục phân), gộp khoảng trắng, cắt còn 200 ký tự. Tiêu đề rỗng coi như không có.
- Ảnh: `og:image`, rồi `twitter:image`. URL tương đối được ghép với `baseURL`. Chỉ nhận `http` và `https`.
- Thẻ `<meta>` được nhận cả khi thuộc tính viết theo thứ tự `content` trước `property`, dùng nháy đơn hay nháy kép, và `name` thay cho `property`.
- Chỉ xét 512 000 ký tự đầu.

## Kho (lược đồ phiên bản 3)

Ba cột mới trên `items`: `link_title`, `link_image_blob`, `link_checked_at`.

- `ClipItem` thêm `linkTitle`, `linkImageBlobName`, `linkCheckedAt`.
- `setLinkPreview(id:title:imageData:at:)`: ghi kết quả (kể cả kết quả rỗng) và thời điểm kiểm tra. Ảnh lớn hơn 2 000 000 byte bị bỏ. Ảnh lưu thành `<mã băm>.preview` trong `blobs/`.
- `linkImageData(for:)`.
- Xoá, cắt bớt, xoá toàn bộ đều xoá tệp ảnh xem trước.
- Sao chép lại cùng liên kết giữ nguyên bản xem trước đã có.
- Kho phiên bản 1 và 2 được nâng lên 3; phiên bản lớn hơn 3 bị từ chối.

Cài đặt: `clipboard.linkPreviews` (Bool, mặc định bật).

## Tải (`LinkPreviewFetcher`, `ClipboardFeature`)

- Chỉ chạy cho mục loại `link` vừa được ghi nhận **từ clipboard**, chưa có `linkCheckedAt`, khi cài đặt đang bật và bộ lọc cho phép.
- Phiên `URLSession` tạm thời: không cookie, không bộ nhớ đệm, không thông tin đăng nhập, thời hạn 6 giây.
- Chỉ dùng phương thức GET. Chỉ đọc khi phản hồi có mã 200 và kiểu nội dung là HTML; đọc tối đa 512 000 byte rồi dừng.
- Sau chuyển hướng, URL cuối cùng phải qua bộ lọc; nếu không thì bỏ kết quả.
- Ảnh đại diện được tải bằng một yêu cầu thứ hai, URL của nó cũng phải qua bộ lọc, tối đa 2 000 000 byte.
- Mỗi mục chỉ được thử một lần, thành công hay thất bại. Lỗi được ghi log, không báo cho người dùng.

## Trường hợp biên

| Tình huống | Xử lý |
|---|---|
| Không có mạng, hết thời hạn, mã lỗi | Ghi `link_checked_at`, không có tiêu đề; thẻ hiện như cũ |
| Trang không phải HTML (PDF, ảnh) | Không đọc nội dung |
| Trang rất lớn | Dừng ở 512 000 byte |
| Tắt cài đặt khi đang tải | Kết quả đang về vẫn được lưu; không có yêu cầu mới |
| Mục bị xoá trước khi tải xong | Bỏ kết quả |

## Kiểm thử

Kiểm thử đơn vị: `LinkPreviewPolicy` (từng quy tắc), `LinkMetadataParser` (thứ tự ưu tiên, thực thể, URL tương đối, thứ tự thuộc tính, HTML hỏng), kho (ghi, đọc, xoá tệp, giữ khi trùng, nâng từ phiên bản 2), cài đặt.

Kiểm chứng trên app thật do Claude làm: chạy một máy chủ web nhỏ trên chính máy này phục vụ một trang có `og:title` và `og:image`; app được chạy với tham số `--allow-local-link-previews` (chỉ để kiểm chứng, vì bộ lọc vốn chặn địa chỉ nội bộ); ghi liên kết vào clipboard riêng; kiểm tra kho có tiêu đề và ảnh, và nhật ký máy chủ chỉ có các yêu cầu GET mong đợi. Kiểm tra thêm: liên kết bị bộ lọc chặn không tạo yêu cầu nào; tắt cài đặt thì không có yêu cầu nào.

## Tiêu chí hoàn thành

1. `Scripts/test.sh` qua toàn bộ.
2. Liên kết hợp lệ có tiêu đề và ảnh trong kho và trên giao diện.
3. Liên kết bị bộ lọc chặn và trường hợp tắt cài đặt đều không sinh yêu cầu mạng.
4. Kho phiên bản 2 mở được và lên phiên bản 3.
