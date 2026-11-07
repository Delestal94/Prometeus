# Duración del día de la empresa (D-0105) — 2026-11-04

Decidió: Claude, por delegación del usuario (2026-11-04). No se abrió issue `decide-usuario` para esta tarea.

## Contexto
D-0105 (`docs/expansion-distritos/detalle/F0-01-diseno.md`) proponía el supuesto S3 y dos alternativas.
Desde el 2026-10-04 rige S3 y la fila 3 de [decisiones delegadas](2026-10-04-expansion-decisiones-delegadas.md).
Ya está construido: `CompanyTuning.DAY_START_MIN` (08:00), `DAY_END_MIN` (20:00) y
`SECONDS_PER_GAME_HOUR = 90.0`; `GameClock` y el módulo `day_clock` (D-0219); `DayCycle` (D-0203) con sus
fases, donde `CLOSING` espera las salidas en curso; el cierre antes de hora (D-0253); la ventana de 4 h de los
pedidos, las ayudas del modo solo (D-0126: último pedido a las 15:00 con 1 jugador) y la economía de 20 días
(D-0117), todas medidas en horas de este reloj.

## Alternativas
- **08:00 a 20:00, 1 h de juego = 90 s reales (18 min por día)** (S3, la propuesta del detalle).
- Día por cantidad de pedidos, sin reloj: se pierde la urgencia compartida y las ventanas de entrega dejan de
  tener una medida; el modo solo y los eventos del día habría que rediseñarlos.
- Día de 12 min: con salidas de 2 a 4 min por zona (`flota.md`) queda poco tiempo de armado entre una y
  otra, y la ayuda del modo solo (último pedido a las 15:00, calculada con 3 salidas de ~3 min) y la curva de
  economía habría que recalcularlas.

## Decisión
**Reloj de 08:00 a 20:00 de juego, 1 h = 90 s reales (día de 18 min).** Corre en el galpón y en las salidas.
A las 20:00 no se corta una salida: el cierre espera que vuelva. El host puede cerrar antes (D-0253). Los
números viven solo en `company_tuning.gd`: si el balance pide otro largo, se cambia ahí y no es una decisión
nueva.

## Por qué
- Un día cabe en una sesión corta y deja lugar a varias salidas de 2 a 4 min con tiempo de armado entre
  ellas.
- Un reloj genera urgencia sin cronómetros por caja (el cronómetro por caja, D-0733, ya se recortó por eso).
- Es lo construido: cambiarlo movería la ventana de pedidos, el modo solo, los eventos y la curva de economía.

## Qué cambia
- `supuestos.md` S3 pasa a decidido.
- Sin trabajo nuevo: el código ya coincide ([`revisar/D-0105.md`](../expansion-distritos/revisar/D-0105.md)).
