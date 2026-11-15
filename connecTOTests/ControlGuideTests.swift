import Testing
@testable import connecTO

struct ControlGuideTests {
    @Test func everyLessonCanBeRead() {
        #expect(!ControlGuide.lessons.isEmpty)
        for lesson in ControlGuide.lessons {
            #expect(!lesson.id.isEmpty)
            #expect(!lesson.symbol.isEmpty)
            #expect(!lesson.title.isEmpty)
            #expect(!lesson.detail.isEmpty)
        }
    }

    @Test func eachControlAppearsOnce() {
        let ids = ControlGuide.lessons.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == [
            "picture",
            "click",
            "rightClick",
            "drag",
            "keyboard",
            "previousSpace",
            "windows",
            "nextSpace",
            "quality",
            "media",
            "permissions",
            "code",
        ])
    }
}
