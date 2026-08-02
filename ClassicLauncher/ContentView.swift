import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag State (shared across all items)

class DragState: ObservableObject {
    @Published var draggedAppName: String? = nil
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var appLoader = AppLoader()
    @StateObject private var dragState = DragState()
    @State private var showHiddenApps = false
    @State private var selectedAppDetails: AppDetails?

    /// Hauteur de la zone à éviter en haut de l'écran.
    /// Sur les Mac avec encoche (MacBook Pro/Air 14"+), renvoie la hauteur de l'encoche (~37 pt).
    /// Sur les Mac sans encoche, renvoie 0.
    private var screenTopSafeInset: CGFloat {
        if #available(macOS 12.0, *) {
            return NSScreen.main?.safeAreaInsets.top ?? 0
        }
        return 0
    }
    /// Index de navigation clavier (TAB) dans les résultats filtrés. nil = aucune sélection.
    @State private var focusedItemIndex: Int? = nil
    
    @Namespace private var folderAnimation
    @State private var showSettings = false
    
    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: appLoader.displaySize.cellWidth), spacing: appLoader.displaySize.gridSpacing)]
    }
    
    /// Liste à plat des AppItem navigables (TAB/ENTRÉE), recalculée uniquement quand launcherItems change.
    var navigableApps: [AppItem] {
        appLoader.launcherItems.compactMap { item -> AppItem? in
            if case .app(let app) = item { return app }
            return nil
        }
    }
    /// Dictionnaire id (String) -> index pour lookup O(1) dans ForEach.
    var navigableAppIndexByID: [String: Int] {
        var dict = [String: Int](minimumCapacity: navigableApps.count)
        for (i, app) in navigableApps.enumerated() { dict[app.id] = i }
        return dict
    }
    
    var body: some View {
        ZStack {
            // Contenu principal
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 20) {
                    HStack(spacing: 15) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.secondary)
                        
                        TextField("Rechercher une application...", text: $appLoader.searchText)
                            .font(.system(size: 28, weight: .light))
                            .textFieldStyle(PlainTextFieldStyle())
                            .onChange(of: appLoader.searchText) { _, _ in
                                // Réinitialise la sélection clavier quand la recherche change
                                focusedItemIndex = nil
                            }
                            
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Circle().fill(Color.black.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                        .help("Réglages")
                    }
                    .padding(.top, max(20, screenTopSafeInset + 8))
                    .padding(.horizontal, 40)
                    
                    // Toolbar
                    HStack(spacing: 20) {
                        HStack(spacing: 8) {
                            Text("Tri :")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Picker("", selection: $appLoader.sortOption) {
                                ForEach(SortOption.allCases, id: \.self) { o in Text(o.rawValue).tag(o) }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 200)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Text("Taille :")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Picker("", selection: $appLoader.displaySize) {
                                ForEach(DisplaySize.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 250)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 15)
                }
                .background(Color.black.opacity(0.1))
                
                if appLoader.isLoading {
                    Spacer()
                    ProgressView("Chargement des applications...")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: appLoader.displaySize.gridSpacing) {
                            LazyVGrid(columns: columns, spacing: appLoader.displaySize.gridSpacing) {
                                let indexByID = navigableAppIndexByID
                                ForEach(appLoader.launcherItems) { item in
                                    switch item {
                                    case .app(let app):
                                        let focused = indexByID[app.id] == focusedItemIndex
                                        AppIconView(
                                            app: app,
                                            loader: appLoader,
                                            dragState: dragState,
                                            isHidden: false,
                                            inFolder: false,
                                            isFocused: focused,
                                            showDetails: { d in self.selectedAppDetails = d }
                                        )
                                    case .folder(let folder, let apps):
                                        if appLoader.openFolderID == folder.id {
                                            Color.clear
                                                .frame(width: appLoader.displaySize.cellWidth, height: appLoader.displaySize.cellHeight)
                                        } else {
                                            FolderIconView(
                                                folder: folder,
                                                apps: apps,
                                                loader: appLoader,
                                                dragState: dragState,
                                                namespace: folderAnimation
                                            )
                                        }
                                    }
                                }
                            }
                            
                            // Section masquées
                            if !appLoader.filteredHiddenApps.isEmpty {
                                Divider().padding(.horizontal, 40)
                                
                                DisclosureGroup(isExpanded: $showHiddenApps) {
                                    LazyVGrid(columns: columns, spacing: appLoader.displaySize.gridSpacing) {
                                        ForEach(appLoader.filteredHiddenApps) { app in
                                            AppIconView(
                                                app: app,
                                                loader: appLoader,
                                                dragState: dragState,
                                                isHidden: true,
                                                inFolder: false,
                                                showDetails: { d in self.selectedAppDetails = d }
                                            )
                                        }
                                    }
                                    .padding(.top, 20)
                                } label: {
                                    Text("Applications masquées (\(appLoader.filteredHiddenApps.count))")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 40)
                            }
                        }
                        .padding(40)
                        .frame(maxWidth: .infinity, minHeight: NSScreen.main?.visibleFrame.height ?? 800, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if appLoader.isJiggleMode {
                                withAnimation { appLoader.isJiggleMode = false }
                            } else if UserDefaults.standard.bool(forKey: "HideOnDeactivate") {
                                NSApp.hide(nil)
                            }
                        }
                    }
                }
            }
            .scaleEffect(appLoader.isLaunching ? 1.5 : 1.0)
            .opacity(appLoader.isLaunching ? 0.0 : 1.0)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35), value: appLoader.isLaunching)
            
            // Overlay du dossier ouvert
            if let folderID = appLoader.openFolderID,
               let folder = appLoader.getFolder(byID: folderID) {
                FolderOverlayView(
                    folder: folder,
                    loader: appLoader,
                    dragState: dragState,
                    namespace: folderAnimation,
                    showDetails: { d in self.selectedAppDetails = d }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appLoader.openFolderID)
        .onAppear { appLoader.loadApps() }
        .sheet(item: $selectedAppDetails) { details in AppDetailsView(details: details) }
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 0) {
                SettingsView()
                Button("Fermer") { showSettings = false }
                    .keyboardShortcut(.defaultAction)
                    .padding(.bottom, 20)
            }
            .frame(width: 450)
        }
        // Fix #1 : Vider la recherche quand l'app reprend le focus
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appLoader.searchText = ""
            focusedItemIndex = nil
        }
        // Fix #2 : Navigation clavier TAB / ENTRÉE
        .background(
            KeyEventHandler { event in
                guard !appLoader.isLoading else { return false }
                
                // TAB : naviguer entre les résultats
                if event.keyCode == 48 { // TAB
                    let apps = navigableApps
                    guard !apps.isEmpty else { return false }
                    if let current = focusedItemIndex {
                        // Shift+TAB = reculer, TAB = avancer
                        if event.modifierFlags.contains(.shift) {
                            focusedItemIndex = current > 0 ? current - 1 : apps.count - 1
                        } else {
                            focusedItemIndex = current < apps.count - 1 ? current + 1 : 0
                        }
                    } else {
                        focusedItemIndex = event.modifierFlags.contains(.shift) ? apps.count - 1 : 0
                    }
                    return true // Consomme l'événement
                }
                
                // ENTRÉE : lancer l'app focusée (ou la première si aucune sélection)
                if event.keyCode == 36 { // Return
                    let apps = navigableApps
                    if let idx = focusedItemIndex, idx < apps.count {
                        appLoader.launchApp(apps[idx])
                        return true
                    } else if !apps.isEmpty && !appLoader.searchText.isEmpty {
                        appLoader.launchApp(apps[0])
                        return true
                    }
                }
                
                // ÉCHAP : vider la recherche
                if event.keyCode == 53 { // Escape
                    if !appLoader.searchText.isEmpty {
                        appLoader.searchText = ""
                        focusedItemIndex = nil
                        return true
                    }
                }
                
                return false
            }
        )
    }
}

// MARK: - App Icon View

struct AppIconView: View {
    let app: AppItem
    @ObservedObject var loader: AppLoader
    @ObservedObject var dragState: DragState
    let isHidden: Bool
    let inFolder: Bool
    var isFocused: Bool = false
    let showDetails: (AppDetails) -> Void
    
    @State private var isDropTargeted = false
    @GestureState private var isDragging = false
    @State private var animateJiggle = false
    
    var isBeingDragged: Bool { dragState.draggedAppName == app.name }
    
    var body: some View {
        let size = loader.displaySize
        
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size.iconSize, height: size.iconSize)
                
                if loader.isFavorite(app) {
                    Image(systemName: "star.fill")
                        .font(.system(size: size.starSize))
                        .foregroundColor(.yellow)
                        .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .offset(x: -8, y: -4)
                }
                
                if loader.isJiggleMode {
                    Button(action: { loader.deleteApp(app) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: size.starSize + 4))
                            .foregroundColor(.gray)
                            .background(Circle().fill(Color.white))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .offset(x: size.iconSize - 12, y: -12)
                }
            }
            
            Text(app.name)
                .font(.system(size: size.fontSize, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .frame(width: size.cellWidth, height: size.cellHeight, alignment: .top)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFocused
                      ? Color.accentColor.opacity(0.25)
                      : isDropTargeted ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.001))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused
                                ? Color.accentColor
                                : isDropTargeted ? Color.accentColor : Color.clear,
                                lineWidth: isFocused ? 2.5 : 2)
                )
        )
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .shadow(color: isFocused ? Color.accentColor.opacity(0.5) : .clear, radius: 8, x: 0, y: 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFocused)
        .rotationEffect(.degrees(loader.isJiggleMode ? (animateJiggle ? 2.5 : -2.5) : 0))
        .opacity(isBeingDragged ? 0.4 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .animation(loader.isJiggleMode ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .default, value: animateJiggle)
        .onChange(of: loader.isJiggleMode) { _, active in
            if active {
                let delay = Double.random(in: 0...0.1)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    animateJiggle = true
                }
            } else {
                animateJiggle = false
            }
        }
        .onTapGesture { 
            if loader.isJiggleMode {
                // Intercepter le clic en mode jiggle si besoin, 
                // mais on peut aussi lancer l'app, Apple Launchpad lance l'app ou empêche le tap
                // On empêche le lancement en mode édition
            } else {
                loader.launchApp(app)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.8)
                .onEnded { _ in
                    withAnimation { loader.isJiggleMode = true }
                }
        )
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        // Drag source
        .onDrag {
            DispatchQueue.main.async { dragState.draggedAppName = app.name }
            return NSItemProvider(object: app.name as NSString)
        }
        // Drop target (for creating folders)
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTargeted) { providers in
            guard !inFolder else { return false }
            guard let draggedName = dragState.draggedAppName, draggedName != app.name else {
                dragState.draggedAppName = nil
                return false
            }
            let targetName = app.name
            let source = draggedName
            DispatchQueue.main.async {
                dragState.draggedAppName = nil
                if let newFolderID = loader.createFolder(appName1: source, appName2: targetName) {
                    loader.openFolderID = newFolderID
                    loader.isEditingFolderName = true
                }
            }
            return true
        }
        .transition(.scale(scale: 0.1).combined(with: .opacity))
        .contextMenu {
            Button("Ouvrir") { loader.launchApp(app) }
            
            Divider()
            
            Button(action: { loader.toggleFavorite(app) }) {
                if loader.isFavorite(app) {
                    Label("Retirer des favoris", systemImage: "star.slash")
                } else {
                    Label("Ajouter aux favoris", systemImage: "star.fill")
                }
            }
            
            Button("Détails de l'app...") { showDetails(loader.getDetails(for: app)) }
            
            Divider()
            
            if inFolder, let folder = loader.folderForApp(app.name) {
                Button("Retirer du dossier") {
                    loader.removeAppFromFolder(app.name, folderID: folder.id)
                    if loader.getFolder(byID: folder.id) == nil {
                        loader.openFolderID = nil
                    }
                }
            }
            
            if isHidden {
                Button("Ne plus masquer") { loader.unhideApp(app) }
            } else {
                Button("Masquer l'application") { loader.hideApp(app) }
            }
            
            Divider()
            
            Button(role: .destructive, action: { loader.deleteApp(app) }) {
                Label("Mettre à la corbeille", systemImage: "trash")
            }
        }
    }
}

// MARK: - Folder Icon View

struct FolderIconView: View {
    let folder: AppFolder
    let apps: [AppItem]
    @ObservedObject var loader: AppLoader
    @ObservedObject var dragState: DragState
    var namespace: Namespace.ID
    @State private var isDropTargeted = false
    @State private var animateJiggle = false
    
    var body: some View {
        let size = loader.displaySize
        let previewApps = Array(apps.prefix(4))
        
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.25))
                    .frame(width: size.iconSize, height: size.iconSize)
                    .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 5)
                
                LazyVGrid(
                    columns: [
                        GridItem(.fixed(size.folderPreviewIconSize), spacing: 4),
                        GridItem(.fixed(size.folderPreviewIconSize), spacing: 4)
                    ],
                    spacing: 4
                ) {
                    ForEach(previewApps) { app in
                        Image(nsImage: app.icon)
                            .resizable()
                            .interpolation(.medium)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(width: size.folderPreviewIconSize, height: size.folderPreviewIconSize)
                    }
                }
                .padding(6)
            }
            .frame(width: size.iconSize, height: size.iconSize)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDropTargeted ? Color.accentColor : Color.white.opacity(0.15), lineWidth: isDropTargeted ? 3 : 1)
            )
            .scaleEffect(isDropTargeted ? 1.06 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDropTargeted)
            
            Text(folder.name)
                .font(.system(size: size.fontSize, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            Text("\(apps.count) app\(apps.count > 1 ? "s" : "")")
                .font(.system(size: size.fontSize - 3))
                .foregroundColor(.secondary)
        }
        .frame(width: size.cellWidth, height: size.cellHeight, alignment: .top)
        .padding(8)
        .background(Color.black.opacity(0.001))
        .matchedGeometryEffect(id: "folder-\(folder.id)", in: namespace)
        .rotationEffect(.degrees(loader.isJiggleMode ? (animateJiggle ? 2.5 : -2.5) : 0))
        .animation(loader.isJiggleMode ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .default, value: animateJiggle)
        .onChange(of: loader.isJiggleMode) { _, active in
            if active {
                let delay = Double.random(in: 0...0.1)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    animateJiggle = true
                }
            } else {
                animateJiggle = false
            }
        }
        .onTapGesture { 
            if !loader.isJiggleMode {
                loader.openFolderID = folder.id 
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.8)
                .onEnded { _ in
                    withAnimation { loader.isJiggleMode = true }
                }
        )
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTargeted) { providers in
            guard let draggedName = dragState.draggedAppName else { return false }
            let fid = folder.id
            DispatchQueue.main.async {
                dragState.draggedAppName = nil
                loader.addAppToFolder(draggedName, folderID: fid)
            }
            return true
        }
        .contextMenu {
            Button("Ouvrir le dossier") { loader.openFolderID = folder.id }
            Divider()
            Button("Dissoudre le dossier") { loader.dissolveFolder(folder.id) }
        }
    }
}

// MARK: - Folder Overlay

struct FolderOverlayView: View {
    let folder: AppFolder
    @ObservedObject var loader: AppLoader
    @ObservedObject var dragState: DragState
    var namespace: Namespace.ID
    let showDetails: (AppDetails) -> Void
    
    @State private var folderName: String = ""
    @FocusState private var nameFocused: Bool
    
    var folderApps: [AppItem] {
        loader.appsInFolder(folder).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    let overlayColumns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
    
    var body: some View {
        ZStack {
            // Fond pour fermer
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { loader.openFolderID = nil }
            
            // Contenu du dossier
            VStack(spacing: 16) {
                // Nom éditable
                if loader.isEditingFolderName {
                    HStack {
                        TextField("Nom du dossier", text: $folderName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 260)
                            .focused($nameFocused)
                            .multilineTextAlignment(.center)
                            .onAppear {
                                if folderName.isEmpty { folderName = folder.name }
                                nameFocused = true
                            }
                            .onSubmit {
                                let trimmed = folderName.trimmingCharacters(in: .whitespaces)
                                loader.renameFolder(folder.id, newName: trimmed.isEmpty ? folder.name : trimmed)
                                loader.isEditingFolderName = false
                            }
                        Button("OK") {
                            let trimmed = folderName.trimmingCharacters(in: .whitespaces)
                            loader.renameFolder(folder.id, newName: trimmed.isEmpty ? folder.name : trimmed)
                            loader.isEditingFolderName = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(folder.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 16))
                    }
                    .onTapGesture {
                        folderName = folder.name
                        loader.isEditingFolderName = true
                        nameFocused = true
                    }
                    .help("Cliquez pour renommer le dossier")
                }
                
                Text("Cliquez sur le nom pour renommer  •  Cliquez en dehors pour fermer")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                
                ScrollView {
                    LazyVGrid(columns: overlayColumns, spacing: 30) {
                        ForEach(folderApps) { app in
                            AppIconView(
                                app: app,
                                loader: loader,
                                dragState: dragState,
                                isHidden: false,
                                inFolder: true,
                                showDetails: showDetails
                            )
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 520)
                
                // Boutons
                HStack(spacing: 16) {
                    Button(action: {
                        loader.openFolderID = nil
                        loader.dissolveFolder(folder.id)
                    }) {
                        Label("Dissoudre le dossier", systemImage: "folder.badge.minus")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button("Fermer") { loader.openFolderID = nil }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .padding(30)
            .frame(maxWidth: 720)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .shadow(radius: 30)
            .matchedGeometryEffect(id: "folder-\(folder.id)", in: namespace)
        }
    }
}

// MARK: - App Details View

struct AppDetailsView: View {
    @Environment(\.presentationMode) var presentationMode
    let details: AppDetails
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: details.app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(details.app.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Taille : \(details.size)")
                    Text("Emplacement : \(details.path)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider().padding(.vertical, 5)
                    
                    Text("Date d'installation : \(details.installDate)")
                    Text("Dernier lancement : \(details.lastLaunchDate)")
                }
            }
            
            HStack {
                Spacer()
                Button("Fermer") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
        }
        .padding(30)
        .frame(width: 500)
    }
}

// MARK: - KeyEventHandler (TAB / ENTRÉE navigation)

/// Capture les événements clavier au niveau de la fenêtre pour permettre la navigation
/// TAB/Shift+TAB entre les résultats et ENTRÉE pour lancer une app, sans perturber
/// la saisie dans le TextField de recherche.
struct KeyEventHandler: NSViewRepresentable {
    /// Callback appelé quand une touche est pressée. Retourner `true` consomme l'événement.
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> KeyHandlerNSView {
        let view = KeyHandlerNSView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: KeyHandlerNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

final class KeyHandlerNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    private var monitor: Any?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, let handler = self.onKeyDown else { return event }
                // Ne pas intercepter si un TextField est en cours d'édition (sauf TAB/RETURN/ESC)
                let interestingKeys: Set<UInt16> = [48, 36, 53] // TAB, Return, Escape
                guard interestingKeys.contains(event.keyCode) else { return event }
                return handler(event) ? nil : event
            }
        } else {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }
    }
    
    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}
