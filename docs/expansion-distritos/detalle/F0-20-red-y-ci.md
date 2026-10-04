# F0 · Grupo 20 — Red, rendimiento, QA y CI (detalle)

> Carril 5 de la rutina `desarrollador`. Todo cambio de RPC elige `PROTOCOL_VERSION` (hoy 27,
> `network_manager.gd:66`) como dice `docs/convenciones-godot.md` §6. Siempre `auditor-red` antes del PR.

### D-2001 · Modelo de autoridad del modo Empresa — A · Opus 5.5 · xhigh · Aviso: no · F0
**Depende de:** D-0201
**Qué:** subsección "Red" de la arquitectura de la expansión. Tabla por estado:

| Estado | Dueño | Cómo viaja |
|---|---|---|
| plata, día y reloj | host | RPC del host (D-0219) |
| stock | host | eventos |
| pedidos | host | eventos |
| layout | host | eventos |
| bloqueos | host | eventos |
| posición de cajas sueltas | host | sincronizador de `DeliveryPackage` como hoy |
| cajas en mano | el que la lleva | predicción N-218 |
| vehículos | host | como hoy |

Cada acción de cliente (tomar producto, colocar en la caja, encintar, despachar, comprar) es una
**petición** al host, que valida y responde con el evento. Nada de estado de negocio en
`MultiplayerSynchronizer` por tick.
**Hecho cuando:** la tabla cubre las 20 acciones del corte vertical y `auditor-red` la aprobó.

### D-2002 · Presupuesto de ancho de banda del modo Empresa — A · Opus 5.5 · high · Aviso: no · F0
**Depende de:** D-2001
**Qué:** medir con el overlay de red (N-216) un día de `bot_company_day` con 4 peers ENet locales. El
presupuesto queda en `docs/rendimiento-pc.md`:
- ≤ 24 KB/s por cliente en el galpón;
- ≤ 40 KB/s con una salida afuera;
- ≤ 64 KB/s con 2 vehículos lejos (decisión mapa continuo, punto 6).
Si se pasa: lista de culpables, en orden.
**Hecho cuando:** los números están medidos y anotados con commit y fecha.

### D-2003 · Eventos de negocio por RPC confiable con número de secuencia — A · Opus 5.5 · xhigh · Aviso: sí (`network_manager.gd`) · F0
**Depende de:** D-2001, D-0210, D-0211
**Qué:** `scripts/core/company/company_net.gd` (hijo de `CompanyWorld`), con un solo RPC
`_apply_event(seq: int, kind: StringName, data: Dictionary)` (reliable, host → todos) y un RPC
`_request(kind, data)` (cliente → host, con `RpcGuard`).
- Cada evento modifica `Inventory`/`OrderBook`/`CompanyState` igual en todos.
- Si un cliente detecta un hueco en `seq`, pide un snapshot (D-2004).
- `PROTOCOL_VERSION` → siguiente número según §6.
**Test** `test_company_net`: 2 peers. El cliente pide mover 3 productos y el host lo valida y aplica en
los dos. Una petición inválida (más de lo que hay) se rechaza sin cambiar nada. 100 eventos seguidos dejan
`Inventory` igual en los dos (comparar `to_dict`).
**Hecho cuando:** el test pasa y `auditor-red` no tiene BUG/RIESGO alto.

### D-2004 · Join tardío y snapshot — A · Opus 5.5 · xhigh · Aviso: sí (`network_manager.gd`) · F0
**Depende de:** D-2003
**Qué:** al entrar un peer a mitad de día, el host manda `CompanyState.to_dict()` + `Inventory` +
`OrderBook` + layout + bloqueos + `seq` actual en un solo RPC comprimido (`var_to_bytes` +
`compress`). Tope de 64 KB; si pasa, se parte en trozos. El mismo snapshot sirve para recuperar huecos de
`seq`.
**Test** `test_company_late_join`: el peer 2 entra después de 50 eventos y queda igual que el host; un
snapshot de un galpón con 300 unidades de stock pesa < 64 KB.
**Hecho cuando:** el test pasa.

### D-2005 · El host se va a mitad de día — A · Opus 5.5 · high · Aviso: sí (`hud_pause.gd`, `level_base.gd` si se reusan) · F0
**Depende de:** D-2003, D-0206
**Qué:** como N-222. Cuando el host se desconecta, los clientes ven el resumen parcial del día y vuelven
al menú. El host, si sigue vivo (se cerró la sesión de red), **guarda** el estado al último evento
aplicado.
**Test** `test_company_host_leaves`: cortar el host a mitad de día deja a los clientes en el menú con el
resumen, sin errores. El save del host tiene el día en curso marcado `interrupted: true` y al cargarlo
arranca ese día desde la apertura.
**Hecho cuando:** el test pasa.

### D-2006 · Un cliente se cae y vuelve — B · Opus 5.5 · high · Aviso: sí (`network_manager.gd`) · F0
**Depende de:** D-2004
**Qué:** reusar el reingreso de N-221 (slot de color, `_displaced_players`). Lo que tenía en las manos
se suelta en el piso al caerse (evento `hands → floor`). Al volver recibe el snapshot.
**Test** `test_company_rejoin`: el cliente se cae con 2 productos en la mano. Los productos quedan en el
piso del host, el stock total no cambia y al volver ve el mismo stock.
**Hecho cuando:** el test pasa.

### D-2007 · `RpcGuard` en todos los RPC nuevos — A · Opus 5.5 · medium · Aviso: no · F0
**Depende de:** D-2003
**Qué:** ampliar el test de N-238 que recorre los RPC del proyecto para que incluya
`scripts/core/company/` y `scripts/gameplay/business/`. Cada `@rpc("any_peer")` debe pasar por
`RpcGuard`.
**Hecho cuando:** el test falla con un RPC nuevo sin guarda (se prueba agregando uno temporal dentro del
test) y pasa con el código real.

### D-2008 · `PROTOCOL_VERSION` de la expansión — A · Opus 5.5 · low · Aviso: sí (`network_manager.gd`) · F0
**Depende de:** D-2003
**Qué:** un solo aumento para el primer PR que agrega RPC de negocio. Los siguientes PRs de la expansión
que cambien RPC suben de nuevo según §6, y la tabla de §6 anota "expansión" en el motivo.
**Hecho cuando:** el número subió y `docs/convenciones-godot.md` §6 tiene la fila.

### D-2009 · Lobby de Steam con nombre de empresa y día — B · Opus 5.5 · medium · Aviso: sí (`net_session.gd`) · F0
**Depende de:** D-0202
**Qué:** metadata del lobby `company_name` y `company_day`. Rich presence `"Empresa <nombre> — día N"`
(texto traducible). Sin Steam (ENet), se ignora.
**Test:** la parte sin Steam: `test_company_lobby_meta` verifica que el diccionario de metadata se arma
bien con y sin empresa activa.
**Hecho cuando:** el test pasa. La prueba real con Steam queda para la build de la PC.

### D-2010 · Save de empresa en la nube de Steam — B · Opus 5.5 · medium · Aviso: no · F0
**Depende de:** D-0206, N-914
**Qué:** que `user://saves/company/` quede dentro de las rutas de Auto-Cloud que define N-914. Si N-914
no está hecha, anotar la ruta en su tarea.
**Hecho cuando:** la ruta figura en la configuración de Auto-Cloud documentada.

### D-2011 · `bench_company` en CI — A · Opus 5.5 · high · Aviso: sí (`.github/workflows/`) · F0
**Depende de:** D-0214
**Qué:** `tests/bench_company.gd`, como `bench_drive`.
- **Qué hace:** arranca el mundo de la empresa, recorre el galpón con la cámara por un camino fijo de
  30 s y después maneja 30 s hacia Barrio Centro.
- **Qué imprime:** `objects`, `nodes`, `draw_calls`, `physics_bodies`, ms por frame (p50, p95) y KB de
  memoria estática.
- **CI:** paso nuevo en `tests.yml` junto a "Measure rendered performance". Solo informa, no falla
  (los FPS de CI no valen).
**Hecho cuando:** CI imprime los números en un PR y la PC los puede repetir.

### D-2012 · Presupuesto de rendimiento — A · Opus 5.5 · medium · Aviso: no · F0
**Depende de:** D-2011
**Qué:** tabla en `docs/rendimiento-pc.md`, con la GPU de la PC y el preset medio:

| Situación | FPS | Draw calls | Cuerpos físicos activos | Nodos |
|---|---|---|---|---|
| Galpón por defecto | ≥ 90 | ≤ 900 | ≤ 400 | ≤ 6000 |
| Galpón grande lleno | ≥ 60 | — | — | — |
| Manejando por Centro | ≥ 75 | — | — | — |

Las PRs de la expansión que bajen más de 10 % la situación que tocan llevan "(perf)" y una tarea.
**Hecho cuando:** la tabla está y la primera fila tiene un número medido por `pc-build`.

### D-2013 · Sin fugas en un día y en diez — A · Opus 5.5 · high · Aviso: no · F0
**Depende de:** D-0214, D-2016
**Qué:** `tests/test_company_leaks.gd`. Corre `bot_company_day` 1 día y después 10 días seguidos
acelerados. Cuenta `Node.get_orphan_node_ids()` y `Performance.OBJECT_COUNT` al cierre de cada día.
**Hecho cuando:** los huérfanos son 0 y los objetos crecen < 2 % entre el día 2 y el 10.

### D-2014 · Filtros de tests de la expansión — A · Opus 5.5 · low · Aviso: no · F0
**Depende de:** —
**Qué:** convención de nombres. Todos los tests de la expansión empiezan con `test_company_`,
`test_zone_`, `test_fleet_`, `test_order_`, `test_box_`, `test_inventory`, `test_product_`, `test_gate_`
o `test_world_`. Documentar en `tools/run-tests.sh --help` (o su encabezado) que `company` es el filtro
de la expansión.
**Hecho cuando:** `tools/run-tests.sh company` corre los tests de la expansión que ya existan.

### D-2015 · Tests afectados en el `pre-push` — A · Opus 5.5 · low · Aviso: no · F0
**Depende de:** D-2014
**Qué:** el hook `pre-push` decide qué tests corren según las carpetas tocadas. Agregar el mapeo
`scripts/core/company/`, `scripts/gameplay/business|districts|fleet/`, `data/products|zones|vehicles|boxes|suppliers|gates/`
→ filtro `company`.
**Hecho cuando:** un push que toca solo `data/products/` corre los tests `company` y nada más (visible en
la salida del hook).

### D-2016 · Bot `bot_company_day` y guion de QA — A · Opus 5.5 · high · Aviso: no · F0
**Depende de:** D-0214 (se completa a medida que existen las piezas de F1)
**Qué:** `tools/bot_company_day.gd` (`extends SceneTree`). Juega el modo Empresa con N jugadores
simulados (peers ENet locales o actores locales).
- **Pasos:** recibir el palet del proveedor, guardar en estantes, tomar los pedidos, armar cajas,
  despachar, manejar con piloto automático por el grafo de calles (D-0304) hasta las casas, entregar,
  volver, cerrar el día.
- **Al final imprime:** plata, entregas, roturas, errores de armado, tiempo por etapa y una línea
  `BOT_OK` o `BOT_FAIL <motivo>`.
- **Guion:** un apartado "Modo Empresa" en `docs/qa-recorrido.md` para `probador-qa`.
- [ ] **D-2016.1** Esqueleto: arranca el mundo y espera el `OPENING`. Imprime `BOT_FAIL not_implemented:<etapa>`
  para cada etapa que todavía no existe, sin colgarse.
- [ ] **D-2016.2** Etapas, a medida que las tareas F1 se cierran (cada PR de F1 suma la suya).
**Hecho cuando:** con todo F1 cerrado imprime `BOT_OK` con 2 jugadores, y es el criterio de cierre de D-0111.

### D-2017 · QA de red par y trío en modo Empresa — B · Opus 5.5 · high · Aviso: no · F0
**Depende de:** D-2016, D-2003
**Qué:** variante de `bot_company_day` con 2 y 3 peers que comparan `CompanyState.to_dict()` al cierre
del día. El guion de `probador-qa` suma "Empresa en red".
**Hecho cuando:** los 3 peers terminan con el mismo diccionario y no hay `ERROR` en ninguno de los logs.

### D-2018 · Módulos nuevos en `portability-check.sh` — A · Opus 5.5 · low · Aviso: no · F0
**Depende de:** D-0220
**Qué:** cada `modules/<nuevo>/` (`day_clock`, `world_cells`, `inventory`, `order_queue`, `build_grid`)
tiene `module.cfg` y `tests/`, y `tools/portability-check.sh` lo recorre (si los descubre solo, verificar
que aparezcan en la salida).
**Hecho cuando:** CI muestra cada módulo nuevo pasando solo en un proyecto vacío.

### D-2019 · Build de Windows con la expansión — B · Opus 5.5 · medium · Aviso: no · F0
**Depende de:** D-0214
**Qué:** verificar que `export_presets.cfg` incluye `data/products|zones|vehicles|boxes|suppliers|gates/`
y `scenes/company/`; si filtra recursos, agregarlos. Pedido a la rutina `pc-build`.
**Hecho cuando:** la build de la PC arranca el modo Empresa (anotado en el informe de `pc-build`).

### D-2020 · Smoke del ejecutable en modo Empresa — B · Opus 5.5 · medium · Aviso: sí (`.github/workflows/release.yml`) · F0
**Depende de:** D-2019
**Qué:** el smoke de `release.yml` hoy arranca el juego. Agregar una segunda corrida con
`--autostart --mode=company` 20 s que falle si el log tiene `SCRIPT ERROR` o `ERROR`.
**Hecho cuando:** el workflow tiene el paso y pasa en la siguiente release.
