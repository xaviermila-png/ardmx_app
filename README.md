# ardmx_app

Monorepo amb les dues apps Flutter de control dels productes ARDMX (control
DMX512 per a pessebres):

- **[`apps/ardmx`](apps/ardmx/README.md)** — app actual, per **Bluetooth Low
  Energy (BLE)**: controla l'**ARDMX One** (v1 i v2, detectat automàticament
  pel handshake del dispositiu) i l'**ARDMX EVO**.
- **`apps/ardmx_classic`** — app per **Bluetooth Classic (SPP)**: controla
  l'**ARDMX4** (Arduino Mega). Producte separat perquè Bluetooth Classic no
  és accessible des d'apps de tercers a iOS sense certificació MFi — BLE sí,
  d'aquí la separació en dues apps.

Cada app és un projecte Flutter independent (el seu propi `pubspec.yaml`,
`android/`, etc.) — vegeu el README de cada una per compilar-la.

## Firmwares relacionats
- [`ardmx-one-firmware`](https://github.com/xaviermila-png/ardmx-one-firmware) (ESP32, BLE)
- [`ardmx-evo-firmware`](https://github.com/xaviermila-png/ardmx-evo-firmware) (ESP32, BLE)
- [`ardmx4-firmware`](https://github.com/xaviermila-png/ardmx4-firmware) (Arduino Mega, Bluetooth Classic)
