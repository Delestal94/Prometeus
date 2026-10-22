# Rendimiento en la PC (build y FPS diarios)

Serie de la rutina `pc-build` (`.claude/rutinas/pc-build.md`): una fila por corrida, sobre el commit de
`origin/main` de ese día. Sirve para ver tendencias: una caída de FPS o una build rota aparecen al día
siguiente.

**PC:** NVIDIA RTX 4060 Ti (driver 610.88, GL Compatibility sobre OpenGL 3.3), AMD Ryzen 5 7600X,
32 GB de RAM, Windows 11. **Resolución:** 1920×1080 en ventana (`--resolution 1920x1080 --windowed`),
vsync apagado (lo apaga el bench).

**Cómo se mide:** `tests/bench_drive.gd` con ventana, semilla 4242, 150 s en reparto y 150 s en Endless
(`--endless`):

```
<godot> --path do-not-drop --resolution 1920x1080 --windowed --script res://tests/bench_drive.gd -- --seconds=150 [--endless]
```

- FPS 1 % bajo = 1000 / p99 ms (el bench no lo imprime).
- Memoria = pico de memoria estática que imprime el bench (no el valor al final).
- Build = export release de "Windows Desktop" a `builds/windows/` y smoke test del `.exe`.
- La serie diaria es "en frío": instancia el nivel directo, sin la pantalla de carga. Desde N-220 el bench acepta
  `--via-loader` (arma el nivel como el juego: modelos precargados, sonidos calientes, ruta por frames) y esa es
  la que mide lo que ve el jugador; los tirones de primer uso de la serie en frío son, en su mayoría, de ese
  arranque (ver "Corrida en frío contra la del juego"). Las dos series no se comparan entre sí.
- Una caída de más del 10 % en FPS promedio o 1 % bajo contra el promedio de las últimas 5 filas, o un
  p99 de más de 33 ms, es una tarea en `tareas-nacho.md`. Con "PC ocupada" en Notas no se comparan.

| Fecha | Commit | Build | FPS reparto (prom / 1 % bajo) | FPS Endless (prom / 1 % bajo) | p99 ms (reparto / Endless) | Draw calls (reparto / Endless) | Memoria MiB (reparto / Endless) | Notas |
|---|---|---|---|---|---|---|---|---|
| 2026-09-30 | `390ee37` | OK, 136 MB | 142 / 72 | 333 / 152 | 13,9 / 6,6 | 2.165 / 463 | 388 / 228 | Primera fila. Reparto: `HUD_RUN_STUCK` a los 116 s (progreso 0,99); los últimos 34 s midieron la pantalla final. Endless: 16 tirones de física de 35-86 ms. Editor de Godot abierto en segundo plano. |
| 2026-10-01 | `1234ed6` | OK, 131 MB | 153 / 95 | 395 / 250 | 10,5 / 4,0 | 2.263 / 460 | 462 / 276 | Reparto: terminó la ruta a los ~108 s, sin `HUD_RUN_STUCK`; 16 frames de más de 33 ms (11 en los primeros 2,2 s de carga, 5 sueltos de 64-195 ms sin física). Endless: 2 frames de más de 33 ms (83 y 255 ms, no son de física); ya no aparecen los 16 tirones de física de ayer. Pico de física por tick: 18,2 / 14,6 ms. La memoria subió 19-21 % contra la fila anterior; no es criterio de tarea, pero queda a la vista. Capturas con GPU OK. Editor de Godot abierto en segundo plano. |
| 2026-10-02 | `5b77246` | OK, 133 MB | 173 / 110 | 467 / 313 | 9,1 / 3,2 | 2.256 / 426 | 465 / 288 | **No comparable con las filas anteriores: mide sin HUD** (regresión del #208, N-919: en un `--script` `hud.gd` no compila y el `HUD` queda sin script; objects 2.542 → 2.255), así que la suba de FPS no cuenta y no se crean tareas de FPS por esta fila. Reparto: terminó la ruta a los ~115 s, sin `HUD_RUN_STUCK`; 2 frames de más de 33 ms (40 ms en la carga, 37 ms a los 24,6 s al nacer la cámara de foto de un rescate). Endless: 150 s sin frames de más de 33 ms. Pico de física por tick: 22,9 / 9,5 ms (de scripts, no de Jolt). El export no copió `steam_appid.txt` (se copió a mano a la build). Capturas con GPU OK (`render_route_dressing` de noche: el borde del camino se lee justo). Editor de Godot abierto en segundo plano. |
| 2026-10-04 | `c63e983` | OK, 134 MB | 22 / 3,9 | 21 / 4,0 | 255,3 / 253,0 | 2.331 / 468 | 468 / 229 | **PC ocupada: no se compara ni crea tareas.** Un juego de Unreal (LOCKDOWN Protocol) tenía la GPU al 90-99 % (7 GB de VRAM, 140 W) y ~5 núcleos de CPU durante las dos corridas; mediana de frame 13,4 / 11,6 ms, pero 815 / 1.063 frames de más de 33 ms (190-255 ms, de GPU compartida, no de scripts). Reparto: no terminó la ruta en 150 s (progreso 0,98, 45 rescates), sin `HUD_RUN_STUCK`. Endless: pico de física por tick 452 ms (scripts, no Jolt; coincide con la contención). Vuelve a medir con HUD (#253, N-919): objects por frame 2.795 en reparto (2.255 sin HUD el 02/10) y sin `SCRIPT ERROR`. Export y smoke test del `.exe` OK; `steam_appid.txt` se copió a mano a la build (el export no lo copia; va solo en builds de prueba). Capturas con GPU OK (depósito, ruta de noche, túnel, menú); en `render_route_house` de noche la calzada es un azul casi plano. Editor de Godot abierto en segundo plano. |
| 2026-10-12 | `59c64f6` | OK, 135 MB | 82 / 55 | 159 / 92 | 18,1 / 10,9 | 2.324 / 458 | 479 / 256 | **PC ocupada: no se compara ni crea tareas.** Con la PC "ociosa" la GPU estaba al 24-49 % y 5,5-7,6 GB de VRAM ocupados por procesos ajenos (League Client, un `python` de ComfyUI, Discord, navegadores); reparto y Endless cayeron por igual (-50 % / -64 % contra la serie) y la física por tick quedó normal (1,5 / 1,2 ms prom.), así que es frame completo compartido, no scripts. Versión `v0.1.0-15-g59c64f6` (build en `builds/windows/2026-10-12-v0.1.0-15-g59c64f6/`, `.pck` 25,8 MB contra 24,8 del 04/10). Reparto: terminó la ruta a los ~115 s, sin `HUD_RUN_STUCK` ni `SCRIPT ERROR`; 6 frames de más de 33 ms (3 en la carga, 64 ms a los 24,6 s en el rescate de la cámara de foto, como el 02/10). Endless: 6 frames de más de 33 ms (dos con el `Segment13`). Pico de física por tick 40,2 / 15,7 ms (scripts, no Jolt). **Preset bajo (lunes, N-205):** reparto 88 / 59 FPS, 1.835 draw calls; Endless 227 / 109 FPS, 497 draw calls; memoria de video 218 / 168 MiB (272 / 223 en alta); en reparto bajo un frame de 439 ms en el mismo rescate de la cámara de foto. `steam_appid.txt` se copió a mano a la build (el export no lo copia). Smoke test del `.exe` OK (en ventana y headless, sin errores de script). Capturas con GPU OK (depósito, ruta de noche, túnel, menú): sin sombras faltantes ni luces quemadas. |

## Pico de física al generar un tramo de Endless (N-219)

Headless, sin GPU (`--headless --script res://tests/bench_drive.gd -- --endless --cpu-only --seconds=90 --seed=4242`),
mismo escenario y semilla antes y después. "Pico por tick" es el máximo de `physics per tick` del bench (del
`physics_frame` al siguiente `process_frame`, o sea incluye el `_physics_process` del streamer). Medido en una PC
compartida con otros procesos: los números sueltos oscilan unos ms.

| Qué | Antes | Después |
|---|---|---|
| Pico por tick (3 corridas antes / 5 después) | 102,7 / 103,6 / 125,6 ms | 12,9 / 10,2 / 17,1 / 20,8 ms (y 127 ms en una corrida con la PC ocupada) |
| Tick promedio | 1,01 ms | 0,98-1,24 ms |
| Construir un puente (`add_child`) | 93 ms la primera, 34-44 ms las siguientes | 3-4 ms |
| Construir un túnel | 22-28 ms | 4-5 ms |
| Construir tramo de obras | 18 ms | 2 ms |
| Unir geometría (`DressingBatcher`) en el mismo tick | 6-11 ms (túnel/puente) | 4-9 ms, un tick después |
| Ticks de más de 20 ms en 90 s (mido frame, no solo física) | 23 | 15-35 según carga de la PC (ruido: los frames de 20-30 ms con `physics` < 3 ms no son del streamer) |

Causa: no eran los `StaticBody3D`/shapes ni el terreno. `RouteSegment._model()` hacía `load()` del `.glb` para cada
pieza y el `PackedScene` se liberaba al instanciar, así que un puente leía ~40 veces del disco; el primer puente además
sintetizaba el loop del río (~55 ms), y la unión de geometría corría en el mismo tick que la construcción.

Medido con ventana real en N-220 (más abajo): el primer tramo de cada tipo en una corrida "en frío" cuesta frames
de 80-120 ms (modelos, mallas y shaders de primer uso) que desaparecen por la pantalla de carga del juego, y con
el camión lleno el paso de Jolt no pasa de 3 ms por tick.

## Auditoría gráfica y física con ventana real (N-220, N-204), 2026-10-01

Base `a6c56f6` + la rama `nacho/N-220-gpu-audit`. Misma PC de la tabla de arriba, 1920×1080 en ventana, vsync
apagado, semilla 4242, Alto salvo que se diga otra cosa. Las tablas de FPS por clima y preset están en el README
→ Rendimiento. Comandos (todos con `--resolution 1920x1080 --windowed --script res://tests/bench_drive.gd --`):

```
--seconds=90 --mood=soleado_atardecer --quality=low --via-loader [--endless]    # una celda de la tabla del README
--seconds=60 --players=5 --cargo=full --via-loader [--endless]                  # camión lleno
--seconds=45 --experiment=nodress|nosegvis|noshadow|nolights|noparticles|notransp|nobatch|nohouses|notruck
--render-scale=2.0                                                              # 4 veces los píxeles
res://tests/bench_load_times.gd -- --trips=solo,endless,solo,endless            # menú, carga y memoria
```

### Qué hay en la escena (censo del bench, de día)

| | Reparto | Endless |
|---|---|---|
| Mallas visibles | 5.208 | 933 |
| `MultiMeshInstance3D` (instancias) | 1.297 (3.319) | 1 (600) |
| Mallas que proyectan sombra | 6.318 | 788 |
| Mallas transparentes (estimado por material) | 74 | 32 |
| `GPUParticles3D` (partículas) | 3 (82; con lluvia 4 y 1.482) | 3 (82) |
| Luces: `SpotLight3D` / `OmniLight3D` / sol (con sombra) | 26 / 6 / 1 (4) | 6 / 4 / 1 (4) |
| Cuerpos físicos | 821 | 78 |

### Dónde se va el cuadro (experimentos, 45 s en frío, Reparto de día salvo que se diga)

"Costo" = ms por frame promedio de la base menos el del experimento (un experimento a la vez; lo que cae dentro del
ruido de ±0,3 ms no vale nada).

| Fuente | Base | Sin la fuente | Costo | Draw calls |
|---|---|---|---|---|
| Decorado de la ruta (`nodress`) | 7,01 ms | 3,53 ms | **50 %** | 2.648 → 1.084 |
| Mallas de los tramos (`nosegvis`) | 7,01 | 4,72 | 33 % | 2.648 → 1.523 |
| Camión (`notruck`) | 7,01 | 6,15 | 12 % | 2.648 → 2.394 (254 el camión) |
| Casas (`nohouses`) | 7,01 | 6,29 | 10 % | 2.648 → 2.417 (231) |
| Luces que no son el sol (`nolights`) | 7,01 | 6,39 | 9 % | iguales: cuesta sombreado, no dibujos |
| Sombras del sol (`noshadow`) | 7,01 | 6,45 | 8 % | 2.648 → 1.693 (955 de la pasada de sombras) |
| Plantas del bosque (`noplants`), partículas, transparencias (74 mallas) | 7,01 | 7,17-7,39 | ruido | iguales |
| **Atardecer**: sombras del sol | 9,00 | 5,80 | **36 %** | 4.778 → 1.593 (3.185) |
| Atardecer: luces | 9,00 | 8,42 | 6 % | |
| Noche: luces | 7,11 | 6,47 | 9 % | |
| Lluvia: partículas (1.482 gotas) | 7,05 | 6,90 | 2 % | |
| **Endless de día**: sin fusionar tramos (`nobatch`, lo que arregló el PR #35) | 2,37 | 3,10 | +31 % | 445 → 971 |
| Endless: camión | 2,37 | 1,93 | 19 % | 445 → 207 |
| Endless: sombras (de día / al atardecer) | 2,37 / 3,07 | 2,37 / 2,35 | 0 % / 23 % | 445 → 153 / 1.427 → 203 |

Lectura: el costo es de CPU, de **cuántos objetos se dibujan** (el Reparto tiene 1.297 multimeshes de 2,6 instancias
en promedio), no de píxeles ni de partículas ni de transparencias. El atardecer es el caso caro por las sombras del
sol bajo: sus sombras largas meten ~3.200 objetos más en la pasada de sombras. Con `shadow2` (dos cascadas) los draw
calls bajan a 3.426 y el frame no mejora (9,31 ms). La lluvia y la noche cuestan poco de más.

### Contra la referencia vieja y el PR #35 (Reparto y Endless de día, 45 s en frío, misma PC y semilla)

| Código | Reparto: FPS / draw calls / mallas | Endless: FPS / draw calls |
|---|---|---|
| 2026-09-24 (`f5d50dd`, el código de la referencia del README) | 195 / 1.927 / 2.992 | 453 / 464 |
| 2026-09-29 antes del PR #35 (`b1ff656`) | 130 / 2.644 / 3.750 | 294 / 1.079 |
| 2026-09-29 con el PR #35 (`96c353a`) | 130 / 2.641 / 3.750 | 376 / 442 |
| 2026-10-01 (hoy, mismo bench) | 143 / 2.648 / 5.210 | 422 / 445 |

El #35 hizo lo que decía: en Endless **baja 59 % los draw calls (1.079 → 442) y el frame 22 %** (3,41 → 2,66 ms) al
fusionar cada tramo al nacer, y no toca el Reparto (que ya fusionaba). Hoy Endless sigue en 445 (apagar la fusión con
`nobatch` lo devuelve a 971). El Reparto **subió** desde el 09-24: 1.927 → 2.644 draw calls (+37 %) y 5,1 → 7,0 ms,
con el mundo más grande (la ruta pasó de 1.412 a 2.086 m, las mallas visibles de 2.992 a 5.210, los `SpotLight3D` de 8 a
26 y las luces con sombra de 1 a 4 por N-319); desde el #35 los draw calls están planos. Que hoy (143 FPS) ande mejor
que el 09-29 (130) con 39 % más de mallas no se investigó.

### Camión lleno y 5 jugadores (60 s, Reparto de día, Alto)

| Escenario | FPS prom. | p99 | Tick de física (prom. / pico) | Scripts + paso de Jolt (prom.) | `RigidBody3D` despiertos |
|---|---|---|---|---|---|
| 1 jugador, 1 caja (la base de siempre) | 156 | 9,4 ms | 0,90 / 25 ms | 0,50 + 0,40 ms | 3,3 de 130 |
| 5 jugadores, sin carga | 149 | 9,7 ms | 1,02 / 20 ms | 0,57 + 0,45 | 5,3 de 134 |
| 5 jugadores, camión lleno (7 cajas): **antes** del arreglo | 127-132 | 11,7-13,3 ms | 1,62-1,69 / **101 ms** | 0,95 + 0,67 | 12-14 de 147 |
| ídem, **después** | 129-132 | 11,4 ms | 1,59-1,65 / 28-42 ms | 0,91 + 0,69-0,74 | 11-14 de 147 |
| Endless, 1 jugador | 394 | 4,9 ms | 0,77 / 10 ms | 0,47 + 0,30 | 2,3 de 34 |
| Endless, 5 jugadores, camión lleno | 370 | 5,1 ms | 1,23 / 26 ms | 0,75 + 0,48 | 14 de 45 |

"5 jugadores" = el local más cuatro `Player_<peer>` falsos en el mismo proceso (sentados en los asientos que cuidan
un soporte cuando hay carga; parados en el depósito cuando no); "camión lleno" = siete cajas, una por soporte
(`package_mount`). No hay red: se mide el costo de simular, dibujar y mover, no el de replicar.

- Con Jolt, `Performance.PHYSICS_3D_ACTIVE_OBJECTS`, `COLLISION_PAIRS` y `ISLAND_COUNT` valen siempre 0 (el servidor de
  Jolt de Godot no los informa). `TIME_PHYSICS_PROCESS` sí, pero promedia distinto del tick medido. Por eso el bench
  cuenta los `RigidBody3D` despiertos y parte el tick con un nodo que corre último en `_physics_process`: lo anterior son
  los scripts y lo posterior el paso de Jolt. Los pares de colisión no se pueden leer; los contactos que informan los
  cuerpos (`--contacts`) incluyen los de cuerpos dormidos y no sirven de medida.
- Lo que cuesta el camión lleno: +0,4 ms de scripts (siete cajas con sus trampas y su cuidado) y +0,3 ms del paso de
  Jolt por tick, y +1,2 ms de frame en total contra una caja. Cuatro jugadores más suman 0,3 ms de frame. El paso de
  Jolt no pasó de 3 ms por tick en ningún caso del Reparto (7 ms en Endless).
- **Problema encontrado y arreglado**: cada caja que se arruinaba derramaba su contenido en un tick de física de
  **40-110 ms** (picos de 85-200 ms por tick con el camión lleno; en el Reparto de 1 caja, 59 ms). Causa:
  `package_contents_view.gd` `_throw_piece()` armaba el collider de cada pieza con
  `mesh.create_convex_shape(true, true)`; con `simplify = true` el motor tarda 10-70 ms **por pieza** (también un
  fragmento de 4 caras; la gallina arruinada, 8 piezas, 227 ms) y rellena las piezas chicas hasta 32 puntos. Con
  `(true, false)` el casco de las mismas mallas tarda menos de 2 ms (microbench headless sobre las mallas de los
  contenidos). Pico de física por tick con el camión lleno: 101 → 28-42 ms; frame máximo 109 → 36 ms; frames de más de
  33 ms en 60 s: 4-5 → 1-2. Test: `test_package_unboxing` ahora exige que derramar una caja ruinosa tarde menos de
  60 ms (con el código viejo da 227 ms). Aviso a Slatex (es su archivo): `docs/avisos/2026-10-01-spill-convex-hull.md`.
- Lo que queda de picos con el camión lleno (26-42 ms, 1-2 por minuto): la nube de polvo y la ragdoll del torso que
  nacen al arruinarse una caja (`RuinDust`, `Torso`: 3 y 20 nodos nuevos en un tick). No se tocó (ya bajo 43 ms).

### Corrida en frío contra la del juego

La misma matriz de 16 corridas (2 modos × 4 climas × 2 presets, 90 s), una vez "en frío" (el nivel instanciado
directo) y otra con `--via-loader`:

| | En frío | Con `--via-loader` |
|---|---|---|
| Corridas con un frame de 280-540 ms | 8 de 16 | **0 de 16** (el peor frame, 72 ms) |
| Frames de más de 33 ms por corrida | 0-18 (la mayoría 1-6) | 0-3 |
| Primeros 2 s de manejo | 7-8 frames de 35-170 ms | sin tirones (0 en 15 s, 3 corridas) |
| Reparto 100 s y Endless 100 s | | máximo de frame 16,6 ms y 30,7 ms |

Los frames de 280-540 ms de la corrida en frío caen en el proceso (`TIME_PROCESS` de 400-500 ms) en momentos que no
se repiten entre corridas: lo más probable es la primera lectura de un modelo, un sonido sintetizado o un shader (el
cargador los precarga en hilos bajo la cubierta; la serie diaria no lo hace). No se probó modelo por modelo. Los
primeros segundos del nivel (35-170 ms) son de primer uso también. Con el cargador del juego el nivel entra sin
ninguno. La rutina de la PC mide en frío, y su "frames de más de 33 ms" exagera lo que ve el jugador. Al generarse un
tramo nuevo de Endless en frío todavía hay frames de 80-120 ms (mallas y materiales al renderer, el caso que N-219
dejaba pendiente); con el cargador no aparecen en 100 s.

### Carga y memoria (`bench_load_times.gd`, ventana 1920×1080, Alto)

| Momento | Tiempo | Memoria estática / video | Objetos / nodos |
|---|---|---|---|
| Arranque del motor al menú dibujado | 3,6 s (3,2 motor y autoloads + 0,4 menú) | 136 / 65 MiB | 4.285 / 711 |
| Botón → cubierta arriba, Reparto, 1.ª vez | 4,5 s (carga 0,47 + armado 3,3 + asentar 0,74) | 448 / 253 MiB | 30.271 / 13.510 |
| ídem, 2.ª vez (cachés calientes) | 3,3 s | 450 / 253 | 30.356 / 13.510 |
| Botón → cubierta arriba, Endless, sola | 1,5 s | 205 / 194 | 11.704 / 2.648 |
| ídem, después de un Reparto | 0,9 s | 351 / 240 | 13.986 / 2.648 |
| De vuelta en el menú | | 340 / 217 MiB (solo Endless: 194 / 171) | 10.800 / 712 |

- Bajo la cubierta el frame más largo es de 380 ms en frío en Reparto (17 de ~1.000 frames pasan de 33 ms; 117 ms con
  los cachés calientes) y de 411 ms en Endless en frío (110 ms caliente); los primeros 120 frames después de que sube
  no pasan de 23 ms. El cargador sigue vivo 2,8 s más por el fundido de la música, sin cubierta.
- Idas y vueltas (Reparto, Endless, Reparto, Endless): al menú vuelve siempre a 340 MiB estáticos y 712 nodos, sin
  huérfanos: no es un leak. Esos ~200 MiB estáticos (y ~150 MiB de video) sobre el menú son los cachés `static` (modelos
  y materiales fusionados, sonidos sintetizados: más de 25, repartidos en `depot_kit.gd`, `dressing_batcher.gd`,
  `route_segment.gd`, `synth_audio*.gd`...). Vaciarlos al volver al menú no es trivial (no hay un registro común) y la
  segunda carga pasaría de 3,3 a 4,5 s: se deja como está. El pico de una corrida de Reparto es de 479 MiB estáticos y
  262 MiB de video (en la serie en frío: 457 / 258; el código del 09-29: 305 / 136, con una ruta de 1.360 m en vez de
  2.086).

### Oportunidades que no se aplicaron (impacto estimado, de mayor a menor)

1. **Decorado**: 1.297 `MultiMeshInstance3D` con 2,6 instancias en promedio (un multimesh por modelo por parche de
   48 m, `DressingBatcher.CELL`). Sin decorado el frame baja 50 % y los draw calls 59 %. Un parche más grande (o juntar
   modelos del mismo material en una malla fusionada) bajaría varios cientos de dibujos; el límite es el recorte por
   frustum y las distancias de dibujo por tamaño. Estimado 15-30 % del frame en Reparto; solo vale en una CPU de un hilo
   lenta, en esta PC ya sobran 140 FPS.
2. **Camión**: 254 draw calls (12 % del Reparto y 19 % del frame de Endless, donde es más de la mitad de los dibujos).
   Fusionar las superficies del modelo por material (conservando puertas y ruedas) bajaría ~100-150 draw calls.
3. **Sombras al atardecer**: 36 % del frame en Reparto y 23 % en Endless. Acortar `shadow_distance` solo al atardecer
   o bajar a 2 cascadas no alcanza (`shadow2` no mejora); habría que limitar los casters de la pasada (decorado chico
   fuera de las sombras). Cambia el aspecto: decisión de arte.
4. **Luces**: `nolights` da 9 % de día y de noche (26 `SpotLight3D`). Un tope de luces activas por distancia al camión.
5. **Casas**: 231 draw calls (10 %), el mismo caso que el decorado.
6. **Cachés `static` al volver al menú**: ~200 MiB estáticos y ~150 MiB de video; sin urgencia (ver arriba).
7. Menos de 5 % o dentro del ruido, no vale la pena: partículas (lluvia 2 %, polvo), transparencias (74 mallas),
   plantas del bosque (3 %), `shadow2`.
8. Poner `--via-loader` en la corrida diaria de `pc-build` (o sumar una segunda serie) para que "frames de más de 33 ms"
   mida lo que ve el jugador; el cambio es de la rutina, no se tocó.

## Ancho de banda del modo Empresa (D-2002)

**Fecha:** 2026-10-22 (D-2002.2: una salida afuera y 2 vehículos lejos). **Commit:** base `origin/main` `a7405f5`
(rama `exp/D-2002.2-exit-bandwidth`). Antes: D-2002.3 el 2026-10-19 sobre `425041a` (`exp/D-2002-shed-pose-rate`) y
D-2002.1 sobre `3d4a242` (`exp/D-2002-bandwidth-budget`). Lo mide `tests/test_company_bandwidth_budget.gd` (corre en
la batería, filtro `company`; imprime líneas `COMPANY_BW`), con los casos en `tests/company_bandwidth_cases.gd`:

```
bash tools/run-tests.sh company_bandwidth
<godot> --headless --path do-not-drop --script res://tests/test_company_bandwidth_budget.gd   # con los números
```

Todo es lo que el host le manda a **cada cliente** (KB/s = 1024 B/s), sin voz (la voz es solo de Steam y tiene su
propio chequeo en `test_net_bandwidth_budget`). El número de cada caso es el de su **peor cliente**: el test prueba
el host en el galpón o a bordo de cada vehículo, y cada cliente. Cada caso da dos números:

- **Modelo:** el mundo real de la empresa (`company_root.tscn`) con cada `MultiplayerSynchronizer` que tiene,
  al intervalo en que el mundo lo deja, contado como lo empaqueta SceneMultiplayer y con un datagrama de Steam en
  el techo (80 B) alrededor de cada paquete: el mismo modelo que `test_net_bandwidth_budget`
  (`tests/bandwidth_model.gd`, compartido, sin cambios). Los floats cuentan como de 64 bits y los enteros como de 32
  (una pose en movimiento; el reloj en ms del jugador, `net_time`, pasa 32767 a los 33 s de juego). Es un techo:
  Steam puede juntar mensajes en un datagrama, y los intervalos distintos se cuentan en paquetes aparte.
  Para las salidas: la camioneta de la flota (`CompanyFleet`, `World/Vehicles/van_classic`) se maneja por código a
  través del portón con la carga completa preparada (sus `cargo_slots`: 7 pedidos de un día tardío, cada uno en su
  caja), así que su sincronizador cuenta al ritmo que manda en movimiento (`NetRestThrottle` despierto: cada 16,7 ms)
  y los eventos `trip_started` / `trip_closed` son los reales que publica `CompanyTripsView`. El jugador a bordo
  (`net_in_vehicle`) manda al ritmo que le da `apply_pose_rate()` (30/s). La carga es el sincronizador de
  `package.tscn` (`BoxToPackage.PACKAGE_SCENE`).
- **Medido (ENet):** 4 u 8 peers ENet en localhost, en un proceso, cada uno con un jugador real (`player.tscn`) por
  peer, sumado a la cuadrilla como lo hace el mundo de la empresa (`CompanyRoot.join_crew()`), y un `CompanyNet`;
  el host publica `units_moved` reales al ritmo de abajo. En las salidas, además, en cada peer la escena del
  vehículo (`vehicle.tscn`, sin `NetRestThrottle`: siempre a su ritmo en movimiento) y sus 7 cajas
  (`package.tscn`: las cuidadas a 30/s, el resto a su ritmo de reposo), con la visibilidad que decidiría
  `CompanyInterest` (a bordo ven todos los vehículos; el galpón, solo si están cerca), y los que viajan mandan como
  pasajeros (`net_in_vehicle`). Se lee como lo lee el overlay de red en LAN (N-216, `NetStats`), cliente por
  cliente, y se le suman los 28 B de IP y UDP de cada datagrama. Todo está quieto y durante la cuenta tiene el
  proceso en pausa: lo que se manda no depende de eso, y 64 jugadores completos en un proceso bajaban a 61 FPS. El
  reloj todavía no pasó los 33 s (`net_time` de 3 B y no de 5). Cuatro corridas seguidas: abajo, el rango. Con 8
  peers en un proceso ENet varía más entre clientes iguales (una vez un cliente del galpón recibió 2,8 KB/s y el
  resto 12,8: probablemente el freno de paquetes no confiables de ENet, con un solo proceso atendiendo a todos); el
  test compara cada cliente con el techo del modelo y el peor con el presupuesto.
- **Lo que ninguno de los dos cuenta:** los deltas `ON_CHANGE` (anim_state, face_*, puertas, `driver_peer_id`,
  visible); el margen los cubre. Los eventos de salida y el keepalive de `CompanyInterest` están solo en el modelo.

Carga de "galpón a full": cada jugador hace una acción de negocio por segundo (tomar, guardar, poner en la grilla,
encintar; a bordo, entregar: una petición que el host convierte en un evento para todos) más una por segundo de
las reglas del host (pedidos, reloj, fases): 5 eventos/s con 4 jugadores, 9 con 8. Cada uno del tamaño del
`units_moved` real más grande (con `pos`: 181 B con su RPC), en un datagrama propio. Con vehículos afuera, además,
un evento de salida por segundo y por vehículo (techo: una salida manda dos), del tamaño del real más grande
(`trip_started` con 7 pedidos y 7 cajas: 409 B). `bot_company_day` todavía es un esqueleto: cuando tenga etapas,
estos ritmos se cambian por un día medido.

**Los casos** (`tests/company_bandwidth_cases.gd`, `case_layout()`; reparto de `roles-tripulacion.md`):

- **Galpón:** toda la cuadrilla en el galpón; la camioneta estacionada afuera, en reposo (cada 0,5 s).
- **Una salida afuera:** un vehículo afuera con 2 a bordo (conductor y un pasajero que cuida una caja: "Ruta 1-2",
  §2.3-2.4) y el resto en el galpón. El vehículo todavía está **cerca** del galpón (a 2 celdas o menos,
  `CELL_LOAD_RADIUS`): los del galpón también reciben el vehículo y su carga. Es el peor momento de la salida.
- **2 vehículos lejos** (`VEHICLES_FAR_MAX`): dos vehículos a más de `CELL_UNLOAD_RADIUS` celdas del galpón, con 2 a
  bordo cada uno, como mucho todos menos 2 (recepción y armado se quedan, §2.3): con 4 jugadores es un conductor en
  cada uno. `CompanyInterest` no le manda los vehículos ni sus cajas al galpón (sí el pulso de keepalive), y los
  dos vehículos van **cerca entre sí** (la misma ruta): cada uno a bordo recibe los dos.
- Cada vehículo lleva carga completa (7 cajas): una cuidada por cada pasajero (o por el conductor si va solo) en
  movimiento, el resto quieta en el rack (a su ritmo de reposo).
- **Con más gente a bordo** (solo se imprime, `crowded_*`): el techo de diseño, conductor y 3 pasajeros por
  vehículo, con un solo jugador en el galpón.

**D-2002.3 (2026-10-19): en el mundo de la empresa cada jugador manda su pose 15 veces por segundo a pie**
(`CompanyTuning.SHED_POSE_RATE_HZ`, la opción "bajar el envío en el galpón" de abajo). El juego de siempre
(Reparto, Infinito) sigue en 30 (`player.tscn`, sin tocar). Desde entonces el test **falla si el galpón pasa
24 KB/s con 4 o con 8 jugadores**, en el modelo o en la medición. **Desde D-2002.2 también falla si con 4 jugadores
una salida pasa 40 KB/s o 2 vehículos lejos pasan 64**; con 8 esos dos no entran todavía en el modelo: se imprimen
(`over_budget` con los culpables) y no fallan (`FULL_CREW_FITS`; el test avisa cuando entren).

| Caso | Presupuesto por cliente | 4 jugadores (modelo / ENet) | 8 jugadores (modelo / ENet) | Estado |
|---|---|---|---|---|
| Galpón, poses a 15/s (D-2002.3) | ≤ 24 KB/s | 9,1 / 5,9-6,0 | 20,2 / 12,8-13,6 | Entran los dos (el test falla si alguno se pasa) |
| Galpón, poses a 30/s (D-2002.1, antes) | ≤ 24 KB/s | 16,1 / 10,8-10,9 | 37,2 / 22,5-25,2 | 4 entraba; 8 se pasaba |
| Una salida afuera (D-2002.2) | ≤ 40 KB/s | 35,6 / 23,1-23,6 | **46,6** / 26,0-30,3 | 4 entra (el test falla si se pasa); 8 se pasa en el modelo (6,6 KB/s), no en ENet |
| 2 vehículos lejos (D-2002.2) | ≤ 64 KB/s | 50,1 / 33,2-33,7 | **66,2** / 38,3-42,7 | 4 entra (el test falla si se pasa); 8 se pasa en el modelo (2,2 KB/s), no en ENet |

El galpón subió 0,4 KB/s desde D-2002.3 (8,7 → 9,1 y 19,8 → 20,2): es la camioneta de la flota estacionada afuera
(D-0302.2.b), que el modelo cuenta sola a su ritmo de reposo (133 B cada 0,5 s).

Detalle del galpón (poses a 15/s; entre paréntesis, a 30/s antes de D-2002.3):

| | 4 jugadores | 8 jugadores |
|---|---|---|
| Por cliente, modelo (de eso, cabeceras de datagrama) | 9,1 KB/s (4,1) — antes 16,1 (7,4) | 20,2 KB/s (9,1) — antes 37,2 (17,1) |
| Por cliente, ENet medido (overlay + IP/UDP) | 5,9-6,0 KB/s (4,6 + 1,4) — antes 10,9 (8,3 + 2,6) | 12,8-13,6 KB/s (9,9-10,5 + 2,9-3,1) — antes 22,5-25,2 |
| Datagramas por segundo a cada cliente (modelo / ENet) | 52 / 50 — antes 95 / 93 | 116 / 106-114 — antes 219 / 191-214 |
| Subida del host (modelo con datagramas / ENet sin IP/UDP) | 27,4 / 13,7 KB/s — antes 48,4 / 24,9 | 141,3 / 59,9-73,6 KB/s — antes 260,6 / 121-135 |

Detalle de las salidas (D-2002.2; el peor cliente y, entre paréntesis, los demás del mismo reparto):

| | Una salida, 4 | Una salida, 8 | 2 lejos, 4 | 2 lejos, 8 |
|---|---|---|---|---|
| A bordo de cada vehículo | 2 | 2 | 1 y 1 | 2 y 2 |
| Peor cliente (modelo) | en el galpón, host en el galpón | en el galpón, host en el galpón | a bordo, host en el galpón | a bordo, host en el galpón |
| Por cliente, modelo (de eso, cabeceras de datagrama) | 35,6 KB/s (13,5) (a bordo 33,1) | 46,6 (18,5) (a bordo 44,1) | 50,1 (12,6) (galpón 17,1) | 66,2 (19,9) (galpón 33,1) |
| Por cliente, ENet medido (overlay + IP/UDP) | 23,1-23,6 (19,5-19,7 + 3,6-3,9) (a bordo 21,4-22,0) | 26,0-30,3 (21,8-24,9 + 4,3-5,4) (a bordo 19,8-28,6) | 33,2-33,7 (29,9-30,1 + 3,3-3,6) (galpón 9,3-9,4) | 38,3-42,7 (33,8-37,0 + 4,5-5,7) (galpón 14,3-16,8) |
| Datagramas por segundo al peor cliente (modelo / ENet) | 173 / 133-144 | 237 / 156-199 | 161 / 121-131 | 255 / 165-208 |
| Subida del host (modelo con datagramas / ENet sin IP/UDP) | 101,7 / 55,9-56,6 | 321,4 / 142-165 | 117,3 / 67,0-67,3 | 364,1 / 157-177 |
| Keepalive de `CompanyInterest` (modelo) | — | — | 2,5 a bordo, 2,4 en el galpón | 2,5 a bordo, 2,4 en el galpón |
| Con más gente a bordo (techo de diseño, solo modelo) | 39,7 (3 a bordo) | 59,9 (4 a bordo) | 50,2 (2 y 1) | 83,6 (4 y 3) |

Por qué ENet da tanto menos que el modelo en las salidas (con 8, 26-30 contra 46,6): ENet junta en un datagrama
los paquetes que salen juntos hacia un peer (el modelo cuenta uno de 80 B por paquete), la camioneta a 145 FPS manda
cada 3 frames (~48/s, no 60) y quieta tiene floats de 4 B (el modelo los cuenta de 8). Steam también junta mensajes,
pero el presupuesto se decide con el techo, como en el galpón.

Lo que pesa cada pieza (modelo, por cliente que la ve): la camioneta en movimiento manda 133 B cada 16,7 ms
(12,6 KB/s sola en su paquete, 4,7 de datagramas; la segunda suma 7,8 en el mismo paquete); una caja manda 150 B
(dos `Transform3D`: `net_transform` y `hold_offset`), 6,8 KB/s cuidada a 30/s y 0,3 en reposo (en el paquete de
las demás); un jugador a bordo reenviado por el host, 5,0 KB/s (a pie en el galpón, 2,5). Un vehículo vacío afuera
(no cuenta para el tope de `CompanyTrips`) cuesta lo mismo que uno cargado menos sus cajas.

Qué se cuenta hoy en el galpón: los sincronizadores del jugador y la camioneta estacionada.
`Player/MultiplayerSynchronizer` manda 82 B (con su cabecera) cada 66,6 ms en el galpón (cada 33,3 ms a bordo y en el juego de siempre); el de
`GelProportions` es solo `ON_CHANGE` (no manda nada quieto, confirmado en la medición). El galpón en sí no tiene
sincronizadores: los bultos del piso son estáticos (regla 10 de `red-autoridad.md`). Las cajas selladas que esperan
en el despacho (D-0715.b, `DeliveryPackage`) sí tienen, pero un mundo recién abierto no tiene ninguna: el galpón no
las cuenta todavía (7 en reposo serían ~2,2 KB/s más); queda para rehacer el galpón con `bot_company_day`. El
snapshot de un join tardío del galpón amueblado pesa unos 960 B comprimido (2.904 B crudo), una sola vez.

**Culpables, en orden (8 jugadores, modelo, poses a 15/s):**

Galpón (20,2 KB/s, entra):

1. Las poses de los otros 6 clientes, reenviadas por el host (`server_relay`, un paquete por jugador y por envío,
   15 por segundo): 15,0 KB/s, de los que 7,0 son cabeceras de datagrama (a 30/s eran 30,1 y 14,1).
2. La pose del jugador del host: 2,4 KB/s (1,2 de datagramas; antes 4,8).
3. Los eventos de negocio, 9 por segundo: 2,3 KB/s (0,7 de datagramas), igual que antes.
4. La camioneta estacionada: 0,4 KB/s (0,2).

Con 4 jugadores el orden es el mismo (5,0 / 2,4 / 1,3 / 0,4 KB/s). Las poses siguen siendo lo que más pesa.

Una salida afuera (46,6 KB/s de 40; el peor es un cliente del galpón con el host en el galpón):

1. La camioneta en movimiento: 12,6 KB/s (4,7 de datagramas).
2. Los 2 que van a bordo, reenviados a 30/s: 10,0 (4,7).
3. Los otros 4 del galpón, reenviados a 15/s: 10,0 (4,7).
4. La caja que cuida el pasajero, a 30/s: 6,8 (2,3).
5. La pose del jugador del host: 2,4 (1,2).
6. Los eventos de negocio, 9 por segundo: 2,3 (0,7).
7. Las otras 6 cajas, quietas en el rack: 1,9 (0,2).
8. Los eventos de salida (techo, uno por segundo): 0,5 (0,1).

Con 4 jugadores (35,6, entra): 12,6 / 10,0 / 6,8 / 2,4 / 1,9 (las cajas quietas) / 1,3 (los eventos, 5 por
segundo) / 0,5.

2 vehículos lejos (66,2 KB/s de 64; el peor va a bordo, con el host en el galpón):

1. Las 2 camionetas en movimiento (las dos cerca, en la misma ruta): 20,4 KB/s (4,7 de datagramas).
2. Los otros 3 que van a bordo, reenviados a 30/s: 15,0 (7,0).
3. Las 2 cajas cuidadas, a 30/s: 11,2 (2,3).
4. Los 3 del galpón, reenviados a 15/s aunque estén lejos (los jugadores no se filtran por distancia): 7,5 (3,5).
5. Las otras 12 cajas, quietas: 3,8 (0,3).
6. El keepalive: cada pulso que `CompanyInterest` le manda al galpón (cada 20 s) despierta las cajas quietas dos
   veces, al prender y al apagar la visibilidad (`NetRestThrottle` despierta con `visibility_changed`), y quedan
   0,5 s a ritmo completo para los que van a bordo: 2,5 (0,0).
7. La pose del jugador del host: 2,4 (1,2). 8. Los eventos de negocio: 2,3 (0,7). 9. Los de salida: 1,0 (0,2).

Con 4 jugadores (50,1, entra): 20,4 / 11,2 / 5,0 (el otro conductor) / 3,8 / 2,5 (uno del galpón) / 2,5
(keepalive) / 2,4 / 1,3 / 1,0. Al cliente que se queda en el galpón el pulso le cuesta 2,4 KB/s (17,1 en total con
4; 33,1 con 8): 2 camionetas, 2 cajas cuidadas y 12 quietas que se despiertan con el pulso (sin despertarlas serían
~0,5).

**Qué haría entrar a 8 (estimado con el mismo modelo; no aplicado):**

- **La camioneta a 30/s en el mundo de la empresa** (0,0333 en vez de 0,0167): comparte el paquete de las cajas
  cuidadas. Una salida 46,6 → 37,9; 2 lejos 66,2 → 53,6. Entran las dos con un solo número. Además a 60 FPS el
  0,0167 ya manda cerca de 30/s (es apenas más que 1/60, el mismo redondeo que `pose_interval()` arregló para el
  jugador): habría que medirlo a mano antes de decidir. El costo es la predicción del conductor (N-218), que
  corrige contra las poses del host la mitad de seguido; si se nota, 60/s solo para el conductor pide un segundo
  sincronizador (cambia el protocolo).
- **Filtrar también a los jugadores por distancia** (la regla de `CompanyInterest`, que la decisión del 2026-10-21
  dejó para "si D-2002.2 mide que no entra en 64"): 2 lejos con 8, 66,2 → 58,7. A una salida cerca del galpón no
  le cambia nada.
- **Los que van sentados (conductor y pasajeros) mandan a 15/s** (`apply_pose_rate()` hoy vuelve a 30 sentado o a
  bordo; sentado, su pose en el espacio del vehículo casi no cambia): una salida 46,6 → 41,6 (no alcanza solo); 2
  lejos → 58,7.
- **Que el pulso no despierte las cajas** (`NetRestThrottle` despierta con cualquier `visibility_changed` de un
  peer; el keepalive de `WorldCellInterest` prende y apaga): 2 lejos 66,2 → 63,7, y el galpón pasa de 2,4 a ~0,5 de
  keepalive. Toca los dos módulos (`net_pose_smoother`, `world_cells`).
- **Que la caja no mande `hold_offset` mientras nadie la tiene en la mano** (hoy va en cada pose, `IDENTITY` si
  nadie la tiene; va con la pose a propósito, así que no basta pasarlo a `ON_CHANGE`): 150 → 98 B por caja; una
  salida −2,1 KB/s. Es `package.tscn` (de Slatex y del Reparto).

Con 4 jugadores las dos salidas entran sin nada de esto. Con el techo de diseño a bordo (conductor y 3 pasajeros, 3
con 4 jugadores) una salida da 39,7: entra sin margen.

**Cómo está hecho D-2002.3:**

- `CompanyRoot.join_crew(player)` (lo usa `_spawn_player` y los jugadores de la medición) mete al jugador en
  `company_crew` y llama `Player.set_on_foot_pose_rate(CompanyTuning.SHED_POSE_RATE_HZ)`. El jugador elige el
  intervalo cada tick al publicar su pose (`player_ride.gd`, `apply_pose_rate()`): a pie, el pedido; subido a un
  vehículo (`net_in_vehicle`) o sentado, el de `player.tscn` otra vez (30/s): `test_company_root` lo prueba con un
  vehículo de mentira y D-2002.2 lo mide a bordo de la camioneta de la flota (`rider_pose_rate`). Solo cuenta el
  del dueño: él manda y el host reenvía al mismo ritmo.
- El intervalo es 0,0666 s y no 1/15 exacto (`pose_interval()`, redondeado hacia abajo a 0,1 ms como el 0,0333 de
  la escena): SceneMultiplayer mira el sincronizador una vez por frame y cuenta desde el frame en que mandó, así
  que con 1/15 exacto un frame que cae un pelo antes espera al siguiente (a 60 FPS, cada 5 frames: 12 por segundo).
  En la medición headless (145 FPS) salen 14,5 por segundo (cada 10 frames).
- Los demás lo dibujan igual de suave: `NetPoseSmoother` aprende el intervalo de los huecos entre poses (el primero
  ya lo fija; un cambio de 30 a 15 lo sigue en 1-2 s) y dibuja 2 intervalos + 2 × jitter atrás. En LAN son ~133 ms
  en vez de ~67: los otros jugadores se ven ~67 ms más atrás en el galpón. `MAX_DELAY` (200 ms) recorta recién con
  más de 33 ms de jitter y aun así deja 3 intervalos (nunca menos de 2); `MAX_EXTRAPOLATION` (100 ms) cubre 1,5
  intervalos, y una pose perdida queda dentro del colchón. Lo prueba `test_net_pose_smoother` (caso de 30 a 15 Hz).
- No cambia el protocolo: ni RPC ni propiedades ni modos de replicación, solo cada cuánto manda el dueño. Un host
  y un cliente de builds distintas se entienden (el que manda a 30 solo gasta más).

**Las otras salidas que se habían estimado (no aplicadas):**

- Que el host junte las poses de todos en sus propios paquetes en vez de reenviar uno por jugador: ~21,6 KB/s a
  30/s. Cambia quién manda las poses (un espejo de cada jugador del lado del host, o un RPC con todas por lote) y
  suma un tick de latencia. Queda si algún día el galpón necesita volver a 30/s.
- A 20 por segundo daba ~25,6 KB/s: no alcanzaba.
- Aceptar que el presupuesto de 24 KB/s es para 4 (lo que pide D-2002) y fijar uno para 8: ya no hace falta.
