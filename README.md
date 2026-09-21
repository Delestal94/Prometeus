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

Abrí `do-not-drop/project.godot` en Godot y ejecutá con **F5**. Elegí
**Preparar entrega**, caminá con WASD y mirá con el mouse. Al acercarte a un
objeto aparece la acción disponible: **E** agarra el paquete, lo deja en su
lugar dentro de la furgoneta y permite tomar el volante una vez cargado.

La entrega empieza al sentarte con la carga a bordo. Usá W/S para acelerar,
frenar y retroceder, A/D para girar y Espacio como freno de mano. Detenete un
segundo en la zona de entrega. Esc pausa también durante la preparación;
R reinicia. Por ahora el paquete queda asignado al soporte al cargarlo y
no se puede volver a agarrar, ni bajar del asiento durante la entrega.

Podés mirar alrededor desde el asiento con el mouse; **C** vuelve a centrar la
vista hacia el frente del vehículo. Con gamepad, el **stick izquierdo** camina
o gira la camioneta, el **stick derecho** mira, su **clic** centra la vista,
los **gatillos** aceleran/frenan y el **botón sur** interactúa a pie o activa
el freno de mano al conducir. Mirar desde el asiento no cambia la dirección
del vehículo. La mirada se conserva después de las sacudidas de los impactos.

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
<godot> --headless --path do-not-drop --script res://tests/check_driver_sightline.gd
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
- `test_loading_flow` — flujo integrado de preparación, bloqueo de abordaje
  prematuro, carga, inicio, pausa, resultados, reinicio y atajo de desarrollo.
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

### Prueba de conexión (manual, dos procesos)

La conectividad real necesita dos procesos y no se puede verificar desde un
entorno sin permisos de red. Corré el anfitrión en una terminal y el cliente en
otra:

```
<godot> --headless --path do-not-drop --script res://tests/net_smoke.gd -- --host
<godot> --headless --path do-not-drop --script res://tests/net_smoke.gd -- --client
```

Ambos imprimen `PASS` si se encuentran. **Si falla, lo primero a revisar es el
firewall de Windows**: la primera vez que Godot abre un puerto suele pedir
permiso, y si el proceso corre sin ventana el pedido nunca aparece y la conexión
queda bloqueada en silencio. En esta máquina el puerto se abre correctamente
pero el cliente no llega, que es exactamente ese síntoma.

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

### Archivado (`docs/historial-exploracion/`)
Documentos de una etapa de exploración anterior, **superados** por el pivote a
"Do Not Drop". Se conservan como registro del proceso, no como referencia vigente:
- `mvp-candidatos.md`, `ideas-candidatas.md`,
  `opcion-descartada-aseguradora-paranormal.md`.
