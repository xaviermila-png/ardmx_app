# Release notes — ARDMX (app)

Historial de versions pujades a Google Play Console, amb els canvis
funcionals reals de cada una (per documentar davant Google que cada
versió respon a feedback de testers). Format: `versionName+versionCode`.

## 1.1.0+2 — 2026-09-20

Respecte a la versió anterior pujada (1.0.0+1, 7 d'agost):

**Novetats**
- Pantalla **Events** (ARDMX EVO): programa fins a 10 accions (un so i/o
  un canal forçat a un valor concret, ara configurable — abans sempre
  255) en un moment determinat del cicle.
- Pantalla **Eines**: copiar tots els valors de canal d'una escena a
  una altra, i exportar/importar tota la configuració del dispositiu.
- Pantalla **Simulació**: gràfic de la corba de cada canal durant tot
  el cicle (ARDMX One v2 i EVO).
- Suport complet per l'**ARDMX One v2** (fins ara l'app només cobria
  l'EVO amb profunditat).
- **PIN de connexió** opcional, per evitar connectar-se sense voler al
  dispositiu d'un altre pessebrista a prop.

**Millores**
- Editor de transicions reescrit: cada canal té les seves 4 transicions
  pròpies (abans eren globals per a tots els canals).
- Disseny actualitzat a Material Design 3, amb millores d'accessibilitat.
- Correccions d'usabilitat: camps que es tallaven amb el teclat en
  pantalla, mides de sliders, navegació més consistent.

**Correccions d'estabilitat (trobades en proves amb testers)**
- Pèrdua d'una edició de canal en canviar d'escena o de grup de canals
  molt seguit (el canvi guanyava la cursa i sobreescrivia l'edició
  abans de desar-la).
- La pantalla RGB no aplicava els canvis de color fins tornar a la
  pantalla de Canals.
- Diverses respostes Bluetooth que arribaven desordenades es
  confonien entre elles (editor de transicions, canvis d'escena).
- El selector d'escenes de la pantalla Eines es desbordava amb el
  màxim de 4 escenes actives.

## 1.0.0+1 — 2026-08-07

Primera versió pujada a Prova interna i Prova tancada (Alfa).
