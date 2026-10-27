# Ghi chú chỉ trên notch: kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bỏ cửa sổ Ghi chú; trang Ghi chú trên notch làm được mọi thứ cửa sổ làm.

**Architecture:** `NotesController` nói với notch qua một bộ closure (`NotesPresenter`) để test được. Trang ghép ba view: `NoteFolderPicker` (bảng chọn thư mục vẽ trong notch), `NoteListColumn` (danh sách nhóm theo ngày, menu chuột phải, thẻ hỏi xoá), cột soạn có `FormatToolbar`. Trạng thái giao diện (bảng chọn, thư mục mới, thẻ xoá, con trỏ trong trình soạn, đang chọn ảnh) nằm trong `NotesPageModel`; controller gộp chúng thành `setKeepsOpen`.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Swift Testing, SwiftPM. Module `Notes` (`NotesFeature`), chỗ nối ở `App`.

**Spec:** `docs/superpowers/specs/2026-10-27-notes-in-notch-design.md`

## Global Constraints

- Sửa trong module Notes; App chỉ đổi chỗ gọi. Không đổi Platform.
- Kiểm chứng bằng `Scripts/test-module.sh Notes`, `Scripts/test.sh`, `swift build`; không gọi `swift test` trực tiếp.
- Chiều cao sheet của trang: 420 pt. Bộ đếm làm mới: 30 giây.
- Kích thước trong notch nhân với `@Environment(\.araScale) ui`.
- Chuỗi giao diện qua `L10n.string`, có ở cả `App/Resources/vi.lproj` và `en.lproj`.
- Commit có tên module ở đầu (`Notes: …`, `App: …`, `Docs: …`), tác giả "The Arawo company".
- Làm trên nhánh `notes-in-notch`, gộp vào `main` khi xong. Không đẩy lên `origin` nếu chưa hỏi.

## Review Focus

- **Chọn ảnh từ thanh định dạng:** `NSOpenPanel` lấy bàn phím, trình soạn mất con trỏ, nên notch có thể đóng giữa chừng. Phải giữ mở trong lúc chọn ảnh. Test `choosingImagesKeepsTheNotchOpen` ở Task 4.
- **Menu kiểu đoạn (`Menu` của SwiftUI) mở ra ngoài notch:** con trỏ ở trên menu không được làm notch đóng. Phải thử tay ở Task 5.
- **"Ghi chú mới" khi notch đóng và Notes chưa chạy:** notch phải mở ngay, không đợi 3–4 giây tạo ghi chú. Test `newNoteShowsThePageBeforeTheNoteIsMade` ở Task 1.
- **Xoá đúng ghi chú đang mở:** trình soạn phải về trạng thái trống, không giữ ghi chú đã xoá. Test `deletingTheOpenNoteClosesIt` ở Task 2.
- **Esc khi đang gõ tên thư mục:** Esc chỉ huỷ ô tên, không đóng notch. Test `escapeClosesWhatIsOpenOnThePageFirst` ở Task 4.

---

### Task 1: Controller mở notch thay cho cửa sổ; bỏ cửa sổ

**Files:**
- Modify: `Modules/Notes/Feature/NotesController.swift`
- Modify: `Modules/Notes/Feature/NotesPageView.swift` (bỏ nút ⤢, `onShowWindow`; thêm trạng thái vào `NotesPageModel`)
- Delete: `Modules/Notes/Feature/NotesWindowController.swift`, `Modules/Notes/Feature/NotesWindowView.swift`
- Move tests: `Modules/Notes/Tests/Feature/NotesWindowTests.swift` → `Modules/Notes/Tests/Feature/NotesPageTests.swift` (giữ các test về toolbar, trình soạn, thư mục; bỏ `windowBuildsOffscreen`, `openingTheWindowStartsNotes`; đổi tên `WindowHarness` → `PageHarness`, `newNoteFromTheWindowGoesToTheChosenFolder` → `newNoteGoesToTheChosenFolder`)
- Modify: `App/Sources/AppDelegate.swift:375-377`, `App/Sources/LaunchArguments.swift:109` (chú thích)

**Interfaces:**
- Produces:
  - `struct NotesPresenter { var showPage: @MainActor () -> Void; var focusEditor: @MainActor () -> Void; var isPageHidden: @MainActor () -> Bool; var setKeepsOpen: @MainActor (Bool) -> Void; var openNotesApp: @MainActor () -> Void }` (internal, trong `NotesController.swift`). Bản thật: `showPage` = `notch.selectPage(id:)` rồi `notch.open()`; `focusEditor` = `notch.focusTextField()`; `openNotesApp` mở `com.apple.Notes` bằng `NSWorkspace`.
  - `NotesController.presenter: NotesPresenter` (internal `var`, test thay được).
  - `public func showPage()`.
  - `NotesController.sheetHeight = 420`, `NotesController.refreshInterval: TimeInterval = 30` (đổi tên từ `windowRefreshInterval`).
  - `NotesPageModel`: `@Published var isEditorFocused = false`, `isChoosingFolder = false`, `isAddingFolder = false`, `newFolderName = ""`, `deletingID: String? = nil`, `isChoosingImages = false`; `var keepsNotchOpen: Bool` (true khi một trong năm cờ đúng hoặc `deletingID != nil`); `let editor = NoteEditorHandle()`; `@Published var focusRequest = 0`.
  - Controller theo dõi `model.objectWillChange` (hoặc từng `$` cờ), gọi `presenter.setKeepsOpen(model.keepsNotchOpen)` chỉ khi giá trị đổi. Rời trang (`pageShowingChanged(false)`) thì đưa các cờ giao diện về mặc định (trừ `isEditorFocused`) và `setKeepsOpen(false)`.
  - `onEditorFocus` gán `model.isEditorFocused`.

- [ ] **Step 1: Chuyển test cửa sổ sang `NotesPageTests.swift`, viết test mới (sẽ hỏng)**

Dùng harness controller như `NoteEditorTests.controller(_:)`, rồi thay `controller.presenter` bằng bản ghi lại lời gọi (`shown`, `focused`, `keeps: [Bool]`, `hidden: Bool`, `notesOpened`).

```swift
@Test func newNoteShowsThePageBeforeTheNoteIsMade()   // presenter.showPage gọi trước khi fake.createNote trả về; sau đó store.open?.id == ghi chú mới, focused == 1
@Test func newNoteThatCannotBeMadeStillShowsThePage()  // fake.accessValue = .denied → shown == 1, store.open == nil
@Test func newNoteWithTheHiddenPageOpensItInNotes()    // hidden = true → shown == 0, fake.shownIDs == [id mới]
@Test func newNoteWithTheHiddenPageAndNoNoteOpensNotes() // hidden = true, .denied → notesOpened == 1
@Test func showPageShowsThePage()                      // controller.showPage() → shown == 1
@Test func timerRunsOnlyWhileThePageShowsWithoutFullDiskAccess() // pageShowingChanged(true) → isRefreshingOnTimer; (false) → !isRefreshingOnTimer
@Test func keepsTheNotchOpenWhileAnythingIsUnderWay()  // lần lượt bật từng cờ của model → keeps.last == true; tắt hết → false; không gọi lặp cùng giá trị
@Test func leavingThePageClosesWhatWasOpenOnIt()       // isChoosingFolder, deletingID đặt; pageShowingChanged(true) rồi (false) → cờ về mặc định, keeps.last == false
```

Nếu `FakeNotesService` chưa ghi lại `show`, thêm `private(set) var shownIDs: [String]`. Cách test "trước khi tạo xong": cho fake một độ trễ tạo ghi chú (thêm `createDelay: Duration?` nếu chưa có) và kiểm `shown == 1` khi `store.open == nil`.

- [ ] **Step 2: Chạy, thấy hỏng**

Run: `Scripts/test-module.sh Notes`
Expected: lỗi biên dịch (`presenter`, `showPage`, các cờ của model chưa có).

- [ ] **Step 3: Cài đặt**

- `newNote()`: hidden → tạo, rồi `store.showInNotes(made)` hoặc `presenter.openNotesApp()` khi không tạo được. Không hidden → `presenter.showPage()` ngay, rồi `flush`, `store.newNote()`, có ghi chú mới thì `model.focusRequest += 1` và `presenter.focusEditor()`.
- `showPage()`: `presenter.showPage()`.
- Bỏ `showWindow`, `makeWindow`, `newNoteInWindow`, `window`, `isWindowShowing`, `isWindowMiniaturized`, `windowShowingChanged`, `windowMiniaturizedChanged`. `pageAppeared` và watcher chỉ dùng `isPageShowing`. `updateRefreshTimer` chạy khi `isPageShowing && !fullView`; `pageShowingChanged` gọi nó.
- Nút + của trang: `model.onNewNote` gọi `store.newNote(in: store.selectedFolderID)` (nil → thư mục mặc định, store đã lo).
- App: `--show-notes` gọi `notes.showPage()`.

- [ ] **Step 4: Chạy, thấy qua; build app**

Run: `Scripts/test-module.sh Notes && swift build`
Expected: mọi test qua, build không lỗi, không có tham chiếu `NotesWindow`.

- [ ] **Step 5: Commit**

`Notes: new notes open on the notch, the Notes window is gone` (gồm cả hai dòng App).

---

### Task 2: Danh sách nhóm theo ngày, menu chuột phải, thẻ hỏi xoá

**Files:**
- Create: `Modules/Notes/Feature/NoteListColumn.swift`
- Modify: `Modules/Notes/Feature/NotesPageView.swift` (cột trái dùng `NoteListColumn`; bỏ `listed(_:recent:isSearching:)` khỏi chỗ xếp danh sách)
- Modify: `Modules/Notes/Feature/NotesController.swift` (`load` chọn ghi chú mở sẵn: ghi chú đầu tiên trong `settings.recentIDs` còn trong danh sách và không khoá, không có thì ghi chú mới nhất không khoá)
- Test: `Modules/Notes/Tests/Feature/NotesPageTests.swift`

**Interfaces:**
- Consumes: `NotesPageModel.deletingID` (Task 1), `NoteListGrouping.groups(_:now:calendar:)`, `NoteListGrouping.monthTitle`.
- Produces:
  - `NotesPageModel.askToDelete(_ id: String)`, `cancelDelete()`, `func confirmDelete(in store: NotesStore) async` (xoá rồi `store.refresh()`, đưa `deletingID` về nil trước khi xoá).
  - `static func NotesController.firstToOpen(_ notes: [NoteSummary], recent: [String]) -> NoteSummary?`.
  - `struct NoteListColumn: View` (store, model). Dòng: tên (hay `notes.untitled`), giờ (`NotesPageView.time`), đoạn trích, biểu tượng ảnh và khoá; `.contextMenu` với `notes.showInNotes` và `notes.delete`; thẻ hỏi xoá ở đầu danh sách như `deleteConfirmation` của cửa sổ cũ, cỡ nhân `ui`.

- [ ] **Step 1: Test hỏng**

```swift
@Test func cancellingTheDeleteKeepsTheNote()      // askToDelete(id) → cancelDelete() → deletingID == nil, fake vẫn còn id
@Test func confirmingTheDeleteRemovesTheNote()    // askToDelete(id) → await confirmDelete(in:) → store.notes không còn id, deletingID == nil
@Test func deletingTheOpenNoteClosesIt()          // openNote(id), confirmDelete → store.open == nil
@Test func firstToOpenPrefersTheLatestOpenedHere() // recent ["b","a"], notes a,b,c (c mới nhất) → "b"; b khoá → "a"; recent rỗng → "c"
```

- [ ] **Step 2: Chạy, thấy hỏng** — `Scripts/test-module.sh Notes`, lỗi biên dịch.
- [ ] **Step 3: Cài đặt** như phần Interfaces. Nếu `store.delete` chưa đóng ghi chú đang mở thì sửa trong `NotesStore.delete` (cùng module).
- [ ] **Step 4: Chạy, thấy qua** — `Scripts/test-module.sh Notes`.
- [ ] **Step 5: Commit** `Notes: the notch lists notes by date, with Show in Notes and Delete`.

---

### Task 3: Bảng chọn thư mục và thư mục mới

**Files:**
- Create: `Modules/Notes/Feature/NoteFolderPicker.swift`
- Modify: `Modules/Notes/Feature/NotesPageView.swift` (hàng trên của cột trái: nút thư mục, ô tìm, +; bảng chọn đè lên danh sách khi `model.isChoosingFolder`)
- Test: `Modules/Notes/Tests/Feature/NotesPageTests.swift`

**Interfaces:**
- Consumes: `NotesPageModel.isChoosingFolder`, `isAddingFolder`, `newFolderName` (Task 1); `NotesStore.createFolder(named:)`, `selectedFolderID`, `folders`.
- Produces:
  - `NotesPageModel.choose(folder id: String?, in store: NotesStore) async`: đặt `selectedFolderID`, đóng bảng chọn, huỷ `deletingID`, `store.refresh()`. Chọn lại thư mục đang chọn thì chỉ đóng bảng.
  - `NotesPageModel.createFolder(in store: NotesStore) async -> Bool`: tên rỗng (sau khi bỏ khoảng trắng) → false, giữ ô mở; thành công → đóng ô và bảng chọn, xoá `newFolderName`.
  - `static func NoteFolderPicker.accounts(of: [NoteFolder]) -> [(name: String, folders: [NoteFolder])]` (chuyển từ `NotesWindowView.accounts`).
  - `struct NoteFolderPicker: View` gồm nút (`folder` + tên thư mục đang chọn hay `notes.allNotes` + `chevron.down`) và `NoteFolderList` (bảng: "Tất cả ghi chú" kèm tổng, nhãn tài khoản, thư mục kèm số, "+ Thư mục mới" và ô nhập với nút tạo và huỷ).

- [ ] **Step 1: Test hỏng**

```swift
@Test func choosingAFolderListsItsNotesAndClosesThePicker() // 2 thư mục, mỗi thư mục 1 ghi chú; isChoosingFolder = true; choose(work) → store.notes chỉ của work, !isChoosingFolder
@Test func choosingAllNotesListsEveryNote()                  // choose(nil) → đủ 2 ghi chú
@Test func anEmptyFolderNameMakesNothing()                   // newFolderName = "   " → createFolder false, isAddingFolder vẫn true, số thư mục không đổi
@Test func aNewFolderIsChosen()                              // newFolderName = "Work" → true, store.selectedFolderID == thư mục mới, !isAddingFolder, !isChoosingFolder
@Test func accountsKeepNotesOrder()                          // chuyển nguyên từ test (nếu có) hoặc: folders [iCloud A, On My Mac B, iCloud C] → [("iCloud",[A,C]), ("On My Mac",[B])]
```

- [ ] **Step 2: Chạy, thấy hỏng** — `Scripts/test-module.sh Notes`.
- [ ] **Step 3: Cài đặt.** Bảng chọn vẽ bằng `.overlay` trong cột trái, không dùng `NSPopover`. Nền `.araCard(radius: 10, level: .raised)`, cuộn được, cao tối đa bằng cột.
- [ ] **Step 4: Chạy, thấy qua** — `Scripts/test-module.sh Notes`.
- [ ] **Step 5: Commit** `Notes: choose and make folders on the notch`.

---

### Task 4: Ghép trang, thanh định dạng, Esc, chuỗi

**Files:**
- Modify: `Modules/Notes/Feature/NotesPageView.swift` (cột phải: `FormatToolbar`, `NoteStatusBanner`, `NoteEditorView(imageSize: .fitWidth(...)).handle(model.editor)`; `.onChange(of: model.focusRequest)` đặt con trỏ vào trình soạn)
- Modify: `Modules/Notes/Feature/FormatToolbar.swift` (cỡ nhân `ui`; nút 24×24 ở cỡ gốc; menu kiểu đoạn chỉ còn biểu tượng và mũi tên; chọn ảnh qua `onChoosingImages`)
- Modify: `Modules/Notes/Feature/NotesController.swift` (`makePage()` gắn `keyHandler`)
- Modify: `App/Resources/vi.lproj/Localizable.strings`, `App/Resources/en.lproj/Localizable.strings`
- Test: `Modules/Notes/Tests/Feature/NotesPageTests.swift`

**Interfaces:**
- Consumes: mọi thứ của Task 1–3.
- Produces:
  - `NotesPageModel.handleKey(_ key: NotchKey) -> Bool`: `.escape` đóng theo thứ tự ô tên thư mục → bảng chọn → thẻ xoá, trả true khi đã đóng một thứ; còn lại false.
  - `NoteEditorHandle.chooseImages(onChoosing: (Bool) -> Void)`: gọi `onChoosing(true)` trước khi mở, `false` khi panel xong. Trong notch dùng `panel.begin` (cửa sổ riêng, sau `NSApp.activate`), không dùng sheet trên panel của notch.
  - Chuỗi đổi khoá: `notes.window.allNotes` → `notes.allNotes`, `notes.window.newFolder` → `notes.newFolder`, `notes.window.folderName` → `notes.folderName`, `notes.window.createFolder` → `notes.createFolder`, `notes.window.cancel` → `notes.cancel`, `notes.window.showInNotes` → `notes.showInNotes`, `notes.window.delete` → `notes.delete`, `notes.window.delete.confirm` → `notes.delete.confirm`, `notes.window.delete.detail` → `notes.delete.detail`. Xoá: `notes.window.title`, `notes.window.newNote`, `notes.window.none.detail`, `notes.openWindow`. Thêm `notes.chooseFolder` ("Chọn thư mục" / "Choose folder") cho `help` của nút thư mục.

- [ ] **Step 1: Test hỏng**

```swift
@Test func escapeClosesWhatIsOpenOnThePageFirst()   // isAddingFolder + isChoosingFolder: escape → !isAddingFolder, isChoosingFolder; escape → !isChoosingFolder; deletingID: escape → nil; không còn gì: escape → false
@Test func choosingImagesKeepsTheNotchOpen()        // handle.chooseImages(onChoosing:) gọi true trước; model.isChoosingImages = true → keeps.last == true (dùng presenter ghi lại của Task 1)
@Test func pageBuildsOffscreen()                    // NSHostingView(NotesPageView(...)) frame 640×420, có ghi chú mở → tìm thấy NoteTextView trong cây view
@Test func everyNotesKeyIsTranslated()              // mọi khoá "notes.*" dùng trong Modules/Notes/Feature có trong cả hai tệp chuỗi; không còn khoá "notes.window."
```

`everyNotesKeyIsTranslated` đọc nguồn và tệp chuỗi theo đường dẫn từ `#filePath`. Nếu App đã có test chung kiểu này thì chỉ chạy nó và bỏ test này.

- [ ] **Step 2: Chạy, thấy hỏng** — `Scripts/test-module.sh Notes`.
- [ ] **Step 3: Cài đặt.** Cột phải: `VStack(spacing: 6 * ui)` gồm toolbar (căn trái), banner, trình soạn trong `.araCard(radius: 12, level: .plate)`; ảnh `.fitWidth(max(80, (rộng cột − 20 * ui).rounded(.down)))`. `keyHandler` gọi `model.handleKey`.
- [ ] **Step 4: Chạy, thấy qua; chạy đủ** — `Scripts/test.sh && swift build`.
- [ ] **Step 5: Commit** `Notes: the notch page has the toolbar, wide pictures and Esc` (kèm chuỗi).

---

### Task 5: Tự thử, thử tay, sổ, gộp

**Files:**
- Modify: `Modules/Notes/Feature/NotesSelfTest.swift` (`openNewNote` gọi `newNote()`, đợi notch mở ở trang Ghi chú, lấy `NoteTextView` trong panel của notch thay vì cửa sổ)
- Modify: `Modules/Notes/README.md`, `Modules/Notes/DESIGN.md` (một đoạn "Sửa 2026-10-27: bỏ cửa sổ"), `App/README.md`, `docs/project/FEATURES.md`, `docs/project/HISTORY.md`

- [ ] **Step 1:** Sửa tự thử, `swift build`.
- [ ] **Step 2:** `Scripts/build-app.sh`, `open build/AraNotch.app --args --self-test-notes <scratchpad>/report.txt`. Báo cáo không có dòng `FAIL`.
- [ ] **Step 3: Thử tay** (chụp màn hình kiểm): trang cao hơn; chọn thư mục, tạo thư mục; menu chuột phải; xoá có thẻ hỏi; ảnh rộng bằng khung; menu kiểu đoạn mở ra mà notch không đóng; chọn ảnh mà notch không đóng; "Ghi chú mới" từ menu thanh trạng thái khi notch đóng; Esc. Điều gì không thử được thì ghi vào sổ ở mục "Chưa thử tay".
- [ ] **Step 4: Ghi sổ.** Sổ Notes: vai trò (không còn cửa sổ), giao diện công khai (bỏ `showWindow`, thêm `showPage`), ghi chú cho người sửa (bảng chọn vẽ trong notch vì sao, giữ mở vì sao), tệp, giới hạn, test. App README: `--show-notes`. FEATURES, HISTORY.
- [ ] **Step 5:** `Scripts/test.sh`, commit `Docs: Notes lives on the notch only`, gộp `notes-in-notch` vào `main` (fast-forward). Không đẩy lên `origin`.
