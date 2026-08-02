import Cocoa
import Foundation
import CoreServices
import UniformTypeIdentifiers
import Combine
import SwiftUI

// MARK: - Data Models

struct AppItem: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let url: URL
    let icon: NSImage
    let isLegacy: Bool
    
    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.name == rhs.name && lhs.url == rhs.url
    }
}

struct AppFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var appNames: [String]
}

struct AppDetails: Identifiable {
    let id = UUID()
    let app: AppItem
    let size: String
    let installDate: String
    let lastLaunchDate: String
    let path: String
}

enum LauncherItem: Identifiable, Equatable {
    case app(AppItem)
    case folder(AppFolder, [AppItem])
    
    static func == (lhs: LauncherItem, rhs: LauncherItem) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: String {
        switch self {
        case .app(let item): return "app-\(item.name)"
        case .folder(let folder, _): return "folder-\(folder.id.uuidString)"
        }
    }
    
    var sortKey: String {
        switch self {
        case .app(let item): return item.name
        case .folder(let folder, _): return folder.name
        }
    }
    
    var isFolderItem: Bool {
        if case .folder = self { return true }
        return false
    }
}

enum SortOption: String, CaseIterable, Codable {
    case alphabetical = "A → Z"
    case favoritesFirst = "★ Favoris"
}

enum ShortcutType: Int, Codable, CaseIterable {
    case f4 = 0
    case optionSpace = 1
    case cmdShiftSpace = 2
    
    var title: String {
        switch self {
        case .f4: return "F4 (Launchpad)"
        case .optionSpace: return "Option (⌥) + Espace"
        case .cmdShiftSpace: return "Cmd (⌘) + Maj (⇧) + Espace"
        }
    }
}

enum DisplaySize: String, CaseIterable, Codable {
    case small = "Petit"
    case normal = "Normal"
    case large = "Grand"
    
    var columnsCount: Int {
        switch self { case .small: return 8; case .normal: return 6; case .large: return 4 }
    }
    var iconSize: CGFloat {
        switch self { case .small: return 56; case .normal: return 80; case .large: return 110 }
    }
    var cellWidth: CGFloat {
        switch self { case .small: return 90; case .normal: return 120; case .large: return 160 }
    }
    var cellHeight: CGFloat {
        switch self { case .small: return 100; case .normal: return 130; case .large: return 170 }
    }
    var fontSize: CGFloat {
        switch self { case .small: return 11; case .normal: return 14; case .large: return 16 }
    }
    var gridSpacing: CGFloat {
        switch self { case .small: return 20; case .normal: return 30; case .large: return 40 }
    }
    var folderPreviewIconSize: CGFloat {
        switch self { case .small: return 20; case .normal: return 28; case .large: return 40 }
    }
    var starSize: CGFloat {
        switch self { case .small: return 12; case .normal: return 16; case .large: return 20 }
    }
}

// MARK: - Data Manager (JSON Persistence)

class DataManager {
    static let shared = DataManager()
    private let fileURL: URL
    
    struct AppData: Codable {
        var folders: [AppFolder] = []
        var hiddenApps: Set<String> = []
        var favoriteApps: Set<String> = []
        var legacySetupDone: Bool = false
        var activeShortcut: ShortcutType = .f4
    }
    
    var data = AppData()
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.classiclauncher"
        let appDir = appSupport.appendingPathComponent(bundleID)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("launcher_data.json")
        load()
        
        // Migration depuis UserDefaults vers JSON si nécessaire
        migrateFromUserDefaultsIfNeeded()
    }
    
    func load() {
        guard let jsonData = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppData.self, from: jsonData) else { return }
        self.data = decoded
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: fileURL)
        }
    }
    
    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let migratedKey = "HasMigratedToJson"
        if defaults.bool(forKey: migratedKey) { return }
        
        if let fd = defaults.data(forKey: "AppFolders"), let folders = try? JSONDecoder().decode([AppFolder].self, from: fd) {
            self.data.folders = folders
        }
        if let ha = defaults.stringArray(forKey: "HiddenAppsList") { self.data.hiddenApps = Set(ha) }
        if let fa = defaults.stringArray(forKey: "FavoriteAppsList") { self.data.favoriteApps = Set(fa) }
        self.data.legacySetupDone = defaults.bool(forKey: "LegacyFolderSetupDone")
        
        save()
        defaults.set(true, forKey: migratedKey)
    }
}

// MARK: - App Scanner (NSMetadataQuery)

class AppScanner: ObservableObject {
    @Published var installedApps: [AppItem] = []
    private var query: NSMetadataQuery?
    static let legacyFolderName = "App systèmes (Legacy)"
    
    func startScanning() {
        query = NSMetadataQuery()
        query?.searchScopes = [NSMetadataQueryLocalComputerScope]
        query?.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated), name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated), name: .NSMetadataQueryDidFinishGathering, object: query)
        
        query?.start()
    }
    
    @objc private func queryUpdated(_ notification: Notification) {
        query?.disableUpdates()
        defer { query?.enableUpdates() }
        
        guard let results = query?.results as? [NSMetadataItem] else { return }
        
        let ws = NSWorkspace.shared
        let fm = FileManager.default
        var loaded: [AppItem] = []
        
        for item in results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            guard isInTrustedDirectory(url) else { continue }
            guard !isInternalHelper(url) else { continue }
            
            var name = url.deletingPathExtension().lastPathComponent
            if let loc = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String {
                var n = loc
                if n.hasSuffix(".app") { n = String(n.dropLast(4)) }
                name = n
            } else {
                let dn = fm.displayName(atPath: path)
                if !dn.isEmpty && dn != url.lastPathComponent { name = dn }
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            }
            
            loaded.append(AppItem(name: name, url: url, icon: ws.icon(forFile: path), isLegacy: false))
        }
        
        // Apps legacy
        var legacyNames: [String] = []
        let legacyDir = URL(fileURLWithPath: "/System/Library/CoreServices/Applications")
        if let en = fm.enumerator(at: legacyDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in en where url.pathExtension == "app" {
                var name = url.deletingPathExtension().lastPathComponent
                let dn = fm.displayName(atPath: url.path)
                if !dn.isEmpty && dn != url.lastPathComponent { name = dn }
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                loaded.append(AppItem(name: name, url: url, icon: ws.icon(forFile: url.path), isLegacy: true))
                legacyNames.append(name)
            }
        }
        
        // Déduplication
        var uniqueByName = [String: AppItem]()
        for app in loaded where uniqueByName[app.name] == nil {
            uniqueByName[app.name] = app
        }
        let sorted = uniqueByName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        DispatchQueue.main.async {
            let currentNames = self.installedApps.map { $0.name }
            let newNames = sorted.map { $0.name }
            if currentNames != newNames {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    self.installedApps = sorted
                    self.setupLegacyFolder(legacyAppNames: legacyNames.filter { uniqueByName[$0] != nil })
                }
            }
        }
    }
    
    private func setupLegacyFolder(legacyAppNames: [String]) {
        if DataManager.shared.data.legacySetupDone { return }
        if !legacyAppNames.isEmpty {
            let folder = AppFolder(name: AppScanner.legacyFolderName, appNames: legacyAppNames)
            DataManager.shared.data.folders.append(folder)
            DataManager.shared.data.legacySetupDone = true
            DataManager.shared.save()
        }
    }
    
    private func isInTrustedDirectory(_ url: URL) -> Bool {
        let path = url.path
        let trusted = ["/Applications/", "/System/Applications/", "/System/Volumes/Preboot/Cryptexes/", NSHomeDirectory() + "/Applications/"]
        return trusted.contains { path.hasPrefix($0) }
    }
    
    private func isInternalHelper(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        let helperPatterns = [" Helper", "XCPreviewAgent", "XCTRunner", "Autoupdate", "crashreporter", "plugin-container", "gpu-helper"]
        return helperPatterns.contains { name.contains($0) }
    }
}

// MARK: - App Cleaner

class AppCleaner {
    static func deepClean(app: AppItem) {
        let fm = FileManager.default
        let bundleID = Bundle(url: app.url)?.bundleIdentifier
        
        // Toujours mettre l'app à la corbeille
        try? fm.trashItem(at: app.url, resultingItemURL: nil)
        
        // Si on a le bundle ID, on cherche les fichiers associés
        guard let bid = bundleID else { return }
        let home = fm.homeDirectoryForCurrentUser
        let pathsToCheck = [
            home.appendingPathComponent("Library/Application Support/\(bid)"),
            home.appendingPathComponent("Library/Caches/\(bid)"),
            home.appendingPathComponent("Library/Preferences/\(bid).plist"),
            home.appendingPathComponent("Library/Saved Application State/\(bid).savedState"),
            home.appendingPathComponent("Library/Containers/\(bid)"),
            home.appendingPathComponent("Library/Group Containers/\(bid)")
        ]
        
        for path in pathsToCheck {
            if fm.fileExists(atPath: path.path) {
                try? fm.trashItem(at: path, resultingItemURL: nil)
            }
        }
    }
}

// MARK: - App Loader (ViewModel)

class AppLoader: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var folders: [AppFolder] = [] { didSet { DataManager.shared.data.folders = folders; DataManager.shared.save() } }
    @Published var isLoading = true
    @Published var searchText = ""
    @Published var isLaunching = false
    @Published var isJiggleMode = false // Mode édition
    
    @Published var sortOption: SortOption { didSet { UserDefaults.standard.set(sortOption.rawValue, forKey: "SortOptionChoice") } }
    @Published var displaySize: DisplaySize { didSet { UserDefaults.standard.set(displaySize.rawValue, forKey: "DisplaySizeChoice") } }
    
    @Published var openFolderID: UUID? = nil
    @Published var isEditingFolderName = false

    private var scanner = AppScanner()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        if let s = UserDefaults.standard.string(forKey: "SortOptionChoice"), let o = SortOption(rawValue: s) { self.sortOption = o } else { self.sortOption = .alphabetical }
        if let s = UserDefaults.standard.string(forKey: "DisplaySizeChoice"), let o = DisplaySize(rawValue: s) { self.displaySize = o } else { self.displaySize = .normal }
        
        self.folders = DataManager.shared.data.folders
        
        scanner.$installedApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newApps in
                self?.apps = newApps
                self?.isLoading = false
            }
            .store(in: &cancellables)
    }
    
    func loadApps() {
        scanner.startScanning()
    }
    
    // MARK: - Persistence Proxy
    
    var hiddenAppNames: Set<String> {
        get { DataManager.shared.data.hiddenApps }
        set { DataManager.shared.data.hiddenApps = newValue; DataManager.shared.save() }
    }
    var favoriteAppNames: Set<String> {
        get { DataManager.shared.data.favoriteApps }
        set { DataManager.shared.data.favoriteApps = newValue; DataManager.shared.save() }
    }
    
    func isFavorite(_ app: AppItem) -> Bool { favoriteAppNames.contains(app.name) }
    
    // MARK: - Computed Properties
    
    private var appsInFolders: Set<String> { Set(folders.flatMap { $0.appNames }) }
    
    private var sortedApps: [AppItem] {
        switch sortOption {
        case .alphabetical: return apps
        case .favoritesFirst:
            return apps.sorted { a, b in
                let fa = isFavorite(a), fb = isFavorite(b)
                if fa == fb { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
                return fa && !fb
            }
        }
    }
    
    var visibleApps: [AppItem] { sortedApps.filter { !hiddenAppNames.contains($0.name) } }
    var hiddenApps: [AppItem] { sortedApps.filter { hiddenAppNames.contains($0.name) } }
    
    var launcherItems: [LauncherItem] {
        let inFolders = appsInFolders
        let hidden = hiddenAppNames
        
        let standalone: [LauncherItem] = visibleApps
            .filter { !inFolders.contains($0.name) }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .map { .app($0) }
        
        let folderItems: [LauncherItem] = folders.compactMap { folder in
            let folderApps = self.apps.filter { folder.appNames.contains($0.name) && !hidden.contains($0.name) }
            if folderApps.isEmpty { return nil }
            if !searchText.isEmpty {
                let folderMatch = folder.name.localizedCaseInsensitiveContains(searchText)
                let anyAppMatch = folderApps.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
                if !folderMatch && !anyAppMatch { return nil }
            }
            return .folder(folder, folderApps)
        }
        
        var items = standalone + folderItems
        
        switch sortOption {
        case .alphabetical:
            items.sort { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
        case .favoritesFirst:
            items.sort { a, b in
                let aFav: Bool; let bFav: Bool
                switch a { case .app(let app): aFav = isFavorite(app); case .folder: aFav = false }
                switch b { case .app(let app): bFav = isFavorite(app); case .folder: bFav = false }
                if aFav == bFav { return a.sortKey.localizedCaseInsensitiveCompare(b.sortKey) == .orderedAscending }
                return aFav && !bFav
            }
        }
        return items
    }
    
    var filteredHiddenApps: [AppItem] {
        let hidden = hiddenApps
        if searchText.isEmpty { return hidden }
        return hidden.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - Folder Actions
    
    @discardableResult
    func createFolder(appName1: String, appName2: String) -> UUID? {
        guard appName1 != appName2 else { return nil }
        removeAppFromAllFolders(appName1)
        removeAppFromAllFolders(appName2)
        let folder = AppFolder(name: "Nouveau dossier", appNames: [appName1, appName2])
        folders.append(folder)
        objectWillChange.send()
        return folder.id
    }
    
    func addAppToFolder(_ appName: String, folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        if folders[idx].appNames.contains(appName) { return }
        removeAppFromAllFolders(appName)
        folders[idx].appNames.append(appName)
        objectWillChange.send()
    }
    
    func removeAppFromFolder(_ appName: String, folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].appNames.removeAll { $0 == appName }
        if folders[idx].appNames.count <= 1 { folders.remove(at: idx) }
        objectWillChange.send()
    }
    
    func removeAppFromAllFolders(_ appName: String) {
        for i in (0..<folders.count).reversed() {
            folders[i].appNames.removeAll { $0 == appName }
            if folders[i].appNames.isEmpty { folders.remove(at: i) }
        }
    }
    
    func renameFolder(_ folderID: UUID, newName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].name = newName
        objectWillChange.send()
    }
    
    func dissolveFolder(_ folderID: UUID) {
        folders.removeAll { $0.id == folderID }
        objectWillChange.send()
    }
    
    func folderForApp(_ appName: String) -> AppFolder? { folders.first { $0.appNames.contains(appName) } }
    func getFolder(byID id: UUID) -> AppFolder? { folders.first { $0.id == id } }
    func appsInFolder(_ folder: AppFolder) -> [AppItem] { apps.filter { folder.appNames.contains($0.name) } }
    
    // MARK: - App Actions
    
    func hideApp(_ app: AppItem)   { var h = hiddenAppNames; h.insert(app.name); hiddenAppNames = h; objectWillChange.send() }
    func unhideApp(_ app: AppItem) { var h = hiddenAppNames; h.remove(app.name); hiddenAppNames = h; objectWillChange.send() }
    func unhideAllApps()           { hiddenAppNames = []; objectWillChange.send() }
    
    func toggleFavorite(_ app: AppItem) {
        var f = favoriteAppNames
        if f.contains(app.name) { f.remove(app.name) } else { f.insert(app.name) }
        favoriteAppNames = f; objectWillChange.send()
    }
    
    func deleteApp(_ app: AppItem) {
        AppCleaner.deepClean(app: app)
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                self.removeAppFromAllFolders(app.name)
                self.apps.removeAll { $0.id == app.id }
            }
        }
    }
    
    func launchApp(_ app: AppItem) {
        isLaunching = true
        openFolderID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSWorkspace.shared.open(app.url)
            NSApp.hide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.isLaunching = false }
        }
    }
    
    func getDetails(for app: AppItem) -> AppDetails {
        let fm = FileManager.default
        var sizeStr = "Inconnue", installStr = "Inconnue", lastLaunchStr = "Jamais"
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short; df.locale = Locale(identifier: "fr_FR")
        
        if let attrs = try? fm.attributesOfItem(atPath: app.url.path), let date = attrs[.creationDate] as? Date { installStr = df.string(from: date) }
        
        var folderSize: Int64 = 0
        if let en = fm.enumerator(at: app.url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in en {
                if let rv = try? f.resourceValues(forKeys: [.fileSizeKey]), let s = rv.fileSize { folderSize += Int64(s) }
            }
        }
        if folderSize > 0 { sizeStr = ByteCountFormatter.string(fromByteCount: folderSize, countStyle: .file) }
        
        if let md = MDItemCreateWithURL(kCFAllocatorDefault, app.url as CFURL), let d = MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date { lastLaunchStr = df.string(from: d) }
        else if let rv = try? app.url.resourceValues(forKeys: [.contentAccessDateKey]), let d = rv.contentAccessDate { lastLaunchStr = df.string(from: d) }
        
        return AppDetails(app: app, size: sizeStr, installDate: installStr, lastLaunchDate: lastLaunchStr, path: app.url.path)
    }
}
