# Agent (AgentCore, AgentFeature, aranotch-hook)

Sổ của module **Agent**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Trang Agent: theo dõi phiên Claude Code (qua hook) và Codex (qua nhật ký phiên), báo khi agent bắt đầu, cần người dùng hay xong, hạn mức 5 giờ và 7 ngày (status line, tài khoản Claude, nhật ký Codex), ước tính mức dùng của một lượt, widget Agent của Tổng quan.

## Target và thư mục

- `AgentCore` — `Sources/AgentCore/`
- `AgentFeature` — `Sources/AgentFeature/`
- `aranotch-hook` — `Sources/aranotch-hook/`

## Phụ thuộc và ai dùng

- Dùng: `AgentFeature` dùng `AgentCore`, `NotchShell`, `NotchCore`. `aranotch-hook` chỉ dùng `AgentCore`.
- Được dùng bởi: App (`AgentController`); `Uninstaller` của app gọi `removeFromClaudeCode`.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `AgentController.init(store: AgentSettingsStore)`
- `AgentController.init(`
- `AgentController.start()`
- `AgentController.installStatusLine()`
- `AgentController.removeStatusLine()`
- `AgentController.var summary: String`
- `AgentController.makeOverviewTile() -> AnyView`
- `AgentController.makePage() -> NotchPage`
- `AgentController.makeSettingsSection() -> AnyView`
- `AgentController.makeNoticeSettings() -> AnyView`
- `AgentController.installHooks()`
- `AgentController.removeFromClaudeCode(settingsFile: URL) throws`
- `AgentController.removeHooks()`

## Ghi chú cho người sửa

- Cấu hình Codex không bao giờ bị sửa (xem giới hạn).

## Dữ liệu lưu

- `~/Library/Application Support/AraNotch/Agents/events.jsonl` (hook ghi, app đọc), `AraNotch/bin/aranotch-hook`, `claude-usage.json` (status line ghi).
- `~/.claude/settings.json` (hook và status line do người dùng cài, có sao lưu `.aranotch-backup-N`), đọc `~/.claude/projects/…/<phiên>.jsonl` và `~/.codex/sessions` (chỉ đọc).
- UserDefaults `agents.announcesWorking`, `agents.announcesAttention`, `agents.announcesFinished`, `agents.readsClaudeAccount`, `agents.tracksCodex`, `agents.turnCosts.claude`, `agents.turnCosts.codex` (`AgentSettingsStore`).
- Chuỗi khoá: chỉ đọc thông tin đăng nhập Claude khi bật "Lấy giới hạn từ tài khoản".

## Quyền hệ thống

Không cần quyền hệ thống. Sửa `~/.claude/settings.json` chỉ khi người dùng bấm cài.

## Test

- Chạy: `Scripts/test-module.sh Agent`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/AgentCoreTests/` (22 suite), `Tests/AgentFeatureTests/` (0 suite)

## Tệp

- `Sources/AgentCore/AgentEvents.swift` — Something a coding agent (Claude Code) reported through its hooks.
- `Sources/AgentCore/AgentHeadline.swift` — What a small tile says about the agents in one line: the most pressing state any session is in, and how many sessions are in it.
- `Sources/AgentCore/AgentUsage.swift` — How much of one rate limit window is used up.
- `Sources/AgentCore/ClaudeHooksInstaller.swift` — Adds this app's hooks to a Claude Code settings document, and takes them out again.
- `Sources/AgentCore/NoticeText.swift` — Fitting what an agent said onto a notice.
- `Sources/AgentCore/UsageForecast.swift` — What is left of an agent's five-hour limit, and what the turn now starting is expected to take from it, going by what recent turns took.
- `Sources/AgentFeature/AgentController.swift` — Observable agent settings; every change is written through to the store.
- `Sources/AgentFeature/AgentEventSpool.swift` — Follows the file the hook helper appends to and hands over each new event.
- `Sources/AgentFeature/AgentNotice.swift` — What a notice about an agent says, on the sign the notch grows into for a few seconds: which agent and where, what it is at, and what the turn means for its five-hour limit.
- `Sources/AgentFeature/AgentWidget.swift` — The agents at work, as a widget of the overview.
- `Sources/AgentFeature/ClaudeAccountReader.swift` — Asks the Claude account for its rate limits every few minutes, as Claude Code's `/usage` does, with the sign-in Claude Code keeps in the keychain.
- `Sources/AgentFeature/ClaudeHooks.swift` — Installs this app's hooks into Claude Code's settings file and removes them again.
- `Sources/AgentFeature/ClaudeSessionProbe.swift` — What the agent list learns from outside the hook events, off the main thread.
- `Sources/AgentFeature/CodexWatcher.swift` — Follows Codex by reading the session logs it writes itself (`~/.codex/sessions`).
- `Sources/aranotch-hook/main.swift` — The executables of this process's ancestors, nearest first: the agent, its shell, and further up the app whose window it runs in.

## Lỗi và giới hạn đã biết

- Trang Agent chỉ biết những gì hook, status line và nhật ký Codex báo: không có nội dung trao đổi. Phiên bị tắt đột ngột (không có sự kiện kết thúc) còn nằm trên trang tối đa 12 giờ.
- Hook chạy một chương trình nhỏ trước mỗi lần Claude Code dùng công cụ; chương trình luôn trả về thành công và không in gì, nên không ảnh hưởng tới agent.
- Hạn mức Claude đến từ hai nguồn: status line của AraNotch (chỉ chạy khi dùng `claude` trong Terminal; tab Code của app Claude không gọi status line) và, khi bật "Lấy giới hạn từ tài khoản Claude" trong Cài đặt › Agent, chính địa chỉ lệnh /usage đọc (`api.anthropic.com/api/oauth/usage`, không phải API công khai, Anthropic có thể đổi), mỗi 5 phút, bằng đăng nhập Claude Code trong Keychain. AraNotch không bao giờ gia hạn đăng nhập đó: khi hết hạn phải chạy `claude` trong Terminal một lần. Số nào mới hơn thì dùng số đó. Khi mốc đặt lại đã qua mà chưa có số mới, app ghi "chưa có số mới" thay vì 0%.
- Theo dõi Codex dựa vào định dạng nhật ký phiên của Codex, vốn không phải giao diện được cam kết: bản Codex sau có thể đổi và làm mất tính năng này. Codex không báo khi nó chờ người dùng cho phép, nên chỉ có hai trạng thái đang chạy và đã xong. Hạn mức Codex là con số Codex ghi lần cuối; không có phiên mới thì không được cập nhật.
- Cấu hình Codex không bị sửa dù chủ dự án đã cho phép: ô `notify` duy nhất của Codex đang được chính Codex Computer Use dùng, đặt chương trình khác vào sẽ làm hỏng nó, và nhật ký phiên đã đủ thông tin.
- Bấm vào phiên agent chỉ đưa app chứa nó lên trước, không chọn đúng cửa sổ hay tab. Chỉ phiên Claude Code báo qua hook mới biết app; phiên Codex thì không. Agent chạy trong tmux hay qua SSH không có app nào để tìm.
- Trang Agent: "Đã dừng" dựa vào dòng cuối bản ghi phiên Claude Code (`~/.claude/projects/…/<phiên>.jsonl`, chỉ đọc 16 KB cuối, chỉ xem dấu ngắt của người dùng); phiên Terminal mới mở không có mã phiên trong dòng lệnh nên vẫn bị quên sau 12 giờ im lặng.
- Mức dùng trong thông báo agent: chỉ có khi agent tự báo. Claude Code báo qua dòng trạng thái, tức là chỉ ở phiên chạy trong Terminal và khi dòng trạng thái của AraNotch đã được cài; phiên chạy trong ứng dụng Claude trên máy không báo, nên ở đó biển chỉ có tên agent và việc đang làm, hoặc một con số cũ kèm giờ. Mức tốn của một lượt là chênh lệch phần trăm giữa lúc bắt đầu và lúc xong, nên chỉ là gần đúng, và không đo khi hai agent chạy cùng lúc. Chỉ tính giới hạn 5 giờ, không tính giới hạn tuần. Thông báo "Đang làm" hiện một lần mỗi lượt, không đổi theo từng công cụ agent dùng.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): widget dùng `WidgetSize`, `WidgetAlert`.
