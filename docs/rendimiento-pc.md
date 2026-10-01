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
