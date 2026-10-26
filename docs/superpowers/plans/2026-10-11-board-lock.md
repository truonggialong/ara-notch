# Board Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Khoá board bằng mật mã, với nội dung được mã hoá AES-GCM trên đĩa.

**Architecture:** `VaultCrypto` (thuần) lo suy khoá, bọc khoá và mã hoá. `ClipboardStore` giữ khoá dữ liệu trong bộ nhớ khi két mở và chuyển mục qua lại giữa dạng thường và dạng trong két. Giao diện thêm hàng nhập mật mã.

**Tech Stack:** Swift 6, CryptoKit (AES-GCM, HMAC), CommonCrypto (PBKDF2), SQLite3, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-board-lock-design.md`

## Global Constraints

- PBKDF2-HMAC-SHA256, 600 000 vòng, muối 16 byte; khoá dữ liệu 256 bit; AES-GCM; mật mã tối thiểu 4 ký tự; lược đồ phiên bản 5; tự khoá sau 300 giây.
- Mật mã và khoá dữ liệu không được ghi ra đĩa hay ra log.
- `ClipboardCore` không import AppKit hay SwiftUI. Không dùng macro SwiftUI.
- Chuỗi hiển thị có đủ `en` và `vi`. Chạy test bằng `Scripts/test.sh`. Mỗi task kết thúc bằng một commit.

## Review Focus

1. **Nội dung thường còn sót trên đĩa sau khi khoá:** trong cột `text`, `link_title`, tên tệp và nội dung tệp. Test ở Task 2.
2. **Sai mật mã và dữ liệu bị sửa:** không được trả dữ liệu rác; phải báo lỗi. Test ở Task 1.
3. **Gộp khi trở về lịch sử:** mục được giải mã trùng nội dung với một mục thường đang có. Test ở Task 2.
4. **Thao tác khi két đang khoá:** khoá board, ghim vào board bị khoá, bỏ ghim, xoá board bị khoá đều phải bị từ chối mà không đổi dữ liệu. Test ở Task 2.
5. **Mở lại app:** két phải khoá; nội dung chỉ đọc được sau khi mở đúng mật mã. Test ở Task 2.

---

### Task 1: `VaultCrypto`

**Files:** Create `Sources/ClipboardCore/VaultCrypto.swift`; Test `Tests/ClipboardCoreTests/VaultCryptoTests.swift`

**Interfaces — Produces:**

```swift
struct VaultKey: Equatable { let data: Data }                       // 32 byte
struct VaultRecord: Equatable { let salt: Data; let iterations: Int; let wrappedKey: Data }
enum VaultCrypto {
    static let iterations = 600_000
    static func makeVault(passcode: String) throws -> (record: VaultRecord, key: VaultKey)
    static func unlock(_ record: VaultRecord, passcode: String) throws -> VaultKey     // ném .wrongPasscode
    static func rewrap(_ record: VaultRecord, from old: String, to new: String) throws -> VaultRecord
    static func seal(_ data: Data, with key: VaultKey) throws -> Data
    static func open(_ data: Data, with key: VaultKey) throws -> Data
    static func keyedHash(_ value: String, with key: VaultKey) -> String              // chuỗi hex
}
```

- [ ] **Step 1: Test thất bại:** tạo rồi mở bằng đúng mật mã cho cùng khoá; sai mật mã ném `wrongPasscode`; hai két cùng mật mã có muối và khoá khác nhau; `seal` rồi `open` trả đúng dữ liệu (kể cả rỗng và 1 MB); hai lần `seal` cùng dữ liệu cho bản mã khác nhau; sửa một byte bản mã thì `open` ném lỗi; mở bằng khoá khác ném lỗi; `rewrap` giữ nguyên khoá dữ liệu, mật mã cũ không còn mở được; `rewrap` với mật mã cũ sai ném `wrongPasscode`; `keyedHash` ổn định với cùng khoá và khác nhau giữa hai khoá.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua.
- [ ] **Step 5:** Commit `feat: add vault cryptography`.

### Task 2: Két trong kho, lược đồ 5

**Files:** Create `Sources/ClipboardCore/ClipboardStore+Vault.swift`; Modify `ClipModels.swift`, `ClipboardStore.swift`, `ClipboardStore+Boards.swift`, `SQLiteDatabase.swift` (nếu cần); Test `Tests/ClipboardCoreTests/ClipboardStoreVaultTests.swift`

**Interfaces — Produces:**

```swift
public enum VaultState: Equatable, Sendable { case notSetUp, locked, unlocked }
extension ClipboardStoreError { case vaultLocked, wrongPasscode, invalidPasscode, vaultAlreadyExists, vaultNotSetUp }
extension ClipBoard { public let isLocked: Bool }
extension ClipItem { public let isEncrypted: Bool }
extension ClipboardStore {
    public static let schemaVersion = 5
    public static let minPasscodeLength = 4
    public var vaultState: VaultState { get }
    public func createVault(passcode: String) throws
    public func unlockVault(passcode: String) throws
    public func lockVault()
    public func changeVaultPasscode(from old: String, to new: String) throws
    public func setBoardLocked(id: Int64, _ isLocked: Bool) throws
}
```

- [ ] **Step 1: Test thất bại** cho từng dòng của bảng hành vi trong spec và năm mục Review Focus, cùng việc nâng từ lược đồ 4.
- [ ] **Step 2–4:** Chạy thất bại, cài đặt, chạy qua toàn bộ.
- [ ] **Step 5:** Commit `feat: encrypt locked boards in the clipboard store (schema v5)`.

### Task 3: Giao diện khoá board

**Files:** Create `Sources/ClipboardFeature/PasscodeViews.swift`; Modify `ClipboardViewModel.swift`, `ClipboardController.swift`, `BoardViews.swift`, `ClipboardPageView.swift`, `ClipboardPanelView.swift`, hai file `Localizable.strings`; `Sources/AraNotch/LaunchArguments.swift`, `AppDelegate.swift`

- [ ] **Step 1:** View model: `vaultState`, `passcodePrompt` (mục đích: mở để xem board, mở để khoá board, tạo két để khoá board; hai chuỗi nhập; khoá lỗi). Bộ điều khiển: các luồng trên, hẹn giờ tự khoá, quay về "Tất cả" khi két khoá.
- [ ] **Step 2:** `PasscodeRowView` với ô nhập ẩn ký tự; chip có ổ khoá; mục menu khoá và bỏ khoá.
- [ ] **Step 3:** Tham số `--seed-vault <mật mã>` (cần `--seed-boards`): tạo két và khoá board "Công việc". `--unlock-vault <mật mã>`.
- [ ] **Step 4:** `Scripts/build-app.sh` sạch. Commit `feat: add passcode lock for boards`.

### Task 4: Kiểm chứng

- [ ] **Step 1:** `Scripts/test.sh` qua toàn bộ.
- [ ] **Step 2:** Với dữ liệu mẫu và `--seed-vault`: `strings` trên `clipboard.sqlite` và trên các tệp trong `blobs/` không chứa nội dung của các mục đã khoá.
- [ ] **Step 3:** Ảnh: chip có ổ khoá; hàng nhập mật mã khi chọn board bị khoá; board hiện nội dung với `--unlock-vault`.
- [ ] **Step 4:** Chuột và bàn phím thật: tạo board, ghim một mục, khoá board với mật mã mới, thoát và mở lại app, nhập sai rồi nhập đúng.
- [ ] **Step 5:** Commit các sửa đổi phát sinh.
