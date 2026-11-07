# Qué pasa con el galpón vacío (D-0106) — 2026-11-04

Decidió: Claude, por delegación del usuario (2026-11-04). No se abrió issue `decide-usuario` para esta tarea.

## Contexto
Cuando toda la tripulación sale a repartir, el galpón queda sin nadie. D-0106
(`docs/expansion-distritos/detalle/F0-01-diseno.md`) proponía el supuesto S4 y dos alternativas. Desde el
2026-10-04 rige S4 y la fila 4 de [decisiones delegadas](2026-10-04-expansion-decisiones-delegadas.md). Ya está
construido: `DayCycle` (D-0203) congela el galpón como minuto propio (`shed_minute()` = minuto del mundo menos
el tiempo congelado), con un cambio como mucho cada `SHED_FREEZE_SETTLE_REAL_SECONDS`, viajando en el evento
`day_phase`; `DayCycle.crew_in_shed` = algún jugador dentro de `CompanyShed.holds()` (D-0316.1). Los pedidos
entran y vencen con la hora del galpón (D-0813.1) y el modo solo cuenta con eso (D-0126). En F1 no hay
empleados.

## Alternativas
- **Se congela si no queda nadie y no hay empleados** (S4, la propuesta del detalle).
- Sigue corriendo y los proveedores se van: castiga al que sale a entregar, que es justo lo que el juego pide;
  solo o en dupla, cada salida perdería mercadería.
- El host tiene que dejar a alguien: imposible solo, y en dupla obliga a uno a mirar el galpón vacío, contra
  la regla de 2 min de `roles-tripulacion.md`.

## Decisión
**Si nadie queda en el galpón y no hay empleados, el galpón se congela**: proveedores y pedidos esperan y el
reloj del galpón no avanza. El reloj del mundo sigue y el día cierra a las 20:00 del mundo, así que congelar
cuesta horas del día y no es gratis. **Con empleados** (F2), el galpón sigue andando y ellos trabajan.

## Por qué
- En F1, solo o en dupla, castigar al que sale es injusto; congelar lo evita sin pausar la ruta.
- Desde F2 los empleados le dan sentido a "dejar el galpón andando", que es parte del crecimiento.
- Es lo construido: `DayCycle`, `CompanyRoot._crew_in_shed()`, la hora de los pedidos y el modo solo ya lo
  suponen.

## Qué cambia
- `supuestos.md` S4 pasa a decidido.
- Trabajo nuevo: `crew_in_shed` todavía no cuenta empleados (no existen), y el proveedor sigue el reloj del
  mundo en lugar de `shed_minute()`. Anotado en [`revisar/D-0106.md`](../expansion-distritos/revisar/D-0106.md).
