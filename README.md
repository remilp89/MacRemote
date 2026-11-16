# MacRemote

Pilote la souris, le clavier et l'écran d'un Mac depuis un iPhone — réseau local ou Tailscale, sans serveur tiers.

## Fonctionnalités
- Trackpad virtuel : déplacer, clic, double-clic, clic droit, défilement 2 doigts, cliquer-glisser (appui long).
- Clavier iOS + rangée de touches (⇧ ⌃ ⌥ ⌘, Échap, Tab, flèches) + **clavier physique** (F1–F12, raccourcis ⌘/⌃/⌥, y compris AZERTY).
- **Retour d'écran** (ScreenCaptureKit) avec mode « toucher direct » et 3 niveaux de qualité.
- **Presse-papiers** partagé (texte) dans les deux sens.
- **Envoi de fichiers** iPhone → Mac (dossier `Téléchargements/MacRemote`).
- Détection automatique (Bonjour) ou **connexion directe par IP** (port 52525), par exemple via [Tailscale](https://tailscale.com) pour contrôler un Mac hors du réseau local.
- **Widget** (écran d'accueil, écran verrouillé) et **bouton Centre de contrôle** (iOS 18) : un tap rouvre l'app et reconnecte le dernier Mac ; reconnexion automatique au lancement.
- Connexion chiffrée (TLS 1.2 PSK) ; appairage par code, puis clé de 256 bits dans le Keychain de l'iPhone.

## Structure
- `MacAgent/` : app de barre de menus pour le Mac piloté (macOS 12+, Intel et Apple Silicon).
- `RemoteiOS/` : app iPhone (iOS 17+) + extension widget.
- `RemoteWidget/`, `RemoteShared/` : widget et données partagées (App Group).
- `Shared/` : protocole et authentification.

## Compiler
Prérequis : Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), un compte développeur Apple.

```sh
DEVELOPMENT_TEAM=XXXXXXXXXX xcodegen generate
open MacRemote.xcodeproj
```
Le Team ID n'est volontairement pas dans le dépôt. **Si tu forkes** : les identifiants de bundle et l'App Group sont uniques chez Apple, donc change `APP_GROUP` et les `PRODUCT_BUNDLE_IDENTIFIER` (préfixe `com.macremote.e239b564`) dans `project.yml`.
Pour installer l'agent sur un autre Mac : build Release universel (`ARCHS="arm64 x86_64"`), signé Developer ID, puis copie de l'app.

## Utilisation
1. Lance l'agent sur le Mac piloté et accorde **Accessibilité** et **Enregistrement de l'écran** (Réglages Système > Confidentialité et sécurité), puis relance l'agent.
2. Ouvre l'app iPhone (autorise le réseau local), choisis le Mac, saisis le code `XXXX-XXXX` affiché dans le menu de l'agent (première fois seulement).
3. Connexion directe : le menu de l'agent liste les adresses IP du Mac ; saisis-en une dans « Connexion directe ».

## Sécurité
- Tout le trafic est chiffré (TLS-PSK avec échange Diffie-Hellman). Le code d'appairage est régénéré après 5 poignées de main ratées.
- Un appareil appairé a le même pouvoir qu'un utilisateur devant le Mac (souris, clavier, écran, fichiers déposés dans Téléchargements). « Oublier tous les iPhone » dans le menu révoque toutes les clés.
- Ne l'expose pas directement sur Internet (pas de redirection de port) : utilise un VPN comme Tailscale.

## Limites connues
- Pas de transfert Mac → iPhone, pas de son, presse-papiers en texte uniquement.
- Pas de notarisation : au premier lancement, clic droit > Ouvrir.

## Licence
MIT — voir `LICENSE`.
