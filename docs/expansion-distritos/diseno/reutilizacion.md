# Qué se reutiliza y qué se reemplaza (D-0119)

> Por sistema del juego actual: cómo lo usa el modo Empresa y con qué archivo nuevo. Es la entrada de
> D-0201 (arquitectura) y de D-0120 (riesgos). Fuentes: [corte-vertical.md](corte-vertical.md),
> [supuestos.md](../detalle/supuestos.md) (S1, S8, S9), [F0-02-arquitectura.md](../detalle/F0-02-arquitectura.md).
> Rutas relativas a `do-not-drop/`; líneas al 2026-10-04 (`origin/main` e25a5a6).

## 1. Regla

**Modo Entrega y Endless no cambian de comportamiento (S1).** Todo lo de abajo se resuelve **agregando**:
una clase nueva que envuelve o lee a la vieja, un caso nuevo en una lista, un campo con valor por defecto.
Ninguna firma pública existente cambia, y ningún test actual se toca salvo para sumarle un caso. Si una
tarea `D-` necesita cambiar una firma vieja, es una decisión aparte con su archivo en `docs/decisiones/`.

Tres maneras de reusar:

- **Igual**: se usa tal cual, sin tocar el archivo.
- **Envuelto**: se usa desde una clase nueva de la expansión (adaptador), o se le agrega algo aditivo
  (una entrada en una lista, una señal al final, un campo nuevo con defecto).
- **Reemplazado**: en modo Empresa no se instancia; lo hace un archivo nuevo. El viejo queda para
  Entrega y Endless.

## 2. Tabla

| # | Sistema | Entrada (archivo:línea) | En modo Empresa | Archivo nuevo | Tarea |
|---|---|---|---|---|---|
| 1 | `Depot` (galpón actual) | `scripts/gameplay/depot/depot.gd:1`; `stock_shelves` :260, `post_orders` :291, `begin_run` :394, `request_supply` :463 | **Reemplazado.** El galpón de la empresa tiene stock real (`Inventory`), pedidos con vencimiento (`OrderBook`) y armado en grilla; `Depot` llena estantes con paquetes ya armados y arma pedidos por casa. Se copian dos constantes como referencia, no el código: `PACKAGE_SCENE` :57 y `PADDING_ABSORPTION` :75 (base de la absorción de D-0213). Corte de escape del §7 del corte vertical: si D-0214 tarda, stock y armado se prueban dentro de la escena del depósito actual sin cambiar `depot.gd` | `scripts/gameplay/business/warehouse.gd` (galpón por defecto) | D-0620, D-0911 |
| 2 | `DepotStation` (kiosco con menú) | `scripts/gameplay/depot/depot_station.gd:2`; `interact` :31, RPC `_open_locally` :43 | **Igual** como patrón: las estaciones del galpón (tablero de pedidos, compra al proveedor, cierre del día) son `Interactable` que abren su menú local. Se reusa la escena como base visual gris | estaciones en `scenes/company/` | D-0603, D-0804 |
| 3 | `DepotOrderBoard` (tablero físico) | `scripts/gameplay/depot/depot_order_board.gd:1`; `write` :67, `mark` :114 | **Envuelto.** El tablero de pedidos de la empresa usa el mismo stand y `say`; un adaptador traduce `OrderBook.open_orders()` al formato de `write` y `order_changed` a `mark`. Si la forma de los datos no entra, se hace un tablero propio con el mismo `_build_stand` copiado | `scripts/gameplay/business/order_board_adapter.gd` | D-0804 |
| 4 | `DepotWorker` (NPC que habla) | `scripts/gameplay/depot/depot_worker.gd:1`; `_say` :121 | **Igual** en F1 como ambientación (el proveedor y su chofer). Los empleados de F2 (grupo 10) son otra clase: trabajan, no solo miran | — (F2: `scripts/gameplay/business/employee.gd`) | D-0601, D-1001 |
| 5 | `DeliveryHouse` (casa y timbre) | `scripts/gameplay/route/delivery_house.gd:2`; `_on_doorbell_rung` :210, `_resolve` :242 | **Envuelto.** La entrega sigue por el timbre; antes de `_resolve`, un validador compara el contenido de la caja (metadata `&"packed_box"` y `&"order_id"` de D-0213) contra el pedido y le pasa el resultado a `OrderBook.mark_delivered`. Las casas se ubican en las celdas de Barrio Centro, no en tramos | `scripts/gameplay/districts/order_delivery_check.gd` | D-0311, D-0340, D-0815 |
| 6 | `RouteStreamer` / `SegmentStreamer` | `scripts/gameplay/route/route_streamer.gd:2` (`_pick_next_script` :104); base `modules/route_gen/segment_streamer.gd:1` (`_spawn_next` :170) | **Reemplazado** para el mapa continuo: `WorldCells` carga celdas de 256 m alrededor de cada vehículo (decisión del mapa continuo). Campo reusa los **tipos de tramo** como piezas de la zona, no el streamer infinito | `modules/world_cells/` + `scripts/gameplay/districts/world_cells_adapter.gd` | D-0303, D-0315 |
| 7 | `RunManager` (autoload: corrida, plazos, resultados) | `scripts/core/run_manager.gd:1`; `MODE_*` :56, `start_run` :259, `register_delivery` :292, `finish_run` :400 | **Envuelto, sin modo nuevo adentro.** Una salida de la empresa no es una corrida: el día lo lleva `DayCycle`. `RunManager` no se arranca en modo Empresa; lo que se quiera reusar de `run_scoring.gd` / `run_tally.gd` se llama desde el resumen del día | `scripts/core/company/day_cycle.gd`, `day_summary.gd` | D-0203, D-0320 |
| 8 | `CrewProgression` (autoload: plata, suministros) | `scripts/core/crew_progression.gd:1`; `STARTING_MONEY` :5, `SUPPLIES` :71, `team_money` :91 | **Igual para Entrega/Endless; no se usa para la plata de la empresa (S8).** La plata vive en `CompanyState.money` (arranca en 500, no en 100). Mérito y cartas se siguen ganando en las salidas. `SUPPLIES` (relleno, repuestos) no se reusa: el relleno de la empresa es por celda (`company_tuning.gd`) | `scripts/core/company/company_state.gd`, `company_tuning.gd` | D-0202, D-0501 |
| 9 | `UnlockManager` (autoload) | `scripts/core/unlock_manager.gd:1`; `TRAP_UNLOCKS` :37, `TRAP_DIFFICULTY_ORDER` :44, `TRUCKS` :54 | **Igual, solo lectura.** `TRAP_DIFFICULTY_ORDER` decide la trampa de una caja con varios productos (D-0213); `TRUCKS` da los números de `VehicleDefinition` (D-0207). Los desbloqueos de la empresa (hitos, licencias) son de F2 y viven en `CompanyState.milestones_done`, no acá | `scripts/gameplay/fleet/vehicle_definition.gd` | D-0207, D-0213 |
| 10 | `UnlockProfile` (guardado de desbloqueos) | `modules/unlock_profile/unlock_profile.gd:19` (`user://unlock_progress.json`) | **Igual.** El save de la empresa es otro archivo (`user://saves/company/<slot>.json`) para no mezclar progreso de dos modos | `scripts/core/company/company_save.gd` | D-0206 |
| 11 | `SafeJson` y migración de `user://` | `modules/persistence/safe_json.gd`, `user_data_migration.gd` | **Igual.** `company_save.gd` escribe y lee con `SafeJson`, como `CrewProgression`; tabla de versiones propia | `scripts/core/company/company_save.gd` | D-0206 |
| 12 | `PackageContent` (contenido de paquete) | `scripts/gameplay/package/package_content.gd:1` (campos :10-14); `.tres` en `data/contents/` | **Igual (S9).** Cada `ProductDefinition` referencia uno; los 10 contenidos son los 10 productos (ya hecho en D-0204, `scripts/gameplay/business/product_definition.gd`) | — | D-0204 ✅ |
| 13 | `DeliveryPackage` (el paquete físico) | `scripts/gameplay/package/package.gd:1`; `trap_definition` :14, sincronizador `scenes/gameplay/package/package.tscn:98`, RPCs :358, :448, :484, :490 | **Envuelto.** La caja armada **es** un `DeliveryPackage`: `box_to_package.gd` instancia `package.tscn` y le pone trampa, contenido, absorción y metadata. Física, cuidado, rescate y su red quedan iguales. Es archivo de Slatex: solo se agrega (aviso) | `scripts/gameplay/business/box_to_package.gd` | D-0213 |
| 14 | Trampas (`TrapDefinition`, `ITrapBehavior`, 7 comportamientos) | `modules/hazards/trap_definition.gd:1` (`create_behavior` :42); `modules/hazards/i_trap_behavior.gd:1`; `scripts/gameplay/traps/*_trap_behavior.gd`; `data/traps/*.tres` | **Igual.** La trampa sale del producto y el armado solo mueve la intensidad (`impact_absorption`) y suma Equilibrio a una caja floja (D-0710). No hay registro de trampas: se cargan por id con `res://data/traps/%s.tres` como `depot.gd:58` | — | D-0213, D-0710 |
| 15 | `SceneLoader` | `modules/scene_loader/scene_loader.gd:1`; `change_scene` :102 (lo usa `scripts/ui/loading_screen.gd:73`) | **Igual** para entrar al mundo de la empresa desde el menú. Dentro del mundo no hay pantallas de carga: zonas por celdas (corte vertical §3) | — | D-0214 |
| 16 | `NetworkManager` (autoload) | `scripts/core/network_manager.gd:1`; `PROTOCOL_VERSION = 28` :68, `LEVEL_SCENES` :141 | **Envuelto.** Se agrega `res://scenes/company/company_world.tscn` al final de `LEVEL_SCENES` (sin eso el cliente no la carga) y el número sube según `convenciones-godot.md` §6 en el primer PR con RPC de negocio. Join tardío y reingreso (N-221) se reusan; el snapshot del negocio va aparte | `scripts/core/company/company_net.gd` | D-0214, D-2003, D-2004, D-2008 |
| 17 | `RpcGuard` | `modules/net_session/rpc_guard.gd:1`; `from_host` :97, `allow_request` :106, `take_request` :126 | **Igual.** Todo `@rpc("any_peer")` nuevo de la expansión pasa por acá; el test de N-238 se amplía a las carpetas nuevas | — | D-2003, D-2007 |
| 18 | `EventBus` (autoload, 58 señales) | `scripts/core/event_bus.gd:1` (extiende `NetEventBus`) | **Envuelto (aditivo).** Señales de negocio nuevas al final, sin reordenar las 58 actuales | — | D-0215 |
| 19 | `level_common.gd` / `level_base.gd` / `level_endless.gd` | `scripts/gameplay/level_common.gd:163` (`--autostart` → `_autostart` :235); `scripts/gameplay/level_base.gd` (`_prepare_mode` :37, `_post_orders` :63, `_assign_orders` :81) | **Reemplazado.** `CompanyWorld` no extiende `level_common.gd`: ese nivel arma ruta, depósito y corrida de una entrega. Lo que se copie (spawns, cámara, vehículo inicial) se copia, no se hereda, para que un cambio en Entrega no rompa la empresa | `scripts/gameplay/districts/company_world.gd` | D-0214 |
| 20 | Menú y argumentos de arranque | `scripts/ui/main_menu.gd`; `_handle_cmdline_args` :150 (`--autostart` :159, `--autostart-endless` :162) | **Envuelto.** Botón "Empresa" y un flag nuevo. Ver decisión del §3 | — | D-0214 |
| 21 | Camioneta (`vehicle.gd`) | `scripts/gameplay/vehicle/vehicle.gd:1` (sin `class_name`); `_ready` :272, `carries` :322, `set_rear_cargo_open` :375 | **Igual en F1** (corte vertical, ítem 11: sin cambios de manejo). `VehicleDefinition` la describe; la base común de flota (D-0208) es por composición y de F0-B, no bloquea el corte | `scripts/gameplay/fleet/vehicle_definition.gd` | D-0207, D-0208 |
| 22 | `VehicleFaults` (fallas y repuestos) | `scripts/gameplay/vehicle/vehicle_faults.gd:2`; `reset_for_run` :129, `stock_spares` :166 | **Igual** dentro de la camioneta. Los repuestos se compran con plata de la empresa recién en F2 (taller); en F1 la camioneta sale sin fallas forzadas | — | — (F2) |
| 23 | `WorldMood` (clima y hora) | `modules/world_mood/world_mood.gd:2`; `darkness` :119, `is_raining` :123 | **Envuelto.** La hora la da el reloj de la empresa (`clock_minutes`, 08:00-20:00), no la corrida; un adaptador traduce minutos a la luz de `WorldMood`. Cada zona tiene sus perfiles en `ZoneDefinition` | `scripts/core/company/game_clock.gd` | D-0219, D-0205 ✅ |
| 24 | `ShopVoteManager` (votación de tienda) | `scripts/core/shop_vote_manager.gd:1` (extiende `CoopVote`); `open_shop` :27 | **No se usa en F1.** La compra al proveedor la decide quien está en la estación, sin votar. `modules/coop_vote/` queda disponible si F2 quiere votar una compra grande | — | D-0601 |
| 25 | `RouteEventManager` (eventos de ruta) | `scripts/core/route_event_manager.gd:1`; `begin_random` :81, `TRAP_PATHS` :18 | **No se usa en F1.** Los eventos son de la ruta infinita; en el mapa continuo los reemplazan los peligros por zona (`ZoneDefinition.hazards`) desde F2 | — | grupo 15 |
| 26 | `HudPause` | `scripts/ui/hud/hud_pause.gd:1`; `_pause` :85 | **Igual** para pausar; el resumen de "el host se fue" reusa el camino de N-222 | — | D-2005 |
| 27 | Jugador, levantar y soltar | `scripts/gameplay/player/player.gd` (`pick_up` :637, `drop_carried` :644); `player_carry.gd:12`; `scripts/gameplay/interaction/` | **Igual** para cajas armadas (son `DeliveryPackage`). Los productos sueltos del estante y el palet son objetos nuevos con su propio punto de interacción sobre `modules/interaction/interactable.gd` | `scripts/gameplay/business/product_pickup_point.gd` | D-0606, D-0703 |
| 28 | Depósito de módulos genéricos | `modules/` (23 módulos, `tools/check_modules.py`) | **Igual, y se suman** `day_clock`, `world_cells`, `inventory`, `order_queue` y `build_grid` según D-0220 | `modules/<nuevo>/` | D-0220, D-2018 |

## 3. Decisión: cómo se arranca el modo Empresa por línea de comandos

**Decisión:** el flag es `--autostart-company` (más `--slot=<n>` opcional), no `--autostart --mode=company`,
**porque** `main_menu.gd:159` y `level_common.gd:163` reaccionan a `--autostart` solo y arrancarían una
entrega antes de leer `--mode`. El flag nuevo sigue el patrón de `--autostart-endless` (:162) y no toca
cómo se lee `--autostart`. Se corrigen D-0214 y D-2020 en su detalle; queda en
`docs/decisiones/2026-10-04-flag-modo-empresa.md`.

## 4. Lo que encontró el relevamiento y conviene saber

- `PROTOCOL_VERSION` ya está en **28** (`network_manager.gd:68`); el detalle de F0-20 decía 27.
- No hay sistema de guardado general ni código de Steam Cloud: el único save de progreso es
  `user://unlock_progress.json` y la configuración (`modules/settings_store/`). D-0206 y D-2010 parten de cero.
- No hay registro de trampas: se cargan por ruta. Si D-0216 (catálogo) lo necesita, lo lee de `data/traps/`
  con `DirAccess`, sin tocar `RouteEventManager.TRAP_PATHS`.
- `vehicle.gd` no tiene `class_name`: lo que la expansión necesite de él va por `VehicleDefinition` y por
  la interfaz de D-0209, no nombrando la clase.
