import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @StateObject private var vm = ASRViewModel()

    @State private var showPickLibrary = false
    @State private var showPickFile = false
    @State private var showPickCover = false

    @State private var showDeleteConfirm = false
    @State private var shareSheet: ShareSheet?

    var body: some View {
        rootView
    }

    // MARK: - Root

    private var rootView: some View {
        NavigationSplitView {
            SidebarView(
                vm: vm,
                showPickLibrary: $showPickLibrary,
                showPickFile: $showPickFile,
                showPickCover: $showPickCover,
                showDeleteConfirm: $showDeleteConfirm
            )
        } detail: {
            MainView(
                vm: vm,
                showDeleteConfirm: $showDeleteConfirm,
                shareSheet: $shareSheet
            )
        }
        .task { await vm.boot() }
        .modifier(PickersAndDialogs(
            vm: vm,
            showPickLibrary: $showPickLibrary,
            showPickFile: $showPickFile,
            showPickCover: $showPickCover,
            showDeleteConfirm: $showDeleteConfirm,
            shareSheet: $shareSheet
        ))
        .sheet(isPresented: $showPickLibrary) {
            FolderPicker(
                onPick: { url in
                    showPickLibrary = false
                    vm.setRootFolder(url)
                },
                onCancel: {
                    showPickLibrary = false
                }
            )
        }
        .sheet(isPresented: $showPickFile) {
            FilePicker(
                allowedTypes: [.item],
                asCopy: false, // para assets: no copies (dejas el original y luego tu código lo copia a library)
                onPick: { url in
                    showPickFile = false
                    vm.setFile(url)
                },
                onCancel: {
                    showPickFile = false
                }
            )
        }
        .sheet(isPresented: $showPickCover) {
            FilePicker(
                allowedTypes: [.png, .jpeg, .webP, .image],
                asCopy: true, // para cover: sí conviene copiar
                onPick: { url in
                    showPickCover = false
                    vm.importCover(from: url)
                },
                onCancel: {
                    showPickCover = false
                }
            )
        }
    }
}

// MARK: - ViewModifier (breaks the big type graph)

private struct PickersAndDialogs: ViewModifier {
    @ObservedObject var vm: ASRViewModel

    @Binding var showPickLibrary: Bool
    @Binding var showPickFile: Bool
    @Binding var showPickCover: Bool
    @Binding var showDeleteConfirm: Bool
    @Binding var shareSheet: ShareSheet?

    func body(content: Content) -> some View {
        content
            .alert("ASR", isPresented: $vm.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.alertMessage)
            }
            .confirmationDialog(
                "Delete asset?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await vm.deleteSelected() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(vm.selected?.name ?? "")
            }
            .sheet(item: $shareSheet) { sheet in
                sheet
            }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @ObservedObject var vm: ASRViewModel

    @Binding var showPickLibrary: Bool
    @Binding var showPickFile: Bool
    @Binding var showPickCover: Bool
    @Binding var showDeleteConfirm: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { bodyContent }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library").font(.caption).foregroundStyle(.secondary)

            Text(vm.rootURL?.path ?? "No folder selected")
                .font(.footnote)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack {
                Button("Select Folder") { showPickLibrary = true }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(14)
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 16) {

            filePickerCard

            metadataCard

            fileTypeCard

        }
        .padding(14)
        .opacity(vm.rootURL == nil ? 0.65 : 1.0)
    }

    private var filePickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File").font(.headline)

            Text(vm.fileURL?.lastPathComponent ?? "No file selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button("Pick File") { showPickFile = true }
                    .disabled(vm.rootURL == nil)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Nombre").font(.caption).foregroundStyle(.secondary)
                TextField("Ej: Cinematic Trailer MP4", text: $vm.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tags").font(.caption).foregroundStyle(.secondary)
                TextField("Ej: trailer, 2026, mp4, marketing", text: $vm.tags)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Cover").font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(vm.isPickingCover ? "Importing..." : "Pick Image") {
                        showPickCover = true
                    }
                    .disabled(vm.rootURL == nil || vm.isPickingCover)

                    coverThumb
                }

                if !vm.coverRelPath.isEmpty {
                    Text("Saved as: \(vm.coverRelPath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button(vm.isEditing ? "Update Asset" : "Save to Catalog") {
                Task { vm.isEditing ? await vm.update() : await vm.save() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)

            if vm.isEditing {
                Button("Cancel") { vm.cancelEdit() }
                    .buttonStyle(.bordered)

                Button("Delete") { showDeleteConfirm = true }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }

            if vm.rootURL == nil {
                Text("Selecciona “Library Folder” para habilitar el resto.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }

    @ViewBuilder
    private var coverThumb: some View {
        if let cover = vm.coverURL {
            let fixedPath = cover.path.replacingOccurrences(of: "\\", with: "/")

            if let ui = ASRImageLoader.uiImage(fromFilePath: fixedPath) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipped()
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            } else {
                Text("No image").foregroundStyle(.secondary)
            }
        } else {
            Text("No image").foregroundStyle(.secondary)
        }
    }

    private var fileTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Type").font(.headline)

            // En iOS, ToggleStyle.radio puede causar problemas dependiendo de SDK.
            // Mejor usar Picker inline.
            Picker("File Type", selection: $vm.fileTypeFilter) {
                ForEach(FileTypeFilter.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.inline)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }

    private var canSave: Bool {
        let hasRoot = vm.rootURL != nil
        let hasFileOrSelected = (vm.fileURL != nil) || (vm.selected != nil)
        let hasName = !vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTags = !vm.tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let notPicking = !vm.isPickingCover

        if vm.isEditing {
            return hasRoot && hasFileOrSelected && hasName && hasTags && notPicking
        } else {
            return hasRoot && hasFileOrSelected && hasName && hasTags && notPicking && !vm.coverRelPath.isEmpty
        }
    }
}

// MARK: - Main

private struct MainView: View {
    @ObservedObject var vm: ASRViewModel

    @Binding var showDeleteConfirm: Bool
    @Binding var shareSheet: ShareSheet?

    var body: some View {
        VStack(spacing: 0) {
            topbar
            Divider()
            ScrollView { listOrGrid }
            paginatorBar
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
    private var pickerQty:some View{
        HStack{
            Picker("Limit", selection: $vm.pageLimit) {
                Text("10").tag(10)
                Text("50").tag(50)
                Text("100").tag(100)
                Text("200").tag(200)
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
    }
    private var paginatorBar: some View {
        HStack(spacing: 12) {
            Text(vm.pageRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Prev") { vm.goPrevPage() }
                .disabled(vm.currentPage <= 1)

            Text("Page \(vm.currentPage) / \(vm.totalPages)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .center)

            Button("Next") { vm.goNextPage() }
                .disabled(vm.currentPage >= vm.totalPages)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }


    private var topbar: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Catalog").font(.title2).bold()
                Text("\(vm.filteredAssets.count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
          

            Spacer()

            HStack(spacing: 10) {
                TextField("Buscar por nombre o tags...", text: $vm.q)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Picker("", selection: $vm.viewMode) {
                    Text("Grid").tag(ViewMode.grid)
                    Text("List").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Button {
                    Task {
                        do { try await vm.refresh() }
                        catch { vm.alert("No pude refrescar. \(error.localizedDescription)") }
                    }
                } label: {
                    Label("", systemImage: "arrow.clockwise")
                }
                .disabled(vm.rootURL == nil)
                pickerQty
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var listOrGrid: some View {
        if vm.viewMode == .list {
            LazyVStack(spacing: 10) {
                ForEach(vm.pagedAssets) { a in
                    AssetCard(asset: a, isSelected: vm.selected?.id == a.id)
                        .onTapGesture { vm.startEdit(a) }
                        .contextMenu {
                            Button("Share") {
                                shareSheet = ShareSheet(activityItems: [URL(fileURLWithPath: a.sourcePath)])
                            }
                        }
                }
            }
            .padding(14)
        } else {
            let cols = [GridItem(.adaptive(minimum: 180), spacing: 14)]
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(vm.pagedAssets) { a in
                    AssetCard(asset: a, isSelected: vm.selected?.id == a.id)
                        .onTapGesture { vm.startEdit(a) }
                        .contextMenu {
                            Button("Share") {
                                shareSheet = ShareSheet(activityItems: [URL(fileURLWithPath: a.sourcePath)])
                            }
                        }
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Card

private struct AssetCard: View {
    let asset: AssetRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 6) {
                Text(asset.name).font(.headline).lineLimit(1)
                Text(asset.tags).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text(URL(fileURLWithPath: asset.sourcePath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
        .overlay(selectionBorder)
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                lineWidth: isSelected ? 2 : 1
            )
    }

    @Environment(\.horizontalSizeClass) private var hSize

    private var coverSize: CGSize {
        if hSize == .compact {
            return CGSize(width: 120, height: 80)
        } else {
            return CGSize(width: 160, height: 100)
        }
    }
    private var cover: some View {
        ZStack(alignment: .topTrailing) {
            let fixedCoverPath = asset.coverPath.replacingOccurrences(of: "\\", with: "/")

            Group {
                if let ui = ASRImageLoader.uiImage(fromFilePath: fixedCoverPath) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.quaternary)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            // 👇 tamaño responsive
            .frame(width: coverSize.width, height: coverSize.height)
            .clipped()
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.quaternary)
            )

            // badge extensión
            Text(getFileExtLabel(asset.sourcePath))
                .font(.caption2)
                .bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
                .padding(8)
        }
        // 👇 evita que el HStack lo deforme
        .fixedSize()
        
    }
}
