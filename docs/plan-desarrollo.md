# Plan de desarrollo por fases — Take My Package

## Fase 5 — Progresión local del MVP

El MVP usa un **perfil local persistente**, no una cuenta. Entregas exitosas y
puntaje acumulado desbloquean contenido permanentemente: Líquido (3 entregas,
250 puntos), pintura violeta (5, 450), Explosivo (7, 750) y Hostil (12, 1500).
El dinero y las cartas permanecen en la campaña cooperativa, separados del
progreso individual. El tutorial inicial es una pantalla estática del menú;
un mini-nivel interactivo queda para una iteración posterior.

> Basado en: `docs/requerimientos-tecnicos.md` (Godot 4.x, física real de vehículo +
> streaming de tramos, confirmado 2026-09-20).
> Última actualización: 2026-09-20
> Principio guía: validar el loop central (conducir + manejar paquetes) lo antes
> posible, **antes** de invertir en multiplayer, arte final o contenido extra. El
> multiplayer y el arte son las partes más caras de rehacer si el loop no es divertido.

## Fase 0 — Setup técnico
- Proyecto Godot 4.x, activar motor de física **Jolt**.
- Escena base: un `VehicleBody3D` controlable con teclado, sobre un tramo de camino
  simple (bloque gris, sin arte).
- Definir la escala/unidades del mundo (importante para que la física de vehículo y de
  paquetes se sienta bien desde el principio, más fácil de ajustar ahora que después).

## Fase 1 — Loop central en single-player, sin arte ni multiplayer

Estado de implementación: existe un prototipo con conducción en primera persona,
preparación a pie (agarrar → cargar → abordar), ruta, daño del paquete y resultados.
La preparación incluye indicaciones contextuales, pausa y controles para evitar
abordar antes de cargar. El atajo `--autostart` realiza la carga y el abordaje.
Las pruebas automatizadas están listadas en el README; la validación subjetiva
del manejo y la diversión sigue pendiente de playtesting. No se considera cerrada
esta fase ni se adelanta por eso el multiplayer.
La cámara de asiento permite mirar con mouse/stick derecho y recentrar con
C/clic del stick derecho, conservando la mirada después de impactos. A pie,
el gamepad usa stick izquierdo para caminar y derecho para mirar.

Objetivo: **responder la pregunta más importante del proyecto** — ¿es divertido manejar
mientras se gestiona un paquete-trampa? Si esto no funciona, nada de lo demás importa.

- Un solo tipo de trampa implementado de punta a punta (recomendado: **"Frágil"**, es
  la más simple de programar: `RigidBody3D` + detección de impacto por umbral de
  fuerza).
- Camino armado con 3-5 tramos placeholder puestos a mano (sin streaming todavía).
- Condición de victoria/derrota simple: llegar al final con el paquete intacto.
- **Sin UI pulida, sin arte, sin sonido** — bloques grises y cápsulas. La única
  pregunta que importa acá es si la mecánica en sí genera tensión/diversión.
- **Hito de salida de esta fase**: jugarlo vos mismo (o con 1 amigo en el mismo teclado
  dividido, si es posible) y confirmar que "se siente bien" antes de seguir.

### Definition of Done — Fase 1
- [x] `VehicleBody3D` responde a `drive_accelerate`/`drive_brake`/`drive_left`/
      `drive_right`/`drive_handbrake` (Input Map de `docs/convenciones-godot.md`) con
      sensación de manejo aceptable (no necesita estar pulido, sí ser controlable).
- [x] `Package` con `FragileTrapBehavior` implementado usando los parámetros de
      `docs/parametros-diseno.md` sección 1 (medidor de integridad, no falla binaria).
- [x] El paquete reacciona visiblemente (aunque sea con color/debug draw) a los tres
      estados: OK / EnRiesgo / Arruinado.
- [x] `EventBus` emite `package_state_changed` y `package_ruined` (y varias más, ver
      `docs/arquitectura.md` sección de señales), confirmado por `tests/test_fragile.gd`.
- [x] Se puede completar una ruta placeholder de punta a punta y ver un resultado
      simple (texto en consola o UI mínima: "entregado intacto" / "arruinado").
- [x] Capas de física configuradas según `docs/convenciones-godot.md` sección 2 (el
      vehículo no atraviesa el paquete, el paquete no se cae del mundo).
- [ ] **Criterio subjetivo (el más importante)**: jugarlo se siente tenso/divertido
      al menos en su forma más básica. Si no, ajustar parámetros de
      `parametros-diseno.md` antes de pasar a la Fase 2 — no seguir sumando features
      sobre una base que no genera diversión.

### El loop de entrega, de verdad (2026-09-22)

Hasta esta fecha "entregar" era **frenar en una zona al final de la ruta**.
Las tres casas con timbre que `route.gd` construye desde el 2026-09-21 eran
inalcanzables: `package_pickup_point.gd` no dejaba volver a levantar un
paquete ya montado, así que ninguna caja podía salir de la furgoneta, así
que toda casa resolvía `missed` — y nada escuchaba `route.house_resolved` de
todos modos, con lo cual entregar bien, entregar roto o pasar de largo daban
exactamente el mismo puntaje. Era un agujero de loop, no una feature a medio
hacer, y ningún test lo cubría porque cada pieza por separado funcionaba.

Lo que hay ahora:

- [x] Bajar una caja en una parada, llevarla a pie y tocar el timbre. Sacarla
      libera el estante y deja de contar como carga a bordo; llevarla lejos
      de la furgoneta ya no la marca como perdida (el vigilante de
      `LOST_CARGO_DISTANCE` ignora lo que alguien tiene en las manos).
- [x] Puntaje por puerta en `RunManager`, aparte de la carga que vuelve en la
      furgoneta: 150 intacto / 75 en riesgo / 20 roto / −60 por vecino que se
      quedó esperando. Una casa nunca atendida penaliza aunque el run termine
      volcando antes de llegar (`expected_houses`, independiente de cómo
      terminó la partida).
- [x] **Celular con modo cámara** (F) y foto de entrega (click). Da bonus, y
      es la prueba que hace caer el reclamo del cliente al final: un paquete
      entregado roto siempre genera queja, uno en riesgo a veces, y sin foto
      de esa puerta el reclamo descuenta. Pedido directo del usuario.
- [x] Cubierto por `tests/test_house_delivery_flow.gd` (el loop entero) y
      `tests/test_phone_camera.gd` (la foto y el reclamo).
- [ ] La meta al final de la ruta sigue cerrando el run, por decisión
      explícita del usuario. Cuántas casas por partida (hoy 3 fijas contra 4
      paquetes fijos) sigue abierto — `docs/tareas-nacho.md` #104/#105/#121.

### Lo que un jugador puede tocar (2026-09-22)

Antes de este pase no había forma de bajar el volumen, cambiar la
sensibilidad del mouse, ni **salir del juego** sin Alt+F4, y desde la pausa
no se podía volver al menú. Ahora: `GameSettings` (autoload, guardado en
`user://settings.cfg`) + `scripts/ui/options_panel.gd`, alcanzable desde el
menú principal y desde la pausa, con volumen, sensibilidad de mirada,
invertir Y y pantalla completa; más botones de Salir y de volver al menú.
La paleta de UI dejó de estar duplicada entre menú y HUD
(`scripts/ui/ui_theme.gd`), y las etiquetas del HUD que se pisaban entre sí
(eventos de ruta sobre el prompt de interacción, avisos de mérito sobre los
pings) tienen cada una su propia línea y su propio reloj. Cubierto por
`tests/test_settings.gd`.


## Fase 2 — Sumar las trampas restantes (single-player)
- Implementar los otros 2-3 tipos de trampa del catálogo (Peso creciente, Equilibrio,
  Ruidoso/vivo), como el sistema modular de "plugins" que definimos en
  `requerimientos-tecnicos.md` sección 4.
- Probar combinaciones de 2-3 trampas simultáneas en single-player (simulando qué pasa
  cuando haya varios jugadores) para validar que el caos escale bien y no se vuelva
  injusto o imposible de seguir.

### Estado (2026-09-20): implementada, falta validarla jugando
- [x] Las tres trampas restantes, cada una como script + `.tres`, sin tocar el loop.
- [x] Los cuatro asientos de pasajero son ocupables y cada uno queda a cargo del
      paquete de su soporte; el input del pasajero llega a su trampa.
- [x] El nivel lleva los cuatro paquetes a la vez y el marcador puntúa por carga.
- [x] `tests/test_traps.gd` y `tests/test_multi_cargo.gd` cubren la lógica headless.
- [ ] **Criterio subjetivo, pendiente**: jugarlo y ver si el caos con 2-3 trampas
      simultáneas se siente divertido o solo abrumador. Ningún test puede responder
      esto; si se siente injusto, los números están en `parametros-diseno.md` y se
      ajustan sin tocar código.

## Fase 3 — Streaming de tramos (mundo "interminable")
- Implementar generación/instanciado de tramos por delante del vehículo y eliminación
  de los tramos que quedaron atrás, usando la posición real del `VehicleBody3D` en el
  mundo (según lo definido en la decisión de arquitectura de movimiento).
- Sistema de combinación de tramos curados (rectas, curvas, puentes angostos, badenes)
  con reglas simples de qué tramo puede seguir a cuál.
- Esta fase es la base técnica tanto para las rutas del modo normal como para el modo
  endless (sección 3.5 del doc técnico).

### Estado (2026-09-21): pieza base construida, ahora integrada en un modo jugable aparte
- [x] `RouteSegment` (`scripts/gameplay/route/route_segment.gd`) — base chainable:
      cada tramo se autoconstruye entre z=0 (entrada) y z=-length (salida), sin
      conocer al tramo anterior ni al siguiente.
- [x] Cuatro tipos concretos en `scripts/gameplay/route/segments/`: recta, badén,
      chicana y puente angosto — cada uno un script chico, `class_name` propio.
- [x] `RouteStreamer` (`scripts/gameplay/route/route_streamer.gd`) — instancia tramos
      por delante de un `target` (el vehículo real, ya conectado — ver más abajo),
      libera los que quedaron atrás, y aplica dos reglas de combinación: nunca repetir
      el mismo tipo dos veces seguidas, y el primer tramo siempre es una recta
      (`first_segment_script`, default `StraightSegment`) — encontrado al conectar
      esto a un vehículo real por primera vez: una chicana o un puente angosto como
      tramo #1 le tira un obstáculo a un conductor que recién agarra el volante.
- [x] `tests/test_route_streaming.gd` cubre spawn/cull/no-repetición con un `Node3D`
      de prueba; `tests/test_level_endless.gd` cubre la integración real (vehículo de
      verdad, sesión larga simulada, conteo de nodos acotado).
- [x] **Modo Endless jugable** (`scenes/gameplay/level_endless.tscn` +
      `scripts/gameplay/level_endless.gd`, docs/tareas-nacho.md #41-55): mismo flujo
      de carga a pie / asiento del conductor / carga de paquetes que `level_base.gd`,
      pero `RouteStreamer` reemplaza a la ruta curada. Niebla y `lookahead_distance`
      ajustados juntos (180 m de anticipación, niebla más densa que el modo normal)
      para que nunca se vea el borde de lo generado con el far clip actual (600 m).
      Deliberadamente **no** comparte código con `level_base.gd` todavía (duplicación
      aceptada a propósito en vez de refactorizar un archivo del que también depende
      Slatex, a mitad de proyecto sin coordinar) — revisar una vez que los dos modos
      estén estables.
- [x] **Punto de entrada desde el menú** (2026-09-22): botón "Modo Endless (solo)"
      en `main_menu.gd`, más el atajo `-- --autostart-endless`. Coordinar con Slatex
      sigue pendiente como buena práctica (es su archivo), pero ya no bloquea probar
      el modo — antes solo se llegaba pasando la escena directo (docs/tareas-nacho.md #45).
- [x] **Puntaje por distancia** (2026-09-22, docs/tareas-nacho.md #44/#52): `RunManager`
      distingue `MODE_DELIVERY`/`MODE_ENDLESS`; en modo endless, `finish_run()` puntúa
      con `current_distance * DISTANCE_POINTS_PER_METER` (placeholder ajustable, sin
      tocar lógica) en vez de la fórmula de carga/tiempo, que no tiene sentido sin zona
      de entrega. `current_distance` se mantiene sincronizado con `distance_traveled`
      de `level_endless.gd` cuadro a cuadro, así que también queda correcto cuando el
      run termina por dentro de `RunManager` (toda la carga arruinada). El leaderboard
      local guarda `mode` por entrada y cachea el top 10 de cada modo por separado, sin
      que uno desplace al otro.
- [ ] **Criterio subjetivo, sin resolver**: ningún test puede decir si la variedad
      procedural se siente bien, ni si el ritmo de dificultad es justo. Playtesting
      real pendiente (docs/tareas-nacho.md #55).

## Fase 4 — Multiplayer
> Se deja para después de validar el loop y las trampas en solitario, porque el
> networking es la parte más costosa de depurar y no tiene sentido pagar ese costo
> sobre una mecánica que todavía no sabemos si es divertida.

**Estado (2026-09-21): implementada fuera de orden.** El networking host-autoritativo
(vehículo, paquetes, interacciones), los dos transportes (Steam vía Spacewar/480 y
ENet para LAN) y el menú principal para crear/unirse a una sala ya están funcionando
y verificados con una conexión real de dos procesos — ver README sección
"Multijugador". Se adelantó porque en la práctica jugar solo (single-player) y con
más gente comparten el mismo código de simulación, y quedó más simple integrarlo ya
que separarlo. Esto **no** reemplaza el criterio subjetivo pendiente de las Fases 1-2:
seguir siendo divertido con varios jugadores reales es, si acaso, una pregunta más
exigente que la versión solo.

- Integrar la API de multiplayer de Godot (host-cliente), empezando con 2 jugadores
  (conductor + 1 pasajero) antes de escalar a 5.
- Sincronizar: transform del vehículo (autoridad del host), estado de cada paquete,
  resultado de cada puzzle individual.
- Probar específicamente cómo se siente la latencia en la física del vehículo (es lo
  más sensible a lag) y ajustar si hace falta interpolación/predicción del lado del
  cliente.

## Fase 5 — Meta-progresión y UI
- Sistema de desbloqueos (nuevas trampas, vehículos, cosméticos) — sección 3.2 del doc
  técnico.
- Menú de partida, lobby multiplayer, pantalla de resultados con puntaje.
- Leaderboard simple (al menos local; global si el scope lo permite).

### Estado (2026-09-21)
- [x] Menú de partida (jugar solo / crear sala / unirse por IP) — `main_menu.gd`.
- [x] Pantalla de resultados con puntaje — overlay de `prototype_hud.gd`, ya mostraba
      el desglose de puntaje; ahora también muestra "¡NUEVO RÉCORD!" o el récord
      actual.
- [x] Leaderboard local — `RunManager` guarda el top 10 de puntajes en
      `user://leaderboard.json`, persiste entre sesiones, cubierto por
      `tests/test_leaderboard.gd`. Global queda fuera de alcance por ahora (no hay
      backend).
- [ ] Sistema de desbloqueos (`UnlockManager`) — no existe todavía, no hay contenido
      que desbloquear más allá de las 4 trampas, que ya están todas disponibles desde
      el arranque.
- [ ] Lobby multiplayer con pantalla de espera — no hace falta con el diseño actual
      (el host entra directo al nivel y los demás se suman dinámicamente, ver
      `main_menu.gd`), así que esto puede no ser necesario en absoluto.

## Fase 6 — Pase de arte (estilo PEAK)
> Deliberadamente tarde: todo lo anterior se probó y ajustó con arte placeholder para
> no gastar tiempo de arte en mecánicas que todavía podían cambiar.

- Reemplazar placeholders por low-poly (Kenney.nl / packs compatibles) para vehículo,
  entorno y paquetes.
- Personajes con ragdoll físico y diseño simple.
- Pase de efectos "clipeables": fallas exageradas visualmente, cámara reactiva a
  golpes (sección 3.4 del doc técnico).

## Fase 7 — Pulido y preparación de Early Access
- Balance de dificultad con playtesting real (grupos de amigos jugando).
- Sonido y música (recordar: presupuestar esto para encargar, según el patrón
  confirmado en `checklist-exito.md`).
- Página de Steam, trailer, precio definido ($8-15 según lo acordado).
- Lanzar en Early Access con el contenido mínimo (1 vehículo, 1 set de tramos, 3-4
  trampas) e iterar con feedback real antes de sumar contenido extra.

---

## Por qué este orden (resumen de la lógica)

1. **Loop antes que contenido**: fases 1-2 validan la mecánica central sin gastar
   tiempo en arte/red.
2. **Contenido antes que infraestructura cara**: el streaming de tramos (fase 3) se
   construye recién cuando ya sabemos que el loop funciona.
3. **Multiplayer al final de la parte técnica, no al principio**: es lo más caro de
   depurar y lo que menos conviene tocar mientras el diseño del loop todavía puede
   cambiar.
4. **Arte al final**: coherente con todo el patrón de la investigación — el arte no es
   el cuello de botella, el diseño de sistemas sí.

## Próximo paso
Si querés, el siguiente documento puede ser un detalle técnico de implementación de la
Fase 1 (estructura de nodos/escenas concreta en Godot para el `VehicleBody3D` + el
primer paquete "Frágil"), para tener algo directamente accionable al sentarte a
programar.
