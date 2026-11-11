# Recorrido técnico (QA sin playtesting)

Esto **no es playtesting**: no evalúa si el juego es divertido, busca errores. Se hace a mano,
con el juego abierto desde el editor (o `godot --path do-not-drop`) y la consola de Godot a la
vista, antes de un push grande o de una build para jugar con amigos.

Cómo anotar: cada error de consola (`ERROR`, `SCRIPT ERROR`, `WARNING` nuevos) y cada cosa que se
vea mal va a la tabla "Hallazgos" de abajo, con fecha, commit, qué se estaba haciendo y, si hace
falta, una captura (`art/qa/`, fuera de `do-not-drop/` para que no entre al build). Lo que se
arregla se tacha; lo que no, pasa a la lista de tareas del dueño.

Atajos útiles (argumentos después de `--`):

| Argumento | Qué hace |
|---|---|
| `--autostart` | Entra directo a una entrega, sin menú. |
| `--autostart-endless` | Entra directo al modo Endless. |
| `--mood=lluvia_noche` | Fuerza el clima y la hora: `soleado`, `nublado`, `lluvia`, `niebla` × `dia`, `atardecer`, `noche` (`world_mood.gd`). |

Ejemplo: `godot --path do-not-drop -- --autostart --mood=niebla_atardecer`.

## Juego completo (Slatex, S-801)

Duración objetivo: **10 minutos**. Hacerlo en una build de desarrollo con la consola visible. No
se evalúa balance ni diversión: cada casilla confirma que el flujo termina, responde al control y
no genera errores nuevos.

Antes de empezar, anotar la versión que se está recorriendo:

| Fecha | Commit | Dispositivo | Resolución | Clima rotado |
|---|---|---|---|---|
| | | teclado/mouse o gamepad | | |

### 1. Menú y opciones (1 minuto)

- [ ] Abrir el juego desde cero: aparece el menú, hay un botón enfocado y se puede navegar sin
  usar el mouse si el dispositivo elegido es gamepad.
- [ ] Abrir **Opciones**, cambiar temporalmente volumen de efectos, escala de UI y una tecla
  reasignable; aplicar y comprobar que el texto/sonido responde.
- [ ] Cerrar Opciones con Atrás/Esc y volver a abrirlo: los valores siguen aplicados. Restaurar los
  valores usados al inicio para no convertir el recorrido en un cambio de configuración.

### 2. Una entrega completa en solitario (5 minutos)

- [ ] Elegir **Jugar solo** y aparecer en el depósito. La pizarra muestra el pedido y el HUD no
  presenta estados de una partida anterior.
- [ ] Acercarse a una caja correcta, **agarrarla**, llevarla al camión y **montarla** en un asiento
  de carga. El aviso de interacción, el modelo y el HUD cambian en cada paso.
- [ ] Sentarse al volante y salir: la entrega comienza, el camión responde a acelerar, frenar,
  girar y tocar bocina, y la carga sigue montada.
- [ ] Durante el trayecto abrir Pausa, entrar y salir de Opciones y reanudar. El mundo permanece
  pausado, el foco vuelve al botón correcto y no se duplica ningún panel.
- [ ] Frenar en la casa asignada, **bajar**, retirar la caja y caminar hasta el porche. El marcador
  de la casa y el aviso del timbre corresponden al pedido.
- [ ] Usar el **timbre** para entregar. La caja desaparece una sola vez y el HUD registra el
  resultado de esa casa.
- [ ] Sacar el celular con **F / gatillo izquierdo**, tomar la **foto** con clic / RB y cerrarlo.
  La foto aceptada aparece en el flujo de resultados o reclamo correspondiente.
- [ ] Volver al camión, llegar a la meta y detenerse hasta cerrar la partida. Resultados muestra
  casa, estado, foto, puntaje, mérito/progreso y permite continuar sin quedar bloqueado.

### 3. Volver al menú (1 minuto)

- [ ] Desde resultados volver al menú. No quedan HUD, audio de la ruta ni nodos de la partida
  anterior; los botones responden una sola vez.
- [ ] Abrir Pausa durante una segunda partida y usar **Volver al menú**. Confirmar el mismo estado
  limpio sin tener que terminar la ruta.

### 4. Endless (2 minutos)

- [ ] Entrar en **Modo Endless (solo)**. El depósito y la pizarra indican Endless, sin pedidos ni
  casas de entrega.
- [ ] Cargar al menos una caja, conducir durante **2 minutos** y cruzar varios tramos. La distancia
  y la dificultad avanzan; no aparece UI exclusiva de Entrega.
- [ ] Terminar volcando, saliendo de ruta o perdiendo la carga. El resultado de Endless conserva
  distancia/récord y vuelve al menú correctamente.

### 5. Cierre y resultado del recorrido (1 minuto)

- [ ] Cerrar el juego desde el botón **Salir**, no matando el proceso. La ventana y el proceso de
  Godot terminan sin error.
- [ ] Revisar toda la consola desde el arranque: no hay `SCRIPT ERROR`, `ERROR` ni `WARNING` nuevo.
- [ ] Copiar cada problema a **Hallazgos** con pasos reproducibles. Si afecta un cambio que se va a
  subir, el recorrido queda **fallido** hasta corregirlo o dejarlo expresamente fuera de alcance.

El recorrido queda aprobado cuando todas las casillas aplicables están marcadas y los hallazgos
que bloquean el cambio están resueltos. Las casillas se desmarcan para la siguiente ejecución; el
historial permanente vive en la tabla de Hallazgos y en los commits que corrigen cada problema.

## Mundo, ruta y camión (Nacho, N-804)

Una pasada por cada combinación de clima y hora (12 en total) no hace falta en cada
recorrido: alcanza con rotar, y que en una semana se hayan visto todas. La tabla de abajo
lleva la cuenta.

### Clima × hora del día

Con `--autostart --mood=<clima>_<hora>`, manejar ~1 minuto desde el depósito y mirar: cielo,
niebla, faros (de noche y con lluvia/niebla tienen que alcanzar más lejos), lluvia (partículas y
sonido, que no llueva adentro del depósito ni de la cabina), sombras y que el decorado lejano no
aparezca de golpe.

| Hora \ clima | soleado | nublado | lluvia | niebla |
|---|---|---|---|---|
| día | [ ] | [ ] | [ ] | [ ] |
| atardecer | [ ] | [ ] | [ ] | [ ] |
| noche | [ ] | [ ] | [ ] | [ ] |

### Tramos y peligros

Salen por semilla, así que no siempre aparecen todos en una entrega; en Endless aparecen todos
en pocos minutos. Tildar cuando se vio cada uno en este recorrido:

- [ ] **Túnel**: la luz de adentro, entrar y salir sin parpadeos, el sonido del mundo sigue.
- [ ] **Cruce de tren**: barrera y luces antes de que pase el tren, el tren no atraviesa al
  camión detenido, la barrera se levanta después.
- [ ] **Puente angosto**: barandas visibles y con colisión, el agua abajo, el camión entra justo.
- [ ] **Ripio**: el camión patina más (se siente en el volante) y vuelve a la normalidad al salir.
- [ ] **Badén, chicana, curva en S, obras, loma, curva**: ningún bloque flotando o enterrado,
  guardarraíl del lado de afuera de las curvas, conos y barrera de obras apoyados.
- [ ] **Ciervo**: pasa por delante; chocarlo cobra la multa, el cartel aparece y se cierra solo
  a los pocos segundos (N-202).
- [ ] **Casas**: cartel "entrega adelante" ~80 m antes, casa fuera del asfalto, timbre alcanzable,
  el vecino sale y vuelve a entrar.

### Depósito y portón

- [ ] Aparecer adentro y bajo techo; ninguna pared ni estante atravesable.
- [ ] Cada estación (pizarra, vestuario, taller, suministros, récords) abre su pantalla.
- [ ] Pizarra con un pedido por casa (entrega) o "RUTA SIN FIN" con el récord (Endless).
- [ ] El portón queda abierto mientras hay alguien a pie adentro y baja cuando el camión salió.
- [ ] Salir de la explanada a la ruta sin que el camión cabecee ni tire la carga (tarea #170).

### Camión

- [ ] Bocina desde la cabina (suena "adentro") y desde afuera (suena "afuera").
- [ ] Caja de herramientas y termo en la caja de carga: se mueven con los baches, no atraviesan
  paredes, se caen si se maneja con la puerta trasera abierta.
- [ ] Faros, luces de freno y polvo de las ruedas.
- [ ] Volcar a propósito en una curva: la detección de vuelco salta y el juego no queda trabado.

## Modo Empresa (expansión, D-2016)

Bot `tests/bot_company_day.gd` (headless, termina solo; las etapas del galpón están en
`tests/bot_company_shed.gd`, los jugadores en `tests/bot_company_crew.gd` y la van en
`tests/bot_company_trip.gd` y `tests/bot_company_van.gd`):

```bash
"$GODOT" --headless --path do-not-drop --script res://tests/bot_company_day.gd -- --players=1
"$GODOT" --headless --path do-not-drop --script res://tests/bot_company_day.gd -- --players=2
```

- Abre `company_root.tscn` con una empresa nueva de semilla fija (los mismos pedidos en cada corrida) y el
  save en `user://bot_company_day` (se borra), y espera el `OPENING` del día (máx. 10 s; si no llega,
  `BOT_FAIL no_opening`).
- Juegan el jugador del host y, con `--players=2` o más, un segundo jugador del equipo en el mundo del
  host: sus pedidos pasan por el chequeo que el host hace de un pedido de otro peer y su posición es la
  pose que ese peer replicaría (sin transporte: la pareja por ENet es D-2017). Con más de 2, el resto
  solo dimensiona los pedidos del día. Los dos se teletransportan al lado de lo que usan, así que cada
  chequeo de alcance es el del juego.
- Las estaciones son las del juego (`CompanyShed.station_for`, que `CompanyRoot` pone como
  `CompanyNet.stations`; el bot no la reemplaza): un hueco de estante es `ShelfPicking.station_id()`, una
  mesa de armado `table:<uid>`.
- Etapas, en orden sobre el mismo mundo (cada una imprime `BOT_STAGE <etapa> ok` o
  `BOT_FAIL <etapa>:<motivo>`, que corta la corrida):
  - `receive_pallet`: los palets del primer camión están en recepción (en el stock y dibujados) y uno
    sellado no da nada. Atajo `pallet_unload`: el bot los abre y saca las unidades él mismo.
  - `shelve_stock`: un hueco rotulado para otro producto rechaza (`wrong_product`); todas las unidades van
    al hueco rotulado con `units_store`, los jugadores por turno.
  - `take_orders`: el mundo planea el día en el `OPENING` y trae cada pedido al libro compartido cuando el
    reloj del galpón llega a su hora; el bot salta el reloj (`BOT_SKIP`) hasta completar 6 que pueda armar.
  - `pack_boxes`: 6 cajas, una por pedido, los jugadores por turno en las mesas: `box_start`,
    `units_take` en los estantes, `box_place` unidad por unidad, `box_fill`, `box_label`, `box_stamp`,
    `box_tape` (y `box_restock` si a la mesa le falta algo). Cada caja cerrada es un `DeliveryPackage` en
    `World/Packages` con su pedido; la plata sale por eventos. Atajos `table_use` (el juego no manda esos
    pedidos al usar la mesa) y `order_claim` (el bot le dice a la mesa qué pedido arma).
  - `dispatch`: cada uno lleva su caja en las manos a la zona de despacho y la apoya; el jugador del host
    usa la estación de despacho, marca todas en el tablero y aprieta Cargar: van al estante de la van, la
    carga queda preparada y el libro de viajes aprende los pedidos.
  - `drive`: el jugador abre la cabina, toma el volante y acelera; el portón arranca el viaje (pedidos
    `OUT`) y el piloto automático sigue el grafo de calles hasta la casa de la primera parada. Con 2
    jugadores el segundo se queda en el galpón armando los pedidos que siguen entrando, a ritmo de persona
    (6 s entre cosa y cosa), y deja cada caja en la zona hasta que vuelve la van.
  - `deliver`: parada por parada la van va hasta la casa (del mapa fijo, de la zona del pedido). Atajo
    `door_settle`: el bot cobra cada pedido con `OrderSettlement.settle` y lo anota en el viaje.
  - `return`: el piloto vuelve (giro en tres tiempos, avenida, entrada al playón) y el portón cierra el
    viaje sin fallados.
  - `close_day`: el reloj salta a las 20:00 (`BOT_SKIP`); `DayCycle` pasa por `CLOSING` a `SUMMARY`; el
    resumen trae los costos del armado y el alquiler que cobró el juego; el juego mismo guardó el día
    cerrado al llegar a `SUMMARY` (la apertura del día siguiente) y el bot solo lo lee.
- Después imprime una línea `BOT_STUB <etapa> <id> [<tareas>] <qué hace el bot>` por cada atajo que
  tomó, las `BOT_SKIP`, una `BOT_ERROR <mensaje>` por cada error del motor registrado en la corrida, y el
  resumen `BOT_COMPANY key=value`: `players`, `money`, `profit` (plata al cerrar menos plata al empezar),
  `deliveries`, `boxes`, `breaks`, `assembly_errors`, `engine_errors`, `return_bundle_units`,
  `idle_max_s_<peer>` (por jugador, el mayor tramo sin nada en las manos ni volante, en segundos reales) y
  `stage_ms_<etapa>`.
- Línea final: `BOT_OK` (salida 0) solo si las 9 etapas dieron `ok`, no hubo ningún `BOT_STUB`, la
  ganancia es mayor que 0, no hubo errores del motor y ningún jugador pasó más de 120 s ocioso; si no,
  `BOT_FAIL` con lo que falló (`stages_missing=<n> stubs=<n> profit=<n> engine_errors=<n>
  idle_<peer>=<s>`, salida 1). `BOT_TIMEOUT` (salida 3) si pasó el límite (`--hard`, 900 s por defecto).
- Hoy (2026-11-11) las 9 etapas pasan con 1 y con 2 jugadores, ganancia positiva y sin errores del motor.
  Con 1 jugador la línea final es `BOT_FAIL stubs=4`: quedan `pallet_unload` (D-0607.c), `table_use`
  (D-0701.b), `order_claim` (D-0804 / D-0807) y `door_settle` (D-0340 + D-0815.b). Con 2 jugadores además
  `idle_2=157`: el que se queda arma 3 cajas más y después se queda sin stock en los estantes para los
  pedidos que entran (`BOT_INFO stay_waits no_order=10 no_stock=35`). La corrida completa tarda unos
  7 a 8 minutos (la van visita varias casas de ida y vuelta).
- Son hallazgos: `no_opening`, `BOT_TIMEOUT`, una etapa que pasa de `ok` a falla, un `BOT_STUB` nuevo,
  `profit` ≤ 0, cualquier `BOT_ERROR`/`ERROR`/`SCRIPT ERROR` del log y un `idle_max_s` sobre 120. Los
  avisos de fin de proceso (`ObjectDB instances were leaked`, `resources still in use`, de todo
  `--script`) no lo son.

## Hallazgos

| Fecha | Commit | Qué se estaba haciendo | Qué pasó | Estado |
|---|---|---|---|---|
| 2026-10-01 | e033559 | Rutina QA (mañana, clima `soleado_noche` + `niebla_atardecer`): instanciar `level_endless.tscn`, `start_debug_delivery`, `reset_run` y `level.free()`, repetido; `Node.print_orphan_nodes` | Cada nivel liberado deja ~50 nodos huérfanos (`Stray Node: RepairTape (MeshInstance3D)`, `Stray Node: ReplacementHen (Node3D)` con sus mallas); 63 reinicios → 3150. Causa probable (sin confirmar): `package_salvage.gd:28-59` crea `tape_mesh`/`toy_mesh` en `_ready()` y los cuelga con `package.add_child.call_deferred(...)`; si el paquete se libera antes del diferido, quedan sin padre. Molesta (fuga por nivel, no por km). Resto del recorrido limpio: entrega, endless 6 km (nodos 2102→2345 planos, memoria 211→234 MB aplanándose), climas, `run-net-pair` y `run-net-trio` PASS. | ~~Abierto~~ Arreglado en #164 (S-908); 2026-10-01 0d7d7d9: 5+5 niveles liberados, 0 huérfanos |
| 2026-10-01 | 0d7d7d9 | Rutina QA (tarde, clima `nublado_dia` + `lluvia_noche`): `--autostart` con cualquier clima y entrar a la entrega desde el menú | Una vez por carga del nivel de entrega: `WARNING: Jolt Physics job system exceeded the maximum number of jobs. This should not happen. Please report this. Waiting for jobs to become available...`. No se repite cada frame. Probable relación con el depósito que se arma por frames y el precalentado (#195, #205): muchos cuerpos/colisiones agregados juntos. Cosmético. Resto limpio: entrega, endless 6 km (nodos 2159→2469→2315, memoria 229→245 MB aplanándose, 0 huérfanos), climas, menú↔nivel ×3 con pantalla de carga, `run-net-pair` y `run-net-trio` PASS. | Abierto: N-917 en `tareas-nacho.md` |
| 2026-10-19 | 5302f6b | Rutina QA (mañana, clima `lluvia_dia`): endless con `bench_drive.gd --cpu-only --seconds=N` | Hitches de física por scripts de 30-63 ms (ritmo de ~1 cada 25-60 s de pared) solo al aparecer un `NarrowBridgeSegment`: `DressingBatcher.merge_segment_geometry` (22-30 ms) corre entero en un tick, `segment_streamer.gd:312` lo llama sin `FrameSlicer`. Los otros 9 tipos de segmento no pasan de 33 ms. En sandbox la CPU es 2-3× más lenta que la documentada. Molesta. | Abierto: N-979 |
| 2026-10-19 | 5302f6b | Idem, 40 s → 400 s | La memoria estática pico sube 304 → 470 MiB con nodos estables: no es del juego, es la sonda (`tests/bench_drive.gd:233,242,266-269,354` guarda datos por frame sin tope; con topes queda plana en 287-293 MiB a 400 s). `progress=0.00` en endless y ~99 rescates por 400 s también son de la sonda (autopiloto sin frenar tras `CurveSegment`); posible nota para `pulidor-jugabilidad`: Chicane/SCurve atrapan al camión entrado mal alineado. Cosmético. | Abierto: N-980 |
