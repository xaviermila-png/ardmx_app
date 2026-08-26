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
- Simulació — visualitzador gràfic de les corbes del cicle (fins a 12
  canals alhora, eix X proporcional a la durada real de cada escena/
  transició), amb controls de Play/Pausa/Stop i un marcador de posició en
  directe mentre el dispositiu reprodueix. Primer botó del submenú de
  Configuració (Simulació / Escenes / Cicle / Paràmetres). Força
  horitzontal en obrir-se. No accessible des de l'ARDMX One v1 (no té
  model d'escenes/transicions). `lib/features/simulacio/`.

## Format d'exportació/importació de la configuració

Un sol esquema JSON (`lib/features/system_config/config_json.dart`,
`ArdmxConfigData`), compartit i vàlid per a l'ARDMX One v2 i l'ARDMX EVO — un
fitxer exportat des d'un dels dos es pot importar a l'altre sense
problemes. El firmware no hi intervé: tot el fitxer es munta/aplica des de
l'app a base de peticions del protocol `!Vxx=valor$` ja existent (V71 per
canal, V18/V08/V40/V21-28/V68/V69...), cap dels dos firmwares genera ni
llegeix JSON directament.

```jsonc
{
  "origen": "ARDMX_ONE",       // o "ARDMX_EVO" — mateixos valors que el "tipus" del handshake V64
  "versio_esquema": 1,
  "versio_firmware": "2.0.0",
  "exportat_el": "2026-08-26T10:00:00.000",
  "numero_escenes": 4,
  "numero_canals": 300,
  "periodes": [5, 10, 15, 20, 25, 30, 35, 40],  // 8 temps acumulats (s)
  "pessebre": "...",
  "descripcio": "...",
  "audio_manual": {                 // NOMÉS present en exportacions de l'EVO
    "numero_musica": 1,
    "nivell_volum": 20
  },
  "canals": [
    {
      "canal": 1,
      "valors": [255, 0, 128, 0],   // 0-255, un per escena
      "transicions": [              // 4, una per sortida d'escena (1→2, 2→3, 3→4, 4→1)
        { "tipus": 0, "salt_percent": 0 },   // 0=Lineal 1=Salt 2=Ease In 3=Ease Out
        { "tipus": 1, "salt_percent": 50 },
        { "tipus": 2, "salt_percent": 0 },
        { "tipus": 3, "salt_percent": 0 }
      ],
      "nom": "Cel"
    }
  ]
}
```

**Importació creuada**: `audio_manual` és l'únic camp que distingeix els dos
productes (l'EVO té DFPlayer/volum; el One v2 no té cap maquinari
equivalent — tampoc hi ha cap configuració pròpia de Mode Manual/Trigger més
enllà de seleccionar-lo com a mode actiu, que no és una dada exportable).
En important:
- Fitxer d'EVO → One v2: `audio_manual` s'ignora silenciosament (avís no
  bloquejant a la pantalla).
- Fitxer de One v2 → EVO: no hi ha `audio_manual` al fitxer, així que la
  cançó i el volum del dispositiu es **forcen a 0/Off** en lloc de deixar
  el que ja hi hagués (avís no bloquejant a la pantalla).
- Ja NO es rebutja cap importació per l'`origen` no coincidir amb el
  dispositiu connectat (abans del format unificat, `model` sí que ho feia).

Sense retrocompatibilitat amb el format antic (un per producte, `model` en
lloc de `origen`, sense `audio_manual`/`versio_esquema`) — un fitxer
exportat abans d'aquest canvi no es pot importar.

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
