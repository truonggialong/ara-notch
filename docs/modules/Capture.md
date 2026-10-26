# Chụp màn hình (CaptureCore, CaptureFeature)

Sổ của module **Capture**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Chụp một vùng, chụp cuộn, chép chữ trong vùng (OCR trên máy), chọn màu trên màn hình, cửa sổ chú thích (mũi tên, khung, tô sáng, bút, chữ, làm mờ, số thứ tự), tách nền ảnh.

## Target và thư mục

- `CaptureCore` — `Sources/CaptureCore/`
- `CaptureFeature` — `Sources/CaptureFeature/`

## Phụ thuộc và ai dùng

- Dùng: `CaptureFeature` dùng `CaptureCore`, `NotchShell`, Vision, CoreImage.
- Được dùng bởi: App (`CaptureController`); app trao `recognizeText`, `cutOutSubject` cho Clipboard, và các hành động chụp cho Tools.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `CaptureController.init(store: CaptureSettingsStore)`
- `CaptureController.var onNotice: ((_ symbol: String, _ message: String) -> Void)?`
- `CaptureController.init(settings: CaptureSettings, shortcuts: ShortcutCenter, pasteboard: NSPasteboard = .general)`
- `CaptureController.start()`
- `CaptureController.makeSettingsSection() -> AnyView`
- `CaptureController.capture()`
- `CaptureController.captureText()`
- `CaptureController.pickColor()`
- `CaptureController.cutOutSubject(fromImageData data: Data, completion: @escaping @MainActor (Data?) -> Void)`
- `CaptureController.recognizeText(inImageData data: Data, completion: @escaping @MainActor (String) -> Void)`
- `CaptureController.captureScrolling()`
- `CaptureController.captureScrolling(in rect: CGRect, framesDirectory: URL? = nil)`
- `CaptureController.capture(rect: CGRect)`
- `CaptureController.openEditor(forImageAt file: URL) -> Bool`
- `CaptureController.recognizeText(inImageAt file: URL, writingTo output: URL)`
- `CaptureController.renderSample(ontoImageAt file: URL, writingTo output: URL)`

## Ghi chú cho người sửa

- Không có.

## Dữ liệu lưu

- UserDefaults `capture.shortcutEnabled` (`CaptureSettingsStore`). Ảnh chụp tạm `aranotch-capture-<uuid>.png` trong thư mục tạm.

## Quyền hệ thống

Ghi màn hình (chụp); Trợ năng (chụp cuộn gửi lệnh cuộn).

## Test

- Chạy: `Scripts/test-module.sh Capture`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/CaptureCoreTests/`, `Tests/CaptureFeatureTests/`

## Tệp

- `Sources/CaptureCore/Annotation.swift` — A colour for drawing on a capture.
- `Sources/CaptureCore/ScrollStitch.swift` — What one pixel row of a frame looks like: how bright it is, on average, in each of several column bands.
- `Sources/CaptureFeature/CaptureController.swift` — Observable capture settings; every change is written through to the store.
- `Sources/CaptureFeature/CaptureEditor.swift` — State of one capture being annotated.
- `Sources/CaptureFeature/CaptureServices.swift` — Takes a picture of a part of the screen with the system's own capture tool, which brings its own selection crosshair.
- `Sources/CaptureFeature/ScrollCapture.swift` — Lets the user drag out a rectangle on the screen under the pointer.

## Lỗi và giới hạn đã biết

- Chụp màn hình cần quyền Ghi màn hình mà chỉ người dùng cấp được trong Cài đặt hệ thống (chủ dự án đã cấp ngày 2026-10-12); chưa có quyền thì ảnh chỉ có hình nền và cửa sổ của chính AraNotch.
- Vùng chụp được chọn bằng công cụ `screencapture` của macOS, không phải giao diện riêng của AraNotch: không có kính lúp hay kích thước tuỳ biến ngoài những gì công cụ đó có. Chưa có chụp cuộn, chưa chụp hẹn giờ, chưa che mờ vùng nhạy cảm.
- Lần đọc chữ trong ảnh đầu tiên sau khi cài hoặc đổi bản app mất khoảng 30 giây vì macOS nạp mô hình nhận dạng; các lần sau khoảng 1 giây. Chữ ở hai cột cạnh nhau được ghép theo hàng ngang, nên thứ tự có thể không như mong muốn.
- Hình đã vẽ không chọn lại, dời hay đổi màu được; chỉ hoàn tác. Công cụ chữ chỉ viết một dòng, cỡ chữ cố định.
- Chụp cuộn tự gửi lệnh cuộn vào cửa sổ nằm dưới giữa vùng chọn, nên cần quyền Trợ năng và con trỏ chuột bị dời tới đó trong chốc lát ở mỗi bước. Trang được nhận ra bằng độ sáng từng dải của mỗi hàng điểm ảnh: trang gần như trống, video hay nội dung đang chuyển động có thể làm việc ghép dừng sớm. Phần đầu trang dính cố định trong vùng chọn sẽ làm ghép sai; nên chọn vùng nằm dưới phần đó. Ảnh dài nhất 30.000 điểm ảnh, tối đa 80 khung.
- Trên máy chủ dự án, lệnh cuộn giả lập bị đảo chiều và mỗi lệnh cuộn một quãng gần như cố định bất kể số dòng yêu cầu (nhiều khả năng do phần mềm chuột hoặc cài đặt cuộn). App tự dò chiều nên vẫn chạy, nhưng vì thế vài khung đầu có thể cuộn ngược lên trước khi đi xuống.
- Tách nền dựa vào Vision của macOS: ảnh không có chủ thể rõ thì báo "không thấy chủ thể". Kết quả được cắt sát chủ thể.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- Chưa có.
