import Testing
@testable import ClipboardCore

@Suite struct CodeDetectorTests {
    @Test(arguments: [
        "func greet(_ name: String) -> String {\n    \"Xin chào, \\(name)!\"\n}",
        "def area(radius):\n    pi = 3.14159\n    return pi * radius ** 2",
        "const sum = (items) => {\n  return items.reduce((a, b) => a + b, 0);\n};",
        "{\n  \"name\": \"AraNotch\",\n  \"version\": 2\n}",
        "<div class=\"card\">\n  <p>Xin chào</p>\n</div>",
        "SELECT id, name\nFROM users WHERE age >= 18;",
        ".card {\n  color: #fff;\n  padding: 8px;\n}",
        "const total = items.reduce((a, b) => a + b, 0);",
        "import Foundation\n\nlet url = URL(string: \"https://example.com\")!\nprint(url.host ?? \"\")",
        "#include <stdio.h>\n\nint main(void) {\n    printf(\"hi\\n\");\n    return 0;\n}",
    ])
    func recognisesCode(_ text: String) {
        #expect(CodeDetector.looksLikeCode(text))
    }

    @Test(arguments: [
        "Hôm nay trời đẹp, chúng ta đi dạo nhé.",
        "The meeting moved to Friday. Please update your calendar and let me know if that works.",
        "Lịch họp tuần này: thứ Ba 9 giờ, phòng họp tầng 3.",
        "- Mua sữa\n- Gọi cho mẹ\n- Nộp báo cáo",
        "Nguyễn Văn A,\n12 Lê Lợi, Quận 1,\nThành phố Hồ Chí Minh,",
        "https://www.apple.com/vn/macbook-pro/",
        "#4A90D9",
        "hello",
        "",
        "{",
        "import thuế tăng 5% trong quý này",
        "Ghi chú:\nmai họp lúc 9 giờ\nnhớ mang laptop",
        "return to sender, address unknown",
    ])
    func leavesProseAlone(_ text: String) {
        #expect(!CodeDetector.looksLikeCode(text))
    }

    @Test func onlyTheBeginningOfLongTextIsExamined() {
        let prose = String(repeating: "Đây là một câu văn bình thường. ", count: 200)
        #expect(!CodeDetector.looksLikeCode(prose + "\nfunc f() { return 1; }"))
    }
}
