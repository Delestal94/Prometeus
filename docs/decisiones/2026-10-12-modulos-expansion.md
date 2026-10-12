# Qué de la expansión va a `modules/` (D-0220)

**Fecha:** 2026-10-12 · **Decidió:** rutina desarrollador, carril 1

**Decisión:** van a módulo `day_clock` (ya está), `world_cells`, `inventory`, `order_queue` y `build_grid` en
F1, y `job_board`, `conveyor_graph`, `milestones`, `buoyancy` y `simple_flight` cuando llegue su fase. Todo lo que
nombra plata, pedidos, productos, trampas, `CompanyTuning`, `EventBus` o `CompanyNet` queda en el juego.
`Inventory` y `OrderBook` ya existen en `scripts/gameplay/business/`: D-0221 y D-0222 extraen su parte
genérica sin cambiar su API pública, en vez de reescribirlos.

**Por qué:** es la regla de `docs/modulos.md` (lo que no sabe del juego es portable) aplicada a la lista de
D-0201, y extraer después de tener la versión del juego andando evita diseñar el módulo a ciegas.

**Dueño de las carpetas nuevas:** Nacho (`file_domain` y `colaboracion-equipo.md`), porque la expansión la
construyen las rutinas que trabajan como Nacho; `modules/` sigue siendo zona compartida.

Tabla completa: `docs/arquitectura.md` §10.4.
