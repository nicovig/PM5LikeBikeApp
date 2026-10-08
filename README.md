# PM5 Bike

Moniteur de vélo d’intérieur, façon Concept2 PM5, pour un Moovyoo X Speeder. L’app lit un capteur de cadence Bluetooth, estime les watts à partir d’une courbe de calibration, et affiche la séance en direct.

Les formules, le protocole CSC et les relevés de calibration sont dans [spec.md](spec.md).

## Matériel

- Vélo Moovyoo X Speeder, sans modification de la console.
- Capteur de cadence BLE (service `0x1816`), fixé sur la manivelle.
- iPhone, ou Android 10 (API 29) et plus récent.

Sans capteur, l’écran Séance tourne en simulation : curseur de RPM ou scénario.

## Écrans

- **Séance** : durée, watts, cadence, vitesse, distance, allure, calories, moyennes réelle et PM5. Pause, abandon ou enregistrement.
- **Séance guidée** : depuis « Séance libre », blocs en temps, distance ou calories, avec un wattage à tenir ou une récup. Le plan se répète, reste en mémoire, et la sortie continue après le dernier bloc jusqu’à Terminer.
- **Historique** : séances enregistrées et courbe de watts.
- **Calibration** : points RPM → watts par niveau de résistance. Le niveau 22 reprend les relevés de la spec.
- **Réglages** : niveau actif, calories PM5 ou selon le poids, lissage, source simulation ou capteur BLE.

## Android 10 et 11

La recherche d’un capteur demande la localisation : il faut l’autoriser et la laisser activée, sinon Android refuse le scan. À partir d’Android 12, cette demande disparaît.

## Lancer

```bash
flutter pub get
flutter run
```

APK de debug :

```bash
flutter build apk --debug
```

Le fichier est `build/app/outputs/flutter-apk/app-debug.apk`.

## Vérifier

```bash
flutter analyze
flutter test
```
