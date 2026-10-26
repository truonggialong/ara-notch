# Nhạc (MediaCore, MediaFeature)

Sổ của module **Media**. Đọc `docs/modules/README.md` trước: luật ranh giới và quy trình sửa lỗi.

## Vai trò

Trang Đang phát: bài đang phát từ mọi app, điều khiển, tua, âm lượng, đổi thiết bị phát, lời bài hát (lrclib.net), báo bài mới cạnh notch, app đang phát tiếng, widget Nhạc của Tổng quan và dòng âm lượng trong widget Máy.

## Target và thư mục

- `MediaCore` — `Sources/MediaCore/`
- `MediaFeature` — `Sources/MediaFeature/`

## Phụ thuộc và ai dùng

- Dùng: `MediaFeature` dùng `MediaCore`, `NotchShell`, CoreAudio, tiến trình phụ `osascript` (MediaRemote).
- Được dùng bởi: App (`MediaController`); `makeVolumeRow()` được app trao cho widget Máy của SystemEvents.

## Giao diện công khai

Những gì app gọi (hàm `public` của controller; các kiểu `public` khác xem trong mã):

- `MediaController.init(settings: MediaSettings, notch: NotchController)`
- `MediaController.start()`
- `MediaController.var outputSummary: String`
- `MediaController.stop()`
- `MediaController.makeVolumeRow() -> AnyView`
- `MediaController.makeOverviewTile() -> AnyView`
- `MediaController.makePage() -> NotchPage`
- `MediaController.makePageSettings() -> AnyView`
- `MediaController.makeNoticeSettings() -> AnyView`
- `MediaController.simulate(line: String)`
- `MediaController.simulate(soundingBundleIDs: [String])`

## Ghi chú cho người sửa

- Không có.

## Dữ liệu lưu

- UserDefaults `media.enabled`, `media.announcesTracks`, `media.showsWhilePlaying`, `media.showsLyrics` (`MediaSettingsStore`).

## Quyền hệ thống

Không cần quyền. Đọc "đang phát" qua giao diện riêng MediaRemote của Apple; lời bài hát gửi tên bài tới lrclib.net khi bật.

## Test

- Chạy: `Scripts/test-module.sh Media`, rồi `Scripts/test.sh`.
- Bộ test: `Tests/MediaCoreTests/` (11 suite)

## Tệp

- `Sources/MediaCore/AudioOutput.swift` — A device sound can be played through.
- `Sources/MediaCore/Lyrics.swift` — The words of a song with the moment each line is sung.
- `Sources/MediaCore/MusicApps.swift` — The apps offered for a start when nothing is playing.
- `Sources/MediaCore/NowPlaying.swift` — The track the system reports as now playing, in whatever app plays it.
- `Sources/MediaCore/SoundingApps.swift` — Working out which apps are sending sound out, from what the audio system reports.
- `Sources/MediaFeature/AudioOutputs.swift` — Lists the sound output devices and switches between them, through Core Audio.
- `Sources/MediaFeature/MediaCommands.swift` — Sends playback commands to whatever app is playing, through the system's media interface.
- `Sources/MediaFeature/MediaController.swift` — State the Now Playing page renders from.
- `Sources/MediaFeature/MediaSettings.swift` — Observable Now Playing settings; every change is written through to the store.
- `Sources/MediaFeature/MediaWidget.swift` — What is playing, as a widget of the overview.
- `Sources/MediaFeature/NowPlayingHelper.swift` — Reads what is playing through a helper process.
- `Sources/MediaFeature/NowPlayingPageView.swift` — The Now Playing page of the notch: the artwork as a card on a small pile of paper, the track beside it, and an outlined bar of playback buttons.
- `Sources/MediaFeature/PlayingBarsView.swift` — A few bars that move while something is playing.
- `Sources/MediaFeature/SoundingAppsMonitor.swift` — An app that is playing something, as the page shows it.

## Lỗi và giới hạn đã biết

- Trang Đang phát dựa trên giao diện riêng của Apple (MediaRemote) qua tiến trình phụ `osascript`; một bản macOS sau có thể chặn cách này, khi đó trang báo "không cho đọc bài đang phát".
- Trang Đang phát cập nhật mỗi giây một lần, nên đổi bài hay tạm dừng từ app khác hiện chậm tối đa một giây; chưa kéo được thanh tiến độ để tua.
- Tên bài báo bên notch bị cắt ngắn vì mỗi bên chỉ rộng 92 điểm.
- Thanh sóng nhạc chỉ là hoạt hình, không đo âm thanh thật (đo thật cần quyền ghi âm thanh hệ thống).
- Danh sách thiết bị âm thanh chỉ đọc lại mỗi lần mở notch.
- Sau khi chọn thiết bị trong menu, notch đóng lại vì con trỏ đang nằm ngoài vùng notch.
- Tua bài dùng lệnh hệ thống mà không phải trình phát nào cũng nghe; trình phát không hỗ trợ thì bỏ qua (đã thử với QuickTime Player và Spotify; chưa thử với Music hay trình duyệt). Thanh âm lượng không hiện với thiết bị không cho máy đặt âm lượng. Bài không có tên thì lấy tên tệp; không có cả hai thì trang vẫn báo chưa có gì đang phát.
- Đang phát từ mọi app: tên bài, thanh tiến độ và các nút điều khiển chỉ có cho app mà macOS coi là "đang phát" (mỗi lúc một app, thường là app bắt đầu phát gần nhất). Các app khác chỉ hiện là đang phát tiếng, không có tên nội dung và không điều khiển được từ notch. Với trình duyệt, trang không biết đó là YouTube, Facebook hay trang nào; chỉ có tiêu đề mà trang web tự đặt. App phát video không tiếng, và lệnh chạy trong Terminal không thuộc app nào, thì không được nhận ra.
- Lời bài hát: chỉ có khi lrclib.net có lời kèm mốc thời gian cho đúng bài; bài không có nghệ sĩ (video web) không được hỏi. Ngày âm lịch dùng lịch âm dương của macOS (tính theo giờ Trung Quốc), vài ngày hiếm hoi lệch một ngày so với lịch Việt Nam.

## Nhật ký sửa lỗi

Mỗi dòng: ngày — lỗi hoặc thay đổi — test đã thêm — commit.

- 2026-10-26 — tái cấu trúc theo module (nhánh `refactor/feature-modules`): widget dùng `WidgetSize`.
