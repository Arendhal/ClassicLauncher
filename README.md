# Classic Launcher 🚀

**Classic Launcher** est une alternative native, légère, hautement performante et paramétrable au Launchpad standard de macOS. Conçu avec **SwiftUI** et **AppKit**, il se base sur les meilleures pratiques pour offrir une expérience fluide, sans aucun lag, tout en s'intégrant profondément au système d'Apple.

![Classic Launcher Preview](https://img.shields.io/badge/macOS-13.0+-black?style=for-the-badge&logo=apple) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift)

---

## ✨ Fonctionnalités clés

### 1. Remplacement total et natif du Launchpad
- **Interception matérielle (Touche F4)** : Grâce à l'utilisation des API bas-niveau `CGEvent.tap`, Classic Launcher peut intercepter nativement la touche F4 de votre Mac pour s'ouvrir instantanément à la place du Launchpad système.
- **Auto-Lancement & Mode "Fantôme"** : Une option intégrée permet à l'application de démarrer automatiquement avec le Mac en arrière-plan (`SMAppService`) et de se masquer automatiquement dès que vous cliquez en dehors de la fenêtre.

### 2. Organisation avancée (Drag & Drop)
- **Création de dossiers intuitifs** : Glissez simplement une icône sur une autre pour créer un "Nouveau dossier".
- **Overlay moderne et élégant** : Ouvrez un dossier pour afficher ses applications via une animation d'overlay avec un arrière-plan en verre dépoli (`ultraThinMaterial`).
- **Gestion facile** : Renommage à la volée, clic droit pour retirer une application ou dissoudre le dossier complet. La persistance est gérée via `UserDefaults`.
- **Legacy Apps intelligentes** : Au premier démarrage, l'application groupe automatiquement les vieux utilitaires système (ex: Trousseaux d'accès) dans un dossier *App systèmes (Legacy)* pour désencombrer votre vue !

### 3. Contrôle & Personnalisation de la vue
- **Mode de Tri** : Triez vos applications alphabétiquement, ou gardez vos Favoris figés en haut de la grille.
- **Favoris & Masquage** : Mettez vos applications favorites en évidence avec une étoile dorée, ou masquez complètement les applications inutiles (elles iront dans une section déroulante "Applications masquées").
- **Zoom dynamique** : Changez la taille d'affichage de la grille à la volée (Petit, Moyen, Grand) d'un simple clic.
- **Détails & Métadonnées** : Clic droit > "Détails de l'app" interroge **Spotlight** (`MDItem`) pour afficher instantanément la taille exacte de l'application, sa date d'installation et son dernier lancement !

### 4. Performances Extrêmes (Zéro Lag)
- Optimisé pour le scroll et le rendu sur écran Retina 120Hz.
- Suppression des calculs d'ombres superflus : le launcher utilise de manière intelligente le drop-shadow natif pré-calculé des icônes de macOS (`NSImage`).
- `LazyVGrid` combiné à une qualité d'interpolation optimale (`.high`), offrant un équilibre parfait entre netteté et rapidité.

---

## 🛠 Structure du projet

Le code est disponible sous forme de **Projet Xcode classique** (`.xcodeproj`) tout en gardant une compatibilité "Package Swift" (`Package.swift`) dans le dossier racine.

- **`ClassicLauncherApp.swift`** : Le cœur de l'app, gère le mode plein écran (`AppDelegate`), l'insertion dans les processus de démarrage (`SMAppService`) et le gestionnaire de raccourcis clavier (`HotKeyManager`).
- **`AppModel.swift`** : Modèle de données asynchrone (`@StateObject`). Gère la lecture du système de fichiers, l'API Spotlight pour les méta-données, la sauvegarde des dossiers et des favoris.
- **`ContentView.swift`** : L'interface SwiftUI complète (Grille, Drag & Drop, Menu contextuels, Overlay des dossiers).
- **`HotKeyManager.swift`** : *(Inclus dans ClassicLauncherApp)* Gère le listener asynchrone de `CGEvent` nécessitant les permissions d'Accessibilité pour court-circuiter le système Apple.

---

## 🚀 Comment l'utiliser / Compiler

### Option 1 : Via Xcode (Recommandé)
1. Ouvrez `ClassicLauncher.xcodeproj` dans **Xcode**.
2. Lancez l'application en cliquant sur le bouton **Run** (`Cmd + R`).
3. Pour remplacer définitivement le Launchpad : Dans la barre des menus macOS de l'application, cliquez sur **Configuration** > **Définir comme lanceur d'apps par défaut**. Autorisez l'accès à l'Accessibilité dans les Réglages Système si demandé.

### Option 2 : Via Swift Package Manager (Terminal)
Vous pouvez lancer l'application en ligne de commande pour le développement rapide :
```bash
cd /chemin/vers/ClassicLauncher
swift run
```

---

## 🔒 Autorisations requises
L'application est "Unsandboxed" par conception, car elle doit lire votre système de fichiers pour lister les applications.
- **Dossiers Applications** : Lecteur libre (Aucun Accès Complet au Disque n'est requis !).
- **Ouverture avec la session** : macOS vous signalera simplement que l'app tourne en tâche de fond.
- **Accessibilité (Clavier)** : Uniquement requis si vous souhaitez intercepter la touche matérielle F4. Si refusé, l'application fonctionne parfaitement via son icône de Dock.
