# Prometeus

Proyecto de desarrollo de un videojuego indie (desarrollo en solitario, asistido por
IA), con el objetivo de aplicar patrones de éxito observados en juegos de Steam hechos
por 1-2 personas.

Nombre del juego (de trabajo): **Do Not Drop** — delivery cooperativo de hasta 5
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

Una vez en la furgoneta: elegí **Preparar entrega**, caminá con WASD y mirá
con el mouse. Al acercarte a un
objeto aparece la acción disponible: **E** agarra el paquete, lo deja en su
lugar dentro de la furgoneta y permite tomar el volante una vez cargado.

La entrega empieza al sentarte con la carga a bordo. Usá W/S para acelerar,
frenar y retroceder, A/D para girar y Espacio como freno de mano. **H** toca
bocina (todos la escuchan, venga de quien venga, no solo del host). Detenete
un segundo en la zona de entrega. Esc pausa también durante la preparación;
R reinicia. Por ahora el paquete queda asignado al soporte al cargarlo y
no se puede volver a agarrar, ni bajar del asiento durante la entrega.

Podés mirar alrededor desde el asiento con el mouse; **C** vuelve a centrar la
vista hacia el frente del vehículo. Con gamepad, el **stick izquierdo** camina
o gira la camioneta, el **stick derecho** mira, su **clic** centra la vista,
los **gatillos** aceleran/frenan y el **botón sur** interactúa a pie o activa
el freno de mano al conducir. Mirar desde el asiento no cambia la dirección
del vehículo. La mirada se conserva después de las sacudidas de los impactos.

Cualquier jugador puede pingear "¡Cuidado!" con el clic de la rueda del mouse (o
D-pad arriba en gamepad) para avisar a los demás sin depender de voice chat externo —
aparece arriba de la pantalla de todos por unos segundos, con quién lo mandó.

## Tests

Las pruebas de lógica corren headless, sin abrir el editor. Reemplazá `<godot>` por la ruta a tu
ejecutable (ej. `D:\Descargas\Godot_v4.7.2-stable_win64_console.exe`):

```
<godot> --headless --path do-not-drop --script res://tests/test_fragile.gd
<godot> --headless --path do-not-drop --script res://tests/test_traps.gd
<godot> --headless --path do-not-drop --script res://tests/test_interaction.gd
<godot> --headless --path do-not-drop --script res://tests/test_loading_flow.gd
<godot> --headless --path do-not-drop --script res://tests/test_multi_cargo.gd
<godot> --headless --path do-not-drop --script res://tests/test_network_roster.gd
<godot> --headless --path do-not-drop --script res://tests/test_hint_relay.gd
<godot> --headless --path do-not-drop --script res://tests/test_main_menu.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_streaming.gd
<godot> --headless --path do-not-drop --script res://tests/test_leaderboard.gd
<godot> --headless --path do-not-drop --script res://tests/test_ping.gd
<godot> --headless --path do-not-drop --script res://tests/test_ruin_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/test_horn.gd
<godot> --headless --path do-not-drop --script res://tests/test_player_colors.gd
<godot> --headless --path do-not-drop --script res://tests/test_impact_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/check_driver_sightline.gd
<godot> --headless --path do-not-drop --script res://tests/check_steam_extension.gd
<godot> --headless --path do-not-drop --script res://scripts/gameplay/route/route_smoke_check.gd
```

Cada uno imprime `PASS` y devuelve exit code 0 si está todo bien.

- `test_fragile` — umbrales de daño, estados e independencia entre paquetes.
- `test_traps` — las otras tres trampas: peso creciente, equilibrio y ruidoso.
- `test_interaction` — agarrar, dejar en el asiento y subirse a manejar.
- `test_multi_cargo` — varias trampas a la vez, y que perder una no termine
  la entrega de todos.
- `test_network_roster` — quién está en la sesión, quién es anfitrión, y que
  jugar solo siga siendo "una sesión de uno" (sin abrir sockets).
- `test_hint_relay` — el texto de ayuda de una trampa (ej. la cuenta
  regresiva del peso creciente) le llega a todos, no solo se lee del lado
  del anfitrión.
- `test_main_menu` — que el menú cargue y que cada botón/atajo elija el
  transporte que promete (crítico: "Crear sala" y "Unirse por IP" tienen que
  terminar en el mismo transporte o nunca se van a encontrar).
- `test_loading_flow` — flujo integrado de preparación, bloqueo de abordaje
  prematuro, carga, inicio, pausa, resultados, reinicio y atajo de desarrollo.
- `test_route_streaming` — la pieza base de streaming de tramos (Fase 3): que
  `RouteStreamer` genere tramos por delante de un objetivo, libere los que
  quedaron muy atrás y nunca repita el mismo tipo dos veces seguidas. Es
  aparte de la ruta curada a mano (`route.gd`), que sigue siendo la que se
  juega hoy.
- `test_leaderboard` — el top de puntajes local de `RunManager`: ordena,
  recorta a 10 entradas, marca correctamente un nuevo récord y sobrevive a
  guardar/cargar de disco (usa un archivo de prueba aparte, no el guardado
  real).
- `test_ping` — el sistema de pings: `EventBus.request_ping()` atribuye
  correctamente al emisor, y `Player._send_ping()` llega hasta ahí con la
  posición y el mensaje reales.
- `test_ruin_feedback` — el paquete arruinado explota en confeti una sola vez,
  en su propia posición (no en el origen del mundo), y se limpia solo al
  terminar.
- `test_horn` — la bocina atribuye correctamente a quien la toca (aunque no
  sea el host) y el "honk" sintetizado en código es audio real, no silencio.
- `test_player_colors` — cada jugador tiene un cuerpo visible (antes no había
  ninguno) con un color distinto y determinístico por `peer_id`.
- `test_impact_feedback` — el golpe de FOV al chocar: solo reacciona la cámara
  del asiento que estás usando, vuelve sola a su valor base, y nunca toca
  `Engine.time_scale` (eso frenaría la física de todos, no solo tu vista).
- `check_driver_sightline` — verifica que nada tape la vista del conductor
  (tablero, volante, o un "vidrio" que en realidad sea opaco). Las mallas
  transparentes y la carrocería vista desde adentro no cuentan como bloqueo.
- `route_smoke_check` — colisiones de la ruta y detección de la zona de entrega.

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

### Vigente (proyecto actual: Do Not Drop)
- `docs/investigacion-mercado.md` — investigación de 20 juegos de Steam hechos por 1-2
  personas: equipo, ventas, motor, tiempo de desarrollo. (Contexto general, sigue
  vigente como referencia de fondo.)
- `docs/checklist-exito.md` — items replicables extraídos de esa investigación.
  (Igual de vigente, son patrones generales.)
- `docs/mecanicas-candidatas.md` — banco de mecánicas transversales reutilizables
  (recurso de referencia general para futuras decisiones).
- `docs/definicion-proyecto.md` — **definición del concepto actual** (Do Not Drop).
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

### Archivado (`docs/historial-exploracion/`)
Documentos de una etapa de exploración anterior, **superados** por el pivote a
"Do Not Drop". Se conservan como registro del proceso, no como referencia vigente:
- `mvp-candidatos.md`, `ideas-candidatas.md`,
  `opcion-descartada-aseguradora-paranormal.md`.
