# ardmx_classic

App Flutter (Android) de control de l'**ARDMX4** (Arduino Mega) per
**Bluetooth Classic (SPP)**. Producte separat d'[`apps/ardmx`](../ardmx/README.md)
(BLE, per a l'ARDMX One i l'ARDMX EVO) perquè Bluetooth Classic no és
accessible des d'apps de tercers a iOS sense certificació MFi.

Mateix protocol de text `!Vxx=valor$` que les apps BLE, sobre un socket SPP
en lloc d'una característica GATT.

## Firmware relacionat
[`ardmx4-firmware`](https://github.com/xaviermila-png/ardmx4-firmware) (Arduino Mega).

## Llicència
Creative Commons Atribució-NoComercial-CompartirIgual 4.0 (CC BY-NC-SA 4.0).
