# SPEC — App « PM5 maison » pour vélo d'intérieur Moovyoo X Speeder

> Document de référence du projet. À placer à la racine du repo (`/SPEC.md`) et à faire lire à Cursor avant toute génération de code.

---

## 1. Objectif

Application mobile (Flutter, iOS + Android) qui :

1. se connecte en Bluetooth Low Energy à un **capteur de cadence** fixé sur le pédalier ;
2. convertit la cadence (RPM) en **watts** grâce à une courbe de calibration propre au vélo ;
3. affiche un écran **type Concept2 PM5 (BikeErg)** : durée, watts, distance, vitesse, allure /1000 m, calories, watts moyens ;
4. enregistre les séances pour consulter l'historique.

**Besoin d'origine** : l'écran du vélo n'affiche que les watts instantanés. On veut la **puissance moyenne d'une séance**, et des données comparables (autant que possible) à un PM5 de BikeErg.

---

## 2. Contexte matériel

- Vélo : **Moovyoo X Speeder** (marque française, modèle arrêté, plus de doc technique disponible chez le constructeur).
- Freinage **magnétique**, niveaux de résistance réglables (l'utilisateur monte jusqu'au **level 22**, qu'il juge ≈ 6/10 de difficulté, référence : Concept2 BikeErg).
- Écran d'origine : en mode « Manuel », il affiche durée, vitesse, RPM, watts, calories. Les valeurs **alternent** (RPM ↔ vitesse, watts ↔ calories). Les watts sont **instantanés uniquement**. Le compteur de calories est inexploitable (très éloigné de celui d'un Concept2).
- **Choix retenu : ne pas modifier le vélo.** Aucune intervention sur la carte électronique. Les watts sont **estimés** à partir de la cadence et d'une courbe de calibration.
- Hypothèse forte : sur ce type de vélo, les watts de la console sont **calculés** (niveau × cadence, sans capteur de force) et non mesurés. À confirmer par le relevé de calibration (section 6).

### Matériel nécessaire
- Un capteur de cadence **Bluetooth (BLE)** à fixer sur la manivelle (~20-40 €, type Wahoo / Garmin / Magene). Vérifier que la fiche indique bien BLE (pas seulement ANT+).
- iPhone 15 + Mac pour développer ; plan B : Android 10 (API 29) ou plus récent (APK).

---

## 3. Bluetooth : profil Cycling Speed and Cadence (CSC)

Standard ouvert du Bluetooth SIG. **Aucune autorisation ni licence nécessaire** pour écrire une app qui lit un capteur. Seules les permissions du téléphone comptent.

| Élément | Valeur |
|---|---|
| Service | `0x1816` (Cycling Speed and Cadence) |
| Caractéristique de mesure | `0x2A5B` (CSC Measurement, notifications) |
| Flags (octet 0) | bit0 = données de roue présentes, bit1 = données de manivelle présentes |
| Données de roue (si bit0) | 4 octets (tours cumulés, uint32) + 2 octets (horodatage dernier événement, uint16) |
| Données de manivelle (si bit1) | 2 octets (tours cumulés, uint16) + 2 octets (horodatage dernier événement, uint16) |
| Unité de temps | 1/1024 s |
| Ordre des octets | little-endian |

### Calcul de la cadence

```
RPM = Δtours / Δtemps(s) × 60
Δtours = (revs - prevRevs) & 0xFFFF       // dépassement 16 bits
Δtemps = ((t - prevT) & 0xFFFF) / 1024.0  // secondes
```

Règles :
- Si `Δtemps == 0` : pas de nouvel événement, conserver la dernière valeur.
- Si aucun événement pendant ~2 s : cadence = 0 (arrêt de pédalage).
- Un capteur de cadence seule envoie typiquement `flags = 0x02`.

### Parser (Dart)

```dart
int? _prevRevs, _prevTime;

double? parseCadence(List<int> d) {
  final flags = d[0];
  if (flags & 0x02 == 0) return null;       // pas de données de manivelle
  var i = 1;
  if (flags & 0x01 != 0) i += 6;            // saute les données de roue
  final revs = d[i] | (d[i + 1] << 8);
  final time = d[i + 2] | (d[i + 3] << 8);

  double? rpm;
  if (_prevRevs != null) {
    final dRevs = (revs - _prevRevs!) & 0xFFFF;
    final dTime = ((time - _prevTime!) & 0xFFFF) / 1024.0;
    if (dTime > 0) rpm = dRevs / dTime * 60;
  }
  _prevRevs = revs;
  _prevTime = time;
  return rpm;
}
```

### Permissions
- **Android 12+** : `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (déclarer `neverForLocation` sur le scan si pas besoin de localisation).
- **Android 10 et 11** : `BLUETOOTH`, `BLUETOOTH_ADMIN`, et `ACCESS_FINE_LOCATION` à l’exécution. La localisation du téléphone doit rester activée pendant la recherche, sinon Android refuse le scan. Ces permissions s’arrêtent à l’API 30.
- **iOS** : clé `NSBluetoothAlwaysUsageDescription` dans `Info.plist`.
- Le **simulateur iOS ne gère pas le BLE** : tests réels sur un iPhone.
- Package conseillé : `flutter_blue_plus`. Filtrer le scan sur le service `0x1816`.
- Outil de debug conseillé avant de coder : l'app gratuite **nRF Connect** (vérifier que le capteur expose `0x1816`).

---

## 4. Watts à partir de la cadence (calibration)

### Principe
À niveau de résistance fixe (**level 22**), la puissance affichée ne dépend (hypothèse) que de la cadence. On modélise :

```
W = a × RPM^b      (b typiquement entre 1 et 2 pour un frein magnétique)
```

Ajustement par régression linéaire sur les logarithmes :

```
b = cov(ln RPM, ln W) / var(ln RPM)
a = exp( mean(ln W) − b × mean(ln RPM) )
```

Table de secours : interpolation linéaire entre points (RPM → W) si la loi de puissance colle mal.

### Valeurs PROVISOIRES (exemple, à remplacer par les vrais relevés)
Exemple de l'utilisateur : 60 → 150 W, 70 → 180, 80 → 220, 90 → 280. Ajustement approché :

```
a ≈ 0.274 ; b ≈ 1.54
```

Écart avec l'exemple ≈ 6 % : ces chiffres sont illustratifs.

### Limites
- Valable uniquement dans la **plage de cadence mesurée**. Hors plage = extrapolation, à signaler visuellement (« hors calibration ») et à exclure ou marquer dans les moyennes.
- Valable uniquement pour le **level 22**. Prévoir une table par niveau (saisie manuelle du niveau dans l'app).
- Les watts affichés par la console sont une **estimation constructeur**, pas une mesure : la fiabilité absolue face à un vrai PM5 est moyenne (≈ 5/10), la reproductibilité d'une séance à l'autre est bonne (≈ 8/10).

---

## 5. Formules Concept2 / PM5 (BikeErg)

> Niveau de confiance indiqué pour chaque bloc. Les formules du rameur sont publiques ; celles propres au BikeErg viennent de la communauté et ont été recoupées avec des relevés, pas d'une doc officielle.

### 5.1 Puissance ↔ allure (public, confiance élevée)

Formule Concept2 (rameur) : `watts = 2.80 / pace³`, avec `pace` en secondes par mètre.

### 5.2 BikeErg : allure /1000 m (communauté, confiance moyenne à élevée)

- Le PM5 d'un BikeErg affiche l'allure par **1000 m**.
- La vitesse du BikeErg est fixée à **2 × celle du RowErg** pour la même puissance (distance et vitesse sont des constructions arbitraires, sans lien avec un vélo réel).
- Conséquence : l'allure /1000 m du BikeErg a la même valeur numérique que l'allure /500 m du rameur à puissance égale.

```
P (W) = 0.35 / (s_par_m)³
v (m/s)  = 1.419 × P^(1/3)
v (km/h) = 5.108 × P^(1/3)
allure /1000 m (s) = 1000 / v(m/s)
```

**Validation** : un relevé communautaire donne 1:37.9 /1000 m pour 373 W ; la formule donne 0.35 / 0.0979³ ≈ 373 W. ✔

Le PM5 n'affiche pas de km/h en natif (l'allure est l'affichage de référence) : afficher l'allure en principal, les km/h en secondaire.

### 5.3 Distance

```
distance += v(m/s) × dt        // intégration à chaque tick
```

### 5.4 Calories (Concept2, confiance élevée)

Formule PM : `cal/h = watts × 4 × 0.8604 + 300`

- `×0.8604` : conversion W → kcal/h ; `×4` : rendement musculaire supposé de 25 %.
- `+300` : métabolisme de base ajouté en continu, **même à faible effort**. Calibré pour un rameur d'environ **175 lb (≈ 79 kg)**.
- Identique pour RowErg, SkiErg et BikeErg.

```
kcal += (3.4416 × W + 300) × dt / 3600
```

Variante rencontrée : `4 × W / 1.1639` à la place de `4 × W × 0.8604` → écart ≈ 0,1 %, négligeable.

**Version personnalisée (poids)** : Concept2 fournit `cal/h réelles = cal/h affichées − 300 + 1.714 × poids(lb)`.
Soit : `cal/h = 3.4416 × W + 3.78 × poids(kg)`. Proposer un réglage « mode PM5 (79 kg) » ou « mon poids ».

### 5.5 Watts moyens : deux définitions (important)

| Définition | Formule |
|---|---|
| **Moyenne réelle** (celle qui intéresse l'utilisateur) | `Σ(W × dt) / durée` |
| **Moyenne « façon PM5 »** | `0.35 / (durée / distance)³` |

D'après un fil du forum Concept2 (ancien, ère PM3/PM4), le PM calcule les watts moyens **à partir de l'allure moyenne**, pas comme moyenne arithmétique des watts instantanés. À cause de la loi cubique (inégalité de Jensen), la valeur « façon PM5 » est **inférieure ou égale** à la moyenne réelle dès que l'effort varie. **À vérifier sur un PM5 BikeErg actuel.** Afficher les deux dans l'app.

### 5.6 Lissage du PM5
Sur le rameur, les watts sont mis à jour par coup. Pas de source claire pour le BikeErg. Prévoir un filtre de lissage paramétrable (moyenne glissante 2-3 s), à caler avec le test en échelon (section 6).

### 5.7 Vecteurs de test (pour les tests unitaires)

Calculs avec les formules ci-dessus :

| Watts | Vitesse (km/h) | Allure /1000 m | kcal/h (mode PM5) |
|---|---|---|---|
| 100 | 23.7 | 2:31.8 | 644 |
| 150 | 27.1 | 2:12.6 | 816 |
| 200 | 29.9 | 2:00.5 | 988 |
| 250 | 32.2 | 1:51.9 | 1160 |
| 300 | 34.2 | 1:45.3 | 1332 |
| 373 | 36.8 | 1:37.9 | 1584 |

Tolérance suggérée : ±0,1 km/h, ±0,5 s, ±2 kcal/h.

---

## 6. Protocole de calibration (à faire sur le vélo)

Au **level 22** uniquement.

Le couple cadence / wattage est une capture à l'instant T du wattage, les valeurs sont les suivantes : 

RPM | Watts
40 -> 105
50 -> 152
60 -> 200
70 -> 256
80 -> 305
90 -> 347
100 -> 393

Les couples (RPM, watts) sont associés **par proximité de temps**. Ignorer les calories de la console. La cadence n'a pas besoin d'être parfaitement stable : toutes les paires servent à la régression.

Critères d'une courbe « régulière » : croissante et lisse, reproductible, suivant à peu près `W = k × RPM^n`. Signaux d'alerte : valeurs différentes à même cadence et même niveau, watts insensibles à la cadence, courbe en dents de scie.

Complément utile : si l'utilisateur peut noter (RPM, watts, allure, calories) sur un vrai BikeErg à effort jugé équivalent, comparer pour valider les formules et estimer l'écart absolu.

---

## 7. Spécification de l'app

### 7.1 MVP
- **Connexion** : écran de scan filtré sur `0x1816`, mémorisation du dernier capteur, reconnexion auto.
- **Écran live (style PM5)** : durée, watts (grand), RPM, distance, vitesse, allure /1000 m, calories, watts moyens (réelle + façon PM5). Écran qui reste allumé pendant la séance.
- **Séance** : démarrer / pause / terminer. Échantillonnage régulier (ex. 4 Hz pour le calcul, 1 Hz pour l'enregistrement).
- **Historique** : liste des séances (date, durée, distance, watts moyens, kcal) + détail avec courbe de watts.
- **Calibration** : écran d'édition de la table RPM → W (par niveau), ajustement `a`, `b` calculé automatiquement, indicateur de plage valide.
- **Réglages** : niveau actif (22 par défaut), poids (mode PM5 79 kg ou perso), lissage, unités.
- **Mode simulation** : source de cadence factice (curseur ou scénario scripté) pour développer sans capteur.

### 7.2 Hors MVP
Export CSV / FIT, synchro Strava, intervalles, partage, plusieurs profils.

### 7.3 Architecture conseillée (Flutter)

```
lib/
  core/
    power_curve.dart        // table + loi de puissance + interpolation + régression
    pm5_metrics.dart        // vitesse, allure, distance, calories, moyennes
  data/
    cadence_source.dart     // interface abstraite : Stream<CadenceSample>
    ble_cadence_source.dart // implémentation flutter_blue_plus + parser CSC
    sim_cadence_source.dart // simulation
    session_repository.dart // stockage local (SQLite via drift ou sqflite)
  features/
    live/                   // écran PM5
    history/
    calibration/
    settings/
test/
  pm5_metrics_test.dart     // vecteurs section 5.7
  power_curve_test.dart     // régression, interpolation, hors plage
  csc_parser_test.dart      // dépassement 16 bits, flags, Δt = 0
```

Principes :
- La logique de calcul (`core/`) est du **Dart pur**, sans dépendance Flutter, testée unitairement.
- La source de cadence est derrière une **interface** ; BLE et simulation sont interchangeables.
- Gestion d'état : au choix (Riverpod conseillé), mais cohérente sur tout le projet.

### 7.4 Cas limites
- Capteur déconnecté en séance : conserver la séance, afficher l'état, reconnexion auto, ne pas compter le temps déconnecté comme du pédalage.
- Arrêt de pédalage (cadence 0) : watts = 0 ; décider si la durée continue (comme un PM5) et si le +300 kcal/h continue (oui sur le PM5 tant que la séance tourne).
- Cadence hors plage calibrée : valeur affichée mais marquée, exclue ou signalée dans les moyennes.
- Valeurs aberrantes du capteur (RPM > 200) : filtrer.
- App en arrière-plan / écran verrouillé : séance non interrompue (considérer un service d'avant-plan sur Android).

---

## 8. Déploiement

- **iPhone depuis le Mac, sans store** : Xcode + Apple ID gratuit (la doc Flutter confirme qu'un compte développeur personnel gratuit suffit pour tester sur appareil), mode développeur activé sur l'iPhone, `flutter run` en USB. Limite : l'app expire après ~7 jours, à réinstaller depuis le Mac ; nombre d'apps plafonné.
- **Payer** : programme Apple Developer (~99 $/an) = TestFlight, pas d'expiration à 7 jours. Inutile au démarrage.
- **Android** : `flutter build apk`, installation directe, gratuit, sans expiration. Un petit Android fixé au guidon est une bonne solution d'usage quotidien.

---

## 9. Risques et points à valider

| Point | Risque | Action |
|---|---|---|
| Watts de la console = calculés ? | Si mesurés, la courbe RPM→W ne tient pas | Relevé de calibration (section 6) |
| Fiabilité absolue vs PM5 | Écart possible de 10-30 % | Comparer avec un vrai BikeErg si possible |
| Moyenne PM5 = dérivée de l'allure | Source ancienne | Vérifier sur un PM5 BikeErg récent |
| Lissage du PM5 | Pas de doc BikeErg | Filtre paramétrable, test en échelon |
| Dérive du frein magnétique | Résistance réelle variable avec la température | Constat à faire ; la table suppose une résistance stable |
| Expiration 7 jours (iOS gratuit) | Gêne à l'usage | Android dédié ou compte payant |

---

## 10. Sources (à re-vérifier avant de s'y fier à 100 %)

- Concept2 : calculateur de watts / allure (formule `2.80 / pace³`).
- Concept2 : FAQ sur le calcul des calories du PM (`watts × 4 × 0.8604 + 300`, calibrage à 175 lb).
- Forum Concept2 : fil sur la vitesse du BikeErg (« deux fois celle du RowErg »), formule `P = 0.35 / (t/1000)³`, relevé 1:37.9 ↔ 373 W.
- Forum Concept2 : fil sur le calcul des watts moyens à partir de l'allure moyenne.
- Documentation Flutter : « Set up iOS development » (compte Apple gratuit, mode développeur).
- Bluetooth SIG : spécification du service Cycling Speed and Cadence (`0x1816`, `0x2A5B`).
