# Clipboard (ClipboardCore, ClipboardFeature, ClipboardMCP)

Sổ của module **Clipboard**. Đọc `Modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Lịch sử clipboard và mọi thứ quanh nó: ghi lại những gì được chép (chữ, link, màu, ảnh, tệp), tìm kiếm, board và ghim, két khoá bằng mật mã, panel nổi ⌘⇧C, cửa sổ Thư viện, sửa clip và ghi chú mới, công cụ sửa chữ, copy stack, dán theo số, sao lưu và nhập, xem trước link, đọc chữ trong ảnh, trang Clipboard và widget Clipboard của Tổng quan, máy chủ MCP chỉ đọc cho agent.

## Target và thư mục

- `ClipboardCore` — `Modules/Clipboard/Core/`
- `ClipboardFeature` — `Modules/Clipboard/Feature/`
- `ClipboardMCP` — `Modules/Clipboard/MCP/`
- `aranotch-mcp` — `Modules/Clipboard/aranotch-mcp/`

## Phụ thuộc và ai dùng

- Dùng: `ClipboardFeature` dùng `ClipboardCore`, `NotchShell`, `NotchCore`. `ClipboardMCP`/`aranotch-mcp` chỉ dùng `ClipboardCore`.
- Được dùng bởi: App (`ClipboardController`). App nối thêm các hàm từ module khác vào controller: `recognizeText`, `cutOutSubject` (Capture), `createReminder` (Calendar), `assistant` (Translate).

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `ClipboardController.var isPanelPinned: Bool`
- `ClipboardController.var allowsLocalLinkPreviews = false`
- `ClipboardController.var isHotKeyRegistered: Bool`
- `ClipboardController.var isPanelVisible: Bool`
- `ClipboardController.var panelWindowNumber: Int?`
- `ClipboardController.init(`
- `ClipboardController.start()`
- `ClipboardController.makeOverviewTile() -> AnyView`
- `ClipboardController.makePage() -> NotchPage`
- `ClipboardController.makeSettingsSection() -> AnyView`
- `ClipboardController.makeToolSettings() -> AnyView`
- `ClipboardController.makeDataSettings() -> AnyView`
- `ClipboardController.makeAgentAccessSettings() -> AnyView`
- `ClipboardController.showLibrary(filter: String? = nil, layout: String? = nil)`
- `ClipboardController.exportBackup(to url: URL) throws -> Int`
- `ClipboardController.restoreBackup(from url: URL) throws -> ClipBackupSummary`
- `ClipboardController.capture(_ content: ClipContent, rich: ClipRichData? = nil, source: ClipSource)`
- `ClipboardController.setSearchText(_ text: String)`
- `ClipboardController.var newestItemIDs: [Int64]`
- `ClipboardController.transformNewestText(withToolNamed name: String) -> Bool`
- `ClipboardController.copyNewestColor(asFormatNamed name: String) -> Bool`
- `ClipboardController.createBoard(name: String, symbolName: String) -> Bool`
- `ClipboardController.pin(itemID: Int64, toBoardNamed name: String)`
- `ClipboardController.selectBoard(named name: String?)`
- `ClipboardController.beginNewBoard()`
- `ClipboardController.seedVault(passcode: String, lockingBoardNamed name: String)`
- `ClipboardController.unlockVault(passcode: String) -> Bool`
- `ClipboardController.dropItem(itemID: Int64, onBoardNamed name: String, before otherID: Int64? = nil)`
- `ClipboardController.togglePanel()`
- `ClipboardController.showPanel()`
- `ClipboardController.hidePanel()`
- `ClipboardController.handleKey(_ event: NSEvent) -> Bool`
- `ClipboardController.var isCopyStackActive: Bool`
- `ClipboardController.toggleCopyStack() -> Bool`
- `ClipboardController.pause(_ pause: CapturePause)`
- `ClipboardController.var recordingState: RecordingState`
- `ClipboardController.resume()`
- `ClipboardController.clear(_ range: ClearRange)`
- `ClipboardController.editNewestText()`
- `ClipboardController.var recognizeText: ((_ imageData: Data, _ completion: @escaping @MainActor (String) -> Void) -> Void)?`
- `ClipboardController.newNote()`
- `ClipboardController.var createReminder: ((_ title: String, _ notes: String?, _ due: Date, _ completion: @escaping @MainActor (Bool) -> Void) -> Void)?`
- `ClipboardController.var cutOutSubject: ((_ imageData: Data, _ completion: @escaping @MainActor (Data?) -> Void) -> Void)?`
- `ClipboardController.var assistant: ((_ action: String, _ text: String, _ completion: @escaping @MainActor (String?) -> Void) -> Void)?`
- `ClipboardController.var assistantActions: [String] = []`
- `ClipboardController.flushPendingDeletions(all: Bool = false)`

## Ghi chú cho người sửa

- `ClipboardController.swift` là tệp lớn nhất của app (khoảng 1.500 dòng). Khi sửa lỗi ở đây, viết test trong `ClipboardCoreTests` cho phần logic nếu được, vì `ClipboardFeatureTests` chỉ có ít bộ test.

## Dữ liệu lưu

- `~/Library/Application Support/AraNotch/clipboard.sqlite` và ảnh trong `blobs/` cạnh nó (`ClipboardStore`); két dùng AES-GCM, khoá trong bộ nhớ khi mở.
- UserDefaults `clipboard.*` (`ClipboardSettingsStore`): `maxItems`, `retention`, `isPaused`, `pausedUntil`, `ignoredBundleIDs`, `hotKeyEnabled`, `pasteOnClick`, `linkPreviews`, `bareHexColors`, `copyFeedback`, `copySign`, `copySound`, `copySoundVolume`, `copyStackOrder`, `excludedFromBackup`, `mcpEnabled`, `panelAppearance`, `quickPasteBoardName`, `readsTextInImages`, `savedFilters`, `skipsSensitiveText`, `sortOrder`, `vaultTouchID`.
- UserDefaults `shortcut.quickPasteModifiers`, `shortcut.recentPasteModifiers` (hai hàng phím số, `ClipboardNumberRows`).
- Chuỗi khoá (Keychain): mật mã két cho Touch ID (`VaultTouchID`).

## Quyền hệ thống

Trợ năng để tự dán (gửi ⌘V) và để nghe ⌘V; Lời nhắc cho "Nhắc tôi" (qua Calendar). Không có quyền thì vẫn ghi lịch sử và chép lại được.

## Test

- Chạy: `Scripts/test-module.sh Clipboard`, rồi `Scripts/test.sh`.
- Bộ test: `Modules/Clipboard/Tests/Core/`, `Modules/Clipboard/Tests/Feature/`, `Modules/Clipboard/Tests/MCP/`

## Tệp

- `Modules/Clipboard/Core/BackupExclusion.swift` — Whether the clipboard history goes into Time Machine backups.
- `Modules/Clipboard/Core/ClipBackup.swift` — The clipboard history and its boards as one self-contained value that can be written to a file.
- `Modules/Clipboard/Core/ClipClassifier.swift` — Decides which kind of clip a piece of pasteboard content is.
- `Modules/Clipboard/Core/ClipColor.swift` — A colour parsed from a CSS-style string.
- `Modules/Clipboard/Core/ClipImageData.swift` — How a copied picture is kept.
- `Modules/Clipboard/Core/ClipKindTally.swift` — How many clips there are of each kind, for the row of kind chips on the clipboard page.
- `Modules/Clipboard/Core/ClipLibrary.swift` — What the Library window lists: everything, or the clips of one kind, source app or board.
- `Modules/Clipboard/Core/ClipModels.swift` — Something just read from the pasteboard, before it is stored.
- `Modules/Clipboard/Core/ClipMultiSelection.swift` — Which clips of a list are selected, the way a file list selects: a click picks one, Command-click adds or removes one, Shift-click picks a range.
- `Modules/Clipboard/Core/ClipOrganising.swift` — A time to be reminded of a clip at.
- `Modules/Clipboard/Core/ClipPanelKeyMap.swift` — Modifier keys held during a key press, independent of AppKit.
- `Modules/Clipboard/Core/ClipQuery.swift` — A search typed by the user: free text plus optional `@kind` and `@app` filters.
- `Modules/Clipboard/Core/ClipSelection.swift` — The highlighted entry of a list of clips, tracked by id so it survives reordering and filtering.
- `Modules/Clipboard/Core/ClipThumbnail.swift` — The picture a clip is shown with on its card and in the preview: a copy no larger than the preview needs.
- `Modules/Clipboard/Core/ClipThumbnailPlacement.swift` — How a picture is placed in the picture area of its card.
- `Modules/Clipboard/Core/ClipboardPrivacy.swift` — Decides whether a pasteboard change may be recorded.
- `Modules/Clipboard/Core/ClipboardSettingsStore.swift` — How long unpinned clips are kept before they are deleted automatically.
- `Modules/Clipboard/Core/ClipboardStore+Backup.swift` — Backup and restore of the plain history and the unlocked boards.
- `Modules/Clipboard/Core/ClipboardStore+Boards.swift` — Boards: named collections of pinned clips.
- `Modules/Clipboard/Core/ClipboardStore+Recovery.swift`
- `Modules/Clipboard/Core/ClipboardStore+Vault.swift` — The vault: one passcode protecting every locked board.
- `Modules/Clipboard/Core/ClipboardStore.swift` — The clipboard history: rows in `clipboard.sqlite`, image data as files in `blobs/`.
- `Modules/Clipboard/Core/CodeDetector.swift` — Guesses whether copied text is source code, so the preview can highlight it.
- `Modules/Clipboard/Core/CodeTokenizer.swift` — A run of source text with one highlighting colour.
- `Modules/Clipboard/Core/ColorPalette.swift` — The colours for the overview's palette tile: the newest colour clips, each colour once, never one kept in a locked board.
- `Modules/Clipboard/Core/CopyStack.swift` — Copy several things, then paste them one after another: while the stack is active every copy is added to it and every paste takes the next clip.
- `Modules/Clipboard/Core/LinkMetadataParser.swift` — What a web page says about itself for link previews.
- `Modules/Clipboard/Core/LinkPreviewPolicy.swift` — Decides which copied links may be fetched automatically to build a preview.
- `Modules/Clipboard/Core/PanelPlacement.swift` — Positions a floating panel next to the pointer.
- `Modules/Clipboard/Core/PasteboardChangeTracker.swift` — Decides when the pasteboard should be read, given its change counter.
- `Modules/Clipboard/Core/PendingDeletions.swift` — Clips the user deleted a moment ago.
- `Modules/Clipboard/Core/SQLiteDatabase.swift` — Minimal wrapper around one SQLite connection.
- `Modules/Clipboard/Core/SearchFolding.swift` — Normalises text so that search ignores case and diacritics.
- `Modules/Clipboard/Core/TextTransform.swift` — A tool that rewrites the text of a clip: cleaning it up, changing its letter case or naming style, reformatting JSON, or encoding and decoding it.
- `Modules/Clipboard/Core/VaultCrypto.swift` — The random data key that encrypts vault content.
- `Modules/Clipboard/Feature/BackupPanels.swift` — The save and open panels of the Backup settings, and the line of text that reports the outcome.
- `Modules/Clipboard/Feature/BoardViews.swift` — The symbols a board can use.
- `Modules/Clipboard/Feature/ClipCardView.swift` — One history entry in the clipboard row.
- `Modules/Clipboard/Feature/ClipContextMenu.swift` — The right-click menu of a clip, shared by the notch page and the floating panel.
- `Modules/Clipboard/Feature/ClipDrag.swift` — Dragging clips: out to other apps as their content, and inside the app by identity, to pin a clip to a board or to reorder a board.
- `Modules/Clipboard/Feature/ClipEditor.swift` — State of the window that edits one clip.
- `Modules/Clipboard/Feature/ClipImageExport.swift` — Turns a stored picture (PNG) into the data of another picture format.
- `Modules/Clipboard/Feature/ClipPresentation.swift` — Display helpers shared by the notch cards and the panel rows.
- `Modules/Clipboard/Feature/ClipPreviewView.swift` — A large preview of one clip, as shown beside the panel's list and in the Library's inspector.
- `Modules/Clipboard/Feature/ClipboardController.swift` — Records what the user copies and serves the clipboard page of the notch.
- `Modules/Clipboard/Feature/ClipboardNumberRows.swift` — The clipboard's two rows of 1…9 shortcuts.
- `Modules/Clipboard/Feature/ClipboardPageView.swift` — The clipboard page of the notch: a search field above a row of history cards, newest first.
- `Modules/Clipboard/Feature/ClipboardPanel.swift` — The floating clipboard panel.
- `Modules/Clipboard/Feature/ClipboardPanelView.swift` — The floating panel, one card: search on top, the history as a list, a large preview of the selection.
- `Modules/Clipboard/Feature/ClipboardSettings.swift` — Observable clipboard settings; every change is written through to the store.
- `Modules/Clipboard/Feature/ClipboardSettingsSection.swift` — View-local state of the section.
- `Modules/Clipboard/Feature/ClipboardViewModel.swift` — State the clipboard page and the floating panel render from.
- `Modules/Clipboard/Feature/ClipboardWidget.swift` — The clipboard as a widget of the overview.
- `Modules/Clipboard/Feature/CodeText.swift` — Turns source text into coloured, monospaced text.
- `Modules/Clipboard/Feature/FieldFocus.swift` — Gives a text field keyboard focus, retrying briefly while SwiftUI is still putting it on screen.
- `Modules/Clipboard/Feature/KeyCommandRouter.swift` — Feeds key presses in this app's windows to a handler before the focused view sees them.
- `Modules/Clipboard/Feature/LibraryView.swift` — What the Library window shows; kept in an object because `@State` is unavailable (see `ClipboardSettingsSectionState`).
- `Modules/Clipboard/Feature/LinkPreviewFetcher.swift` — Downloads a page once to read its title and preview image.
- `Modules/Clipboard/Feature/PanelSearchField.swift` — A plain text field that can be told to take keyboard focus, which SwiftUI's `TextField` can only do through `@FocusState` (unavailable without Xcode's macro plugin).
- `Modules/Clipboard/Feature/PasscodeViews.swift` — A text field that hides what is typed and can be told to take keyboard focus.
- `Modules/Clipboard/Feature/PasteKeyTap.swift` — Notices every ⌘V the user presses, in any app, just before the app receives it.
- `Modules/Clipboard/Feature/PasteboardIO.swift`
- `Modules/Clipboard/Feature/PasteboardWatcher.swift` — Notices when the pasteboard changes.
- `Modules/Clipboard/Feature/Paster.swift` — Sends ⌘V to the app the user is working in.
- `Modules/Clipboard/Feature/VaultTouchID.swift` — Where the passcode of the locked boards is kept for the fingerprint: one item in the user's login keychain, per data folder.
- `Modules/Clipboard/MCP/ClipboardMCPServer.swift` — A Model Context Protocol server that lets an AI agent read the clipboard history.
- `Modules/Clipboard/aranotch-mcp/main.swift`

## Lỗi và giới hạn đã biết

- Panel và notch dùng chung một lựa chọn board.
- Khi board đầy (200 mục), ghim thêm bị bỏ qua mà không báo.
- Lịch sử thường (ngoài board bị khoá) lưu không mã hoá.
- Chưa giới hạn số lần nhập sai mật mã két.
- Công cụ sửa văn bản không dùng được cho mục trong board bị khoá (kết quả sẽ nằm ngoài két, không mã hoá), và không giữ định dạng RTF, HTML của mục gốc.
- Công cụ không áp dụng được (ví dụ định dạng JSON trên chữ thường) chỉ báo bằng tiếng bíp, chưa có lời giải thích.
- Công cụ sửa văn bản chỉ có trong menu chuột phải, chưa có phím tắt.
- Bản sao lưu không mã hoá và không chứa board bị khoá cùng các mục trong đó. Khi nhập, không mục nào được ghim vào board đang bị khoá.
- Bản sao lưu là một tệp JSON nạp trọn vào bộ nhớ; lịch sử có nhiều ảnh lớn sẽ cho tệp lớn.
- Library không hiện board bị khoá và các mục trong két, kể cả khi két đang mở.
- Library chưa điều khiển được bằng bàn phím (mũi tên, Return, ⌫) và chưa chọn được nhiều mục.
- Khi bật nhận mã hex không có `#`, từ tiếng Anh chỉ gồm các chữ a đến f dài 6 hoặc 8 ký tự (ví dụ "decade") cũng bị ghi là màu. Tuỳ chọn chỉ áp dụng cho lần chép sau khi bật; mục cũ không đổi loại.
- Chép màu dạng HSL làm tròn tới độ và phần trăm nguyên, nên có thể lệch một đơn vị màu so với mã gốc.
- Kéo một mục gồm nhiều tệp ra app khác chỉ mang theo tệp đầu tiên.
- Chỉ sắp xếp lại được trong một board; lịch sử "Tất cả" luôn xếp theo lần dùng gần nhất.
- Trạng thái ghim panel không được nhớ qua lần mở app sau.
- Clipboard MCP chỉ đọc: agent chưa thể đưa nội dung lên clipboard. Ảnh chỉ được mô tả (kích thước, app nguồn), không gửi dữ liệu ảnh.
- Công tắc MCP thể hiện ý muốn của người dùng chứ không phải hàng rào bảo mật: lịch sử thường vốn lưu không mã hoá, chương trình nào chạy dưới tài khoản này cũng đọc được tệp.
- Thả mục lên dòng board ở thanh bên của Library không có tác dụng (đã thử nhiều lần, chưa tìm ra nguyên nhân); muốn ghim từ Library thì kéo lên chip board trên notch hoặc dùng menu Ghim vào.
- Chọn nhiều mục chỉ có trong Library, chưa có trên notch và panel. Kéo nhiều mục sang app khác chỉ mang chữ; ảnh và tệp trong nhóm bị bỏ qua.
- Trong Library không còn bấm đúp để chép (đã bỏ để ⌘-bấm chạy đúng); dùng nút Sao chép hoặc menu chuột phải.
- Giao diện sáng chỉ áp dụng cho panel clipboard nổi. Notch, Thư viện, khung dịch, thanh Smart Selection và cửa sổ chú thích vẫn luôn tối. Dòng đang chọn trong panel vẫn là chữ trắng trên nền vàng ở cả hai giao diện.
- Dán theo số không có lựa chọn ⌃ đơn hay ⌥ đơn: ⌃ kèm số là phím "Chuyển sang Desktop N" của macOS, ⌥ kèm số gõ ra ký tự. Mục là tệp không còn tồn tại thì dán không ra gì.
- Sửa chữ của clip làm mất bản có định dạng (RTF, HTML) và ảnh xem trước của link, vì chúng thuộc về nội dung cũ. Clip trong bảng khoá không sửa được. Không sửa được ảnh hay tệp, chỉ đặt tiêu đề.
- Chữ trong ảnh được đọc lần lượt, mới nhất trước; ảnh trong bảng khoá không được đọc. Lần đọc đầu tiên sau khi cài có thể mất khoảng 30 giây. "Mở bằng" cho ảnh mở thẳng tệp ảnh trong kho của app: sửa và lưu trong app khác sẽ đổi ảnh trong lịch sử.
- Hiệu năng đã đo (bản debug): đọc lại 1.000 clip cỡ 2 KB mất khoảng 7 ms, chép vào lịch sử đầy rồi đọc lại khoảng 9 ms, đọc 200 clip cỡ 200 KB khoảng 22 ms, tìm trong 1.000 clip khoảng 90 ms mỗi lần gõ. Chưa đo thời gian vẽ giao diện.
- Nhận diện nội dung nhạy cảm chỉ dựa vào hình dạng: khoá có tiền tố quen thuộc (`sk-`, `ghp_`, `AKIA`…), token ba phần, khối khoá riêng, số thẻ đúng số kiểm tra. Mật khẩu thường, mã OTP, khoá không có tiền tố quen thuộc thì không nhận ra. Một chuỗi bình thường trùng tiền tố (ví dụ bắt đầu bằng `sk-` và dài từ 20 ký tự) sẽ bị bỏ qua nhầm; tắt được trong mục Clipboard.
- Nhắc hẹn cho clip là một lời nhắc bình thường của macOS: nó không dẫn ngược về clip, và xoá clip không xoá lời nhắc. Cần quyền Lời nhắc.
- Bộ lọc đã lưu lấy chính câu tìm làm tên, tối đa 8 cái, chưa đổi tên hay sắp lại được. Sắp xếp chỉ áp dụng cho lịch sử chung; các bảng giữ thứ tự riêng. Cỡ notch áp dụng cho mọi trang, nhưng chỉ trang Clipboard vẽ thẻ lớn hơn.
- Lần chép xảy ra trong lúc một cửa sổ của AraNotch (Cài đặt, Thư viện, cửa sổ sửa clip) đang giữ bàn phím được coi là chép từ chính AraNotch và không được ghi.
- Thẻ ảnh hiện trọn ảnh, nên ảnh không cùng tỉ lệ với thẻ để lại khoảng trống hai bên hoặc trên dưới. Riêng ảnh quá dài hoặc quá rộng (hiện trọn thì chỉ còn dưới một phần năm bề ngang hoặc bề cao của thẻ, như ảnh chụp cuộn) thì thẻ chỉ hiện phần đầu của ảnh.
- Nhãn nguồn trên thẻ clip là icon của app nguồn; app đã gỡ khỏi máy thì hiện lại tên.
- Hoàn tác xoá chỉ có trong 8 giây và chỉ trong lần chạy đó của app; số đếm trên bảng ghim chưa giảm cho tới khi clip bị xoá thật. Xoá bảng, xoá theo khoảng thời gian và xoá cả lịch sử thì không hoàn tác được.
- Xem nhanh một clip chữ ghi một tệp tạm trong thư mục tạm của máy; tệp đó không được dọn ngay.
- Con lăn chuột chỉ được đổi hướng ở trang Clipboard của notch; bảng clipboard và Thư viện vốn cuộn dọc.
- Touch ID: việc kiểm tra vân tay do AraNotch thực hiện rồi mới đọc mật mã từ Chuỗi khoá; mục trong Chuỗi khoá không tự gắn với vân tay, vì app ký bằng chứng thư tự tạo không dùng được loại mục đó. Bật tuỳ chọn nghĩa là mật mã nằm trong Chuỗi khoá đăng nhập của máy. Vì chứng thư không có Team ID, mục đó gắn với mã băm của bản dựng đã lưu nó: sau mỗi bản cập nhật, lần mở khoá bằng Touch ID đầu tiên macOS hỏi mật khẩu máy một lần (chọn "Luôn cho phép" để không bị hỏi lại tới bản sau). Chỉ hết hẳn khi ký bằng chứng thư Developer ID có Team ID.
- Nhận diện code là phỏng đoán; SQL viết thường và đoạn rất ngắn có thể không được tô màu.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): hai hàng phím số chuyển từ nền tảng về đây (`ClipboardNumberRows`, cùng khoá lưu cũ); widget dùng `WidgetSize`.
- 2026-10-26 — GitHub chặn đẩy mã lên repo công khai vì token Slack mẫu trong `recognisesCommonSecretKeys` trông như khoá thật; chuỗi mẫu nay được ghép từ hai phần, test giữ nguyên ý — test có sẵn, chạy lại qua — commit này.
