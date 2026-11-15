import SwiftUI

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private var lessons: [ControlLesson] { ControlGuide.lessons }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TabView(selection: $page) {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { offset, lesson in
                        lessonPage(lesson)
                            .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Button(page == lessons.count - 1 ? "Listo" : "Siguiente") {
                    if page == lessons.count - 1 {
                        dismiss()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .navigationTitle("Cómo se usa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func lessonPage(_ lesson: ControlLesson) -> some View {
        VStack(spacing: 16) {
            Image(systemName: lesson.symbol)
                .font(.system(size: 56))
                .frame(height: 72)
                .accessibilityHidden(true)
            Text(lesson.title)
                .font(.title2.weight(.semibold))
            Text(lesson.detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    GuideView()
}
