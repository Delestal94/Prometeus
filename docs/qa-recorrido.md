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

> Sección de Slatex: menú, opciones, una entrega completa a pie y en el camión (agarrar, montar,
> manejar, bajar, timbre, foto), pausa, volver al menú, Endless 2 minutos, cerrar. La completa
> con su S-801.

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

## Hallazgos

| Fecha | Commit | Qué se estaba haciendo | Qué pasó | Estado |
|---|---|---|---|---|
| | | | | |
