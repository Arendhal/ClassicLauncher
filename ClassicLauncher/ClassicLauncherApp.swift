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
        if let window = LauncherWindow.main {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Masque la barre des menus pour occuper tout l'écran (requiert de masquer le dock)
        NSApp.presentationOptions = [.hideMenuBar, .hideDock]
        LauncherWindow.main?.level = .popUpMenu
        maximizeWindow()
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Restaure la barre des menus dès qu'on quitte le focus
        LauncherWindow.releaseScreen()
        // Comportement "Launchpad" : si on clique en dehors, on masque le launcher
        if UserDefaults.standard.bool(forKey: "HideOnDeactivate") {
            NSApp.hide(nil)
        }
    }

    private func maximizeWindow() {
        // Au démarrage la fenêtre SwiftUI n'existe pas encore : on réessaie au tour suivant
        guard let window = LauncherWindow.main else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.maximizeWindow() }
            return
        }
        guard let screen = NSScreen.main else { return }

        // Permet à la fenêtre de dessiner son contenu sous l'encoche (safe area)
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }

        // Utilise screen.frame (plein écran incluant la zone de la barre des menus et l'encoche).
        // Uniquement si nécessaire : un setFrame force une passe de layout de toute la grille.
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true, animate: false)
        }
    }
}

// MARK: - Launcher Window

/// Point d'accès unique à la fenêtre plein écran du launcher et à son animation de disparition.
enum LauncherWindow {
    static var main: NSWindow? { NSApplication.shared.windows.first }

    private static let dismissDuration: CFTimeInterval = 0.18
    private static let zoomKey = "launcherDismissZoom"
    private static var isDismissing = false

    /// Rend l'écran : niveau de fenêtre normal + barre des menus / Dock restaurés.
    /// Indispensable avant de lancer une app, sinon ses fenêtres (dialogue Gatekeeper,
    /// fenêtre d'attente…) s'ouvrent SOUS le launcher en niveau .popUpMenu.
    static func releaseScreen() {
        if !NSApp.presentationOptions.isEmpty { NSApp.presentationOptions = [] }
        if let window = main, window.level != .normal { window.level = .normal }
    }

    /// Fait disparaître le launcher (fondu + léger zoom) puis masque l'application.
    /// L'animation est composée par le WindowServer / Core Animation : la hiérarchie SwiftUI
    /// n'est pas re-rendue image par image, contrairement à un .scaleEffect/.opacity.
    static func dismiss(completion: (() -> Void)? = nil) {
        releaseScreen()
        guard let window = main, window.isVisible, !NSApp.isHidden, !isDismissing else {
            if !NSApp.isHidden { NSApp.hide(nil) }
            completion?()
            return
        }
        isDismissing = true
        window.ignoresMouseEvents = true

        if let layer = window.contentView?.layer {
            // Les layers des NSView ont leur anchorPoint en (0,0) : on zoome autour du centre
            let b = layer.bounds
            var t = CATransform3DMakeTranslation(-b.midX, -b.midY, 0)
            t = CATransform3DConcat(t, CATransform3DMakeScale(1.12, 1.12, 1))
            t = CATransform3DConcat(t, CATransform3DMakeTranslation(b.midX, b.midY, 0))

            let zoom = CABasicAnimation(keyPath: "transform")
            zoom.fromValue = CATransform3DIdentity
            zoom.toValue = t
            zoom.duration = dismissDuration
            zoom.timingFunction = CAMediaTimingFunction(name: .easeOut)
            zoom.fillMode = .forwards
            zoom.isRemovedOnCompletion = false
            layer.add(zoom, forKey: zoomKey)
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = dismissDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            if !NSApp.isHidden { NSApp.hide(nil) }
            // Remise à l'état initial une fois la fenêtre hors écran (aucun flash visible)
            window.contentView?.layer?.removeAnimation(forKey: zoomKey)
            window.alphaValue = 1
            window.ignoresMouseEvents = false
            isDismissing = false
            completion?()
        })
    }
}

// MARK: - HotKey Manager

class HotKeyManager {
    static let shared = HotKeyManager()

    /// Contexte transmis au callback C via `refcon` (le callback ne peut rien capturer).
    /// Immuable pendant la vie du tap : lecture sans verrou depuis le thread du tap.
    private final class TapContext {
        let shortcut: ShortcutType
        var tap: CFMachPort?
        init(shortcut: ShortcutType) { self.shortcut = shortcut }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var context: TapContext?
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

        let ctx = TapContext(shortcut: DataManager.shared.data.activeShortcut)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let ctx = Unmanaged<TapContext>.fromOpaque(refcon).takeUnretainedValue()

                // 0. macOS désactive le tap s'il a répondu trop lentement : on le réactive
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = ctx.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }

                // 1. Intercepter le raccourci personnalisé
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    let activeShortcut = ctx.shortcut

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
                
                // passUnretained : on rend l'événement reçu tel quel (passRetained le faisait fuiter à chaque frappe)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(ctx).toOpaque()
        )

        guard let tap = eventTap,
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            eventTap = nil
            return
        }
        ctx.tap = tap
        context = ctx
        runLoopSource = source

        // Le tap tourne sur son propre thread : un main thread occupé (rendu SwiftUI, scan des apps…)
        // ne peut plus retarder les frappes clavier de tout le système ni faire désactiver le tap.
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.tapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun() // Rend la main quand stop() retire la source / arrête la boucle
        }
        thread.name = "ClassicLauncher.HotKeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        isIntercepting = true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoop = tapRunLoop {
                if let source = runLoopSource {
                    CFRunLoopRemoveSource(runLoop, source, .commonModes)
                }
                CFRunLoopStop(runLoop)
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
            runLoopSource = nil
            tapRunLoop = nil
        }
        // `context` est volontairement conservé jusqu'au prochain start() : un callback encore
        // en vol sur le thread du tap peut y accéder sans risque d'accès à une zone libérée.
        isIntercepting = false
    }
    
    func activateLauncher() {
        DispatchQueue.main.async {
            if NSApp.isHidden {
                NSApp.unhide(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            LauncherWindow.main?.makeKeyAndOrderFront(nil)
        }
    }
}
