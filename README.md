# PM5 Bike

Moniteur de vélo d’intérieur, façon Concept2 PM5, pour un Moovyoo X Speeder. L’app lit un capteur de cadence Bluetooth, estime les watts à partir d’une courbe de calibration, et affiche la séance en direct.

Les formules, le protocole CSC et les relevés de calibration sont dans [spec.md](spec.md).

## Matériel

- Vélo Moovyoo X Speeder, sans modification de la console.
- Capteur validé : Van Rysel KIT202 (BLE et ANT+). Il fait vitesse ou cadence, pas les deux en même temps.
- iPhone, ou Android 10 (API 29) et plus récent.

Sans capteur, l’écran Séance tourne en simulation : curseur de RPM ou scénario.

## Capteur Van Rysel

Le jumelage dans les réglages Bluetooth du téléphone ne fonctionne pas. Android demande d’utiliser l’application : c’est normal. On choisit le capteur dans Réglages, source « Capteur BLE ».

- LED rouge : mode cadence, celui qu’il faut. LED verte : mode vitesse. Pour changer, retire la pile CR2032 et remets-la.
- Le capteur se rendort. Tourne la pédale plusieurs fois pour le réveiller, puis lance « Rechercher un capteur » pendant qu’il clignote. La recherche dure 20 secondes.
- Le nom affiché ressemble à `44885-1`. Les autres appareils BLE du coin apparaissent aussi. L’app vérifie le service cadence (`0x1816`) seulement après la connexion.
- Sur Android 10 et 11, autorise la localisation et laisse-la activée pendant la recherche.

## Écrans

- **Séance** : durée, watts, cadence, vitesse, distance, allure, calories, moyennes réelle et PM5. Pause, abandon ou enregistrement.
- **Séance guidée** : depuis « Séance libre », blocs en temps, distance ou calories, avec un wattage à tenir ou une récup. Le plan se répète, reste en mémoire, et la sortie continue après le dernier bloc jusqu’à Terminer.
- **Historique** : séances enregistrées et courbe de watts.
- **Calibration** : points RPM → watts par niveau de résistance. Le niveau 22 reprend les relevés de la spec.
- **Réglages** : niveau actif, calories PM5 ou selon le poids, lissage, source simulation ou capteur BLE.

## Lancer

```bash
flutter pub get
flutter run
```

APK à installer sur le téléphone :

```bash
flutter build apk --release
```

Le fichier est `build/app/outputs/flutter-apk/app-release.apk`. Désinstalle l’ancienne version avant de l’installer.

## Vérifier

```bash
flutter analyze
flutter test
```
