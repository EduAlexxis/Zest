import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("lastWallpaperPath") private var lastWallpaperPath: String = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var securityAccessActive = false
    
    @State private var videoURL: URL? = nil
    @AppStorage("lastWallpaperLoop") private var isLooping: Bool = true
    @AppStorage("lastWallpaperPlayAudio") private var playAudio: Bool = false
    @AppStorage("playAudioInPreview") private var playAudioInPreview: Bool = false
    @AppStorage("lastWallpaperTransform") private var transform: VideoTransform = .none
    @State private var showingPicker = false
    @State private var isAppliedToWallpaper = false
    
    @StateObject private var libraryStore = VideoLibraryStore()
    

    struct ResolvedItem: Identifiable, Equatable {
        let id: UUID
        var item: VideoLibraryItem
        let url: URL
    }
    
    @State private var resolvedItems: [ResolvedItem] = []
    @State private var selectedItem: ResolvedItem? = nil
    

    @State private var isTranscoding = false
    @State private var transcodeProgress: Double = 0.0
    @State private var transcodeError: String? = nil
    @State private var showingErrorAlert = false
    

    @State private var searchText = ""
    @State private var activeTab: String = "Library"
    @State private var hoveredURL: URL? = nil
    @State private var showInspector = false
    @State private var showingSettings = false
    
    @ObservedObject private var settings = SettingsManager.shared
    
    let tabs = ["Library", "Favorites", "Explore", "Updates"]
    

    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]
    
    var filteredItems: [ResolvedItem] {
        var baseItems = resolvedItems
        if activeTab == "Favorites" {
            baseItems = baseItems.filter { $0.item.isFavorite }
        }
        if searchText.isEmpty {
            return baseItems
        } else {
            return baseItems.filter {
                let displayName = $0.item.customName ?? $0.url.lastPathComponent.deletingPathExtension()
                return displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {

                VStack(spacing: 0) {

                    HStack(spacing: 16) {

                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                                .font(.title2)
                                .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                            
                            Text("Zest")
                                .font(.title2.weight(.bold))
                                .tracking(0.5)
                        }
                        .padding(.trailing, 16)
                        

                        HStack(spacing: 4) {
                            ForEach(tabs, id: \.self) { tab in
                                Button {
                                    activeTab = tab
                                } label: {
                                    Text(tab)
                                        .font(.subheadline.weight(activeTab == tab ? .semibold : .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(activeTab == tab ? Color.white.opacity(0.15) : Color.clear)
                                        .cornerRadius(6)
                                        .foregroundColor(activeTab == tab ? .primary : .secondary)
                                }
                                .buttonStyle(.plain)
                                .animation(.snappy, value: activeTab)
                            }
                        }
                        
                        Spacer()
                        

                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search wallpapers...", text: $searchText)
                                .textFieldStyle(.plain)
                                .frame(minWidth: 100, maxWidth: 180)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                        

                        Button {
                            showingPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Add video from disk")
                        

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("App Settings")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                    
                    Divider()
                    

                    if activeTab == "Library" || activeTab == "Favorites" {
                        if filteredItems.isEmpty {
                            VStack(spacing: 12) {
                                Spacer()
                                Image(systemName: activeTab == "Favorites" ? "heart.fill" : "film")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text(searchText.isEmpty ? (activeTab == "Favorites" ? "No favorites yet" : "No wallpapers in library") : "No matching wallpapers")
                                    .font(.headline)
                                Text(searchText.isEmpty ? (activeTab == "Favorites" ? "Click the heart icon on any card to add it here." : "Drag & drop a video file here or click + to add one.") : "Try adjusting your search query.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if searchText.isEmpty && activeTab == "Library" {
                                    Button("Import Video File") {
                                        showingPicker = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .padding(.top, 8)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(filteredItems) { resolved in
                                        VideoCardView(
                                            url: resolved.url,
                                            customName: resolved.item.customName,
                                            isFavorite: resolved.item.isFavorite,
                                            isSelected: selectedItem?.id == resolved.id,
                                            isHovered: hoveredURL == resolved.url,
                                            onSelect: {
                                                selectFromLibrary(resolved)
                                                withAnimation(.spring()) {
                                                    showInspector = true
                                                }
                                            },
                                            onApply: {
                                                selectFromLibrary(resolved)
                                                applyWallpaper()
                                            },
                                            onDelete: {
                                                removeFromLibrary(resolved)
                                            },
                                            onReveal: {
                                                NSWorkspace.shared.activateFileViewerSelecting([resolved.url])
                                            },
                                            onToggleFavorite: {
                                                toggleFavorite(resolved)
                                            }
                                        )
                                        .onHover { isHovering in
                                            hoveredURL = isHovering ? resolved.url : nil
                                        }
                                    }
                                }
                                .padding(24)
                            }
                        }
                    } else if activeTab == "Explore" {

                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "safari")
                                .font(.system(size: 48))
                                .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text("Coming Soon")
                                .font(.title2.weight(.bold))
                            Text("Stay tuned for future additions to the app.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {

                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Updates")
                                .font(.headline)
                            Text("Zest version 1.0.0. You are up to date!")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 520)
                

                if showInspector, let selected = selectedItem {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Wallpaper Settings")
                                .font(.headline)
                            Spacer()
                            Button {
                                withAnimation(.spring()) {
                                    showInspector = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                        
                        Divider()
                        
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 16) {

                                VideoPlayerView(url: selected.url,
                                                isLooping: isLooping,
                                                playAudio: playAudioInPreview,
                                                transform: transform)
                                .frame(height: 150)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                                

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Wallpaper Title")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    TextField("Wallpaper Name", text: Binding(
                                        get: { selected.item.customName ?? selected.url.lastPathComponent.deletingPathExtension() },
                                        set: { newValue in
                                            var updated = selected
                                            updated.item.customName = newValue.isEmpty ? nil : newValue
                                            self.selectedItem = updated
                                            if let idx = resolvedItems.firstIndex(where: { $0.id == selected.id }) {
                                                resolvedItems[idx] = updated
                                            }
                                            libraryStore.update(updated.item)
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                }
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Toggle(isOn: $isLooping) {
                                        Text("Loop Video")
                                    }
                                    .toggleStyle(.checkbox)
                                    
                                    Toggle(isOn: $playAudio) {
                                        Text("Play Audio")
                                    }
                                    .toggleStyle(.checkbox)
                                    
                                    Toggle(isOn: Binding(
                                        get: { selected.item.isFavorite },
                                        set: { _ in
                                            toggleFavorite(selected)
                                        }
                                    )) {
                                        HStack {
                                            Image(systemName: selected.item.isFavorite ? "heart.fill" : "heart")
                                                .foregroundColor(selected.item.isFavorite ? .red : .secondary)
                                            Text("Favorite Wallpaper")
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Transform / Rotation")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Picker("", selection: $transform) {
                                            ForEach(VideoTransform.allCases) { t in
                                                Text(t.label).tag(t)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        
                        Divider()
                        

                        VStack(spacing: 8) {
                            Button {
                                applyWallpaper()
                            } label: {
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                        .foregroundColor(.white)
                                    Text("Apply to Desktop")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            if isAppliedToWallpaper {
                                Button(role: .destructive) {
                                    WallpaperManager.shared.stop()
                                    isAppliedToWallpaper = false
                                } label: {
                                    HStack {
                                        Image(systemName: "stop.fill")
                                        Text("Stop Wallpaper")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                        .padding(20)
                    }
                    .frame(width: 280)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(minWidth: 800, minHeight: 480)
            .background(.regularMaterial)
            

            if isTranscoding {
                Color.black.opacity(0.4)
                    .transition(.opacity)
                
                VStack(spacing: 16) {
                    ProgressView(value: transcodeProgress) {
                        Text("Converting wallpaper video...")
                            .font(.headline)
                            .foregroundColor(.primary)
                    } currentValueLabel: {
                        Text(String(format: "%.0f%%", transcodeProgress * 100))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 250)
                    
                    Text("Optimizing video format for macOS playback.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(radius: 10)
                .transition(.scale.combined(with: .opacity))
            }
            
            if !hasCompletedOnboarding {
                Color.black.opacity(0.3)
                    .transition(.opacity)
                    .zIndex(90)
                
                OnboardingOverlayView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(isPresented: $showingSettings)
        }
        .alert("Import Error", isPresented: $showingErrorAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            if let error = transcodeError {
                Text(error)
            } else {
                Text("An unknown error occurred during video conversion.")
            }
        })
        .onDrop(of: [UTType.fileURL.identifier, UTType.item.identifier], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                var fileURL: URL? = nil
                if let data = item as? Data {
                    fileURL = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    fileURL = url
                } else if let nsURL = item as? NSURL {
                    fileURL = nsURL as URL
                }
                
                if let fileURL {
                    DispatchQueue.main.async {
                        importVideoURL(fileURL)
                    }
                }
            }
            return true
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.movie, .video, .item]) { result in
            switch result {
            case .success(let pickedURL):
                importVideoURL(pickedURL)
            case .failure(let error):
                print("Importer failed: \(error)")
            }
        }
        .onAppear {
            loadLibraryOnAppear()
            
            if !lastWallpaperPath.isEmpty {
                let resolvedURL = URL(fileURLWithPath: lastWallpaperPath)
                self.videoURL = resolvedURL
                

                if let matched = resolvedItems.first(where: { $0.url.standardizedFileURL.path == resolvedURL.standardizedFileURL.path }) {
                    self.selectedItem = matched
                }
                

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.applyWallpaper()
                }
            }
        }
        .onDisappear {
            if securityAccessActive {
                videoURL?.stopAccessingSecurityScopedResource()
                securityAccessActive = false
            }
        }
        .frame(minWidth: 1025, minHeight: 553)
    }
    
    private func importVideoURL(_ url: URL) {
        VideoTranscoder.shared.needsConversion(url: url) { needsConversion in
            DispatchQueue.main.async {
                if needsConversion {
                    self.isTranscoding = true
                    self.transcodeProgress = 0.0
                    self.transcodeError = nil
                    
                    VideoTranscoder.shared.transcode(url: url, progressHandler: { progress in
                        DispatchQueue.main.async {
                            self.transcodeProgress = progress
                        }
                    }) { transcodedURL, error in
                        self.isTranscoding = false
                        if let error = error {
                            self.transcodeError = error.localizedDescription
                            self.showingErrorAlert = true
                        } else if let transcodedURL = transcodedURL {
                            self.saveImportedVideo(url: transcodedURL, originalName: url.lastPathComponent.deletingPathExtension())
                        }
                    }
                } else {
                    self.saveImportedVideo(url: url, originalName: url.lastPathComponent.deletingPathExtension())
                }
            }
        }
    }
    
    private func saveImportedVideo(url: URL, originalName: String) {
        let accessed = url.startAccessingSecurityScopedResource()
        
        var bookmarkData: Data? = nil
        do {
            bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            print("Failed to create security-scoped bookmark: \(error). Trying standard bookmark...")
            do {
                bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch {
                print("Failed to create standard bookmark: \(error)")
            }
        }
        
        if securityAccessActive {
            videoURL?.stopAccessingSecurityScopedResource()
        }
        self.videoURL = url
        self.securityAccessActive = accessed
        
        if let bookmark = bookmarkData {
            var newItem = self.libraryStore.append(bookmark)
            newItem.customName = originalName
            self.libraryStore.update(newItem)
            let resolved = ResolvedItem(id: newItem.id, item: newItem, url: url)
            if !self.resolvedItems.contains(where: { $0.url == url }) {
                self.resolvedItems.append(resolved)
            }
            self.selectedItem = resolved
            withAnimation(.spring()) {
                self.showInspector = true
            }
        } else {
            let newItem = VideoLibraryItem(id: UUID(), bookmark: Data(), customName: originalName, isFavorite: false)
            let resolved = ResolvedItem(id: newItem.id, item: newItem, url: url)
            if !self.resolvedItems.contains(where: { $0.url == url }) {
                self.resolvedItems.append(resolved)
            }
            self.selectedItem = resolved
            withAnimation(.spring()) {
                self.showInspector = true
            }
        }
    }
    
    private func applyWallpaper() {
        guard let url = videoURL else { return }
        self.lastWallpaperPath = url.path
        
        WallpaperManager.shared.apply(url: url,
                                       loop: isLooping,
                                       playAudio: playAudio,
                                       transform: transform)
        isAppliedToWallpaper = true
    }
    
    private func loadLibraryOnAppear() {
        resolvedItems.removeAll()
        for item in self.libraryStore.items {
            var isStale = false
            var resolved: URL? = nil
            do {
                resolved = try URL(resolvingBookmarkData: item.bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            } catch {
                resolved = try? URL(resolvingBookmarkData: item.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            }
            if let resolved = resolved {
                resolvedItems.append(ResolvedItem(id: item.id, item: item, url: resolved))
            }
        }
    }
    
    private func selectFromLibrary(_ resolved: ResolvedItem) {
        if securityAccessActive {
            videoURL?.stopAccessingSecurityScopedResource()
        }
        let accessed = resolved.url.startAccessingSecurityScopedResource()
        self.securityAccessActive = accessed
        self.videoURL = resolved.url
        self.selectedItem = resolved
    }
    
    private func removeFromLibrary(_ resolved: ResolvedItem) {
        if let idx = resolvedItems.firstIndex(where: { $0.id == resolved.id }) {
            resolvedItems.remove(at: idx)
        }
        if selectedItem?.id == resolved.id {
            if securityAccessActive {
                videoURL?.stopAccessingSecurityScopedResource()
                securityAccessActive = false
            }
            selectedItem = nil
            videoURL = nil
            showInspector = false
        }
        self.libraryStore.remove(id: resolved.id)
    }
    
    private func toggleFavorite(_ resolved: ResolvedItem) {
        var updated = resolved
        updated.item.isFavorite.toggle()
        
        if let idx = resolvedItems.firstIndex(where: { $0.id == resolved.id }) {
            resolvedItems[idx] = updated
        }
        if selectedItem?.id == resolved.id {
            selectedItem = updated
        }
        libraryStore.update(updated.item)
    }
}


struct VideoCardView: View {
    let url: URL
    let customName: String?
    let isFavorite: Bool
    let isSelected: Bool
    let isHovered: Bool
    
    let onSelect: () -> Void
    let onApply: () -> Void
    let onDelete: () -> Void
    let onReveal: () -> Void
    let onToggleFavorite: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            ZStack(alignment: .topTrailing) {
                VideoThumbnailView(url: url)
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
                

                HStack {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.body.bold())
                            .foregroundColor(isFavorite ? .red : .white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    

                    Menu {
                        Button(action: onApply) {
                            Label("Apply Wallpaper", systemImage: "desktopcomputer")
                        }
                        Button(action: onReveal) {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        Divider()
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
                .padding(8)
            }
            

            VStack(alignment: .leading, spacing: 4) {
                Text(customName ?? url.lastPathComponent.deletingPathExtension())
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("Local Video Wallpaper")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.02))
        }
        .background(.thinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : (isHovered ? .white.opacity(0.3) : .white.opacity(0.1)), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 8 : 4, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .onTapGesture(count: 2) {
            onApply()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
    }
}

extension String {
    func deletingPathExtension() -> String {
        let url = URL(fileURLWithPath: self)
        return url.deletingPathExtension().lastPathComponent
    }
}

enum VideoTransform: String, CaseIterable, Identifiable {
    case none, mirror, rotate90, rotate180, rotate270
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .mirror: return "Mirror"
        case .rotate90: return "Rotate 90°"
        case .rotate180: return "Rotate 180°"
        case .rotate270: return "Rotate 270°"
        }
    }
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var settings = SettingsManager.shared
    @AppStorage("playAudioInPreview") private var playAudioInPreview: Bool = false
    @State private var activeTab = "General"
    
    let tabs = ["General", "Performance", "Audio & Video", "About"]
    
    var body: some View {
        VStack(spacing: 0) {

            HStack {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            

            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        activeTab = tab
                    } label: {
                        Text(tab)
                            .font(.body.weight(activeTab == tab ? .semibold : .regular))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(activeTab == tab ? Color.white.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                            .foregroundColor(activeTab == tab ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .animation(.snappy, value: activeTab)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            Divider()
            

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if activeTab == "General" {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("System Configuration")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Toggle(isOn: $settings.launchAtLogin) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Launch at Login")
                                        .font(.body)
                                    Text("Automatically start Zest when you log in to macOS.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Toggle(isOn: $settings.hideDesktopElements) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Hide Desktop Elements")
                                        .font(.body)
                                    Text("Hides files, folders, and icons on the macOS Desktop (Finder restart required).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("App Theme")
                                    .font(.body)
                                Text("Select the visual theme for Zest library UI.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $settings.appTheme) {
                                    Text("System Default").tag("System")
                                    Text("Light").tag("Light")
                                    Text("Dark").tag("Dark")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 300)
                            }
                        }
                        .padding(.vertical, 8)
                        
                    } else if activeTab == "Performance" {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Wallpaper Automation & Resources")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Toggle(isOn: $settings.muteWhenInactive) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mute when using other apps")
                                        .font(.body)
                                    Text("Mutes the desktop wallpaper audio when Zest is not the active app.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Toggle(isOn: $settings.pauseInFullscreen) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Stop when in fullscreen")
                                        .font(.body)
                                    Text("Pauses the video rendering completely when other apps are fullscreen to save CPU/GPU cycles.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Toggle(isOn: $settings.pauseWhenFocused) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pause when focused")
                                        .font(.body)
                                    Text("Pauses playback if another app's window covers the screen (semi-fullscreen/focused).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Toggle(isOn: $settings.pauseOnBattery) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pause on battery power")
                                        .font(.body)
                                    Text("Pauses video wallpaper playback when running on battery to conserve energy.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Toggle(isOn: $settings.pauseOnLowPowerMode) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pause when in low power mode")
                                        .font(.body)
                                    Text("Pauses video wallpaper playback when low power mode is active.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                        .padding(.vertical, 8)
                        
                    } else if activeTab == "Audio & Video" {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Playback Preferences")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Global Wallpaper Volume")
                                        .font(.body)
                                    Spacer()
                                    Text(String(format: "%.0f%%", settings.volume * 100))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $settings.volume, in: 0...1)
                                    .accentColor(.accentColor)
                                
                                Text("Applies a global volume scale to all playing desktop video wallpapers.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Fade In Duration")
                                        .font(.body)
                                    Spacer()
                                    Text(String(format: "%.1fs", settings.fadeInDuration))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $settings.fadeInDuration, in: 0...5, step: 0.1)
                                    .accentColor(.accentColor)
                                
                                Text("Transition time to fade audio in when activating wallpapers or unmuting.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Fade Out Duration")
                                        .font(.body)
                                    Spacer()
                                    Text(String(format: "%.1fs", settings.fadeOutDuration))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $settings.fadeOutDuration, in: 0...5, step: 0.1)
                                    .accentColor(.accentColor)
                                
                                Text("Transition time to fade audio out when deactivating wallpapers or muting.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                             }
                             
                             Divider()
                             
                             Toggle(isOn: $playAudioInPreview) {
                                 VStack(alignment: .leading, spacing: 2) {
                                     Text("Play Audio in Preview")
                                         .font(.body)
                                     Text("Allows wallpaper audio to play while previewing videos in the app.")
                                         .font(.caption)
                                         .foregroundColor(.secondary)
                                 }
                             }
                             .toggleStyle(.checkbox)
                         }
                         .padding(.vertical, 8)
                     } else if activeTab == "About" {
                         VStack(spacing: 16) {
                             Image(systemName: "heart.fill")
                                 .font(.system(size: 40))
                                 .foregroundColor(.red)
                                 .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
                                 .padding(.top, 8)
                             
                             Text("Zest")
                                 .font(.title.weight(.bold))
                                 .foregroundColor(.primary)
                             
                             Text("Version 1.0.0")
                                 .font(.subheadline)
                                 .foregroundColor(.secondary)
                             
                             VStack(spacing: 4) {
                                 Text("Made with love by")
                                     .font(.body)
                                     .foregroundColor(.secondary)
                                 Text("EduAlexxis")
                                     .font(.headline.weight(.semibold))
                                     .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                             }
                             
                             Text("Thank you so much for using Zest! If you enjoy the app and want to support its development, you can support me by buying me a coffee.")
                                 .font(.caption)
                                 .foregroundColor(.secondary)
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal, 24)
                                 .lineLimit(nil)
                                 .fixedSize(horizontal: false, vertical: true)
                             
                             Button {
                                 if let url = URL(string: "https://buymeacoffee.com/EduAlexxis") {
                                     NSWorkspace.shared.open(url)
                                 }
                             } label: {
                                 HStack(spacing: 8) {
                                     Image(systemName: "cup.and.saucer.fill")
                                     Text("Buy me a coffee")
                                 }
                                 .font(.headline)
                                 .foregroundColor(.black)
                                 .padding(.horizontal, 24)
                                 .padding(.vertical, 8)
                                 .background(Color.yellow)
                                 .cornerRadius(16)
                             }
                             .buttonStyle(.plain)
                             .padding(.top, 8)
                         }
                         .frame(maxWidth: .infinity)
                         .padding(.vertical, 8)
                     }
                 }
                 .padding(20)
            }
            .frame(height: 350)
            
            Divider()
            

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 500)
        .background(.ultraThinMaterial)
    }
}

struct OnboardingOverlayView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentStep = 0
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Zest")
                    .font(.title3.weight(.bold))
                    .tracking(0.5)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
            

            ZStack {
                if currentStep == 0 {

                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 64))
                            .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 5)
                            .scaleEffect(1.1)
                        
                        Text("Welcome to Zest")
                            .font(.title.weight(.bold))
                            .foregroundColor(.primary)
                        
                        Text("A lightweight, premium video wallpaper engine designed specifically for macOS. Bring your desktop to life with smooth audio integration and resource automation.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    
                } else if currentStep == 1 {

                    VStack(spacing: 20) {
                        Text("Optimized & Automated")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)
                            .padding(.top, 16)
                        
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "bolt.fill")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("FFmpeg AV1 Transcoding")
                                        .font(.headline)
                                    Text("Incompatible codecs like AV1 are automatically converted in the background for flawless native playback.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "play.slash.fill")
                                    .font(.title2)
                                    .foregroundColor(.yellow)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Resource Preservation")
                                        .font(.headline)
                                    Text("Wallpapers pause automatically when games/apps are fullscreen or when your Mac runs on battery.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Audio Volume Fades")
                                        .font(.headline)
                                    Text("Audio dynamically fades out when switching apps and loops smoothly without harsh transitions.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    
                } else if currentStep == 2 {

                    VStack(spacing: 16) {
                        Text("Configure Preferences")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)
                            .padding(.top, 16)
                        
                        VStack(spacing: 14) {
                            Toggle(isOn: $settings.launchAtLogin) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Launch at Login")
                                        .font(.headline)
                                    Text("Start Zest automatically when logging into macOS.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            
                            Divider()
                                .padding(.horizontal, 24)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Select Theme")
                                    .font(.headline)
                                Picker("", selection: $settings.appTheme) {
                                    Text("System Default").tag("System")
                                    Text("Light").tag("Light")
                                    Text("Dark").tag("Dark")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 280)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    
                } else if currentStep == 3 {

                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "heart.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.red)
                            .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        Text("Thank You!")
                            .font(.title.weight(.bold))
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 2) {
                            Text("Zest was made with love by")
                                .font(.body)
                                .foregroundColor(.secondary)
                            Text("EduAlexxis")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        
                        Text("Import video wallpapers into your library by clicking the + button or dragging files directly onto the app window. To access options, look for Zest inside your menu bar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                        
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                hasCompletedOnboarding = true
                            }
                        } label: {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(20)
                                .shadow(color: .white.opacity(0.2), radius: 10, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        
                        Spacer()
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .frame(height: 280)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentStep)
            
            Divider()
            

            HStack {

                HStack(spacing: 6) {
                    ForEach(0..<4) { step in
                        Circle()
                            .fill(currentStep == step ? Color.orange : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                            .animation(.snappy, value: currentStep)
                    }
                }
                
                Spacer()
                

                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderless)
                }
                

                if currentStep < 3 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 580, height: 420)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 500)
}



