# Plan de desarrollo por fases — Do Not Drop

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

### Estado (2026-09-21): pieza base construida y probada en aislamiento, no integrada al juego
- [x] `RouteSegment` (`scripts/gameplay/route/route_segment.gd`) — base chainable:
      cada tramo se autoconstruye entre z=0 (entrada) y z=-length (salida), sin
      conocer al tramo anterior ni al siguiente.
- [x] Cuatro tipos concretos en `scripts/gameplay/route/segments/`: recta, badén,
      chicana y puente angosto — cada uno un script chico, `class_name` propio.
- [x] `RouteStreamer` (`scripts/gameplay/route/route_streamer.gd`) — instancia tramos
      por delante de un `target` (pensado para el vehículo), libera los que quedaron
      atrás, y aplica la regla de combinación más simple posible: nunca repetir el
      mismo tipo dos veces seguidas.
- [x] `tests/test_route_streaming.gd` cubre spawn/cull/no-repetición con un `Node3D`
      de prueba en vez del vehículo real.
- [ ] **No reemplaza todavía la ruta curada a mano** (`route.gd`/`route.tscn`), que
      sigue siendo la que juega `level_base.gd` — integrarlo (conectar `start()` al
      vehículo real, decidir cómo conviven tramos curados fijos con streaming
      aleatorio en el modo normal) queda pendiente, junto con el criterio subjetivo:
      ningún test puede decir si la variedad procedural se siente bien.

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
