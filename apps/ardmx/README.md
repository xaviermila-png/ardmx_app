# ardmx

App Flutter (Android) de control per **Bluetooth Low Energy (BLE)** dels
productes ARDMX basats en ESP32:

- **ARDMX One** — detecta automàticament si la unitat connectada és **v1**
  (una única escena estàtica, ja desplegada en unitats de camp, mai
  reflashejada) o **v2** (4 escenes + 4 transicions per canal) mirant el
  número major de versió del handshake d'identificació del dispositiu
  (V64), i obre l'arbre de pantalles corresponent.
- **ARDMX EVO** — mateix model de 4 escenes/transicions que l'One v2, més
  reproducció d'àudio MP3 sincronitzada amb el cicle (DFPlayer Mini) i un
  mode Manual (Trigger extern).

No controla l'ARDMX4 (Arduino Mega, Bluetooth Classic) — per això hi ha
l'app germana `apps/ardmx_classic` en aquest mateix repo.

## Protocol
Tots dos dispositius parlen el mateix protocol de text `!Vxx=valor$` /
`!Vxx=valor$` sobre una característica GATT d'escriptura, amb les respostes
arribant per notificació — **mateixos UUIDs de servei/escriptura/
notificació als dos firmwares** (deliberadament: el mateix transport per al
mateix protocol), així que un sol escaneig BLE (filtrat pel UUID de servei)
troba qualsevol dels dos productes. El dispositiu es distingeix un cop
connectat mitjançant un handshake JSON (`V64`), no pel transport ni pel nom
Bluetooth.

## Pantalles principals (per producte)
- Menú Principal — selector de mode (Escena fixa 1-4, Automàtic, Manual
  [només EVO], Configuració) i, si el cicle és actiu, barra de progrés.
- Escena / Canals — navegació d'escena i de grup de 3 canals, sliders +
  camp numèric per nivell, editor de transicions per canal.
- Programació Cicles — durades de les 8 fases del cicle (Escena/Transició
  alternades), Play/Pausa.
- Paràmetres — nom del pessebre, descripció, nombre de canals/escenes
  actius (i, a l'EVO, la cançó a reproduir).
- Configuració — nom Bluetooth, PIN de connexió opcional, exportació/
  importació de la configuració, reset de fàbrica.

## Compilar
```
flutter pub get
flutter build apk --debug      # per provar en un mòbil connectat
flutter build apk --release    # APK signat de release
flutter build appbundle --release  # AAB signat, per pujar a Google Play
```
Requereix `android/key.properties` + el keystore que hi apunta (no
versionats) per a les builds de release — sense ells, Gradle cau a la
signatura de debug.

## Llicència
Creative Commons Atribució-NoComercial-CompartirIgual 4.0 (CC BY-NC-SA 4.0).
