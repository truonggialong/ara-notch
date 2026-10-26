# Dịch (TranslateCore, TranslateFeature)

Sổ của module **Translate**. Đọc `Modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Dịch nhanh đoạn đang chọn (⌘⇧G) bằng Google, thay đoạn chọn bằng bản dịch, đọc to; Smart Selection (thanh Copy, Dịch, Tìm hiện cạnh đoạn vừa chọn); tóm tắt và viết lại bằng Apple Intelligence trên máy (`TextAssistant`, dùng từ menu clip).

## Target và thư mục

- `TranslateCore` — `Modules/Translate/Core/`
- `TranslateFeature` — `Modules/Translate/Feature/`

## Phụ thuộc và ai dùng

- Dùng: `TranslateFeature` dùng `TranslateCore`, `NotchShell`, FoundationModels, AVFoundation.
- Được dùng bởi: App (`TranslateController`); app trao `assistant` cho Clipboard và "dịch" cho Tools.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `TranslateController.init(store: TranslateSettingsStore)`
- `TranslateController.let assistant = TextAssistant()`
- `TranslateController.init(settings: TranslateSettings, shortcuts: ShortcutCenter)`
- `TranslateController.start()`
- `TranslateController.makeSettingsSection() -> AnyView`
- `TranslateController.translate(_ text: String)`
- `TranslateController.showSelectionBar(for text: String)`
- `TranslateController.translateSelection()`

## Ghi chú cho người sửa

- Không có.

## Dữ liệu lưu

- UserDefaults `translate.enabled`, `translate.target`, `translate.alternate`, `translate.smartSelection` (`TranslateSettingsStore`).

## Quyền hệ thống

Trợ năng (đọc và thay đoạn đang chọn). Đoạn chữ chỉ gửi tới Google khi người dùng dịch.

## Test

- Chạy: `Scripts/test-module.sh Translate`, rồi `Scripts/test.sh`.
- Bộ test: `Modules/Translate/Tests/Core/`

## Tệp

- `Modules/Translate/Core/GoogleTranslate.swift` — The result of one translation.
- `Modules/Translate/Core/SmartSelection.swift` — Tells a press and release that may have selected text from a plain click.
- `Modules/Translate/Feature/SmartSelectionController.swift` — Reads what is selected in the app in front, through Accessibility.
- `Modules/Translate/Feature/TextAssistant.swift` — Summarises and rewrites text with the model Apple Intelligence keeps on this Mac.
- `Modules/Translate/Feature/TranslateController.swift` — Observable quick-translate settings; every change is written through to the store.

## Lỗi và giới hạn đã biết

- Dịch nhanh gửi đoạn chữ đang chọn tới Google qua một địa chỉ miễn phí không chính thức (chủ dự án đã chọn). Google không cam kết địa chỉ này: có thể bị chặn hoặc đổi, và dùng nó trong sản phẩm phát hành không đúng điều khoản của Google. Trước khi phát hành cần cân nhắc lại.
- Khi bật dịch nhanh, ⌘⇧G bị AraNotch giữ nên không còn tới app khác (nhiều app dùng ⌘⇧G cho "Tìm trước đó"). Chưa đổi được phím tắt.
- Với app không báo vùng chọn qua Trợ năng, dịch nhanh tự chép vùng chọn (⌘C), nên đoạn đó cũng nằm lại trên clipboard và trong lịch sử.
- Smart Selection chỉ thấy vùng chọn mà app báo qua Trợ năng. App không báo (một số app Electron, một số trình duyệt khi chưa bật trợ năng) thì thanh không hiện; app không tự chép vùng chọn để dò.
- Smart Selection đọc đoạn đang chọn sau mỗi lần kéo hoặc bấm đúp chuột ở app bất kỳ khi công tắc bật. Đoạn chữ chỉ rời máy khi người dùng bấm Dịch hoặc Tìm; Tìm đưa đoạn chữ vào địa chỉ tìm kiếm của Google.
- Thanh Smart Selection có thể hiện nhầm một lần khi kéo một thứ không phải chữ (một cửa sổ chẳng hạn) trong lúc ô đang nhập vẫn còn chữ được chọn. Chọn bằng bàn phím (⇧ và mũi tên) không làm thanh hiện.
- Apple Intelligence chỉ có trên macOS 26 trở lên, máy đủ điều kiện, đã bật và đã tải xong mô hình; trạng thái chỉ được đọc khi mở app. Chữ dài hơn 12.000 ký tự bị cắt trước khi đưa cho mô hình.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- Chưa có.
