import Testing
@testable import MediaCore

@Suite struct AudioOutputTests {
    private func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    @Test func readsTheSystemsTransportCodes() {
        #expect(AudioOutput.Transport(code: code("bltn")) == .builtIn)
        #expect(AudioOutput.Transport(code: code("blue")) == .bluetooth)
        #expect(AudioOutput.Transport(code: code("blea")) == .bluetooth)
        #expect(AudioOutput.Transport(code: code("airp")) == .airPlay)
        #expect(AudioOutput.Transport(code: code("usb ")) == .usb)
        #expect(AudioOutput.Transport(code: code("hdmi")) == .display)
        #expect(AudioOutput.Transport(code: code("dprt")) == .display)
        #expect(AudioOutput.Transport(code: code("virt")) == .virtual)
        #expect(AudioOutput.Transport(code: code("grup")) == .virtual)
        #expect(AudioOutput.Transport(code: 0) == .other)
    }

    @Test(arguments: [
        ("MacBook Pro Speakers", AudioOutput.Transport.builtIn, "laptopcomputer"),
        ("External Headphones", .builtIn, "headphones"),
        ("AirPods Pro của Long", .bluetooth, "airpodspro"),
        ("AirPods Max", .bluetooth, "airpodsmax"),
        ("AirPods", .bluetooth, "airpods"),
        ("JBL Flip 6", .bluetooth, "hifispeaker"),
        ("Sony WH-1000XM5 Headphones", .bluetooth, "headphones"),
        ("Phòng khách", .airPlay, "airplayaudio"),
        ("LG UltraFine", .display, "display"),
        ("Scarlett 2i2", .usb, "cable.connector"),
        ("BlackHole 2ch", .virtual, "waveform"),
        ("Gì đó", .other, "speaker.wave.2"),
    ])
    func picksASymbolForTheDevice(_ sample: (String, AudioOutput.Transport, String)) {
        #expect(AudioOutput(id: 1, name: sample.0, transport: sample.1).symbolName == sample.2)
    }
}
