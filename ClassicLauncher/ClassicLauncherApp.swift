import SwiftUI
import AppKit
import ServiceManagement

@main
struct ClassicLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isDefaultLauncher") var isDefaultLauncher = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(.all)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea(.all))
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Classic Launcher") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "Classic Launcher"
                        ]
                    )
                }
            }
            
            CommandMenu("Configuration") {
                Toggle("Définir comme lanceur d'apps par défaut", isOn: $isDefaultLauncher)
                    .onChange(of: isDefaultLauncher) { _, newValue in
                        setupDefaultLauncher(enabled: newValue)
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        
        Settings {
            SettingsView()
        }
    }
    
    private func setupDefaultLauncher(enabled: Bool) {
        // 1. Activer/Désactiver le lancement au démarrage
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("Erreur Login Items: \(error)")
            }
        }
        
        // 2. Activer l'interception clavier globale (F4)
        if enabled {
            HotKeyManager.shared.start()
        } else {
            HotKeyManager.shared.stop()
        }
        
        // 3. Le paramètre HideOnDeactivate est directement lié à isDefaultLauncher
        UserDefaults.standard.set(enabled, forKey: "HideOnDeactivate")
        
        // 4. Afficher une petite alerte informative pour guider l'utilisateur
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            if enabled {
                alert.messageText = "Classic Launcher activé en tâche de fond"
                alert.informativeText = "L'application s'ouvrira au démarrage et interceptera la touche F4 (Launchpad).\n\n⚠️ Si vous n'avez pas accordé les autorisations d'Accessibilité, macOS vient d'afficher une demande. Vous DEVEZ accepter dans 'Confidentialité et sécurité' pour que la touche fonctionne."
            } else {
                alert.messageText = "Mode classique restauré"
                alert.informativeText = "L'application ne démarrera plus automatiquement et ne bloquera plus le Launchpad d'Apple."
            }
            alert.addButton(withTitle: "OK")
            if let window = NSApplication.shared.windows.first {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
}

struct SettingsView: View {
    @State private var selectedShortcut = DataManager.shared.data.activeShortcut
    
    var body: some View {
        Form {
            Section(header: Text("Raccourci Global").font(.headline)) {
                Picker("Activer avec :", selection: $selectedShortcut) {
                    ForEach(ShortcutType.allCases, id: \.self) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedShortcut) { _, newValue in
                    DataManager.shared.data.activeShortcut = newValue
                    DataManager.shared.save()
                    // Redémarrer l'écouteur si nécessaire
                    if UserDefaults.standard.bool(forKey: "isDefaultLauncher") {
                        HotKeyManager.shared.stop()
                        HotKeyManager.shared.start()
                    }
                }
                
                Text("Nécessite d'autoriser l'application dans les réglages d'Accessibilité de macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 400, height: 150)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        maximizeWindow()
        
        // S'assurer que le mode plein écran et la disparition sont synchronisés
        // au démarrage si l'option était déjà activée.
        if UserDefaults.standard.bool(forKey: "isDefaultLauncher") {
            UserDefaults.standard.set(true, forKey: "HideOnDeactivate")
            // Démarrer l'écouteur F4 au lancement si l'option est active !
            HotKeyManager.shared.start()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        maximizeWindow()
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Masque la barre des menus pour occuper tout l'écran (requiert de masquer le dock)
        NSApp.presentationOptions = [.hideMenuBar, .hideDock]
        if let window = NSApplication.shared.windows.first {
            window.level = .popUpMenu
        }
        maximizeWindow()
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        // Restaure la barre des menus dès qu'on quitte le focus
        NSApp.presentationOptions = []
        if let window = NSApplication.shared.windows.first {
            window.level = .normal
        }
        // Comportement "Launchpad" : si on clique en dehors, on masque le launcher
        if UserDefaults.standard.bool(forKey: "HideOnDeactivate") {
            NSApp.hide(nil)
        }
    }
    
    private func maximizeWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApplication.shared.windows.first,
                  let screen = NSScreen.main else { return }
            
            // Permet à la fenêtre de dessiner son contenu sous l'encoche (safe area)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            
            // Utilise screen.frame (plein écran incluant la zone de la barre des menus et l'encoche)
            window.setFrame(screen.frame, display: true, animate: false)
        }
    }
}

// MARK: - HotKey Manager

class HotKeyManager {
    static let shared = HotKeyManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isIntercepting = false
    
    func start() {
        guard !isIntercepting else { return }
        
        // Vérifie les droits d'accessibilité (et affiche la demande système si besoin)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("Accessibilité non accordée. L'alerte système devrait apparaître.")
            return
        }
        
        // On écoute les touches standard et les touches média système
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << 14) // 14 = NSSystemDefined
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                
                // 1. Intercepter le raccourci personnalisé
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    let activeShortcut = DataManager.shared.data.activeShortcut
                    
                    var isMatch = false
                    
                    switch activeShortcut {
                    case .f4:
                        if keyCode == 118 { isMatch = true }
                    case .optionSpace:
                        if keyCode == 49 && flags.contains(.maskAlternate) { isMatch = true }
                    case .cmdShiftSpace:
                        if keyCode == 49 && flags.contains(.maskCommand) && flags.contains(.maskShift) { isMatch = true }
                    }
                    
                    if isMatch {
                        HotKeyManager.shared.activateLauncher()
                        return nil // Bloque l'événement
                    }
                }
                
                // 2. Intercepter la touche "Média" Launchpad
                if type.rawValue == 14 { // 14 = NSSystemDefined
                    if let nsEvent = NSEvent(cgEvent: event) {
                        if nsEvent.subtype.rawValue == 8 {
                            let data1 = nsEvent.data1
                            let keyCode = (data1 & 0xFFFF0000) >> 16
                            let keyFlags = (data1 & 0x0000FFFF)
                            let keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA
                            
                            // NX_KEYTYPE_LAUNCH_PANEL est 160
                            if keyCode == 160 {
                                if keyState {
                                    HotKeyManager.shared.activateLauncher()
                                }
                                return nil // Bloque l'événement système
                            }
                        }
                    }
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )
        
        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isIntercepting = true
        }
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        isIntercepting = false
    }
    
    func activateLauncher() {
        DispatchQueue.main.async {
            if NSApp.isHidden {
                NSApp.unhide(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
