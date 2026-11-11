# F1 · Grupo 02 — Arquitectura (detalle)

> Carril 1 de la rutina `desarrollador`. Las tareas de arquitectura del grupo 02 que son de F1. Las de F0 están en
> [F0-02-arquitectura.md](F0-02-arquitectura.md).

### D-0251 · Un día cortado vuelve a su apertura — A · Opus 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-11-04, lote local)** — el código ya estaba (PR #678, 7fa155d8: apertura del día 1 antes de los flags, `CompanySave.mark_interrupted()`); `test_company_autosave` suma ahora los flags de desarrollo fuera del slot, los palets de la apertura y `was_interrupted()` tras cargar. Revisión 2026-11-07: el menú de empresas muestra el chip "Día cortado" (`CompanySlotsPage._add_row`, `test_company_slots_menu`) y `test_company_autosave` prueba `mark_interrupted()` directo (`saved_at` intacto, slot vacío, solo `.bak`).
**Depende de:** D-0134 (diseño), D-0236, D-2005
**Qué:** [guardado.md](../diseno/guardado.md), reglas 1 y 2. Solo en el host (también jugando solo):
- [x] D-0251.1 **Crear la empresa guarda su apertura del día 1.** En `CompanyRoot`, cuando `load_into` no cargó nada
  y se llama a `new_company()`: guardar el slot después de `DefaultShed` y **antes** de `CompanyDevFlags.apply`
  (con el stock y `pallets` como los deja un save). Un slot con un save de una build más nueva no se pisa (como hoy).
- [x] D-0251.2 **Un corte no escribe la empresa.** `save_interrupted_day()` deja de escribir `to_dict()`: solo marca
  `interrupted: true` en el archivo que ya está (nueva `CompanySave.mark_interrupted(slot, dir)`, que lee el JSON,
  cambia la clave y lo escribe por `SafeJson`, sin tocar `company` ni `saved_at`). Sin archivo, no hace nada.
  `load_into` sigue poniendo el reloj en `DAY_START_MIN` (el archivo ya está a esa hora).
- [x] D-0251.3 Comentarios de `company_save.gd` (encabezado y `load_into`: "what happened after it is kept" pasa a
  "the day's opening, nothing of the cut day") y de `company_root.gd`. El resumen local del cliente (D-2005) no
  cambia: muestra lo que vio.
- Decisión: no sube `CompanySave.VERSION`. Las claves no cambian de significado para el lector; solo cambia cuándo se
  escribe (regla 5 de guardado.md).
- Decisión: al salir del mundo el host recarga la empresa del slot también después de un cierre (salir en el
  resumen). Si no, volver a entrar en la misma sesión jugaría otra vez el día cerrado y lo cobraría dos veces.
**Test** `test_company_autosave` (ampliado): una empresa nueva deja su slot del día 1 sin los flags de desarrollo;
abrir el día, cobrar un pedido (`earn`), mover unidades a una mano, salir a mitad de día y cargar devuelve la plata,
el `ledger`, el stock y `pallets` de la apertura, con `was_interrupted()` en true. Salir en `SUMMARY` sigue guardando
el día siguiente sin `interrupted`. `test_company_host_leaves` y `test_company_save` siguen verdes.
**Hecho cuando:** el test pasa. La tarea que enganche el cobro (`OrderSettlement`) o el alquiler (`FixedCosts`) al
mundo lleva `Depende de: D-0251` y no se mezcla antes ([guardado.md](../diseno/guardado.md) §5).

### D-0252 · Stock sin lugares en curso al guardar — A · Opus 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR #686, 1481f6bd)** — `ReturnBundle` (`scripts/core/company/return_bundle.gd`): `for_save()` junta
manos, bultos, cajas y paquetes en `floor:0` sin reservas (`CompanyRoot.stock_for_save()` la usa) y, al cargar en el
host, `place()` pone el bulto en `RETURN_BUNDLE_SPOT` o en la celda libre más cercana (`spot()`); `test_company_save_stock`.
**Depende de:** D-0134 (diseño), D-0236, D-0715 (cajas), D-2006 (bultos del piso)
**Qué:** [guardado.md](../diseno/guardado.md) §3.
- [x] D-0252.1 `stock_for_save()` pasa también `floor:<n>`, `box:<id>` y `package:<id>` al bulto de devolución
  `floor:0` (`CompanyRoot.SAVED_HANDS_LOCATION`), con los totales por producto iguales, y deja **todas** las
  reservas en 0 (son de pedidos que al día siguiente ya no existen).
- [x] D-0252.2 `CompanyTuning.RETURN_BUNDLE_SPOT` (al lado de las mesas del galpón por defecto, dentro del piso de
  la etapa 0). Al cargar, si hay stock en `floor:0`, `FloorBundles` le pone esa posición (el host la publica en el
  snapshot), así se puede tomar como cualquier bulto.
- [x] D-0252.3 Si el lugar fijo queda tapado por una pieza del `layout`, usar el punto libre más cercano con la
  misma regla de alcance que los bultos (D-2006).
- Decisión: el punto es el medio de la celda (10, 1) de la etapa 0, `(4.5, 0, -2.5)`: la punta norte del pasillo
  frente a las mesas, fuera de donde se para el que arma y fuera de la zona de despacho. En una etapa más grande
  sigue en esa celda (las piezas conservan sus celdas al agrandar), no en el mismo punto del mundo.
- Decisión: "libre" es una celda del piso sin pieza encima (tampoco la zona de despacho pintada), fuera del muelle y
  de la salida, y a la que la tripulación llega caminando (`WalkReachability`, la misma que cuida el modo
  construcción). Parado ahí, el bulto queda dentro de `REMOTE_REACH` como cualquier bulto. Lo más cercano se mide
  desde el punto fijo; los empates van a la fila y después a la columna más baja. Lo calcula solo el host y viaja en
  el snapshot.
- Decisión: la lista de lo que va al bulto es de prefijos en curso (`hands:`, `floor:`, `box:`, `package:`); un
  lugar nuevo que no esté ahí se guarda igual que hoy. No se normaliza al cargar: un save de antes de D-0252 puede
  tener bultos `floor:<n>` sin posición (solo se le pone posición a `floor:0`).
- Decisión: no sube `PROTOCOL_VERSION` ni `CompanySave.VERSION`: no hay RPC nuevo y la clave `floor` del snapshot ya
  existía con la misma validación; el save cambia qué guarda, no su formato.
**Test:** guardar con unidades en una mano, en el piso, en una caja abierta y en un paquete. Cargar y verificar que
los totales por producto son los mismos, que todo está en estante, palet, carrito, muelle o `floor:0`, y que un
jugador con alcance puede tomar una unidad de `floor:0` (la petición la acepta el host).
**Hecho cuando:** el test pasa. `bot_company_day` anota cuántas unidades quedan en el bulto al cierre (para medir
si con 8 jugadores hay que partirlo por producto).

### D-0253 · Cerrar el día antes — A · Opus 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR #684, f6152778)** — `DayCycle.close_early()` y `DayClose` (botón, confirmación y aviso
de las salidas, con sus textos) hechos y probados. Dibujarlos (D-0253.a) pasa a D-1909, que ya lo incluye: el modo
Empresa no tiene menú de pausa y D-1909 es de F5. Decisión: no se espera una tarea de F5 para cerrar la de F1.
**Depende de:** D-0134 (diseño), D-0203, D-0236
**Qué:** [guardado.md](../diseno/guardado.md), regla 2: la forma de cortar sin perder lo hecho.
- [x] D-0253.1 `DayCycle.close_early()` (solo en el host, en `OPERATING`): pasa a `CLOSING` en ese momento por el
  mismo camino que las 20:00. No entran pedidos nuevos (`CompanyDayOrders` ya no agrega en `CLOSING`), se espera a
  `trips_out() == 0` y viene `SUMMARY`, que guarda como siempre. Las penalidades de lo no entregado se cobran igual
  que a las 20:00. En otra fase no hace nada (devuelve false).
- [x] D-0253.2 **Decisión: lo pide solo el host, sin voto.** El host ya es el que abre el día siguiente, y un voto es
  una pantalla más para 1 de cada 18 minutos. Va en el menú de pausa del modo Empresa (D-1909) como "Cerrar el día",
  con confirmación. Un cliente lo ve deshabilitado, con el texto "Lo cierra el host".
- [x] D-0253.3 El aviso en las dos salidas (menú de pausa → Salir al menú y Salir del juego) con un día en
  `OPERATING` o `CLOSING`: "Salir ahora pierde lo hecho desde las 08:00. Para guardarlo, cerrá el día." Las claves
  van a `strings_ui.csv` (es y en).
  Hecho del lado de la lógica: `scripts/gameplay/business/day_close.gd` (`DayClose.button()` da texto, habilitado,
  pista del cliente y confirmación; `DayClose.exit_warning()` da el aviso solo en el host con el día en `OPERATING`
  o `CLOSING`) y las claves `UI_COMPANY_CLOSE_DAY*` / `UI_COMPANY_EXIT_LOSES_DAY`.
- [x] D-0253.a Dibujar el botón y el aviso en el menú de pausa del modo Empresa con `DayClose`, cuando exista
  (D-1909; [decisión](../../decisiones/2026-10-22-cerrar-el-dia-antes.md)). Captura con `revisor-visual`.
  Hecho con D-1909 (2026-11-01, rama `codex/D-1909-company-pause-menu`): `scripts/ui/company_pause_menu.gd`,
  probado por `tests/test_company_pause_menu.gd`. La captura queda para una sesión con ventana.
**Test** `test_day_cycle` (ampliado): `close_early()` a las 12:00 pasa a `CLOSING`, no deja entrar pedidos, espera
una salida afuera y llega a `SUMMARY`; en `OPENING` o `SUMMARY` devuelve false; en un cliente no hace nada.
`test_company_autosave`: después de cerrar antes, el slot queda en el día siguiente sin `interrupted`.
**Hecho cuando:** los tests pasan y el menú de pausa tiene el botón y el aviso (captura con `revisor-visual`).

### D-0254 · Partir `company_root.gd` y `company_net.gd` — A · Opus 5.5 · medium · Aviso: no · F1
**[~] Parcial (2026-11-11, PR #861)** — falta la pasada de `auditor-red` sin hallazgos que pide la fila (un subagente no puede lanzarla; la revisión de aceptación miró la red y no encontró defectos) y la prueba a mano de [`revisar/D-0254.md`](../revisar/D-0254.md). Lo demás está: `company_net.gd` 1000 → 820 líneas y `company_root.gd` 948 → 692, sin cambiar el protocolo (67) ni las listas de `kind`: cada dominio declara sus `kind` y `CompanyNet` solo los junta y los enruta; `test_company_net_domains`.
**Depende de:** #844 (alquiler), #845 (montacargas), #850 (cierre del día, protocolo 67): los tres en `main`.
**Qué:** [riesgos.md](../diseno/riesgos.md) R-16 y la [revisión D-0140](../diseno/revision-diseno.md): los dos archivos
estaban contra el tope de 1000 líneas de gdlint, y la puerta (D-0340), el cobro (D-0815.b), el palet (D-0607.c) y la
mesa (D-0701.b, D-0715.b) suman cada una un `kind` o un enganche. Solo se mueve código: mismos RPC, mismos `kind`,
mismos nodos y nombres en el árbol.
- [x] D-0254.1 **Unidades fuera de `CompanyNet`.** `CompanyUnitsNet` (`scripts/core/company/company_units_net.gd`):
  `units_take`, `units_store` y `units_drop` (filas 5 a 7), su evento `units_moved`, el alcance de toda petición en
  una estación (`reach()`, regla 4: unidades, mesas, carros, palets) y dónde estuvo cada peer (`_last_origin`).
  `CompanyNet.units`; `within_reach()`, `last_known_position()` y `UNITS_DROP` quedan como reenvíos.
- [x] D-0254.2 **Transporte del snapshot fuera de `CompanyNet`.** `CompanySnapshotSync`
  (`scripts/core/company/company_snapshot_sync.gd`): el límite de una petición por peer cada 5 s, el número y los
  trozos de cada snapshot en el host, y en el cliente cuándo volver a pedir y los trozos que junta. Sin RPC ni
  señales: los cuatro `@rpc` (`_request`, `_apply_event`, `_snapshot`, `_rejected`) siguen en `CompanyNet` con la
  misma firma, y también la API pública (`grant_snapshot`, `send_snapshot`, `wait_for_snapshot`, `poll_snapshot`,
  `apply_snapshot`...). `CompanyNet.sync`.
- [x] D-0254.3 **Cada dominio declara sus `kind`.** `REQUEST_KINDS`, `EVENT_KINDS`, `HOST_EVENT_KINDS` y
  `CRITICAL_KINDS` de `CompanyNet` son la suma de las listas de cada dominio (`CompanyUnitsNet`, `CompanyLayoutNet`,
  `CompanyTableNet`, `CompanyPackages`, `CompanyCarts`, `CompanyPallets`, `CompanyTripsView`, `CompanyOrdersNet`,
  `CompanySupplierNet`, `CompanyWalletNet`, `CompanyShopNet`, `CompanyTowNet`, `CompanyColdNet`) más las propias
  (`snapshot_request`, `clock_anchor`, `day_phase`). `_handle_request()` y `_apply_state()` tienen una rama por
  dominio (`<Dominio>.REQUEST_KINDS.has(kind)`), sin `else`; el chequeo de alcance de mesas, carros y palets pasó a
  su dominio (`on_request()`), y el de vender una pieza con caja o palet a `CompanyLayoutNet.on_request()`.
- [x] D-0254.4 **Tripulación fuera de `CompanyRoot`.** `CompanyCrew` (`scripts/gameplay/company_crew.gd`): el
  `World/PlayerSpawner`, quién se spawnea y dónde, `join()`, `in_shed()` (D-0316.1) y el `player` propio.
  `CompanyRoot.crew`; `CREW_GROUP`, `SPAWN`, `CREW_SPACING`, `SPAWN_CLEARANCE`, `PLAYER_PREFIX`, `PLAYER_SCENE`,
  `crew_spawn()`, `free_spawn()` y `join_crew()` quedan como alias.
- [x] D-0254.5 **Fondo y uso de piezas fuera de `CompanyRoot`.** `CompanyBackdrop`
  (`scripts/gameplay/company_backdrop.gd`: sol, cielo y losas de zona, mismos nombres de nodo) y `ShedUse`
  (`scripts/gameplay/shed_use.gd`: estante y transpalet → `request_for` / `PalletJackUse`), donde entran después el
  uso de la mesa (D-0701.b) y del palet (D-0607.c). `CompanyRoot.shed_use`.
- Decisión: el guardado del día (`save_closed_day`, `save_interrupted_day`, `stock_for_save`, `host_day_seen`) se
  queda en `CompanyRoot`. Con las piezas de arriba el archivo ya baja a 692 (158 de margen) y esas funciones leen
  estado privado del root que los tests tocan directo (`_hosted_state`); moverlas sumaba reenvíos sin bajar riesgo.
- Decisión: `test_company_layout_net` y `test_company_shed_expand_net` leían las ramas `match` de `_apply_state()`;
  ahora leen las ramas por dominio. Lo que comprueban es lo mismo: cada `kind` cae en una sola rama y no hay rama
  para "lo demás". [Decisión](../../decisiones/2026-11-11-company-net-por-dominios.md).
- Qué toca después un `kind` nuevo: ver [red-autoridad §18](../diseno/red-autoridad.md) ("Qué toca una acción
  nueva"): en la mayoría de los casos solo su dominio, con las excepciones que lista ahí. `PROTOCOL_VERSION` sube
  igual que antes (convenciones-godot §6).
**Test** `test_company_net_domains` (nuevo): los cuatro `@rpc` de `CompanyNet`, ningún `kind` de antes de partir
perdido (solo eso: un `kind` nuevo no edita el test), cada dominio con sus cuatro listas, cada `kind` de un solo dominio, las listas de `CompanyNet` = propias + dominios,
una rama por dominio y sin `else` en las dos funciones, los alias de `CompanyRoot` y los dos archivos (y los nuevos)
bajo 850 líneas. `test_company_late_join` y `test_company_rejoin` leen el estado movido en su lugar nuevo
(`sync._rx_id`, `units._last_origin`) sin cambiar aserciones.
**Hecho cuando:** los dos archivos bajo 850 líneas, `PROTOCOL_VERSION` igual, `test_protocol_version` sin tocar,
`tools/run-tests.sh company` y `net` verdes, `tools/lint.sh` sin problemas nuevos.
