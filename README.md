# MacRemote

Contrôle souris/clavier (et affichage de l'écran) d'un Mac depuis un iPhone, sur le réseau local.

- `MacAgent/` : app de barre de menus à lancer sur le Mac piloté (macOS 12+).
- `RemoteiOS/` : app iPhone (iOS 16+).
- `Shared/` : protocole + authentification (TLS 1.2 PSK).
- Générer le projet Xcode avec ton propre Team ID Apple : `DEVELOPMENT_TEAM=XXXXXXXXXX xcodegen generate`
  (le Team ID n'est volontairement pas dans le dépôt ; les identifiants de bundle `com.macremote.*` peuvent être changés dans `project.yml`).

## Permissions sur le Mac piloté
Réglages Système > Confidentialité et sécurité : **Accessibilité** (souris/clavier) et **Enregistrement d'écran** (retour d'écran).

## Sécurité
Connexion chiffrée TLS-PSK. 1re connexion : code `XXXX-XXXX` du menu de l'agent → clé aléatoire 256 bits
mémorisée (Keychain iPhone). Le code est régénéré après 5 poignées de main ratées.
