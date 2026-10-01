# Prometeus

[![Tests](https://github.com/Delestal94/Prometeus/actions/workflows/tests.yml/badge.svg)](https://github.com/Delestal94/Prometeus/actions/workflows/tests.yml)

Proyecto de desarrollo de un videojuego indie (desarrollo en solitario, asistido por
IA), con el objetivo de aplicar patrones de éxito observados en juegos de Steam hechos
por 1-2 personas.

Nombre oficial del juego: **Take My Package** (desde 2026-09-22; antes el nombre de trabajo era "Do Not Drop", por eso el proyecto Godot sigue en `do-not-drop/`) — delivery cooperativo de hasta 8
jugadores: 1 conduce, hasta 7 llevan un paquete con una "trampa" cada uno (ver
`docs/definicion-proyecto.md` y `docs/requerimientos-tecnicos.md`).

## Motor
Godot 4.x — el proyecto del juego vive en `do-not-drop/`.

## Probar el prototipo

Abrí `do-not-drop/project.godot` en Godot y ejecutá con **F5**. Arranca en un
**menú principal**: "Jugar solo" entra directo sin sesión de red (el
comportamiento de siempre); "Crear sala" hostea con el transporte que esté
disponible (Steam si está corriendo, si no LAN) y entra directo a la
furgoneta sin esperar en ninguna sala — los que se sumen después aparecen
dinámicamente; "Unirse por IP" fuerza LAN y conecta al código de sala (ej. `K7QM-4TXA`,
que el HUD del anfitrión muestra en vez de la IP) o a la dirección que escribas. Los amigos de Steam también pueden sumarse aceptando una
invitación desde la lista de amigos en cualquier momento.

Atajos de línea de comandos para probar rápido sin clickear:
`-- --autostart` (solo, salteando la carga a pie), `-- --host-lan` (fuerza
LAN, sin depender de que Steam esté corriendo) y `-- --join=<ip>` (se une
por LAN a esa dirección).

**Modo Endless**: genera tramos
indefinidamente en vez de la ruta curada de 220 m, y el run termina
perdiendo (carga perdida, vuelco o salir de la ruta), nunca entregando —
ver `docs/plan-desarrollo.md` Fase 3 para el estado completo. Se entra con
el botón "Modo Endless (solo)" del menú principal, o directo por línea de
comandos:

```
<godot> --path do-not-drop -- --autostart-endless
```

(el atajo anterior pasando la escena directo con `--autostart` sigue
funcionando igual, salteando también la carga a pie:)

```
<godot> --path do-not-drop res://scenes/gameplay/level_endless.tscn -- --autostart
```

**La ruta se genera al azar en cada partida** (2026-09-22), pero **una sola
vez por sesión**: el anfitrión elige la semilla y se la pasa a cada uno que
se suma antes de que cargue el nivel (`NetworkManager.world_seed`). Hasta el
2026-09-22 cada máquina sorteaba la suya, así que en multijugador **cada
jugador veía un camino distinto** y el cliente miraba la furgoneta del
anfitrión atravesar casas que de su lado no estaban. Jugando solo la semilla
queda en 0 y la ruta se sortea fresca cada vez, como antes. en vez de un
trazado fijo, cada tramo entre una casa y la siguiente son 400-600m armados
encadenando tipos de segmento (recta, badén, chicana, puente angosto, curva
en S, ripio, zona de obras, barro (raro: el camión se atasca y la tripulación lo saca empujando, con la eslinga de la tienda o esperando a la grúa con multa) y curvas reales que doblan el rumbo del camino de
verdad). Las casas se calculan al construir la ruta: una por pasajero, con
mínimo de una si jugás solo; por eso la distancia total varía según la
tripulación. En multijugador la decide el host la primera vez que arma la ruta
de la sesión y se la pasa a cada uno que se suma junto con la semilla, así que
todos construyen las mismas casas (quien se suma después no agrega casas hasta
una partida nueva).
`CurveSegment` es el único tipo que cambia la dirección del
camino; los demás siguen siendo obstáculos dentro de un carril recto.

**El depósito** (2026-09-23): toda partida (entrega y Endless) arranca adentro del
depósito central de la empresa, con el camión estacionado mirando al portón. Elegí
**Preparar entrega**, caminá con WASD y mirá con el mouse; al acercarte a algo aparece la
acción disponible.
- **La pizarra de pedidos** (junto al camión) dice qué paquete espera cada casa y en qué
  estante está (`A-1`…`B-8`). Hay dos paquetes de cada tipo en las estanterías de
  despacho, así que hay que leerla: la casa devuelve cualquier otra caja. El mismo
  pedido figura en el cartel de cada casa y en el objetivo del HUD ("Casa 1: A-6
  (falta)"), y al agarrar una caja el aviso dice su estante.
- **E** agarra el paquete y lo deja en el rack del camión; al sentarte al volante con
  carga a bordo arranca la entrega. Si salen sin algún pedido, el juego lo avisa.
- **Vestuario** (casilleros): uniforme. **Taller** (terminal al lado del camión): camión y
  pintura, se ven al instante (los elige el anfitrión). **Suministros** (mostrador): con
  la plata del equipo, *Acolchado de estantes* (la carga sufre 25 % menos por golpes) y
  *Seguro de envío* ($30 por cada caja entregada rota), para el próximo reparto.
  **Equipo del mes** (corcho): progreso y desbloqueos.
- Cuando el camión salió y no queda nadie a pie adentro, **el portón se cierra** solo.
- Adentro no llueve (se oye en el techo), hay operarios que saludan, un autoelevador
  que frena si te le cruzás, cinta transportadora, radio, reloj con la hora real.

La entrega empieza al sentarte con la carga a bordo. Usá W/S para acelerar,
frenar y retroceder, A/D para girar y Espacio como freno de mano. **H** toca
bocina (todos la escuchan, venga de quien venga, no solo del host). Esc pausa
también durante la preparación; R reinicia.

**Entregar en las casas** (2026-09-22): frená cerca de una casa, bajate,
**E** sobre un paquete lo saca de su estante (libera el lugar y deja de
contar como carga a bordo), llevalo hasta el porche y **E** en el timbre se
lo da al vecino. El estado del paquete al momento de tocar decide la
reacción, y pasar de largo una casa penaliza: el vecino se quedó esperando.
Hasta esta versión esto era imposible — no se podía sacar un paquete ya
cargado, así que las casas de la ruta eran decorado y todas terminaban
como "no entregada" sin que nada lo puntuara.

**Abrir los paquetes** (2026-09-23): **T** (D-pad abajo) abre o cierra la
caja que tenés en las manos, la de tu asiento o la que estás mirando. Las
solapas se abren de verdad y adentro está lo que se lleva (jarrón de
porcelana, gallina, torta de bodas, masa madre), en el mismo estado que el
paquete: fisuras si está en riesgo, pedazos si se arruinó. Una caja abierta
que se vuelca o se golpea fuerte **derrama el contenido** como piezas físicas
y el paquete se pierde; y entregarla abierta baja la entrega a "con reparos".

**El celular y la foto de entrega**: con **F** sacás el celular y la pantalla
pasa a modo cámara; **click** (o RB) saca la foto de la entrega que acabás de
hacer. Da puntos por sí sola, pero lo importante viene al final: los clientes
cuyo paquete llegó golpeado se quejan en la pantalla de resultados, y la foto
de su propia puerta es lo único que cierra el reclamo. Sin foto, te lo
descuentan. Las fotos tomadas se muestran al terminar.

Podés mirar alrededor desde el asiento con el mouse; **C** vuelve a centrar la
vista hacia el frente del vehículo. Con gamepad, el **stick izquierdo** camina
o gira la camioneta, el **stick derecho** mira, su **clic** centra la vista,
los **gatillos** aceleran/frenan y el **botón sur** interactúa a pie o activa
el freno de mano al conducir. Mirar desde el asiento no cambia la dirección
del vehículo. La mirada se conserva después de las sacudidas de los impactos.

**Opciones y salir**: el menú principal tiene **Opciones** (idioma Español/English, volumen,
sensibilidad de la mirada, efectos de impacto, invertir eje Y, pantalla completa — se guardan en
`user://settings.cfg`) y **Salir**. Desde la pausa se llega a las mismas
opciones y a **Menú**, que deja la sesión limpia antes de volver.

Cualquier jugador puede pingear "¡Cuidado!" con un toque del clic de la rueda del mouse
(o D-pad arriba en gamepad); al mantenerlo aparece una rueda de seis mensajes elegibles
con mouse o stick derecho. El aviso muestra quién lo mandó sin depender de voice chat.

Si tu caja ya se arruinó, todavía podés ayudar con una caja en riesgo de un asiento
contiguo o a pie junto a ella. El segundo jugador aporta media fuerza al estabilizar o
calmar, puede completar secuencias y gana mérito por sostener la ayuda; una caja admite
como máximo al responsable y a un ayudante.

**Progreso, variantes y espectador** (2026-09-23): las entregas exitosas y el puntaje
acumulado se guardan en `user://unlock_progress.json`. Desde **Progreso** y
**Cosméticos** del menú se consultan los desbloqueos y se eligen uniforme, pintura y
vehículo; cada premio muestra por separado el avance de entregas y puntos. **Récords**
separa Entrega de Endless y conserva fecha y tamaño de la tripulación. La Furgoneta ágil
se desbloquea con 4 entregas y 350 puntos. Si sos pasajero,
tu paquete se arruinó y seguís sentado, **Tab** (Back en gamepad) alterna una cámara
espectadora detrás de la furgoneta. La pantalla de resultados ahora desglosa cada fuente
del puntaje — entregas, vecinos sin atender, fotos y multiplicador — además del total.
También resume cada casa con su trampa, estado y foto; entrega premios de mérito por jugador,
cuenta cómo terminó el evento de ruta y muestra cuánto falta para el próximo desbloqueo.

## Tests

**Rostros del personaje (2026-09-24):** en Personalización, la pestaña **Rostro**
permite combinar seis estilos de ojos y seis de boca, o dejar cada parte vacía.
La vista 2D y el personaje 3D muestran la misma combinación al instante. Se guarda
en el perfil, se aplica al jugador del depósito y se replica a los compañeros.
Uniforme y camión conservan sus propias pestañas y desbloqueos.

`test_character_faces` cubre selecciones independientes, guardado/migración,
preview, materiales por jugador, parpadeo y configuración de réplica.
`test_character_motion` mide el cierre de los loops (también `TurnInPlace`), que la bola del pie apoyado no
patine en `Walk` (3,6 m/s) ni en `Stroll` (1,5 m/s), que los brazos se balanceen,
que `Jump` termine en el primer cuadro de `Idle` y el alcance real de las muñecas a la caja. `render_character_faces.gd` genera capturas para revisión visual.

**La forma normal:** `tools/run-tests.sh` corre toda la batería headless en paralelo (~1 minuto)
y muestra solo el resumen y las fallas; `tools/run-tests.sh depot traps` corre solo los tests
cuyo nombre contiene esos textos. Después de clonar, `tools/setup-hooks.sh` activa el hook
`pre-push`: cada `git push` con cambios de código corre el lint, `check_modules` y solo los tests
afectados por lo que cambia la rama contra `main` (`FULL_TESTS=1 git push` corre la batería entera;
`SKIP_TESTS=1` saltea los tests) y no sube nada si falla. GitHub Actions corre la batería completa
repartida en cuatro runners en cada push a `main` y en cada PR (es la compuerta requerida); si un test
falla en CI, `tools/run-tests.sh` anota el nombre con `::error`. Detalle en
[CONTRIBUTING.md](CONTRIBUTING.md).

Los `render_*.gd` y `check_*.gd` necesitan pantalla y alguien que mire las capturas: no son
parte de la batería (con Claude, los corre el agente `revisor-visual`).

Los **módulos portables** (`do-not-drop/modules/`, ver `docs/modulos.md`) traen sus propios tests en
`modules/<nombre>/tests/`, que la batería también corre. `tools/portability-check.sh` prueba cada módulo
solo, en un proyecto Godot vacío: si pasa, esa carpeta se puede copiar a otro juego y funciona.
`python tools/check_modules.py` revisa que ningún módulo nombre algo del juego.

Para generar el lote fijo de Steam/tienda de S-902 (cinco PNG de 1920×1080 en
`user://store_shots/`: depósito cargando, conducción con carga en riesgo, entrega,
explosión y resultados):

```
<godot> --path do-not-drop --resolution 1920x1080 --script res://tests/render_store_shots.gd
```

En builds de depuración, **F10** activa o desactiva el modo captura: oculta todas
las capas del HUD y cualquier viewmodel, y restaura su visibilidad al salir.

El balance reproducible de trampas tampoco forma parte de la batería rápida. Primero
`sim_record_drive.gd` maneja cinco rutas reales y guarda la aceleración, inclinación e impactos
de cada cuadro; después `sim_trap_balance.gd` repite esos recorridos con los siete
comportamientos y los perfiles ausente, torpe y experto, con y sin 150 ms de latencia:

```
<godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/sim_record_drive.gd
<godot> --headless --path do-not-drop --script res://tests/sim_trap_balance.gd
```

La duración completa se mide aparte con el mismo piloto automático: en cada parada un bot real
baja de la furgoneta, recoge la caja asignada, camina al timbre, la entrega y vuelve. La matriz
recorre cinco rutas con 1, 2, 3 y 4 casas a 50 km/h:

```
<godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/bench_delivery_time.gd
```

Para correr un test suelto a mano, sin abrir el editor, reemplazá `<godot>` por la ruta a tu
ejecutable (ej. `D:\Descargas\Godot_v4.7.2-stable_win64_console.exe`):

```
<godot> --headless --path do-not-drop --script res://tests/test_fragile.gd
```

Cada uno imprime `PASS` y devuelve exit code 0 si está todo bien. **Qué cubre cada test** lo dice
su propio encabezado (las líneas `## ...` debajo de `## Run:`); no hay lista que mantener a mano,
porque la lista del README la editaban todos los PRs y chocaban entre sí. El índice se arma solo:

```bash
tools/list-tests.sh              # todos: nombre — qué cubre
tools/list-tests.sh depot red    # solo los que contienen "depot" o "red"
tools/list-tests.sh --missing    # los que no tienen descripción (CI exige que salga vacío)
```

Aparte de `tests/`, `scripts/gameplay/route/route_smoke_check.gd` verifica colisiones de la ruta y
la zona de entrega.

### Rendimiento

`bench_drive.gd` construye el nivel real, sienta al conductor y deja que un piloto
automático recorra la ruta entera a fondo mientras mide cada frame. Corre **sin**
`--headless` (mide el render de verdad):

```
<godot> --path do-not-drop --script res://tests/bench_drive.gd -- --seconds=150
```

Imprime ms por frame (promedio, p50/p95/p99, máximo), draw calls, costo de física por
tick, *judder* de la cámara (qué tan parejo avanza lo que se ve: 0 es perfecto) y cada
frame que supere `--hitch=33` ms con su contexto. `--experiment=noshadow|shadow2|noplants|nodress|nohouses|nosegvis|notruck`
apaga una fuente de costo para medir cuánto vale. El piloto no esquiva chicanas: si se
traba lo reubica más adelante (cuenta como `rescues`).
`check_interpolation.gd` (también con ventana) verifica la interpolación física: ruedas del
camión estacionado, puertas que se abren, caja montada y la vista del conductor avanzando en
cada frame; guarda capturas `check_interpolation_*.png` en `user://` para mirarlas. Referencia del 2026-09-23 en la
máquina de desarrollo, semilla 4242: antes de optimizar 8,6 ms/frame promedio, p95 22 ms,
~6.200 draw calls y la cámara quieta en el 64% de los frames; después ~3,6–6 ms, p95
~6,5–8 ms, ~1.500 draw calls y ningún frame quieto.

FPS reales con GPU (tareas de Nacho N-204), 2026-09-24, `bench_drive.gd` con ventana a
1920×1080, 60 s por corrida, vsync apagado. PC de desarrollo: AMD Ryzen 5 7600X, NVIDIA
RTX 4060 Ti (driver 596.36, GL Compatibility sobre OpenGL 3.3), 32 GB de RAM. `--endless`
maneja Endless y `--mood=` fuerza clima y hora.

| Modo | Clima / hora | FPS prom. | 1 % más bajo | p95 ms | Draw calls prom. |
|---|---|---|---|---|---|
| Reparto | día | 156 | 93 | 8,0 | 1.837 |
| Reparto | atardecer | 139 | 85 | 9,9 | 2.748 |
| Reparto | noche | 159 | 94 | 8,4 | 1.974 |
| Reparto | lluvia (día) | 164 | 104 | 7,8 | 1.798 |
| Endless | día | 380 | 219 | 3,6 | 530 |
| Endless | atardecer | 312 | 188 | 4,2 | 1.465 |
| Endless | noche | 375 | 244 | 3,5 | 625 |
| Endless | lluvia (día) | 393 | 261 | 3,3 | 535 |

La meta de 60 FPS estables a 1080p se cumple con margen (el 1 % más bajo nunca baja de 85).
El atardecer es el caso más caro en los dos modos (más draw calls; lo más probable son las
sombras largas del sol bajo, sin medir todavía). Una vez compilados los shaders no hay tirones; los que aparecen son de
los primeros segundos o de cuando el piloto reubica el camión. La física promedia 0,55-0,75 ms
por tick con picos de 12-19 ms. Falta medir el preset bajo en una PC modesta (N-205).

**N-204 y N-220, 2026-10-01** (base `a6c56f6` + la rama `nacho/N-220-gpu-audit`; misma PC, 1920×1080 en
ventana, vsync apagado, semilla 4242, 90 s por corrida, `--via-loader`). `bench_drive.gd` sumó:
`--quality=low|medium|high` (fuerza el preset de N-205 solo para esa corrida, sin guardarlo), `--via-loader`
(arma el nivel por la pantalla de carga del juego: modelos precargados, sonidos calientes, ruta por frames;
sin esto mide un arranque "en frío" que da tirones de primer uso que el jugador no ve), `--players=5
--cargo=full` (cuatro jugadores falsos sentados y siete cajas en el camión), `--render-scale=` (hasta 2,0, para
estresar la GPU) y los experimentos `noparticles|nolights|notransp|nobatch`; el informe suma un censo de la
escena, el costo de la física partido en scripts y paso de Jolt, y los cuerpos rígidos despiertos.
`bench_load_times.gd` (nuevo) mide menú, carga de cada nivel y memoria. Preset **Alto** (el de fábrica) y
**Bajo**; "1 % bajo" = 1000 / p99:

| Modo | Clima / hora | Alto: FPS prom. | Alto: 1 % bajo (p99 ms) | Alto: draw calls | Bajo: FPS prom. | Bajo: 1 % bajo (p99 ms) | Bajo: draw calls |
|---|---|---|---|---|---|---|---|
| Reparto | día | 143 | 89 (11,3) | 2.644 | 166 | 98 (10,3) | 1.932 |
| Reparto | atardecer | 117 | 71 (14,1) | 4.387 | 137 | 69 (14,5) | 3.322 |
| Reparto | noche | 140 | 85 (11,7) | 2.740 | 152 | 90 (11,1) | 2.234 |
| Reparto | lluvia (día) | 152 | 102 (9,8) | 2.497 | 172 | 115 (8,7) | 1.941 |
| Endless | día | 376 | 231 (4,3) | 782 | 406 | 258 (3,9) | 432 |
| Endless | atardecer | 332 | 187 (5,4) | 1.375 | 323 | 187 (5,4) | 1.277 |
| Endless | noche | 390 | 243 (4,1) | 579 | 394 | 242 (4,1) | 558 |
| Endless | lluvia (día) | 391 | 248 (4,0) | 453 | 396 | 239 (4,2) | 435 |

Las 16 corridas: de 0 a 3 frames de más de 33 ms cada una (el peor, 72 ms) y ningún tirón de física (pico
de 21 ms por tick). **Meta de N-204: se cumple en esta PC.** 60 FPS estables a 1080p con el preset de fábrica: el peor caso (Reparto al atardecer)
promedia 117 y su 1 % bajo es 71; el preset Bajo no baja de 137 de promedio ni de 69 de 1 % bajo (la meta es
45). En esta PC el Bajo sobra: el juego va limitado por la CPU (un núcleo: dibujar ~2.600 objetos con
GL Compatibility y los scripts), así que el Bajo solo gana 9-17 % en Reparto y casi nada en Endless. **No hay PC
modesta a mano**, y lo que sigue es una emulación, no un número de otra máquina: con `--render-scale=2.0`
(4 veces los píxeles) el Reparto de día sigue en 146 FPS y, a 5.128×2.842 internos (7 veces los píxeles de
1080p, Alto con MSAA 4×, al atardecer) en 109 FPS en Reparto y 197 en Endless; la GPU de esta PC tiene
margen de más de 7× en relleno, y la memoria de video sube 258 → 774 MiB sin que el cuadro se mueva.
Limitar a 2 núcleos físicos (afinidad) tampoco cambia nada (154 y 144 FPS en Reparto con Bajo y Alto): el
juego usa ~1 núcleo. Lo que no se puede emular es una CPU de un solo hilo más lenta (reloj e IPC): ahí el
costo de dibujo (~2.600 draw calls) es lo que pesa, ver oportunidades en `docs/rendimiento-pc.md`.

Física con 5 jugadores y el camión lleno (Reparto de día, Alto, 60 s, 4 jugadores falsos sentados y siete cajas
cargadas, una por soporte; mismo proceso, sin red): promedio 129-132 FPS y p99 11,4 ms contra 156 FPS y 9,4 ms
con un jugador y una caja. Jolt no informa `PHYSICS_3D_ACTIVE_OBJECTS` / `COLLISION_PAIRS` / `ISLAND_COUNT`
(valen 0), así que el bench cuenta los `RigidBody3D` despiertos (de 3 a 11-14, sobre 130-146 en total) y parte
el tick: scripts 0,5 → 0,9 ms y paso de Jolt 0,4 → 0,7 ms de promedio, nunca más de 3 ms. Detalle y el tirón
que apareció (derramar una caja ruinosa: 100 ms por tick) en `docs/rendimiento-pc.md`.

Carga y memoria (`bench_load_times.gd`, ventana 1920×1080): del arranque del motor al menú dibujado, 3,6 s
(3,2 s motor y autoloads, 0,4 s el menú). Desde el botón hasta que sube la cubierta de carga: Reparto 4,5 s la
primera vez y 3,3 s con los cachés calientes; Endless 1,5 s y 0,9 s. Con el nivel a la vista, los primeros 120
frames no pasan de 23 ms. Memoria estática: menú 136 MiB; Reparto listo 448 MiB (pico de la corrida 479);
Endless listo 205 MiB solo y 351 MiB después de un Reparto (pico 266); al volver al menú quedan 340 MiB
(los cachés `static`), sin crecer en cuatro idas y vueltas ni dejar huérfanos.

`bench_depot.gd` (S-208) mide lo que cuestan por frame los paquetes y el HUD en el depósito:
14 cajas, 5 jugadores, semilla 4242, 600 frames, headless (`--fixed-fps 60`, sin GPU). Llama a mano
el `_process` de cada `package_feedback.gd` y del HUD con `Time.get_ticks_usec()` (esa es la cifra
de la meta) y la contrasta con el tiempo de frame con esos scripts apagados;
`Performance.TIME_PROCESS` se imprime pero oscila varios ms entre pasadas idénticas en render por
software, así que no sirve para juzgar. Referencia del 2026-09-30, CPU de la nube, render por
software (comparable solo con corridas de la misma máquina). Meta: paquetes + HUD < 1,5 ms por frame.

| | Antes | Después |
|---|---|---|
| `package_feedback.gd` (14 nodos), prom. / p95 | 0,30 / 0,46 ms | 0,29 / 0,42 ms |
| HUD `_process`, prom. / p95 | 0,37 / 0,50 ms | 0,12 / 0,18 ms |
| Paquetes + HUD, prom. / p95 | 0,67 / 0,95 ms | 0,41 / 0,59 ms |
| Frame completo con ellos encendidos menos apagados | 0,9-1,0 ms | 0,6-0,7 ms |

Cumple la meta desde antes (0,67 ms) y con más margen ahora. El costo que sobraba estaba en
`HudPrompts.refresh_hint()`: reescribía el texto BBCode y el color del `RichTextLabel` de
controles cada frame aunque no hubieran cambiado (dos tercios del `_process` del HUD); ahora
escribe solo si cambió, igual que los avisos (`hud_notices.gd`) y la etiqueta del envío de
`package_feedback.gd`.

`bench_route_shocks.gd` mide qué tan fuerte golpea cada tipo de tramo a la carga
(headless, `--fixed-fps 60`, `-- --cruise=50` o `--cruise=30`); la tabla está en
`docs/parametros-diseno.md` ("Golpes por tipo de tramo").

`bench_route_duration.gd` mide cuánto dura una entrega manejándola: arma la ruta real para
cada semilla y cantidad de casas, y un piloto automático la recorre a velocidad de crucero,
frenando en cada casa (cada parada suma 25 s). Corre headless y más rápido que el tiempo
real con `--fixed-fps 60`:

```
<godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/bench_route_duration.gd -- --seeds=1-20 --houses=1,2,3,4
```

Imprime una línea por corrida y una tabla por cantidad de casas (minutos promedio, máximo y
mínimo, velocidad media). Resultados en `docs/parametros-diseno.md` ("Duración de la entrega").


La prueba de controles de cámara requiere una ventana real: el controlador
headless de Godot no captura el mouse. Se abre brevemente y se cierra sola:

```
<godot> --path do-not-drop --resolution 320x180 --script res://tests/test_look_controls.gd
```

Comprueba mouse/stick, límites de giro, centrado, orientación relativa al asiento,
sacudidas, bloqueo en pausa/menús, movimiento a pie y velocidad de giro a 30/120 FPS.

## Multijugador

Hay dos transportes detrás de la misma interfaz `MultiplayerPeer` de Godot, y
`NetworkManager` elige solo:

- **Steam (así se juega de verdad).** Sala de Steam relayeada por Valve: sin
  abrir puertos, sin firewall, con NAT punch-through. Es lo que usan PEAK y
  Lethal Company. Requiere tener instalada la extensión **GodotSteam**, que ya
  trae el `SteamMultiplayerPeer` incorporado.
- **ENet (desarrollo local).** Un socket UDP común contra `127.0.0.1`. Se queda
  porque para probar dos instancias en la misma máquina Steam es incómodo: P2P
  entre dos copias con la misma cuenta no funciona bien.

El proyecto **compila y testea sin GodotSteam instalado** — todo lo de Steam se
alcanza por `Engine.get_singleton` / `ClassDB.instantiate`, nunca por nombre. Si
la extensión no está, `NetworkManager` cae a ENet solo.

### GodotSteam (ya instalado)

**GodotSteam GDExtension 4.22.1** está en `do-not-drop/addons/godotsteam/`, con
binarios precompilados para Windows, Linux, macOS y Android. Declara
`compatibility_minimum = 4.4`, así que funciona con nuestro 4.7.2.

No hace falta activar ningún plugin: el `plugin.cfg` que trae es solo un
*actualizador* opcional, y la GDExtension carga sola desde su `.gdextension`.

`steam_appid.txt` está en el repo con **480** (Spacewar, la app de ejemplo de
Valve). Sirve para desarrollo: da P2P y NAT punch-through sin tener un app id
propio. **No se puede publicar con ese id** — cuando haya app id real, se
reemplaza.

Para que Steam funcione de verdad hace falta, además, **tener Steam abierto y
con sesión iniciada**. Si no lo está, `NetworkManager` cae a ENet solo; podés
comprobar en qué estado está con:

```
<godot> --headless --path do-not-drop --script res://tests/check_steam_extension.gd
```

> Si clonás el repo en otra máquina (o agregaste algún script con
> `class_name` nuevo), corré una vez
> `<godot> --headless --path do-not-drop --import` antes de los tests: Godot
> registra ahí tanto las GDExtensions como las clases globales
> (`class_name`), y sin ese paso ni la extensión de Steam carga ni un
> `class_name` nuevo se puede referenciar por nombre, aunque los archivos
> estén.

> Al exportar, usá las **plantillas normales de Godot**, no las de GodotSteam.
> Con la versión GDExtension, mezclarlas trae problemas.

### Prueba de conexión local (manual, dos procesos)

El test siempre fuerza el transporte **ENet** (no AUTO), a propósito: si Steam
está corriendo en la máquina, AUTO elegiría Steam, y el P2P de Steam entre dos
instancias con la misma cuenta no anda bien — no tiene sentido pelear con esa
limitación acá, cuando lo que este test verifica es la conectividad local.

Corré el anfitrión en una terminal y el cliente en otra:

```
<godot> --headless --path do-not-drop --script res://tests/net_smoke.gd -- --host
<godot> --headless --path do-not-drop --script res://tests/net_smoke.gd -- --client
```

Ambos imprimen `PASS` si se encuentran.

Con tres jugadores (tareas de Nacho N-207), `tools/run-net-trio.sh` levanta un anfitrión y dos
clientes ENet en localhost (el segundo entra 6 s tarde) y compara que los tres vean la misma
semilla, las mismas casas, los mismos pedidos, la misma ruta y la misma fase del cruce de tren.
Después los dos clientes piden a la vez la misma caja (N-213): el anfitrión se la da a uno solo y
los tres tienen que nombrar al mismo dueño (`grab=`)
(`GODOT=<ejecutable sin _console> tools/run-net-trio.sh`).

**Usá el ejecutable normal de Godot, no el que termina en `_console.exe`.**
En Windows, las reglas del firewall quedan atadas a la ruta exacta del
ejecutable — una regla aprobada para `Godot_v4.7.2-stable_win64.exe` no cubre
`Godot_v4.7.2-stable_win64_console.exe`, aunque sean la misma versión. Con el
binario equivocado, el anfitrión abre el puerto pero nunca ve llegar a nadie,
en silencio (sin ventana, tampoco hay pop-up de permiso que aceptar). Podés
revisar qué reglas tenés con:

```powershell
Get-NetFirewallRule -DisplayName "Godot Engine" | Get-NetFirewallApplicationFilter
```

Si ninguna regla apunta al ejecutable que estás usando, esa es la causa.

Para levantar el juego salteando la fase de carga a pie (útil al iterar sobre el
manejo):

```
<godot> --path do-not-drop -- --autostart
```

### Medir la red y simular mala conexión

**F3** abre, en cualquier pantalla, el panel de red de tu máquina: transporte (Steam o LAN) y
rol, y una fila por conexión con ping, pérdida, KB/s que entran y salen, y bytes en cola, más
los totales. En Steam los números salen de `Steam.getConnectionRealTimeStatus` (por conexión);
en LAN, de ENet, que da ping y pérdida por jugador pero el tráfico solo como total y ninguna
cola. `-- --net-stats` arranca con el panel abierto.

`-- --net-sim=<lag>,<jitter>,<pérdida>` (ms, ms, %) convierte la conexión de ese proceso en una
mala:

- **Steam:** los sockets de Steam demoran, desordenan en el tiempo y pierden cada paquete, en
  las dos direcciones (`NETWORKING_CONFIG_FAKE_PACKET_*`). La mitad del lag va a lo que sale y
  la mitad a lo que entra, así que la ida y vuelta crece en `lag`; cada paquete espera además
  entre 0 y `jitter` ms en cada dirección, y se pierde el `pérdida` % de los paquetes.
- **LAN (ENet):** ENet no simula nada, así que se retienen las poses del camión en el
  cliente (el mismo colchón que `--fake-lag`) y el input de cuidado que el cliente manda al host
  (`tender_input_lag.gd`, solo de ida): `lag` más 0 a `jitter` ms tarde, y se pierde el
  `pérdida` % de las poses y de las muestras de input.

Pasalo en un solo lado (el cliente): en los dos, se suman. El panel muestra la simulación
activa.

**Perfil de prueba estándar: 150 ms, ±20 ms y 2 % de pérdida.** Toda feature de red se prueba
así antes de darla por cerrada (`docs/investigacion-red.md`). `--net-sim` solo, o
`--net-sim=standard`, es ese perfil:

```
<godot> --path do-not-drop -- --join=<ip> --net-sim
<godot> --path do-not-drop -- --net-sim=150,20,2 --net-stats
```

## Documentación

### Vigente (proyecto actual: Take My Package)
- `docs/investigacion-mercado.md` — investigación de 20 juegos de Steam hechos por 1-2
  personas: equipo, ventas, motor, tiempo de desarrollo. (Contexto general, sigue
  vigente como referencia de fondo.)
- `docs/checklist-exito.md` — items replicables extraídos de esa investigación.
  (Igual de vigente, son patrones generales.)
- `docs/mecanicas-candidatas.md` — banco de mecánicas transversales reutilizables
  (recurso de referencia general para futuras decisiones).
- `docs/definicion-proyecto.md` — **definición del concepto actual** (Take My Package).
- `docs/inventario-assets.md` — **la lista de assets**: qué existe, qué falta integrar y qué falta crear.
- `docs/requerimientos-tecnicos.md` — stack técnico, motor, networking, arte, diseño
  de adicción/rejugabilidad.
- `docs/arquitectura.md` — arquitectura de software del proyecto (componentes,
  patrones, estructura de carpetas).
- `docs/plan-desarrollo.md` — plan de desarrollo por fases, con Definition of Done.
- `docs/parametros-diseno.md` — valores numéricos iniciales de cada trampa y fórmula
  de puntaje.
- `docs/controles-y-ui.md` — esquema de controles y flujo de UI/lobby.
- `docs/convenciones-godot.md` — Input Map, capas de física, estructura real de
  carpetas y convenciones de nombres dentro del proyecto Godot (`do-not-drop/`).
- `docs/direccion-visual.md` — punto de vista del jugador (FOV, límites de cámara),
  paleta de colores, iluminación, qué se ve y qué no, efectos visuales y pipeline de
  arte para la Fase 6.
- `docs/especificaciones-visuales.md` — inventario numerado de 100 mejoras concretas
  de modelado, animación, ambientación, cámara e interacción entre modelos, con
  prioridad por costo/impacto.
- `docs/colaboracion-equipo.md` — cómo se reparte el trabajo entre dos personas en
  paralelo (Nacho y Slatex): división por dominio de archivos, zona compartida y
  flujo de trabajo.
- `docs/avisos/` — un archivo por aviso de cambio en la zona compartida o en archivos del
  otro integrante (los anteriores al 2026-09-30, en `archivo-2026-09.md`).
- `docs/tareas-nacho.md` / `docs/tareas-slatex.md` — 100 tareas cada una, repartidas
  por dominio (vehículo/ruta/ambientación vs. jugador/paquetes/interacción/UI/
  progresión) para minimizar conflictos al trabajar en paralelo.
- `docs/agregar-vehiculo.md` — convención que `VehiclePresentation` espera de
  cualquier vehículo (nombres de nodo, no rutas fijas) para sumar uno nuevo sin
  tocar ese script.

### Archivado (`docs/historial-exploracion/`)
Documentos de una etapa de exploración anterior, **superados** por el pivote a
"Do Not Drop" (hoy Take My Package). Se conservan como registro del proceso, no como referencia vigente:
- `mvp-candidatos.md`, `ideas-candidatas.md`,
  `opcion-descartada-aseguradora-paranormal.md`.
