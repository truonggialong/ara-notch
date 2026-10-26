# Nền tảng (NotchCore, NotchShell)

Sổ của module **Platform**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Khung notch dùng chung cho mọi tính năng: hình notch, mở và đóng theo con trỏ, trang và hàng tab, hoạt động hai bên notch (live activity), biển thông báo, nhiều màn hình, cỡ hiển thị, phím tắt toàn cục, cài đặt của khung, và bộ thiết kế `Design/` (màu, chữ, nút, thẻ, widget, chọn ngày giờ, icon). Không biết tính năng nào cụ thể.

## Target và thư mục

- `NotchCore` — `Sources/NotchCore/`
- `NotchShell` — `Sources/NotchShell/`

## Phụ thuộc và ai dùng

- Dùng: Chỉ framework hệ thống; `NotchShell` dùng `NotchCore`.
- Được dùng bởi: Mọi `<X>Feature` và app `AraNotch`.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `NotchController.var onOpenSettings: (() -> Void)?`
- `NotchController.var geometry: NotchGeometry?`
- `NotchController.let settings: ShellSettings`
- `NotchController.var isOpenPublisher: AnyPublisher<Bool, Never>`
- `NotchController.var isKeyWindow: Bool`
- `NotchController.var selectedPageID: String?`
- `NotchController.var pageChrome: CGFloat`
- `NotchController.var selectedPagePublisher: AnyPublisher<String?, Never>`
- `NotchController.owns(_ window: NSWindow?) -> Bool`
- `NotchController.let shortcuts: ShortcutCenter`
- `NotchController.var isHiddenByUser = false`
- `NotchController.init(settings: ShellSettings, shortcuts: ShortcutCenter? = nil, leadingPageID: String? = nil)`
- `NotchController.var onFileDrag: (() -> Void)?`
- `NotchController.register(page: NotchPage)`
- `NotchController.var allPages: [PageDescriptor]`
- `NotchController.isPageHidden(id: String) -> Bool`
- `NotchController.setPageHidden(_ isHidden: Bool, id: String)`
- `NotchController.movePage(id: String, by offset: Int)`
- `NotchController.start()`
- `NotchController.open()`
- `NotchController.toggleOpen()`
- `NotchController.focusTextField()`
- `NotchController.toggleHidden()`
- `NotchController.close()`
- `NotchController.setKeepsOpen(_ keeps: Bool, forPage id: String)`
- `NotchController.setBeingEdited(_ isEdited: Bool, forPage id: String)`
- `NotchController.releaseKeyboardFocus()`
- `NotchController.setSheetHeight(_ height: CGFloat?, forPage id: String)`
- `NotchController.selectPage(id: String)`
- `NotchController.present(_ activity: NotchLiveActivity)`
- `NotchController.dismissActivity(id: String)`
- `NotchController.setRestingActivity(_ activity: NotchLiveActivity?, id: String)`
- `NotchController.var treatsDisplaysAsNotchless = false`

## Ghi chú cho người sửa

- **Ngoại lệ có chủ ý:** `ShortcutAction` (danh mục phím tắt toàn cục, có tên hành động của Clipboard, Translate, Capture) nằm ở đây, vì việc kiểm tra trùng phím cần thấy mọi phím. Thêm một phím tắt toàn cục mới cho tính năng = thêm một case ở đây; đó là thay đổi giao diện công khai của nền tảng, phải báo trước.
- `NotchController` là đầu mối mà tính năng dùng: `register(page:)`, `present(_:)`, `setRestingActivity`, `setSheetHeight`, `setKeepsOpen`, `setBeingEdited`, `shortcuts`.
- Bộ widget dùng chung: `WidgetSize`, `WidgetAlert`, `WidgetMeasure`, `WidgetPalette` (`NotchCore`), `AraWidget` và `\.araTileSize` (`NotchShell/Design`).

## Dữ liệu lưu

- UserDefaults `shell.*`: `openOnHover`, `hoverDelay`, `hapticsEnabled`, `pageOrder`, `hiddenPages`, `startPage`, `hidesFromCapture`, `swipeToOpen`, `swipeSensitivity`, `interactionPadding`, `displayMode`, `hidesInFullScreen`, `pillStyle`, `notchSize`, `appearance`, `hasSeenWelcome` (`ShellSettingsStore`).
- UserDefaults `shortcut.<action>` cho từng `ShortcutAction` (`ShortcutStore`); hàng phím số lưu ở khoá do tính năng khai báo (`NumberRow.storageKey`).
- Khoá cũ chỉ còn để dọn hoặc chuyển dữ liệu: `recentNames.event|reminder|timer` và `calendar.pageSize` bị xoá mỗi lần mở app (`RetiredSettings` trong `Pickers.swift`); `clipboard.panelAppearance` vẫn được đọc làm giá trị dự phòng khi chưa có `shell.appearance` (`ShellSettingsStore.appearance`).

## Quyền hệ thống

Không cần quyền nào. `PointerMonitor` theo dõi chuột toàn cục không cần quyền; phím tắt toàn cục dùng Carbon hot key, không cần quyền.

## Test

- Chạy: `Scripts/test-module.sh Platform`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/NotchCoreTests/` (47 suite), `Tests/NotchShellTests/` (4 suite)

## Tệp

- `Sources/NotchCore/AppAppearanceAndSearch.swift` — The look of the app's windows.
- `Sources/NotchCore/AppLanguage.swift` — The language the app speaks: the Mac's, or one chosen for this app alone.
- `Sources/NotchCore/AppUpdate.swift` — The rules of the app's updates that need no updater to state: when it runs, which feed it may be pointed at by hand, and how releases are named where they are published.
- `Sources/NotchCore/DisplayChooser.swift` — Which display the notch lives on when several are connected.
- `Sources/NotchCore/FullScreenRule.swift` — When an app is full screen on a display (a video, a presentation), the notch on that display gets out of the way; a notice still drops out of it for its few seconds.
- `Sources/NotchCore/LiveActivityQueue.swift` — A request to show something beside the closed notch for a while.
- `Sources/NotchCore/NotchDropLayout.swift` — A notice that drops out of the closed notch: the notch grows downwards into a sign, one piece with it, instead of showing something on either side.
- `Sources/NotchCore/NotchGeometry.swift` — How the notch is drawn on a display that has no hardware notch.
- `Sources/NotchCore/NotchStateMachine.swift` — Decides when the notch opens and closes.
- `Sources/NotchCore/PageRegistry.swift` — Identity and tab appearance of one notch page.
- `Sources/NotchCore/Pickers.swift` — The geometry of the clock face a time is chosen on.
- `Sources/NotchCore/ScreenDescriptor.swift` — Plain measurements of one display, in global coordinates with a bottom-left origin.
- `Sources/NotchCore/ShellSettingsStore.swift` — Reads and writes the shell's settings.
- `Sources/NotchCore/Shortcuts.swift` — The modifier keys of a shortcut.
- `Sources/NotchCore/SwipeAccumulator.swift` — Turns the scroll deltas of one trackpad gesture into at most one page switch.
- `Sources/NotchCore/ThemePalette.swift` — A colour of the theme, as plain numbers, so the palette can be checked without drawing.
- `Sources/NotchCore/TooltipAndKeys.swift` — Where a tooltip goes on screen, in AppKit's coordinates (y grows upwards).
- `Sources/NotchCore/UninstallPlan.swift` — What taking AraNotch off a Mac removes, besides the app itself: its hooks and status line are taken out of Claude Code's settings (which are changed, never removed), the caches go, and with them, when the user asks, the clipboard history, the agent data and the settings.
- `Sources/NotchCore/VerticalSwipeDetector.swift` — How far two fingers must travel for a swipe to count.
- `Sources/NotchCore/WidgetAlert.swift` — When a widget turns from its own colour to the alert orange: something wants the user soon.
- `Sources/NotchCore/WidgetMeasure.swift` — How much of a widget's bars to fill.
- `Sources/NotchCore/WidgetPalette.swift` — The colours of the overview's widgets: dark cards on the black notch, in every appearance, with each feature's colour made brighter so it stands out, and one orange for what wants the user now.
- `Sources/NotchCore/WidgetSize.swift` — How big a widget is drawn, in cells of the grid it stands on: small is one cell, wide two side by side, large two by two.
- `Sources/NotchShell/Design/AraControls.swift` — Whether the pointer is over a control.
- `Sources/NotchShell/Design/AraGlyph.swift` — The app's own drawings, for the places that give it a face: the tabs of the notch and the menu bar.
- `Sources/NotchShell/Design/AraIcon.swift` — The app's icons, by what they mean.
- `Sources/NotchShell/Design/AraMomentPicker.swift` — What the floating picker is choosing.
- `Sources/NotchShell/Design/AraPalette.swift` — One of the colours mixed in beside the black, the white and the orange: each page of the notch has one, and so has each kind of clip.
- `Sources/NotchShell/Design/AraPaper.swift` — A small caption: what the things under or beside it are.
- `Sources/NotchShell/Design/AraPickers.swift` — Names typed before, for features that do not see the core module.
- `Sources/NotchShell/Design/AraQuickLook.swift` — Shows files in the system's Quick Look panel, the one the space bar opens in Finder.
- `Sources/NotchShell/Design/AraScale.swift`
- `Sources/NotchShell/Design/AraSettingsKit.swift` — A group of related switches in Settings shown as one row of chips: a lit chip is on.
- `Sources/NotchShell/Design/AraSign.swift` — A notice written like a wayfinding sign: on the left what speaks (an icon, its name and perhaps a line about it), a hairline, and on the right the news in one or two rows, each a label with, where it helps, a small line under it and a box of digits or a disc.
- `Sources/NotchShell/Design/AraSurface.swift` — Measures and motion shared by every surface of the app.
- `Sources/NotchShell/Design/AraTooltip.swift` — Shows the name of an icon button right away.
- `Sources/NotchShell/Design/AraWidget.swift` — The smallest text a widget has, before enlargement.
- `Sources/NotchShell/GlobalHotKeys.swift` — Global shortcuts that work in every app.
- `Sources/NotchShell/InputMethodKeys.swift`
- `Sources/NotchShell/L10n.swift` — Looks up user-facing strings in the app bundle's `Localizable.strings`.
- `Sources/NotchShell/NSScreen+Descriptor.swift`
- `Sources/NotchShell/NotchController.swift` — Owns the notch window and connects pointer input to the state machine.
- `Sources/NotchShell/NotchLiveActivity.swift` — Something shown beside the closed notch for a short while: one view to the left of the notch and one to the right.
- `Sources/NotchShell/NotchPage.swift` — A page shown inside the open notch: its tab descriptor plus the view to display.
- `Sources/NotchShell/NotchPanel.swift` — Transparent window that sits above the menu bar.
- `Sources/NotchShell/NotchRootView.swift` — The notch itself: a black shape that grows from the notch into the open panel.
- `Sources/NotchShell/NotchShape.swift` — Black notch outline: rounded bottom corners, and concave "ears" where it meets the screen edge.
- `Sources/NotchShell/NotchViewModel.swift` — State the notch views render from.
- `Sources/NotchShell/PointerMonitor.swift` — Reports pointer movement, clicks and scrolling, whichever app they are delivered to.
- `Sources/NotchShell/ShellSettings.swift` — Observable settings for the shell; every change is written through to the store.
- `Sources/NotchShell/ShortcutCenter.swift` — The app's global shortcuts in one place: which keys they are (the user can change or remove each one), what they do, and whether the system accepted them.

## Lỗi và giới hạn đã biết

- Khi bật ẩn khỏi quay màn hình, công cụ chụp ảnh của chính Claude cũng không thấy notch, panel và Library.
- Notch chỉ hiện trên một màn hình tại một thời điểm, không hiện đồng thời trên mọi màn hình.
- Viên Pill nổi phía trên cửa sổ các app, ngay dưới thanh menu, nên che một dải nhỏ ở mép trên của cửa sổ nằm giữa màn hình. Vị trí và kích thước viên chưa chỉnh được.
- Phím tắt toàn cục: macOS không cho biết app khác có đang dùng cùng tổ hợp hay không. Trên máy chủ dự án, ⇧⌘2 (chụp vùng, mặc định tắt) cũng là phím của CleanShot X, nên bật lên thì cả hai cùng mở khung chụp; cần đổi tổ hợp ở một trong hai app.
- Icon vẽ riêng mới có cho các tab của notch, nút cài đặt và thanh menu; các icon còn lại dùng thư viện ký hiệu của macOS qua danh mục `AraIcon`. Chú giải tức thì có ở nút icon và tab; các menu thả xuống dạng icon vẫn dùng chú giải chậm của macOS.
- Bấm vào hoạt động bên notch: cú bấm cũng đi xuống thanh menu nằm dưới vùng đó, vì cửa sổ của notch không chặn chuột khi đang đóng.
- Notch chỉ nhận bàn phím khi được mở bằng phím tắt (hoặc sau khi bấm vào một ô chữ); mở bằng rê chuột thì phím vẫn thuộc về app đang dùng. Tab trong notch đổi trang, không đi lần lượt qua từng nút.
- Giao diện Sáng chưa áp cho notch (luôn tối) và chú giải tức thì (luôn tối).
- Cỡ hiển thị: notch mở ở 110% rộng 704 điểm, ở 150% rộng 960 điểm, nên lúc mở che thêm vài mục của thanh menu ở hai bên notch. Ở 150% hàng tab và thông báo cạnh notch chỉ lớn tới 130%. Lựa chọn "Lớn" hay "Rất lớn" đã lưu từ trước bản 0.2.1 nay ứng với 125% và 150%.
- Vuốt ngang trên notch đóng để chuyển bài chưa có công tắc tắt riêng. Thứ bị vuốt ẩn cạnh notch trở lại sau lần mở notch kế tiếp, không có nút gọi lại riêng.
- Vẫn cần bàn phím: gõ nội dung (ô tìm, ghi chú, chữ chú thích trên ảnh, văn bản cần dịch), mật mã khi không dùng Touch ID, ghi phím tắt trong Cài đặt, và Esc để huỷ chụp một vùng (do công cụ chụp của hệ thống đảm nhận). Chip gợi ý hiện dòng đầu của clipboard nếu ngắn hơn 40 ký tự, kể cả khi đó là thứ bạn không định dùng làm tên.
- Toàn màn hình và gỡ cài đặt (0.18.0): app toàn màn hình được nhận ra bằng một cửa sổ thường phủ kín màn hình, nên một cửa sổ không viền phủ kín (một số trò chơi, trình chiếu) cũng làm notch ẩn, và một app toàn màn hình chưa kịp hiện cửa sổ trong 0,6 giây có thể chưa được nhận ra cho tới lần đổi app sau. Gỡ cài đặt chỉ mới thử trên thư mục nhà giả; mục mở cùng máy và việc chuyển app vào Thùng rác chưa thử thật. Biển ở cuối trang Lịch che một phần danh sách trong vài giây.
- Notch trên mọi màn hình: chỉ notch ở màn hình có con trỏ trả lời. Khi notch đang mở hoặc đang ghim ở một màn hình thì notch ở các màn hình khác không mở được cho tới khi nó đóng. Mỗi lần con trỏ đổi màn hình, hiệu ứng của biển đang hiện bắt đầu lại ở hai màn hình vừa đổi vai. Trên màn hình không có tai thỏ, từ bản 0.17.1 notch chờ chỉ là vạch 150 × 10 điểm; khi nó lớn ra (bị chạm, có thông báo, có bài đang phát hay đồng hồ) nó vẫn che một đoạn giữa thanh menu, và lúc chờ phải đưa chuột lên sát mép trên mới chạm được.
- Biển thông báo: mỗi dòng chữ dài quá 170 điểm bị cắt bằng dấu ba chấm; lời của agent tối đa hai dòng. Phần trên của biển cao bằng notch và để trống, vì ở giữa là tai thỏ. Biển không theo giao diện sáng của các cửa sổ khác. Các tia màu vẽ lại liên tục trong vài giây biển hiện, tốn khoảng một phần năm một lõi CPU trong lúc đó (đo ở bản dựng thử), nhiều hơn dải màu của bản 0.15.0. Trên biển hẹp gần bằng tai thỏ, hai góc trên nằm sát tai thỏ nên màu ở góc ít thấy hơn. Chưa có cài đặt để chọn lại kiểu thông báo hai bên notch như trước.
- Cỡ hiển thị: tỉ lệ chỉ áp dụng cho notch và những gì hiện cạnh notch; cửa sổ Thư viện, bảng clipboard và Cài đặt giữ cỡ chữ riêng. Ở 120% trang Lịch cao hết mức hiện ít hàng hơn một chút, vì notch vẫn dừng ở 80% chiều cao màn hình.
- Trang thấp đi dưới con trỏ (0.7.1): khi một trang co lại làm con trỏ nằm ngoài notch (mở bảng chọn ngày giờ, đóng ô chỉnh, xong một lời nhắc ở cuối danh sách), notch ở yên chờ con trỏ quay lại. Nếu con trỏ đi thẳng sang chỗ khác thì notch vẫn mở cho tới lần bấm chuột kế tiếp ở ngoài. Chưa thử tay với con trỏ thật: chủ dự án đang dùng máy.
- Chủ đề thẻ giấy: màu của trang và của loại clip là cố định, chưa có cài đặt để đổi hay tắt. Ô chọn, thanh trượt và công tắc trong Cài đặt vẫn là điều khiển của macOS, chỉ đổi màu nhấn sang đỏ gạch. Ở chế độ Sáng, viền đỏ gạch của thẻ trùng màu nền đỏ rượu nên thẻ tách khỏi nền bằng màu kem của nó chứ không bằng viền. Thanh tiêu đề của Thư viện và Cài đặt không còn chữ tiêu đề. Màu của lịch (vạch bên trái sự kiện) vẫn là màu người dùng đặt trong app Lịch.
- Hàng tab chỉ chứa khoảng 6 tab bên trái notch.
- Trên màn hình không có notch, bấm notch ảo đang đóng cũng bấm trúng mục thanh menu bên dưới.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): bỏ tên Overview khỏi nền tảng (`PageRegistry.order(_:leading:)`, `NotchController(leadingPageID:)`); `OverviewTileSize` → `WidgetSize`, `OverviewAlert` → `WidgetAlert`; hàng phím số thành khái niệm chung `NumberRow`, `ShortcutCenter.setNumberRow`; chuỗi `settings.shortcuts.quickPaste.refused` → `settings.shortcuts.numberRow.refused`.
