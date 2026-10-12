# Protocolo 32: fases del día del modo Empresa desde el host (D-0203)

**Fecha:** 2026-10-12 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 32** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su
  línea del historial. **Cambió el protocolo** aunque no hay RPC nuevo: `CompanyNet._apply_event` lleva un
  tipo de evento nuevo (`day_phase`) y el snapshot una parte nueva (`day_cycle`). Un cliente con 31 y un host
  con 32 no se conectan (error de versión en el menú).
- **`scripts/core/company/day_cycle.gd`** (nuevo, `class_name DayCycle`, hijo del mundo, no autoload): las
  fases OPENING, OPERATING, CLOSING y SUMMARY las decide solo el host; cada cambio sale **una vez** como
  `day_phase` y todos los peers (el host también) lo aplican con el mismo código, que valida los datos y emite
  las señales de `EventBus` que ya existían (`company_day_started`, `company_day_closing`,
  `company_day_summary`; `event_bus.gd` no se tocó). Aplicar un snapshot no dispara ninguna.
- **Galpón congelado (S4)**: `DayCycle.shed_minute()` es el minuto propio del galpón; se queda quieto mientras
  no hay nadie adentro y las salidas siguen (el reloj del mundo no se pausa). Cada congelado/descongelado es
  otro `day_phase` (misma fase, `frozen` distinto), como mucho uno por `SHED_FREEZE_SETTLE_REAL_SECONDS`.
- **`scripts/core/company/company_net.gd`**: constante `DAY_PHASE` (en `EVENT_KINDS` y `HOST_EVENT_KINDS`),
  variable `day_cycle: DayCycle` y el caso `day_phase` en `_apply_state()` (con `push_warning` si llega sin
  `DayCycle`). Firmas y RPCs sin cambios.
- **`scripts/core/company/company_tuning.gd`**: `SHED_FREEZE_SETTLE_REAL_SECONDS`.
- **`scripts/gameplay/company_root.gd`**: crea un `GameClock` y un `DayCycle` hijos en todos los peers y los
  engancha a `CompanyNet` antes del snapshot; el host abre el día de `CompanyState.day` ya con el mundo
  armado. El guardado "interrumpido" (D-2005) sigue igual.
- Test nuevo: `tests/test_day_cycle.gd`; `test_company_root` suma el cableado y `test_company_host_leaves`
  desactiva el reloj en su raíz de prueba (`NetOnlyRoot`).

## Qué tiene que hacer Slatex

Nada obligatorio. Para la pantalla de cierre: escuchar `EventBus.company_day_summary(day, summary)` (o leer
`DayCycle.summary` si abre tarde) y llamar `DayCycle.next_day()` en el host al apretar "seguir"; para la hora
del galpón, `DayCycle.shed_minute()`. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 33.
