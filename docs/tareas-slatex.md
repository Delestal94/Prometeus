# Tareas de Slatex (Cristian) — Jugador, Paquetes, Interacción, UI y Progresión

> Última actualización: 2026-09-25 (estado relevado sobre `d15ad02`).
> Reescrita entera: las tareas 1-100 de la versión anterior están cerradas o reubicadas
> (ver "Qué pasó con la lista anterior" al final). Esta lista sigue los 9 pilares de
> producción de un videojuego y **solo tiene trabajo que Slatex puede terminar sin esperar
> a Nacho y sin playtesting**.
>
> División de dominios y zona compartida: `docs/colaboracion-equipo.md`.

## Cómo leer esta lista

- **ID**: `S-<pilar><número>` (S-101 es pilar 1, tarea 01). Las subtareas son `S-101.1`,
  `S-101.2`… y se marcan con `[ ]` / `[x]` a medida que se hacen.
- **Prio**: **A** hacer ya (cierra algo roto o a medias) · **B** suma valor claro ·
  **C** pulido.
- **Modelo**: qué modelo de ChatGPT usar y con qué esfuerzo (ver la sección siguiente).
- **Aviso**: `sí` = toca la zona compartida o un archivo de Nacho. No hay que esperarlo:
  se deja el aviso en `docs/colaboracion-equipo.md` **en el mismo commit**, con un cambio
  chico y aislado, siguiendo la regla de oro (agregar antes que cambiar firmas).
- **Hecho cuando**: el criterio verificable. Sin eso la tarea no se marca.
- **Sin playtesting**: todo lo que antes decía "falta playtesting" se reemplazó por una
  forma de medir con código (simuladores, bots, tests, benchmarks). Lo que
  genuinamente necesita gente jugando está al final, en "Para cuando haya playtesting",
  y **no se hace ahora**.

---

## Modelo recomendado (Cristian usa ChatGPT)

Datos a septiembre de 2026. Hoy conviven la generación **GPT-6** (Astra, Sol, Luna) y la
anterior **GPT-5.6** (Sol, Terra, Luna). Terra **no tiene versión GPT-6**. Todos aceptan
esfuerzo de razonamiento `none`, `low`, `medium` (por defecto), `high`, `xhigh` y `max`.

| Modelo | Cuándo usarlo en este proyecto | Esfuerzo |
|---|---|---|
| **GPT-6 Sol** (tu modelo por defecto) | Casi todo el código: una mecánica, un panel de UI, un test, un script de Blender. Rinde muy cerca de Astra en programación y cuesta mucho menos. | **high** para una tarea que toca 1-3 archivos. **xhigh** cuando toca 4 o más o cruza red (RPC). |
| **GPT-6 Astra** | Lo difícil de verdad: red y autoridad del host, refactors de archivos grandes (`player.gd`, `prototype_hud.gd`), diseñar el simulador de balance, diagnosticar un test que falla y no se entiende por qué. | **high**. Pasá a **xhigh** si falló una vez. **max** solo si xhigh falló dos veces. |
| **GPT-6 Luna** | Texto y datos: documentación, textos de la UI, traducción al inglés, notas de los paquetes, editar números en un `.tres`, redactar la página de Steam. | **medium**. **low** para cambios mecánicos (renombrar, formatear). |
| **GPT-5.6 Terra** | **No usarlo.** Es la generación anterior, sin reemplazo en GPT-6. Solo si tu plan no ofrece GPT-6: Terra en **high** en lugar de Sol. | — |

Si tu plan de ChatGPT no ofrece Astra, usá **Sol en xhigh** donde la lista diga Astra.
En cada tarea está anotado el modelo recomendado (por ejemplo `Sol · high`).

### Cómo trabajar una tarea con ChatGPT

ChatGPT no ve el repo ni corre Godot solo (salvo que uses Codex conectado al repo). Por eso:

1. **Contexto**: pegale siempre `CLAUDE.md`, `docs/convenciones-godot.md` §0-2 y los archivos
   que figuran en "Archivos" de la tarea, **enteros**. Si un archivo pasa de ~800 líneas,
   pegale solo las funciones que la tarea nombra, más la cabecera (`extends`, señales, `const`, `var`).
2. **Pedido**: copiá la tarea tal cual está acá (título, subtareas, "Cómo", "Hecho cuando").
   Plantilla:
   > Proyecto Godot 4.7, GDScript tipado, renderer GL Compatibility, red host-autoritativa.
   > Seguí el estilo de los archivos adjuntos (comentarios `##`, nombres en inglés, textos
   > de UI en español). Tarea: `<pegar tarea>`. Devolveme: (1) el diff completo por archivo,
   > (2) el test nuevo `tests/test_<tema>.gd` con el patrón `extends SceneTree` + `_expect` +
   > `quit(_failures)`, (3) la línea para la lista de tests del README.
3. **Verificar vos**: aplicá el cambio y corré `tools/run-tests.sh <filtro>` (por ejemplo
   `tools/run-tests.sh route_event`). Si algo falla, pegale a ChatGPT **solo** el resumen de
   fallas (`tools/run-tests.sh -v <filtro>`), no el log entero.
4. **Capturas** (`tests/render_*.gd`): necesitan ventana. Correlas vos y adjuntale la imagen a
   ChatGPT si hay que ajustar algo visual.
5. **Cerrar**: marcá `[x]` acá con el hash del commit, anotá el test en el README, y si hubo
   aviso, escribilo en `docs/colaboracion-equipo.md`. Commit en inglés con prefijo
   (`feat:`, `fix:`, `test:`, `docs:`…).

---

## Orden de ataque (hitos)

| Hito | Objetivo | Tareas |
|---|---|---|
| **M1 — Cerrar lo que está a medias** | Que ningún sistema del juego quede anunciado y sin terminar. | S-101, S-102, S-103, S-104, S-105, S-203, S-210, S-804 |
| **M2 — Base técnica para lo que sigue** | Partir los archivos gigantes antes de sumarles UI; red robusta. | S-201, S-202, S-204, S-206, S-209 |
| **M3 — Onboarding y UX** | Que alguien que nunca jugó entienda qué hacer sin que se lo expliquen. | S-106, S-107, S-501, S-502, S-504, S-505, S-506, S-508, S-510 |
| **M4 — Balance medido y juice** | Números justificados por simulación; fallas que den ganas de clipear. | S-108, S-109, S-110, S-111, S-301, S-302, S-310, S-401 a S-404, S-601 a S-604 |
| **M5 — Preparación de lanzamiento** | Inglés, tienda, capturas, logros. | S-509, S-306, S-901 a S-907, S-805 |

Dentro de un hito, el orden de la tabla es el recomendado.

---

## 1. Game Design

### S-101 · Terminar los eventos de ruta (hoy se anuncian y nunca se resuelven) — A · `Astra · high` para diseñar, `Sol · xhigh` para implementar · Aviso: sí (`run_manager.gd`)

**Problema real**: `RunManager.start_run()` llama `RouteEventManager.begin_random()` y el
HUD muestra el banner, pero **nadie llama nunca `resolve_active()`**. El evento queda activo
para siempre y, como `begin_event()` rechaza uno nuevo mientras hay otro activo, en toda la
sesión hay a lo sumo un evento, y no se puede resolver. Además `_emit_event()` emite solo en
local: si el host lo resolviera, los clientes no se enterarían.

**Archivos**: `scripts/core/route_event_manager.gd`, `scripts/core/run_manager.gd` (zona
compartida), `scripts/gameplay/package/package.gd`, `scripts/gameplay/package/package_feedback.gd`,
`scripts/ui/prototype_hud.gd`, `scripts/core/event_bus.gd` (solo si hace falta una señal nueva).

- [x] **S-101.1 Recortar el sorteo.** (commit `2287979`) Constante `ROUTE_POOL: Array[StringName]` con
  `inspection`, `impatient_client`, `mixed_labels`, `mimetic_package`, `parasite_box`.
  `rear_door_jam` (necesita las puertas del camión, dominio de Nacho) y `confusing_shop`
  (necesita la tienda en ruta) quedan en `EVENTS` pero **fuera del sorteo**, con un
  comentario que explique por qué. `begin_random()` sortea solo del pool.
- [x] **S-101.2 Duración y vencimiento.** (commit `2287979`) Cada evento suma `"duration"` (segundos, entre 45 y
  90) y `"fine"` (multa en dinero del equipo, entre 15 y 30). En `_physics_process`, **solo en
  el host** y solo con `RunManager.is_running`, descontar el tiempo; al llegar a 0 resolver con
  `success = false` y cobrar la multa con `CrewProgression.spend(mini(fine, team_money))`
  (la plata nunca queda negativa). Al terminar la partida (`run_ended`) cualquier evento activo
  se cierra como fallido sin multa, y `reset_route()` corre en cada `start_run`.
- [x] **S-101.3 Resolver en red.** (commit `2287979`) Reemplazar `_emit_event` por `EventBus.relay(...)` para
  `route_event_started`, `route_event_updated` y `route_event_resolved`, así el host decide y
  todos lo ven. Revisar que `_remote_start_run` en `run_manager.gd` no dispare el evento dos
  veces en el cliente (hoy el cliente lo reinicia con `begin_event`; con relay alcanza con que
  el cliente copie el estado sin volver a emitirlo).
- [x] **S-101.4 Inspección sorpresa.** (commit `2287979`) A los `duration - 15` s el host evalúa: toda caja del grupo
  `cargo` que siga en carga está `is_loaded` y no `is_open`. Si se cumple, éxito: dinero al
  equipo y mérito (`award_action`) para cada jugador sentado en un asiento de pasajero. Si no,
  multa. Mientras tanto, `route_event_updated` manda `{"loose": n}` para que el HUD muestre
  "Faltan asegurar 2 cajas".
- [x] **S-101.5 Cliente impaciente.** (commit `2287979`) Al empezar, elegir una casa del pedido (escuchar
  `houses_assigned`, que ya existe). Éxito si llega `house_delivery_recorded` para esa casa con
  resultado intacto antes del vencimiento. Si falla, además de la multa, poner
  `RunManager.results["time_bonus"] = 0` al cerrar (agregar una bandera `lost_time_bonus`
  en `RunManager`, no tocar la fórmula).
- [x] **S-101.6 Etiquetas mezcladas.** (commit `2287979`) Se activa con el primer `vehicle_impact` fuerte después de
  sortear el evento. El host elige dos cajas en carga y **intercambia solo la etiqueta visible**
  (el `Label3D` del contenido declarado en `package_feedback.gd`, más una marca "?" en el HUD):
  la carga real y el pedido no cambian. Se resuelve cuando alguien abrió (T) **las dos** cajas
  (el contenido real se ve al abrir). Mérito para quien abrió la segunda. Propiedad nueva
  replicada en `package.gd`: `label_swapped_with: StringName`.
- [x] **S-101.7 Paquete mimético.** (commit `2287979`) El host elige una caja en carga y le pone
  `disguise_trap_id` (replicado): el HUD y la caja muestran el ícono y el nombre de otra trampa
  de igual o menor dificultad. El primer impacto por encima de `impact_threshold_light` la
  revela (partículas + sonido). Éxito si 20 s después de revelarse no está arruinada.
- [x] **S-101.8 Caja parásita.** (commit `2287979`) El host enlaza dos cajas montadas: cada punto de daño que recibe
  una se le aplica al 50 % a la otra. Para separarlas, dos jugadores distintos tienen que mantener
  la acción primaria (`steady`) sobre una caja cada uno durante 2 s a la vez (usar lo que ya llega
  por `submit_tender_input`). Solo, en solitario, este evento no se sortea (`NetworkManager.peer_ids.size() < 2`).
- [x] **S-101.9 HUD.** (commit `2287979`) El banner del evento (`event_label`) pasa a tener tres partes: título,
  objetivo y cuenta regresiva, y se actualiza con `route_event_updated`. Tiene su propia zona
  (ver S-501): no comparte línea con el aviso de interacción.
- [x] **S-101.10 Tests.** (commit `2287979`) `tests/test_route_events.gd`: cada uno de los 5 eventos del pool se
  resuelve bien y vence mal; un evento no queda activo después de `run_ended`; la multa nunca deja
  la plata negativa; en solitario no sale `parasite_box`. Actualizar `test_route_event_manager.gd`.

**Hecho cuando**: una partida con el nivel de entrega sortea un evento, lo muestra con cuenta
regresiva, y termina resuelto o vencido en todos los casos; tests verdes.

### S-102 · Mérito individual por acciones reales — A · `Sol · xhigh` · Aviso: sí (`run_manager.gd`)

**Problema real**: `CrewProgression.award_action()` solo lo llama el evento de ruta (que nunca se
resuelve, S-101). Hoy nadie gana mérito nunca, y `merit_changed` se emite en local, así que un
cliente tampoco vería el suyo.

**Archivos**: `scripts/core/crew_progression.gd`, `scripts/gameplay/package/package.gd`, las
trampas en `scripts/gameplay/traps/`, `scripts/ui/prototype_hud.gd`.

- [x] **S-102.1 Saber quién hizo qué.** (commit `e3928bb`) En `package.gd`, guardar en el host el último peer que
  mandó input útil (`_last_tender_peer`, con `multiplayer.get_remote_sender_id()` o el id local si
  es 0) y el último que la tuvo en la mano.
- [x] **S-102.2 Hitos desde las trampas.** (commit `e3928bb`) Agregar a `i_trap_behavior.gd` una función
  `take_milestones() -> Array[StringName]` (por defecto vacía) que cada trampa llena cuando pasa
  algo meritorio, y el paquete la consume cada frame en el host. Hitos: `defused` (Explosivo
  desactivado), `calmed` (Hostil o Ruidoso vuelve de riesgo a OK), `dried` (Líquido: charco en 0
  después de haber pasado 30), `leveled` (Equilibrio vuelve a OK desde riesgo),
  `sequence` (Peso creciente resuelto).
- [x] **S-102.3 Hitos desde el paquete.** (commit `e3928bb`) `rescued`: alguien levanta una caja que estaba en el piso
  fuera del camión durante la partida y la vuelve a montar. `handover`: traspaso mano a mano.
  `photo_saved`: la foto de entrega anuló un reclamo (escuchar `delivery_photo_taken`).
- [x] **S-102.4 Tabla de puntos** (commit `e3928bb`) en `crew_progression.gd`: `MERIT_POINTS := {&"defused": 25,
  &"rescued": 20, &"calmed": 10, &"dried": 10, &"leveled": 8, &"sequence": 8, &"handover": 5,
  &"photo_saved": 15}`. El `action_id` tiene que ser único por hecho:
  `"%s:%s:%d" % [package_id, milestone, contador]`, así un mismo hito no se cobra dos veces.
- [x] **S-102.5 Red.** (commit `e3928bb`) `merit_changed` y `card_changed` pasan por `EventBus.relay`.
- [x] **S-102.6 Test** (commit `e3928bb`) `tests/test_merit.gd`: cada hito suma lo de la tabla una sola vez; el mérito
  va al peer correcto; un hito repetido en el mismo frame no duplica.

**Hecho cuando**: jugando solo, desactivar un explosivo muestra "Mérito +25" y el total aparece en
resultados (S-508).

### S-103 · Cartas: dejar solo las que se pueden usar y hacerlas usables — A · `Sol · xhigh` · Aviso: sí (`project.godot`, acción nueva)

**Problema real**: `_grant_card_chance()` reparte cartas, el HUD dice "Carta obtenida", y no hay
ninguna forma de usarlas. Prioridad e Información dependen de una tienda en ruta que no existe.

**Decisión de alcance (control de scope, ya tomada)**: para el MVP quedan **Rescate**,
**Descuento** y **Re-voto**. Prioridad e Información salen del reparto (sus valores del enum se
conservan para no romper nada guardado).

- [x] **S-103.1** (commit `955e585`) `CrewProgression.DRAWABLE_CARDS := [Card.RESCUE, Card.DISCOUNT, Card.REVOTE]`;
  `_grant_card_chance` sortea solo de ahí. Borrar `priority_issued` si queda sin uso.
- [x] **S-103.2 Acción `use_card`** (commit `955e585`) en `project.godot` (G / D-pad izquierda) y reasignable en
  `GameSettings` como las demás. Aviso por `project.godot`.
- [x] **S-103.3 Rescate en partida** (commit `955e585`): con un evento de ruta activo, `use_card` manda una RPC al host
  (`CrewProgression.request_use_card`, `@rpc("any_peer")`), que llama
  `RouteEventManager.use_rescue(peer)`. Sin evento activo, el HUD dice "No hay nada que rescatar".
- [x] **S-103.4 Descuento y Re-voto en el depósito** (commit `955e585`): botones en la sección de suministros de
  `depot_panel.gd`, visibles solo si el jugador tiene esa carta (ver S-104).
- [x] **S-103.5 HUD** (commit `955e585`): ficha con el nombre de la carta en la esquina de dinero y la tecla para usarla
  (`UiTheme.keycaps`). El toast "Carta obtenida" pasa a decir cuál.
- [x] **S-103.6 Test** (commit `955e585`) `tests/test_cards.gd`: nunca sale Prioridad ni Información; Rescate resuelve el
  evento activo y se consume; sin evento no se consume.

### S-104 · Votación de suministros en el depósito — A · `Sol · xhigh` · Aviso: no

**Problema real**: `ShopVoteManager` está completo pero `open_shop()` no se llama nunca. En el
mostrador de suministros compra el que llega primero.

**Archivos**: `scripts/core/shop_vote_manager.gd`, `scripts/ui/depot_panel.gd`. **No hace falta
tocar `depot.gd`**: la compra final se sigue haciendo con `depot.buy_supply(id)` en el host.

- [x] **S-104.1** (commit `c05ed44`) En `shop_vote_manager.gd`: `request_vote(offer_id)` con `@rpc("any_peer")` que en el
  host valida y llama `vote(sender, offer_id)`; `resolve_winner(peers) -> StringName` que decide
  **sin gastar** (la plata la descuenta `depot.buy_supply`, para no cobrar dos veces). Empate: gana la
  oferta más barata. Nadie votó: no se compra nada.
- [x] **S-104.2** (commit `c05ed44`) El host abre la votación (`open_shop(CrewProgression.SUPPLIES)`) la primera vez que
  alguien abre el mostrador en el depósito, y la cierra cuando votaron todos los conectados o a los
  20 s del primer voto. Al cerrar: `depot.buy_supply(ganador)`.
- [x] **S-104.3** (commit `c05ed44`) En solitario no hay votación: el botón compra directo como hoy.
- [x] **S-104.4** (commit `c05ed44`) UI: cada oferta muestra quién la votó (círculos con el color de cada jugador) y la
  cuenta regresiva; Descuento (S-103) aparece como botón "Usar Descuento (−50 %)" sobre la oferta
  ganadora; Re-voto borra los votos.
- [x] **S-104.5 Test** (commit `c05ed44`) `tests/test_supply_vote.gd` (con `ShopVoteManager` y `CrewProgression`
  instanciados sin red, como `test_shop_vote_manager.gd`): gana la mayoría, empate a la más barata,
  el dinero se descuenta una sola vez.

### S-105 · Guardar la campaña cooperativa — A · `Sol · high` · Aviso: no

**Problema real**: el dinero, las cartas y el mérito viven en memoria: al cerrar el juego se
pierden y la economía no significa nada entre sesiones.

- [x] **S-105.1** (commit `c694bdf`) `CrewProgression.save_campaign()` / `load_campaign()` en `user://crew_campaign.json`
  (dinero, suministros pendientes, cartas y mérito **por color de jugador**, no por peer id, porque el
  id cambia en cada conexión). Mismo patrón que `unlock_manager.gd`, con `version: 1`.
- [x] **S-105.2** (commit `c694bdf`) Guarda el host al terminar cada partida y al comprar. En línea manda la campaña del
  host; los clientes no escriben la suya.
- [x] **S-105.3** (commit `c694bdf`) Botón "Empezar campaña nueva" en `progress_panel.gd`, con confirmación.
- [x] **S-105.4** (commit `c694bdf`) Escritura segura (ver S-210).
- [x] **S-105.5 Test** (commit `c694bdf`) `tests/test_crew_campaign_save.gd`: guarda, recarga, conserva; archivo corrupto
  no rompe y arranca con $100.

### S-106 · Introducción gradual de trampas desde el perfil — A · `Sol · high` · Aviso: no

`docs/economia-y-contramedidas.md` dice que las primeras entregas presentan solo Frágil y
Equilibrio. Hoy las 4 básicas salen desde la primera partida.

- [x] **S-106.1** (commit `2a2ad10`) Sumar a `UnlockManager.UNLOCKS`: `growing_weight_trap` (1 entrega, 0 pts) y
  `noisy_trap` (2 entregas, 100 pts); agregarlas a `TRAP_UNLOCKS`. Correr los umbrales siguientes para
  que la curva quede: Frágil+Equilibrio → Peso creciente (1) → Ruidoso (2) → Líquido (4) → Explosivo (8)
  → Hostil (13).
- [x] **S-106.2** (commit `2a2ad10`) `PROFILE_VERSION` 3: un perfil que ya supera los umbrales nuevos los recibe
  desbloqueados al cargar (no quitarle nada a nadie).
- [x] **S-106.3** (commit `2a2ad10`) Verificar que con solo 2 trampas (4 cajas) siempre alcanzan para las casas
  (`max(jugadores - 1, 1)`, máximo 4). Si no alcanza, `locked_traps()` libera la trampa de menor
  dificultad que falte. Test en `test_locked_traps.gd`.
- [x] **S-106.4** (commit `2a2ad10`) Actualizar `docs/plan-desarrollo.md` Fase 5 con la curva nueva.

### S-107 · Reglas de dificultad para armar el pedido — B · `Sol · high` · Aviso: sí (una línea en `depot.gd`)

Pendiente de `docs/controles-y-ui.md` ("la selección semi-aleatoria y sus reglas de balance
siguen pendientes").

- [ ] **S-107.1** Módulo puro `scripts/gameplay/traps/order_balancer.gd` (`class_name OrderBalancer`,
  funciones `static`): recibe trampas disponibles (`TrapDefinition`), cantidad de casas, partidas
  completadas del perfil y un `RandomNumberGenerator` con la semilla de la sesión; devuelve la lista de
  ids de trampa por casa.
- [ ] **S-107.2** Reglas: suma de `difficulty` del pedido ≤ `4 + casas + min(completed_runs, 6)`;
  nunca dos de dificultad 4 juntas antes de 10 partidas; no repetir trampa mientras haya distintas
  disponibles; siempre al menos una de dificultad ≤ 2.
- [ ] **S-107.3** Integración: `depot.gd` `post_orders()` usa el resultado para elegir la caja de cada
  casa. Es un cambio de 3-5 líneas en un archivo de Nacho: aviso en `colaboracion-equipo.md`.
- [ ] **S-107.4** Test `tests/test_order_balancer.gd`: 1000 semillas por cantidad de casas, ninguna
  rompe las reglas; la misma semilla da el mismo pedido (todos los peers calculan igual).

### S-108 · Simulador de balance de trampas (reemplaza al playtesting de balance) — A · `Astra · xhigh` para diseñarlo, `Sol · high` para implementarlo · Aviso: no

Cierra lo que antes era "#41/#51/#59/#67: falta playtesting". No mide diversión: mide si cada
trampa es **perdible, ganable y con momentos de casi-perder**, que es lo que `parametros-diseno.md`
pide de los números.

- [ ] **S-108.1 Grabar manejo real.** `tests/sim_record_drive.gd`: maneja el camión de verdad por una
  ruta (mismo conductor automático que `test_vehicle_stress.gd`, pero respetando curvas) y guarda por
  frame de física lo que las trampas reciben: aceleración, inclinación de la caja, impactos (delta de
  velocidad). Salida: `tests/sim_data/drive_<semilla>.json`. 5 semillas.
- [ ] **S-108.2 Pasajeros bot.** Tres perfiles: *ausente* (no toca nada), *torpe* (reacciona con
  0,8 s de retraso, acierta 60 % de las secuencias, suelta el botón 20 % del tiempo) y *experto*
  (0,25 s, 95 %). Cada perfil también con +150 ms de latencia de red simulada.
- [ ] **S-108.3 Simulador.** `tests/sim_trap_balance.gd` (no va en la batería, como `bench_drive.gd`):
  para cada `data/traps/*.tres` × perfil × manejo grabado, corre el `ITrapBehavior` real 50 veces y
  anota % arruinadas, segundos en riesgo, y *casi-pérdidas* (integridad mínima entre 5 y 25 sin llegar a
  0). Imprime una tabla y la guarda en `tests/sim_data/balance_report.md`.
- [ ] **S-108.4 Objetivos** (escribirlos en `docs/parametros-diseno.md` antes de ajustar):
  ausente arruina 80-100 %; torpe 30-55 % con al menos 1 casi-pérdida por viaje; experto < 12 %.
  La latencia de 150 ms no puede subir el % del experto más de 8 puntos.
- [ ] **S-108.5 Ajustar** los `params` de los `.tres` hasta cumplir los objetivos (sin tocar scripts de
  trampa) y documentar valor viejo → nuevo y por qué en `parametros-diseno.md`.

**Hecho cuando**: el reporte muestra las 7 trampas dentro de los objetivos y el doc lo explica.

### S-109 · Algo que hacer cuando tu paquete ya se arruinó — A · `Sol · xhigh` · Aviso: no

`docs/critica-diseno-abogado-del-diablo.md` §6: quien pierde su caja pasa el resto del viaje sin
hacer nada. El modo espectador ayuda a mirar, no a jugar.

- [ ] **S-109.1 Ayudante.** Un paquete acepta input de hasta **dos** peers: el que lo atiende y un
  ayudante (otro jugador sentado en un asiento contiguo o a pie a menos de 1,5 m). En `package.gd`,
  `submit_tender_input` guarda el input por peer y combina: `steady`/`calm` del ayudante suman 50 % de
  la fuerza; las secuencias (Explosivo, Peso creciente) las puede completar cualquiera de los dos.
- [ ] **S-109.2** El aviso de interacción muestra "Ayudar con la caja de <color>" y el ayudante gana el
  hito `assist` (5 de mérito cada 10 s ayudando con la caja en riesgo).
- [ ] **S-109.3** Hostil pasa a pedir dos personas en su fase difícil: CALMÁ necesita la suma de dos
  inputs para bajar rápido (dato en `hostile.tres`, no código especial).
- [ ] **S-109.4** Test `tests/test_assist.gd`: dos peers simulados atienden la misma caja; la corrección
  combinada es la esperada; un tercer peer es ignorado.

### S-110 · Medir cuánto dura una entrega (regla de oro de 2-5 min) — B · `Sol · high` · Aviso: no (solo informa a Nacho)

- [ ] **S-110.1** `tests/bench_delivery_time.gd`: con el conductor automático de S-108.1 y un bot que
  baja, camina y toca el timbre, medir el tiempo total de una entrega con 1, 2, 3 y 4 casas, a
  velocidad de crucero.
- [ ] **S-110.2** Escribir el resultado en `docs/parametros-diseno.md` ("Duración medida") y dejar aviso
  a Nacho en `colaboracion-equipo.md` con los números. Ajustar el largo de la ruta es de Nacho: esta
  tarea termina al entregar la medición, no espera su respuesta.

### S-111 · Congelado breve al arruinarse una caja (el "slow-mo" pendiente) — C · `Sol · high` · Aviso: no

`requerimientos-tecnicos.md` §3.4 lo deja pendiente porque `Engine.time_scale` rompe la física
del host. Hacerlo **solo visual y local**:

- [ ] 0,35 s en los que las partículas de ruina (`package_feedback.gd`) corren a `speed_scale = 0.15`,
  un destello blanco suave en la viñeta del HUD y un golpe de sonido grave. La física no cambia.
- [ ] Opción "Efectos de impacto" en opciones para apagarlo (accesibilidad, ver S-502).
- [ ] Test: tras `package_ruined` el `Engine.time_scale` sigue en 1.0 y las partículas vuelven a 1.0.

---

## 2. Programación y arquitectura técnica

### S-201 · Partir `prototype_hud.gd` (1176 líneas) en componentes — A · `Astra · high` · Aviso: no

Antes de sumar todo lo de UX (pilar 5), porque cada tarea de UI toca este archivo.

- [x] (commits `d324ecd`, `780a489`, `15ede48`, `44ff262`, `f70b064`) **S-201.1** Listar qué usan los tests del HUD (`grep -n "hud\." tests/test_hud_flow.gd` y los
  demás) para no romper esos nombres.
- [x] (commits `d324ecd`, `780a489`, `15ede48`, `44ff262`, `f70b064`) **S-201.2** Crear `scripts/ui/hud/`: `hud_cargo_panel.gd` (filas de carga e íconos),
  `hud_prompts.gd` (interacción, tapa de caja, atajos), `hud_notices.gd` (toasts, eventos, pings,
  avisos del depósito), `hud_results.gd` (pantalla de resultados), `hud_pause.gd` (pausa).
  `prototype_hud.gd` queda como el que los arma y conecta señales (objetivo: < 350 líneas).
- [x] (commits `d324ecd`, `780a489`, `15ede48`, `44ff262`, `f70b064`) **S-201.3** Mover **sin cambiar comportamiento**. Un commit por componente, tests del HUD verdes
  en cada uno (`tools/run-tests.sh hud score spectator ping`).
- [x] (commit `f70b064`) **S-201.4** Captura con `tests/render_hud.gd` antes y después: tienen que verse iguales.

### S-202 · Partir `player.gd` (1131 líneas) — B · `Astra · high` · Aviso: no

- [ ] Separar en nodos hijos con script propio: `player_interaction.gd` (alcance, avisos, E),
  `player_carry.gd` (caja en mano), `player_seat_pose.gd` (pose sentado, manos que atienden).
- [ ] **Las funciones `@rpc` se quedan en `player.gd`** (Godot resuelve la RPC por la ruta del nodo; si
  se mueven, se rompe la red). Esas funciones solo delegan.
- [ ] Tests verdes: `tools/run-tests.sh interaction seat carry player driver look`.

### S-203 · Detectar camión atascado también en el modo entrega — A · `Sol · high` · Aviso: sí (`level_base.gd`)

Nacho encontró (su #97) que el camión puede quedar encajado sin volcar ni salir de la ruta;
`level_endless.gd` ya lo detecta, `level_base.gd` no.

- [x] (commit `204cfdc`) Copiar la misma regla (6 s casi quieto con el motor pedido → termina la partida con "La
  camioneta quedó atascada"), **sin** contar el tiempo parado en el depósito, en una casa, o con el
  conductor fuera del asiento.
- [x] (commit `204cfdc`) Test en `test_stuck_detection.gd`: parado en depósito, casa o sin conductor no dispara;
  encajado contra un obstáculo con el acelerador pedido sí.

### S-204 · Test automático de dos procesos (reemplaza "requiere playtest de red") — A · `Astra · xhigh` · Aviso: no

Cierra lo que quedaba de #79 (cosméticos en dos clientes) y #96 (dos jugadores con el mismo objeto).

- [ ] **S-204.1** `tests/net_pair.gd`, sobre el patrón de `tests/net_smoke.gd` (ENet en localhost,
  `--host` / `--client`): el host carga `level_base.tscn`; el cliente se une con un uniforme elegido.
- [ ] **S-204.2** Chequeos: el host ve el `cosmetic_id` del cliente; los dos intentan agarrar la misma
  caja en el mismo frame y solo uno la tiene; el cliente se sienta en un asiento ocupado y es rechazado;
  el cliente suelta una caja a mitad de traspaso y queda en el piso en los dos procesos.
- [ ] **S-204.3** `tools/run-net-pair.sh` que lanza los dos procesos y junta los códigos de salida.
  Agregarlo a CI como job aparte si tarda < 60 s.

### S-205 · Respuesta inmediata al mantener, aunque haya lag — B · `Astra · high` · Aviso: no

- [ ] Verificar si en un cliente la barra, el aviso de la trampa y las manos del asiento reaccionan al
  presionar o recién cuando vuelve el estado del host. Probarlo con latencia artificial: opción de
  depuración `--fake-lag=150` que retrasa `submit_tender_input` en `package.gd` (solo en build de debug).
- [ ] Si esperan al host: mostrar localmente el "estoy sosteniendo" (manos, brillo del botón, sonido)
  al instante y dejar que la integridad siga viniendo del host.
- [ ] Test con el retraso activado: la pose de manos cambia el mismo frame del input.

### S-206 · Errores de conexión que un jugador entienda — A · `Sol · high` · Aviso: sí (`network_manager.gd`)

- [ ] **S-206.1** `NetworkManager.PROTOCOL_VERSION := 1` y enviarla en el handshake. Si no coincide, el
  host rechaza con motivo `version`. (El handshake ya cambió dos veces y hoy un cliente viejo solo ve un
  timeout.)
- [ ] **S-206.2** En `main_menu.gd`, `_on_session_failed(reason)` traduce cada motivo a un texto con
  qué hacer: "El anfitrión tiene otra versión del juego: actualicen los dos", "No hubo respuesta en 8 s:
  revisá la IP y que el firewall de Windows permita Take My Package (ver README)", "La sala está llena".
- [ ] **S-206.3** Test `tests/test_connection_errors.gd`: cada motivo muestra su texto.

### S-207 · Unirse por código corto en LAN — C · `Sol · high` · Aviso: no

- [ ] `scripts/ui/room_code.gd` (estático): IPv4 + puerto ↔ código de 8 caracteres sin letras ambiguas
  (sin O/0/I/1). El HUD del anfitrión muestra el código en vez de la IP; "Unirse" acepta código o IP.
- [ ] Test: ida y vuelta para 1000 direcciones; un código mal tipeado se rechaza con mensaje.

### S-208 · Rendimiento del dominio de Slatex — B · `Sol · high` · Aviso: no

- [ ] `tests/bench_depot.gd`: depósito con 14 cajas y 5 jugadores simulados, 600 frames; medir
  `Performance.TIME_PROCESS` y el tiempo de `package_feedback.gd` y del HUD.
- [ ] Meta: < 1,5 ms por frame entre paquetes + HUD. Candidatos típicos: labels que reescriben
  `text` cada frame aunque no cambió (causa relayout), `find_child` en `_process`, materiales duplicados.
- [ ] Resultado anotado en el README → Rendimiento.

### S-209 · Jugador que se desconecta en medio de la partida — A · `Astra · high` · Aviso: sí (`level_base.gd`)

- [x] (commits `c77194f`, `d20df06`) Cuando un peer se va: su caja en mano queda en el piso donde estaba; si estaba sentado, el
  asiento se libera; si conducía, el camión frena solo; su casa asignada sigue esperando.
- [ ] Probarlo con `tests/net_pair.gd` (S-204): el cliente se cierra con caja en mano y el host sigue sin
  errores.

### S-210 · Guardados que no se corrompen — A · `Sol · high` · Aviso: sí (`run_manager.gd` para el leaderboard)

- [x] (commit `c694bdf`) Función común `scripts/core/safe_json.gd`: escribe en `<archivo>.tmp` y renombra
  (`DirAccess.rename`), así un corte de luz no deja el archivo a medias; al leer, si el JSON es
  inválido, lo renombra a `<archivo>.bad` y devuelve el valor por defecto.
- [x] (commit `11328c1`) Usarla en `unlock_manager.gd`, en la campaña (S-105) y en el leaderboard de `run_manager.gd`.
- [x] (commit `11328c1`) Test `tests/test_safe_json.gd`: archivo truncado → no crashea, crea `.bad`, perfil por defecto.

---

## 3. Arte y dirección visual

### S-301 · Íconos de Líquido, Explosivo y Hostil — A · `Luna · medium` para el prompt, generación de imagen aparte · Aviso: no

Hoy el HUD tiene ícono para 4 de las 7 trampas (`assets/ui/icons/tx_ui_trap_*_256.png`).

- [ ] Generarlos con el mismo estilo que los 4 existentes: `art/tools/comfy_generate.py` con
  `art/prompts/estilo-base.md` (o la generación de imágenes de ChatGPT, pasándole los 4 íconos de
  referencia). 256×256, fondo transparente, silueta legible a 42 px.
- [ ] Nombres: `tx_ui_trap_liquid_256.png`, `tx_ui_trap_explosive_256.png`, `tx_ui_trap_hostile_256.png`.
  Mapearlos en `UiTheme.trap_icon()`.
- [ ] Registrar cada imagen en `art/ai-registro.md` (declaración de IA de Steam) y en
  `docs/inventario-assets.md` §1.
- [ ] Test `tests/test_trap_icons.gd`: cada `data/traps/*.tres` tiene ícono propio (ninguno cae en el
  genérico).

### S-302 · Contenidos propios para cada trampa — B · `Sol · high` (Blender Python) · Aviso: no

Hoy Equilibrio, Líquido y Explosivo llevan la **misma** torta de bodas y Ruidoso y Hostil la
**misma** gallina (`data/traps/*.tres` → `contents`).

- [ ] Modelos nuevos con `assets/tools/build_cargo_packages.py` (mismo esquema de nodos `Filler`,
  `Intact`, `Damage`, `Ruined`): **Líquido** → bidón de leche de vidrio; **Explosivo** → caja de fuegos
  artificiales; **Hostil** → mapache en una jaula de mimbre; **Equilibrio** → torre de copas (la torta
  queda como segunda opción).
- [ ] Un `.tres` en `data/contents/` por modelo y agregarlo al `contents` de su trampa. Segundo
  contenido para Frágil (lámpara antigua) y Ruidoso (cachorro) para que no se repitan siempre.
- [ ] Capturas con `tests/render_packages.gd` (necesita ventana: las corrés vos).
- [ ] `test_package_unboxing.gd` ampliado: cada contenido tiene los 4 nodos.

### S-303 · Íconos de acción del HUD — B · generación de imagen + `Sol · high` para integrar · Aviso: no

- [ ] Agarrar, soltar, sentarse, timbre, foto, bocina, ping, abrir caja, usar carta. 128×128, mismo
  estilo que los de trampa. `assets/ui/icons/tx_ui_action_<acción>_128.png`.
- [ ] `UiTheme.action_icon(id)`; los avisos de interacción muestran ícono + tecla + texto corto.

### S-304 · Celular en la mano y marco de la cámara — B · `Sol · high` · Aviso: sí (`presentation/phone_camera.gd` no tiene dueño en el reparto)

- [ ] Mostrar `models/props/handheld/sm_prop_phone.glb` en la mano derecha del viewmodel mientras la
  cámara del celular está abierta (hoy el GLB está sin usar, `inventario-assets.md` §2). **Ojo
  (2026-09-24):** ya no hay manos de primera persona (pedido del usuario: nada de manos que no sean
  del personaje), así que el celular no puede colgar de una; ver aviso en `colaboracion-equipo.md`.
- [ ] Marco de UI del celular (bordes redondeados, hora, batería, botón de obturador) como `Control`
  en `scripts/ui/phone_frame.gd`.

### S-305 · Accesorios cosméticos 3D — C · `Sol · high` · Aviso: no

- [ ] 4 accesorios low-poly con script de Blender: gorra, chaleco reflectivo, casco de obra, mochila
  térmica. `models/characters/accessories/`.
- [ ] Engancharlos con `BoneAttachment3D` (cabeza / columna) en `player.tscn`, uno por categoría.
- [ ] Desbloqueos en `UnlockManager.COSMETICS` y columna nueva en `cosmetics_panel.gd`; replicar
  `accessory_id` como `cosmetic_id`.

### S-306 · Logo como imagen — B · generación de imagen + `Luna · medium` · Aviso: no

- [ ] Wordmark "TAKE MY PACKAGE" en PNG transparente 2048 px de ancho, a partir de `UiTheme.logo()`
  (Lilita One + cinta amarilla), más una versión apilada cuadrada. `assets/ui/logo/`.
- [ ] Usarlo en el menú en lugar del logo armado con tipografía. Es la base de las cápsulas (S-903).

### S-307 · Ilustración de fondo de resultados — C · generación de imagen · Aviso: no

- [ ] La tripulación frente a la furgoneta al terminar la ruta, 1920×1080, con zona libre a la
  izquierda para el puntaje. Registrar en `art/ai-registro.md`.

### S-308 · Animaciones de emote — C · `Sol · high` (Blender Python) · Aviso: no

- [ ] Saludar, señalar, pulgar arriba, agarrarse la cabeza: 4 animaciones cortas agregadas al GLB del
  jugador. Desde el 2026-09-24 el jugador es el personaje redondeado de Astra: se suman como
  poses nuevas en `art/rounded_character/build_game_export.py` (ver `assets/README.md`,
  "Personajes"). Las dispara la rueda de pings (S-505).

### S-309 · Mantener al día la dirección visual del dominio — A · `Luna · medium` · Aviso: sí (`especificaciones-visuales.md`, filas propias)

- [ ] Actualizar filas de jugador/paquetes/UI en `docs/especificaciones-visuales.md` y
  `docs/inventario-assets.md` §1-3 cada vez que se cierra una tarea de este pilar (antes #99).

### S-310 · Fallas distintas por trampa (momentos para clipear) — B · `Sol · high` · Aviso: no

Hoy toda caja arruinada tira el mismo confeti de cubitos.

- [ ] En `package_feedback.gd`, un efecto por trampa: Frágil → esquirlas de porcelana; Líquido →
  salpicadura y charco en el piso; Explosivo → estallido de confeti y humo de colores (nada de fuego
  realista); Ruidoso y Hostil → el animal salta de la caja y escapa corriendo 3 s con física simple;
  Equilibrio → la torre se derrumba en piezas; Peso creciente → la caja se hunde con un golpe seco.
- [ ] Cada efecto dura < 2 s y se libera solo. Test en `test_ruin_feedback.gd` por trampa.

---

## 4. Audio y diseño sonoro

### S-401 · Sonidos de interfaz — A · `Sol · high` · Aviso: no

- [ ] `scripts/ui/ui_sounds.gd` (autocontenido, **sin tocar `synth_audio.gd`**, que es zona
  compartida): pasar el mouse, clic, abrir y cerrar panel, toast, desbloqueo, voto, error. Sintetizados
  igual que `SynthAudio` (generar `AudioStreamWAV` en código), por el bus `SFX`.
- [ ] `UiTheme.button()` conecta hover/press automáticamente, así todos los botones suenan.
- [ ] Test: cada botón de `main_menu.gd` tiene el sonido conectado; el volumen de efectos lo afecta.

### S-402 · Voces sin palabras ("gibberish") — B · `Sol · xhigh` · Aviso: no

**Actuación de voz (decisión)**: el MVP no tiene voces grabadas (costo, localización). En su
lugar, balbuceo sintetizado estilo Animal Crossing, con tono propio por color de jugador.

- [ ] Síntesis de sílabas con formantes (3-4 vocales, 60-120 ms cada una), tono base por
  `PLAYER_COLORS`, por el bus `Voice`. En `scripts/gameplay/player/player_voice.gd`.
- [ ] Disparadores: ping (según la opción de la rueda), golpe fuerte (el flinch de la vieja #12), ragdoll, entrega
  intacta, caja arruinada propia.
- [ ] Opción de volumen "Voces" ya existe: verificar que lo respeta.

### S-403 · Stingers de resultado y desbloqueo — B · `Sol · high` · Aviso: no

- [ ] Frases musicales cortas sintetizadas (2-4 s): entrega perfecta, entrega con pérdidas, récord,
  desbloqueo, evento resuelto, evento fallido. Por el bus `Music`. En `ui_sounds.gd`.

### S-404 · Mezcla medida de los sonidos de trampa — A · `Sol · high` · Aviso: no

Balance de volumen sin depender del oído (Nacho dejó registrado en su #83 que editar valores a ciegas
no sirve).

- [ ] `tests/audio_loudness_report.gd`: genera cada sonido de trampa y de UI, calcula RMS y pico
  en dBFS, y lista la diferencia contra un objetivo (−18 dBFS RMS para efectos de trampa, −24 para UI).
- [ ] Ajustar el `volume_db` de cada reproductor del dominio de Slatex para quedar a ±2 dB del objetivo.
  Tabla antes/después en `docs/direccion-visual.md` (sección de audio) o un `docs/audio.md` nuevo.

---

## 5. UI / UX

### S-501 · HUD con jerarquía: una cosa urgente a la vez — A · `Sol · xhigh` (después de S-201) · Aviso: no

Resuelve `critica-diseno-abogado-del-diablo.md` §5.

- [ ] **S-501.1** Definir en `docs/controles-y-ui.md` tres capas con zona fija de pantalla:
  **crítico** (tu caja en riesgo, evento con cuenta regresiva, cuenta del explosivo) arriba al centro,
  grande, con pulso; **contexto** (aviso de interacción, tapa de la caja) abajo al centro; **información**
  (velocidad, dinero, distancia, carga de los demás) en las esquinas, chico y quieto.
- [ ] **S-501.2** Nunca dos textos en la misma zona: cola con prioridad en `hud_notices.gd`.
- [ ] **S-501.3** Barra de atajos: se oculta sola después de 3 partidas completadas o 60 s sin usar
  ayuda; opción "Ayudas de controles: siempre / al principio / nunca".
- [ ] **S-501.4** El dinero del equipo solo se ve en el depósito, en la pausa y en resultados.
- [ ] **S-501.5** Test en `test_hud_flow.gd`: con evento + aviso + toast a la vez, cada uno en su zona y
  ninguno tapado. Captura antes/después con `render_hud.gd`.

### S-502 · Accesibilidad: daltonismo, texto y efectos — A · `Sol · high` · Aviso: no

- [ ] Estados de caja con forma además de color: OK ✓, En riesgo ! (con pulso), Arruinada ✕, en las filas
  de carga y sobre la caja.
- [ ] Opción "Paleta para daltonismo" que cambia verde/amarillo/rojo por la paleta Okabe-Ito
  (azul/naranja/bermellón) en `UiTheme`.
- [ ] Opción "Tamaño de texto de menús" (100 / 125 / 150 %), aparte de la escala del HUD que ya existe.
- [ ] Opción "Subtítulos de sonidos": "[tictac acelerando]", "[gruñido]", "[vidrio que cruje]" en la
  zona de contexto, para los sonidos de trampa en riesgo.
- [ ] Todas persistidas en `GameSettings`; `test_settings.gd` ampliado.

### S-503 · Tipografía legible a distancia de sillón — C · `Luna · medium` · Aviso: no

- [ ] Revisar que ningún texto del HUD al 60 % de escala quede por debajo de 14 px efectivos a 1080p;
  subir los que no cumplan. Tabla de tamaños en `docs/direccion-visual.md` §3.

### S-504 · Todo el menú con gamepad — A · `Sol · high` · Aviso: no

- [ ] Cada panel (`options`, `progress`, `tutorial`, `cosmetics`, `leaderboard`, `depot_panel`, pausa y
  resultados) da foco a su primer botón al abrir y devuelve el foco al botón que lo abrió al cerrar.
- [ ] Vecinos de foco en grillas (cosméticos) para que el stick no salte de columna.
- [ ] B / Círculo cierra cualquier panel (hoy lo hacen algunos).
- [ ] Test `tests/test_gamepad_focus.gd`: al abrir cada panel hay un `Control` con foco.

### S-505 · Rueda de pings — B · `Sol · xhigh` · Aviso: no

Hoy hay un único ping "¡Cuidado!" (`player.gd` `_send_ping`).

- [ ] Tocar ping = ping rápido como hoy. Mantener = rueda de 6: ¡Cuidado!, ¡Ayuda!, ¡Frená!, Acá, Gracias,
  Sí/No. Selección con el mouse o el stick derecho.
- [ ] Sin cambios de red: `EventBus.request_ping(position, label)` ya lleva el texto.
- [ ] Color e ícono por tipo en el marcador (`_mark_pinger`); "¡Ayuda!" dispara el emote (S-308) y la
  voz (S-402) si existen.
- [ ] Test en `test_ping.gd`: cada opción llega con su etiqueta.

### S-506 · Onboarding: tutorial en fichas y consejos de primera vez — A · `Sol · high`, textos con `Luna · medium` · Aviso: no

La decisión de pantalla estática sigue (sin mini-nivel), pero hoy es un solo párrafo largo.

- [ ] **S-506.1** `tutorial_panel.gd` en páginas: 1) el objetivo (entregar a cada casa la caja de la
  pizarra), 2) conductor, 3) pasajero, 4) una ficha por trampa **desbloqueada** (ícono, qué la rompe, qué
  hacer, tecla del dispositivo en uso con `UiTheme.keycaps`), 5) dinero, mérito y cartas en dos líneas.
  Navegable con gamepad.
- [ ] **S-506.2** Consejos de primera vez en partida: la primera vez que un perfil tiene una trampa en la
  mano o en su asiento, aparece su ficha resumida 6 s en la zona de contexto. Se guarda `seen_tips` en el
  perfil de `UnlockManager`.
- [ ] **S-506.3** Al abrir el juego por primera vez (perfil sin partidas), el menú ofrece "Cómo jugar"
  resaltado.
- [ ] **S-506.4** Test: cada trampa tiene su ficha; un consejo visto no vuelve a salir.

### S-507 · Panel de tripulación en el depósito — B · `Sol · high` · Aviso: no

- [ ] Con Tab en el depósito: lista de jugadores conectados con su color, uniforme, quién está sentado
  al volante y quién tiene caja. Sirve de "lobby" sin frenar a nadie.
- [ ] Para el anfitrión: el código o la IP de la sala (S-207) para pasar a los demás.

### S-508 · Pantalla de resultados completa — A · `Sol · high` · Aviso: no

- [ ] Una fila por casa con ícono de la trampa, resultado y si tuvo foto.
- [ ] Premios de la entrega a partir del mérito (S-102): "MVP" (más mérito), "Rescatista", "Desactivador",
  "Mano firme". Con el color de cada jugador.
- [ ] Barra de progreso hacia el próximo desbloqueo: "Te faltan 2 entregas y 120 pts para Explosivo".
- [ ] Evento de ruta de la partida y cómo terminó.
- [ ] Test en `test_score_breakdown.gd` / `test_hud_flow.gd`.

### S-509 · Idioma inglés — A (para lanzar) · `Sol · high` para extraer, `Luna · medium` para traducir · Aviso: sí (`project.godot`)

Hoy todos los textos están escritos en español dentro del código.

- [ ] **S-509.1** Extraer los textos de **los archivos de Slatex** (`scripts/ui/`, avisos de
  `player.gd`/`package.gd`/`interaction/`, `get_hint()` de cada trampa, `UnlockManager`, `CrewProgression`,
  `RouteEventManager`) a `do-not-drop/translations/strings.csv` con claves (`HUD_CARGO_TITLE`…) y columnas
  `es,en`. Usar `tr("CLAVE")`.
- [ ] **S-509.2** Registrar el CSV en `project.godot` (internationalization) y opción "Idioma" en opciones.
- [ ] **S-509.3** Traducir al inglés con tono de juego (no literal).
- [ ] **S-509.4** Test `tests/test_translations.gd`: toda clave usada existe en las dos columnas; ningún
  texto de la UI de Slatex queda sin pasar por `tr()` (buscar comillas con letras acentuadas en
  `scripts/ui/`).
- [ ] Los textos de archivos de Nacho (casas, depósito) los extrae él: dejar el aviso con la lista de
  archivos y la convención de claves. No es bloqueante para esta tarea.

### S-510 · Progreso y récords que se entiendan — B · `Sol · high` · Aviso: no

- [ ] `progress_panel.gd`: barra por desbloqueo (entregas y puntos por separado), ícono del contenido y
  qué da ("Nueva trampa: Explosivo").
- [ ] `leaderboard_panel.gd`: pestañas Entrega / Endless, tamaño de tripulación y fecha legible.
- [ ] Test `test_progress_ui.gd` ampliado.

---

## 6. Narrativa y guion

### S-601 · Premisa y tono en una página — B · `Sol · medium` · Aviso: no

- [ ] `docs/narrativa.md`: qué es la empresa Take My Package, quién manda (una jefa que solo habla por
  la radio del depósito y por notas), por qué los paquetes son tan raros (clientes excéntricos del
  pueblo), tono (humor absurdo, nunca cruel ni con sangre). Lista de 10 clientes recurrentes con nombre
  y manía. Es la referencia para S-602 a S-604.

### S-602 · Remitentes, notas y etiquetas escritas a mano — B · `Luna · medium` para textos, `Sol · high` para código · Aviso: no

- [ ] Campos nuevos en `package_content.gd`: `sender`, `recipient`, `notes: PackedStringArray` (3-5 por
  contenido). La etiqueta de envío muestra remitente y destinatario; al abrir la caja (T), la línea de
  "adentro" suma la nota ("Es la torta de mi boda. No la miren.").
- [ ] Una garabateada a mano por caja ("NO AGITAR!!!", "ESTE LADO ARRIBA (EN SERIO)") como `Label3D` con
  tipografía de marcador. Narrativa ambiental sin cinemáticas.

### S-603 · La jefa habla en el depósito — C · `Luna · medium` · Aviso: no

- [ ] Pool de 20 líneas de inicio de jornada según el pedido y la campaña ("Tres entregas. Una es una
  gallina. No pregunten.") mostradas en la pizarra del `depot_panel.gd` y como toast al entrar.
- [ ] Reacción según la última partida ("Ayer rompieron dos cosas. Hoy no.").

### S-604 · Reclamos de clientes con voz propia — B · `Luna · medium` · Aviso: no

- [ ] Los reclamos de la pantalla de resultados salen de un pool por cliente y resultado (roto, en
  riesgo, abierta, equivocada) en vez de un texto genérico. Pool en `data/text/complaints.json` o dentro
  de la tabla de traducciones (S-509).

### S-605 · Textos de trampas y eventos con tono — C · `Luna · medium` · Aviso: no

- [ ] Reescribir `get_hint()` de las 7 trampas y los `prompt` de los eventos de ruta con el tono de
  S-601, máximo 6 palabras por aviso (se leen manejando).

---

## 7. Producción y gestión de proyecto

### S-701 · Esta lista como tablero — A · `Luna · low` · Aviso: no

- [ ] Cada tarea cerrada: `[x]` + hash del commit en la misma línea. Si una tarea resulta más grande de lo
  pensado, partirla acá en subtareas antes de seguir.
- [ ] Una vez por semana, actualizar "Última actualización" y mover a "Hecho" lo cerrado del hito.

### S-702 · Qué queda fuera del MVP (control de alcance) — A · `Luna · medium` · Aviso: no

- [ ] Sección nueva en `docs/plan-desarrollo.md` con la lista cerrada de lo que **no** se hace antes de
  Early Access: chat de voz propio, matchmaking público, cartas Prioridad e Información, tienda en ruta,
  tutorial jugable, más de 7 trampas, servidores dedicados, microtransacciones. Cualquier idea nueva se
  anota en una sección "Después del lanzamiento", no en esta lista.

### S-703 · Avisos al día — A · `Luna · low` · Aviso: sí

- [ ] Cada tarea con Aviso `sí` deja su entrada en `docs/colaboracion-equipo.md` en el mismo commit.
- [ ] Borrar de ese documento los avisos de más de un mes que ya no afectan a nadie (dejar solo los vigentes).

---

## 8. QA (sin playtesting)

### S-801 · Recorrido técnico de 10 minutos antes de cada push grande — A · — · Aviso: no

Esto **no es playtesting** (no evalúa si es divertido): busca errores.

- [ ] Checklist en `docs/qa-recorrido.md`: abrir el juego, cambiar opciones, jugar solo una entrega
  completa (agarrar, montar, manejar, bajar, timbre, foto), pausa, volver al menú, Endless 2 minutos,
  cerrar. Anotar cualquier error de la consola de Godot.

### S-802 · Tests de contrato para todo lo que se agrega por datos — A · `Sol · high` · Aviso: no

- [ ] `tests/test_trap_contract.gd`: recorre `data/traps/*.tres` y verifica para cada una: crea su
  comportamiento, la integridad queda en [0, max] con input vacío y con input aleatorio durante 30 s
  simulados, `get_hint()` nunca vacío, tiene ícono (S-301), contenido propio (S-302), sonido de riesgo, y
  un desbloqueo o está en el set inicial. Una trampa nueva que no cumpla falla este test.
- [ ] Mismo criterio para `data/contents/*.tres` (nodos `Filler`/`Intact`/`Damage`/`Ruined`).

### S-803 · Bot de caos — B · `Sol · xhigh` · Aviso: no

- [ ] `tests/test_chaos_bot.gd`: un jugador bot hace acciones al azar (con semilla fija) durante 5 minutos
  simulados en el nivel de entrega: agarrar, soltar, abrir, montar, sentarse, pararse, pingear, sacar foto.
  Falla si aparece un `push_error`, un NaN en posiciones o una caja fuera del mundo.

### S-804 · Nada anunciado queda colgado — A · `Sol · high` · Aviso: no

- [x] (commit `6175d6e`) Test `tests/test_no_dangling_state.gd`: al terminar una partida, `RouteEventManager` no tiene evento
  activo, `ShopVoteManager.active` es falso fuera del depósito, ninguna caja queda con `occupied_by` de un
  jugador que ya no existe. Es el test que hubiera detectado S-101.

### S-805 · Telemetría local para cuando haya playtesting — B · `Sol · high` · Aviso: no

- [ ] Opción "Guardar registro de partidas" (apagada por defecto). Si está activa, al terminar cada partida
  escribe `user://telemetry/<fecha>.json` con: duración, trampas del pedido, tiempo en riesgo por trampa,
  qué rompió cada caja, evento de ruta, puntaje. Nada se manda por red.
- [ ] Script `tools/telemetry-summary.py` que resume una carpeta de registros en una tabla. Así el primer
  playtesting ya produce datos sin preparar nada.

### S-806 · Batería verde y rápida — A · — · Aviso: no

- [x] (commits `3c4ac88`, `37581a2`) Después de cada tarea: `tools/run-tests.sh` con filtro de lo tocado. Antes de push, el hook corre todo.
- [ ] Si un test propio tarda más de 20 s, revisar si se puede acortar sin perder lo que verifica.

---

## 9. Negocio, marketing y distribución

### S-901 · Texto de la página de Steam — B · `Luna · medium` (redactar), `Sol · medium` (revisar) · Aviso: no

- [ ] `docs/marketing/steam-page.md` en español e inglés: descripción corta (≤ 300 caracteres), descripción
  larga con 5 viñetas de características, requisitos mínimos (GL Compatibility → hardware modesto),
  etiquetas (Co-op, Online Co-Op, Physics, Driving, Funny, Party Game).
- [ ] Una frase de gancho que diga los roles asimétricos: "Uno maneja. Los demás intentan que nada explote."

### S-902 · Modo captura para imágenes y tráiler — B · `Sol · high` · Aviso: no

- [ ] Tecla de depuración (F10, solo build de debug) que oculta todo el HUD y el viewmodel.
- [ ] `tests/render_store_shots.gd`: 5 escenas fijas (depósito cargando, manejo con cajas en riesgo, entrega
  en una casa, caja explotando, resultados) a 1920×1080. Necesita ventana: la corrés vos.

### S-903 · Cápsulas de Steam — C · generación de imagen · Aviso: no

- [ ] Con el logo (S-306): 460×215, 616×353, 231×87, 1232×706, 600×900, 3840×1240. `assets/store/`.
  Registrar en `art/ai-registro.md`.

### S-904 · Press kit — C · `Luna · medium` · Aviso: no

- [ ] `docs/marketing/presskit.md`: ficha (nombre, equipo, plataforma, precio objetivo $8-15, fecha
  tentativa de Early Access), descripción, características, logo, capturas (S-902), contacto.

### S-905 · Cómo enseñan los competidores — B · `Sol · medium` con búsqueda web · Aviso: no

- [ ] Una página (`docs/marketing/onboarding-competidores.md`) comparando cómo PEAK, Lethal Company y
  Totally Reliable Delivery Service enseñan sus controles y sus reglas en los primeros 5 minutos, y qué
  tomar para S-506. Con fuentes.

### S-906 · Registro de decisión de monetización — A · `Luna · medium` · Aviso: no

- [ ] En `docs/plan-desarrollo.md`: precio único $8-15, sin microtransacciones, cosméticos solo se
  ganan jugando, actualizaciones gratis. Verificar que ningún cosmético del código tenga precio en dinero real.

### S-907 · Logros — B · `Sol · high` · Aviso: no

- [ ] Diseñar 15 logros atados a hitos que ya existen o que suma esta lista (primera entrega, primer
  explosivo desactivado, entrega perfecta con 4 casas, 10 rescates, sacar foto a una caja arruinada…).
  Tabla en `docs/plan-desarrollo.md` Fase 5.
- [ ] Sistema local en `UnlockManager` (`achievements` en el perfil) con toast. El puente a Steam queda para
  cuando haya AppID propio (hoy es el 480 de prueba).

---

## Para cuando haya playtesting (no se hace ahora)

Quedan registradas para no perderlas. Cuando se decida hacer playtesting, se usan los datos de
S-805 y los objetivos de S-108.

| Ítem viejo | Qué hay que observar |
|---|---|
| #41, #51, #59, #67 | Si los números de las trampas, ya ajustados por simulación (S-108), se sienten justos. |
| #47 | Tutorial con alguien que nunca vio el juego. |
| #94, #95 | Cada trampa sola y las 7 combinadas en una entrega. |
| #98 | Partida real con 4-5 personas. |

---

## Qué pasó con la lista anterior (1-100)

- **Cerradas** (89): modelado y animación del jugador y de los paquetes, interacción paquete-jugador,
  progresión y desbloqueos, las trampas Líquido/Explosivo/Hostil, cosméticos, opciones, HUD y
  resultados, guía para agregar trampas. El detalle de cada una está en el historial de git de este
  archivo (`git log -p docs/tareas-slatex.md`).
- **Reubicadas** en esta lista:
  #41/#51/#59/#67 (balance) → S-108 · #79 (cosméticos con dos clientes) y #96 (dos jugadores con el mismo
  objeto) → S-204 · #99 (especificaciones visuales) → S-309.
- **Movidas a "Para cuando haya playtesting"**: #47, #94, #95, #98.
- **Encontradas a medias en el relevamiento del 2026-09-24** (nunca estuvieron en la lista vieja):
  eventos de ruta sin resolución (S-101), mérito que nadie otorga (S-102), cartas sin uso (S-103),
  votación que nunca se abre (S-104), campaña que no se guarda (S-105), contenidos repetidos entre
  trampas (S-302), íconos faltantes para 3 trampas (S-301).

## Modelado pendiente (101-106) — relevamiento 2026-09-23

> Anotado por Nacho al relevar el modelado pendiente de todo el juego; detalle en
> `docs/inventario-assets.md` §10. Son sugerencias para tu dominio: reordenalas o descartalas.

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 101 | Ragdoll con el modelo del jugador (huesos del rig) en vez de cápsulas sueltas (`player_ragdoll.gd`). | B | Pendiente |
| 102 | Maniquí del panel de cosméticos con el modelo del jugador en vez de cápsula + esfera (`cosmetics_panel.gd`), para que la vista previa muestre lo que se va a ver en juego. | A | Pendiente |
| 103 | Accesorios cosméticos con geometría (gorras, chalecos), cuando se retome la decisión del #76. | C | Pendiente |
| — | ~~Cuerpo del jugador con el personaje redondeado de Astra.~~ **[x] Hecho por Nacho (2026-09-24, pedido del usuario)** — `sm_char_player_rounded.glb` con clips Idle/Walk/Jump/PickUpPackage/Sit, camiseta con el color del equipo, IK de manejo continuo sin cilindros; aviso en `colaboracion-equipo.md`. Los NPC siguen con el modelo viejo. El #101 (ragdoll) ahora tendría que usar este rig. | A | Hecho |
| — | ~~Manos flotantes en primera persona.~~ **[x] Hecho por Nacho (2026-09-24, pedido del usuario)** — sin guantes/cápsulas en las cámaras ni en el volante; las manos que atendían la trampa desde el asiento (#10) se fueron con ellos. Aviso en `colaboracion-equipo.md`. | A | Hecho |
| 104 | Rehacer el celular (`sm_prop_phone.glb`, 92 triángulos) e integrarlo en `phone_camera.gd`, que hoy no carga ningún modelo. | B | Pendiente |
| 105 | Borrar las cajas viejas `models/cargo/sm_cargo_package_*.glb`: sin uso desde las cajas por trampa. | A | Pendiente |
| 106 | Revisar los ojos/tentáculos del paquete Hostil (esferas y barras en `package_feedback.gd`): ¿alcanzan como chiste o merecen un modelo? | C | Pendiente |
