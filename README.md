# Prometeus

[![Tests](https://github.com/Delestal94/Prometeus/actions/workflows/tests.yml/badge.svg)](https://github.com/Delestal94/Prometeus/actions/workflows/tests.yml)

Proyecto de desarrollo de un videojuego indie (desarrollo en solitario, asistido por
IA), con el objetivo de aplicar patrones de éxito observados en juegos de Steam hechos
por 1-2 personas.

Nombre oficial del juego: **Take My Package** (desde 2026-09-22; antes el nombre de trabajo era "Do Not Drop", por eso el proyecto Godot sigue en `do-not-drop/`) — delivery cooperativo de hasta 5
jugadores: 1 conduce, hasta 4 llevan un paquete con una "trampa" cada uno (ver
`docs/definicion-proyecto.md` y `docs/requerimientos-tecnicos.md`).

## Motor
Godot 4.x — el proyecto del juego vive en `do-not-drop/`.

## Probar el prototipo

Abrí `do-not-drop/project.godot` en Godot y ejecutá con **F5**. Arranca en un
**menú principal**: "Jugar solo" entra directo sin sesión de red (el
comportamiento de siempre); "Crear sala" hostea con el transporte que esté
disponible (Steam si está corriendo, si no LAN) y entra directo a la
furgoneta sin esperar en ninguna sala — los que se sumen después aparecen
dinámicamente; "Unirse por IP" fuerza LAN y conecta a la dirección que
escribas. Los amigos de Steam también pueden sumarse aceptando una
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
en S, ripio, zona de obras y curvas reales que doblan el rumbo del camino de
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
`pre-push`: cada `git push` con cambios de código corre la batería y no sube nada si falla.
GitHub Actions la corre también en cada push a `main` y en cada PR. Detalle en
[CONTRIBUTING.md](CONTRIBUTING.md).

Los `render_*.gd` y `check_*.gd` necesitan pantalla y alguien que mire las capturas: no son
parte de la batería (con Claude, los corre el agente `revisor-visual`).

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
