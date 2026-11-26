import SwiftUI
import JLiveCore

struct CategoriesView: View {
    let platform: LivePlatform
    let service: LiveService
    let selection: LiveCategory?
    let onSelect: (LiveCategory?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [LiveCategoryGroup] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var filter = ""

    private var filteredGroups: [LiveCategoryGroup] {
        let keyword = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.compactMap { group in
            let children = group.children.filter {
                keyword.isEmpty || $0.name.localizedCaseInsensitiveContains(keyword) || group.name.localizedCaseInsensitiveContains(keyword)
            }
            return children.isEmpty ? nil : LiveCategoryGroup(id: group.id, name: group.name, children: children)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JLiveLayout.sectionSpacing) {
                    Button { choose(nil) } label: {
                        HStack {
                            Label("推荐直播", systemImage: "sparkles")
                            Spacer()
                            if selection == nil { Image(systemName: "checkmark") }
                        }
                        .font(.subheadline.weight(.semibold)).padding(16)
                        .background(JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                    if isLoading && groups.isEmpty {
                        ProgressView("正在加载分区…").frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                            Button("重试") { Task { await load(refreshing: true) } }.disabled(isLoading)
                        }
                    }
                    ForEach(filteredGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.name).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                                ForEach(group.children) { category in categoryButton(category) }
                            }
                        }
                    }
                    if !isLoading && error == nil && filteredGroups.isEmpty {
                        EmptyState(symbol: "square.grid.2x2", title: filter.isEmpty ? "暂无分区" : "没有匹配的分区")
                    }
                }
                .padding(JLiveLayout.pageInset)
            }
            .background(JLiveTheme.background)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $filter, prompt: "查找分区")
            .navigationTitle("\(platform.shortName)分区").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task { await load() }
            .refreshable { await load(refreshing: true) }
        }
    }

    private func categoryButton(_ category: LiveCategory) -> some View {
        Button { choose(category) } label: {
            VStack(spacing: 12) {
                AsyncImage(url: category.imageURL) { image in image.resizable().scaledToFit() } placeholder: {
                    Image(systemName: "square.grid.2x2.fill").font(.title2).foregroundStyle(JLiveTheme.color(platform))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 58)
                Text(category.name).font(.caption.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(selection?.id == category.id ? JLiveTheme.accent.opacity(0.12) : JLiveTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selection?.id == category.id ? JLiveTheme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityLabel(category.name).accessibilityIdentifier("category-\(category.id)")
        .accessibilityAddTraits(selection?.id == category.id ? .isSelected : [])
    }

    private func choose(_ category: LiveCategory?) {
        onSelect(category)
        dismiss()
    }

    private func load(refreshing: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { groups = try await service.categories(platform: platform, refreshing: refreshing) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
