# Lịch (CalendarCore, CalendarFeature)

Sổ của module **Calendar**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Trang Lịch: tháng và biểu đồ ngày, sự kiện và lời nhắc (thêm, sửa, đánh dấu xong), ước tính thời lượng, các ngày tới, ngày âm lịch, nút Tham gia cuộc họp, báo trước cuộc họp cạnh notch, widget Hôm nay của Tổng quan.

## Target và thư mục

- `CalendarCore` — `Sources/CalendarCore/`
- `CalendarFeature` — `Sources/CalendarFeature/`

## Phụ thuộc và ai dùng

- Dùng: `CalendarFeature` dùng `CalendarCore`, `NotchShell`, EventKit.
- Được dùng bởi: App (`CalendarController`); app đưa `createReminder` của Calendar cho Clipboard.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `CalendarController.init(settings: CalendarSettings, notch: NotchController)`
- `CalendarController.showPicker(named name: String)`
- `CalendarController.makeOverviewTile() -> AnyView`
- `CalendarController.makePage() -> NotchPage`
- `CalendarController.makeSettingsSection() -> AnyView`
- `CalendarController.makePageSettings() -> AnyView`
- `CalendarController.start()`
- `CalendarController.simulate()`
- `CalendarController.writeSummary(to file: URL)`
- `CalendarController.createReminder(`
- `CalendarController.canWriteReminders() -> Bool`

## Ghi chú cho người sửa

- `CalendarPageView.swift` (khoảng 1.100 dòng) và `CalendarController.swift` lớn; logic thuần (ngày, biểu đồ, lặp lại, ước tính) nằm ở `CalendarCore` và có test.

## Dữ liệu lưu

- UserDefaults `calendar.estimates`, `calendar.leadMinutes`, `calendar.meetingAlerts`, `calendar.showsLunarDate` (`CalendarSettingsStore`).
- Sự kiện và lời nhắc nằm trong Lịch và Lời nhắc của macOS (EventKit); ước tính thời lượng chỉ lưu trong AraNotch.

## Quyền hệ thống

Lịch và Lời nhắc (chỉ hỏi từ trang Lịch).

## Test

- Chạy: `Scripts/test-module.sh Calendar`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/CalendarCoreTests/`

## Tệp

- `Sources/CalendarCore/Agenda.swift` — A calendar event as the notch shows it.
- `Sources/CalendarCore/DayAgenda.swift` — What is on one chosen day.
- `Sources/CalendarCore/DayRing.swift` — A day as a ring of 24 hours: midnight at the top, going clockwise.
- `Sources/CalendarCore/DaySummary.swift` — What is left of today, for the calendar widget: how many events and reminders are still to come or under way, when the next timed one starts and what it is, and how many reminders are overdue.
- `Sources/CalendarCore/DayTimeline.swift` — One day laid out as a chart: a row for each event and reminder, placed across the hours.
- `Sources/CalendarCore/NextUp.swift` — The one thing of today a small tile has room for: the meeting under way or coming next, else an all-day event, else the first open reminder.
- `Sources/CalendarCore/QuickChoices.swift` — A day offered for one click under the month of a picker: today and the two days after it, the Saturday ahead, and this day next week.
- `Sources/CalendarCore/ReminderDetail.swift` — How urgent a reminder is, as the reminders app shows it.
- `Sources/CalendarCore/ReminderFailure.swift` — Why a change to a reminder did not go through, for the notice that says so: before, the notch only beeped and the change was gone at the next reload.
- `Sources/CalendarCore/UntilNext.swift` — How long until the next thing of the day, as a widget's chip says it: "in 40′", "in 2 h", "now".
- `Sources/CalendarCore/UpcomingDays.swift` — One thing on a day ahead: an event, or an open reminder due that day.
- `Sources/CalendarCore/WeekAndLunar.swift` — The week a date is in, as a strip of seven days.
- `Sources/CalendarFeature/AgendaSource.swift` — Whether the app may read the user's events or reminders.
- `Sources/CalendarFeature/CalendarController.swift` — State the calendar page renders from.
- `Sources/CalendarFeature/CalendarPageView.swift` — The calendar page of the notch: the month on the left and, beside it, the chosen day as a chart of its hours with the reminders that have none listed under it.
- `Sources/CalendarFeature/CalendarSettings.swift` — Observable calendar settings; every change is written through to the store.
- `Sources/CalendarFeature/CalendarSettingsSection.swift` — The calendar's line in Settings › Notices: the meeting about to start.
- `Sources/CalendarFeature/CalendarWidget.swift` — Today as a widget of the overview.

## Lỗi và giới hạn đã biết

- Trang Lịch chỉ đọc sự kiện của hôm nay và ngày mai; lời nhắc chỉ hiện những cái đến hạn trước hết ngày mai và những cái không có ngày. Chưa chọn được lịch hay danh sách nào được hiện: mọi lịch trong máy đều được đọc.
- Báo trước cuộc họp không có âm thanh, và tên cuộc họp bị cắt ngắn vì chỗ bên notch hẹp. Nhiều cuộc họp cùng giờ thì chỉ báo cuộc sớm nhất.
- Bấm vòng tròn là ghi thẳng "đã xong" vào Lời nhắc của người dùng; app chưa có nút hoàn tác (phải mở app Lời nhắc để bỏ đánh dấu).
- Nút Tham gia chỉ nhận link https của Zoom, Google Meet, Microsoft Teams, Webex và Whereby tìm thấy trong địa chỉ, địa điểm hoặc ghi chú của sự kiện.
- Trang Lịch: sự kiện mới luôn vào lịch mặc định của máy, dài một tiếng (hoặc cả ngày); muốn đổi lịch, địa điểm hay thời lượng thì bấm sự kiện để sửa trong ứng dụng Lịch. Bấm lời nhắc chỉ mở ứng dụng Lời nhắc, chưa thấy nó tự chọn đúng lời nhắc đó. Cách mở sự kiện dựa vào kiểu liên kết `ical://ekevent/…` mà Apple không công bố chính thức, nên có thể đổi theo bản macOS.
- Chọn giờ: sự kiện mới vẫn dài một tiếng, chưa chọn được giờ kết thúc. Mặt đồng hồ trên notch nhỏ (đường kính 118 điểm trước khi phóng), nên số phút chỉ ghi mỗi 5 phút.
- Trang Lịch mới: ảnh chụp tự động của app (--snapshot-dir) ra notch đóng khi trang đổi chiều cao, phải chụp cửa sổ thật. Tên dài bị cắt ở cột tên rộng 150 điểm (rê chuột để xem đủ). Notch cao tối đa 80% chiều cao màn hình, quá nữa thì cuộn. Các sự kiện chồng giờ nhau vẫn mỗi sự kiện một hàng, không gộp.
- Sửa lời nhắc: macOS không cho ứng dụng khác đọc hay đổi cờ, thẻ, việc con, ảnh đính kèm và "khi nhắn tin" của một lời nhắc; nhắc theo địa điểm không làm theo lựa chọn của chủ dự án (lời nhắc đã có địa điểm thì giữ nguyên). Lặp lại chỉ có năm kiểu; một kiểu lặp phức tạp hơn đặt ở nơi khác (hai tuần một lần, có ngày kết thúc) hiện thành kiểu gần nhất và được giữ nguyên cho tới khi chính mục lặp lại bị đổi. Báo sớm được ghi thành một chuông báo thứ hai trước giờ hạn; chưa kiểm tra ứng dụng Lời nhắc hiện chuông đó ở đâu.
- Sửa lời nhắc: việc ghi và xoá trên Lời nhắc thật chưa được thử tay, chỉ thử với dữ liệu giả lập. Tên và ghi chú vẫn phải gõ. Ô chỉnh đóng khi đổi sang ngày khác; thay đổi chưa bấm "Xong" khi đó bị bỏ.
- Việc đã xong: chỉ hiện ở cỡ cao hết mức, chỉ theo ngày hoàn thành (không theo hạn), không có giờ hoàn thành, không mở ô chỉnh được và không có thanh trên biểu đồ. Việc lặp lại sau khi đánh dấu xong chuyển sang lần kế tiếp nên có thể không hiện trong nhóm. Bảng chọn "tới một ngày" không còn nút mở trên trang, vì lịch tháng luôn hiện.
- Xem trước khi đang chỉnh (0.9.1): từ 0.9.2 hàng lựa chọn của một chip (lặp lại, báo sớm, ưu tiên, ước tính, danh sách) ở yên sau khi chọn, để thử mức khác và nhìn biểu đồ; nó đóng khi bấm "Xong", bấm lại chip đó, hoặc mở chip khác. trong lúc ô chỉnh mở, biểu đồ ngày vẽ lời nhắc theo những gì đang chọn (ước tính, giờ, tên), chưa cần bấm "Xong"; "Huỷ" thì trở lại như đã lưu. Riêng ngày: nếu ngày đang chọn đưa lời nhắc ra khỏi ngày đang xem thì hàng vẫn ở yên cho tới khi bấm "Xong", để ô chỉnh không mất chỗ đứng. Lặp lại, báo sớm, mức ưu tiên và danh sách không có gì để vẽ nên không xem trước. Chưa thử trên lời nhắc thật.
- Ước tính thời lượng: chỉ có trong AraNotch trên máy này; ứng dụng Lời nhắc và các thiết bị khác không thấy. Ước tính gắn với mã của lời nhắc, nên một lời nhắc lặp lại giữ ước tính cho các lần sau; ước tính của lời nhắc đã xong hay bị xoá ở nơi khác thì nằm lại trong cài đặt, không tự dọn (xoá từ ô chỉnh thì dọn). Thanh không hiện ở nhóm quá hạn và ở ô Tổng quan. Việc bắt đầu từ hôm trước chỉ vẽ phần trong ngày.
- Nút chọn nhanh: bốn giờ 9:00, 12:00, 15:00, 19:00 và năm ngày là cố định, chưa có cài đặt để đổi. "Tuần sau" là ngày này tuần sau (cộng bảy ngày), không phải thứ Hai tuần sau.
- Ghim khi chọn ngày giờ (0.7.2): trong lúc bảng lịch tháng và mặt đồng hồ của trang Lịch đang mở (sự kiện mới, lời nhắc mới, sửa lời nhắc, tới một ngày), notch được ghim: con trỏ rời đi hay bấm ra ngoài đều không đóng, nút ghim sáng lên; bấm "Xong" (hoặc chọn xong ngày) thì thôi ghim. Esc vẫn đóng notch và bỏ bảng chọn. Sang trang khác thì ghim tạm thôi, quay lại trang Lịch thì có lại. Chưa thử tay với con trỏ thật.
- Ngày âm lịch mặc định chỉ bật khi ngôn ngữ đầu tiên của máy là tiếng Việt hoặc tiếng Trung; máy để tiếng Anh thì phải tự bật trong Cài đặt › Lịch. Cửa sổ của app mở trên màn hình đang dùng, nên khi có màn hình ngoài chúng mở ở đó.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): widget dùng `WidgetSize`.
