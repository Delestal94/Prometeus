# Aviso: S-604, reclamos de clientes con voz propia (2026-09-30)

Rama `nacho/S-604-client-complaints`. Toca `scripts/ui/hud/hud_results.gd` (Slatex) y la zona compartida
(`run_manager.gd`, `level_base.gd`, `event_bus.gd`, `network_manager.gd`). **Sube `PROTOCOL_VERSION` de 8 a 9**
(cuando se fusione con otras ramas que también la suban, usar el valor mayor + 1). Los archivos nuevos de Nacho
(`client_complaints.gd`, cambios en `depot.gd` y `delivery_house.gd`) no necesitan aviso.

## Qué cambió

- `hud_results.gd`: `_show_complaints()` arma cada línea con la función estática nueva `complaint_line(complaint)`:
  "Casa N · Cliente: «línea» + qué pasó". Si el reclamo no trae cliente (resultados viejos, tests), queda el texto
  genérico de siempre (`HUD_COMPLAINT_PAID` / `HUD_COMPLAINT_SETTLED`). Claves nuevas en `strings_ui.csv`:
  `HUD_COMPLAINT_VOICED_PAID`, `_SETTLED`, `_NOTED`. El label y su ancho no cambian.
- `run_manager.gd`: cada reclamo de `results["complaints"]` suma `client`, `result` (`ruined`, `at_risk`, `opened`,
  `wrong`) y `line` (la CLAVE `WORLD_COMPLAINT_*`, no el texto); una puerta a la que le ofrecieron una caja ajena
  suma una nota `wrong` con `noted: true` que no descuenta. `register_delivery()` recibe un 4.º parámetro opcional
  `opened`; nuevo `refused_houses`. El puntaje y el desglose no cambian.
- `level_base.gd::_on_house_resolved`: pasa `opened` (lo lee de `DeliveryHouse.handed_over_open`).
- `Depot.assignments()` (y la señal `houses_assigned`) llevan un 4.º elemento: el id del contenido (de él sale el
  cliente). `Route.assign_packages()` lo ignora.

## Qué tiene que hacer Slatex

Nada. Un contenido nuevo que sea un cliente nuevo necesita entrada en `ClientComplaints.CLIENTS`/`LINES` y sus
líneas en `strings_world.csv`; `test_client_complaints` lo exige.
