# Protocolo 31: reloj del día del modo Empresa desde el host (D-0219)

**Fecha:** 2026-10-12 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 31** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su
  línea del historial. **Cambió el protocolo** aunque no hay RPC nuevo: `CompanyNet._apply_event` lleva un
  tipo de evento nuevo (`clock_anchor`) y el snapshot una parte nueva (`clock`). Un cliente con 30 y un host
  con 31 no se conectan (error de versión en el menú); con el mismo número, uno viejo descartaría el ancla,
  vería un hueco de `seq` y pediría un snapshot por cada cambio de marcha.
- **Módulo nuevo `modules/day_clock/`** (zona compartida): `DayClock` (`RefCounted`, puro, sin nada del
  juego): ancla `{minute, speed, paused}` + tick local, `minute_at()`, `set_anchor()`, `to_dict()` /
  `from_dict()` y `anchor_ok()` para validar lo que llega por red. Test propio
  `modules/day_clock/tests/test_day_clock.gd`; filas nuevas en `docs/modulos.md`.
- **`scripts/core/company/company_net.gd`**: agregados, sin cambiar firmas: constante `CLOCK_ANCHOR`
  (sumada a `EVENT_KINDS`), variable `clock: GameClock`, función `publish(kind, data)` (host: un evento que
  no vino de un pedido; mismo camino que `_publish`) y el caso `clock_anchor` en `_apply_state()`. RPCs
  iguales: `_apply_event` sigue `@rpc("authority", "call_local", "reliable")`, canal 0.
- **`scripts/core/company/game_clock.gd`** (nuevo, `class_name GameClock`, adaptador del módulo): el host
  cambia la marcha con `start(minute)`, `pause()`, `resume()` y `set_speed()`; cada cambio sale **una vez**
  como `clock_anchor` (nada periódico). Cada peer lo toma en `apply_anchor()` con su propio tick menos
  medio RTT (`NetStats.round_trip_seconds`, sin nombrar autoloads). `minute_now()` da la hora en cualquier
  peer. `attach(net, company)` lo cuelga de un `CompanyNet` y suma la parte `clock` del snapshot. En el host
  escribe el minuto entero en `CompanyState.clock_minutes` mientras corre; en un cliente nunca.
- Test nuevo: `tests/test_game_clock.gd` (dos peers ENet en un proceso, tiempo simulado).

## Qué tiene que hacer Slatex

Nada. Para mostrar la hora del modo Empresa en la UI: `GameClock.minute_now()` (minutos desde medianoche,
con fracción) cada cuadro; para enterarse de una pausa, `CompanyNet.event_applied` con `kind ==
&"clock_anchor"` y `company_state_restored`. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 32.
