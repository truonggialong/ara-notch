# Tệp (FilesCore, FilesFeature)

Sổ của module **Files**. Đọc `Modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Trang Tệp: thả tệp lên notch để đổi định dạng ảnh, thu nhỏ, nén, gộp PDF, gửi AirDrop; kéo kết quả ra ngoài, Xem nhanh.

## Target và thư mục

- `FilesCore` — `Modules/Files/Core/`
- `FilesFeature` — `Modules/Files/Feature/`

## Phụ thuộc và ai dùng

- Dùng: `FilesFeature` dùng `FilesCore`, `NotchShell`.
- Được dùng bởi: App (`FilesController`; `NotchController.onFileDrag` mở trang Tệp khi đang kéo tệp).

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `FilesController.init()`
- `FilesController.makePage() -> NotchPage`
- `FilesController.showDropTargets()`
- `FilesController.filesAreBeingDragged()`
- `FilesController.add(_ urls: [URL])`
- `FilesController.run(actionNamed name: String)`

## Ghi chú cho người sửa

- Không có.

## Dữ liệu lưu

- Kết quả ghi cạnh tệp gốc (tên có số khi trùng), qua tệp tạm `.partial`. Danh sách tệp chỉ nằm trong bộ nhớ.

## Quyền hệ thống

Không cần quyền.

## Test

- Chạy: `Scripts/test-module.sh Files`, rồi `Scripts/test.sh`.
- Bộ test: `Modules/Files/Tests/Core/`

## Tệp

- `Modules/Files/Core/FileActions.swift` — The image formats files can be converted to.
- `Modules/Files/Core/FileDropTile.swift` — The actions shown as places to drop while files are dragged over the Files page: letting go over one adds the files and does it at once.
- `Modules/Files/Feature/FilesController.swift` — State the Files page renders from.

## Lỗi và giới hạn đã biết

- Trang Tệp chỉ xử lý ảnh; tệp loại khác chỉ gửi được AirDrop. Danh sách tệp mất khi thoát app. Chưa chọn được mức nén hay kích thước tuỳ ý.
- Đổi định dạng và thu nhỏ không giữ siêu dữ liệu của ảnh gốc (EXIF, vị trí chụp); ảnh xoay theo EXIF được ghi lại theo chiều đứng đúng.
- Khi giữ nút chuột, app theo dõi vị trí con trỏ 15 lần mỗi giây để nhận ra tệp đang được kéo tới notch.
- Kéo tệp: nếu vẫn đẩy tệp lên sát mép trên màn hình thì macOS vẫn có thể bật Mission Control; app không tắt được hành vi đó của hệ thống, chỉ mở notch sớm để không cần lên tới mép. Vùng mở sớm cũng có nghĩa notch sẽ mở khi kéo tệp ngang qua ngay dưới notch để tới chỗ khác.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- Chưa có.
