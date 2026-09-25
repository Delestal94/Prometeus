# Personaje: animación y rostro

El modelo de juego es `sm_char_player_rounded.glb` (~18.600 triángulos, camiseta
teñible) con ocho clips. `animation_library.py` los genera; `model_fixes.py`
corrige pesos y geometría oculta antes de exportar; `build_game_export.py` arma el
GLB. `personaje_animado.blend` guarda las acciones editables y
`personaje_redondeado.blend` sigue siendo la referencia de modelado (no se guarda).

## Cómo están hechos los clips

Cada clip es una función del tiempo que devuelve una pose: un diccionario de
parámetros (inclinaciones de pelvis/columna/pecho/cabeza, barriga, brazos, pies).
Al ser números, las poses se mezclan exacto: `Jump` aterriza y termina en el
primer cuadro de `Idle`, y `PickUpPackage` parte de donde cuelgan de verdad las
manos en `Idle`. `PickUpPackage` y `PickUpHigh` comparten las curvas de tiempo
(`pickup_timing()`), así el juego los mezcla cuadro a cuadro. `TurnInPlace` empieza
y termina en el primer cuadro de `Idle`.

- **Brazos en FK** (`IK_brazo = 0` por clip): cuelgan del pecho, siguen al torso y
  describen arcos con arrastre. Los dos pickups y `Sit` los pasan a IK, porque las
  manos tienen que tocar algo.
- **Piernas con IK.** El pie rota sobre la bola (talón arriba) o sobre el borde
  del taco (punta arriba), así el punto que toca el suelo no patina.
- Muestreo a 60 Hz, interpolación lineal.

## Clips

| Clip | Duración | Qué hace |
| --- | --- | --- |
| `Idle` | 6 s, loop | Dos respiraciones, un cambio de peso lento entre pies, mirada que acompaña; los brazos pendulan detrás de la cadera. |
| `Walk` | 0,33 s, loop | Trote corto y rápido (6 pasos/s, 0,6 m por paso) a 3,6 m/s, con fase de vuelo, balanceo de pato, barriga que rebota con retraso, brazos que bombean y se abren al pasar junto a la panza. |
| `Stroll` | 0,6 s, loop | Caminata real a 1,5 m/s: doble apoyo, taco primero, cadera en péndulo invertido. Para el stick a medias. |
| `Jump` | 1,6 s | Brazos que vienen desde atrás y abajo (el impulso), "Y" de festejo arriba con piernas recogidas, aleteo cómico al caer, piernas que buscan el piso. Al tocar: aplastamiento que sigue la velocidad de caída, cabeza y barriga que siguen de largo, brazos que bajan tarde. Parpadeo de impacto. |
| `PickUpPackage` | 1,6 s | Los ojos van primero, mini subida antes de bajar, sentadilla con cola atrás (no se dobla de cintura), abrazo a la caja, subida con las piernas y leve esfuerzo hacia atrás, asentamiento. Tiempos iguales a los de la caja en `player.gd`. |
| `PickUpHigh` | 1,6 s | La misma agarrada con la caja a la cintura (estante, mesa): sin sentadilla, rodillas apenas flojas, inclinación leve hacia la caja, brazos al frente que la traen al pecho. Mismos tiempos que `PickUpPackage`. |
| `TurnInPlace` | 0,8 s, loop | Pasos al girar parado: dos pasitos por ciclo (2,5 pasos/s; `Walk` da 6), izquierdo y después derecho. Antes de cada uno el peso pasa al otro pie (pelvis y cadera cargada, pecho y cabeza que compensan); el pie despega el talón sobre la bola, sube ~7 cm, se abre apenas y vuelve a apoyar de taco donde estaba. Brazos en FK que se abren un poco para equilibrar. Sin giro propio: sirve para los dos sentidos. |
| `Sit` | 4 s, loop | Manos apoyadas sobre la panza (los codos salen para rodearla), respiración que las levanta, mirada, pies que se balancean por turnos. |

### Por qué `Walk` es un trote

La pierna mide ~0,55 m y el jugador va a 3,6 m/s: número de Froude 2,4 (caminar
llega hasta ~0,5). A esa velocidad un personaje así corre. La versión anterior daba
pasos de 0,8 m (1,9 veces la pierna, casi un espagat). Ahora son 6 pasos/s de 0,6 m.
Con el stick a medias, `player.gd` usa `Stroll` (histéresis 2,2–2,6 m/s) y
conserva la fase al cambiar: los dos ciclos empiezan con el pie izquierdo apoyando.

### Agarrar según la altura de la caja

`player.gd` mezcla `PickUpPackage` (caja en el piso) y `PickUpHigh` (caja a la
cintura) por la altura, sobre los pies, del punto donde las manos tocan la caja (el
mismo de `carry_pose.gd`): peso 0 con el agarre a 0,51 m (el del clip del piso), 1 a
0,925 m (el del clip alto; `PICKUP_GRAB_Z` × 0,5). El peso se calcula en `pick_up()`
en cada peer, así que no se replica nada. Sin `AnimationTree`: la mezcla se hornea
una vez por escalón de 1/8 como un clip más (`blend_clips()`, hueso por hueso a
30 Hz) en la librería `pickup_blend` del `AnimationPlayer`. Una caja más alta que el
pecho usa `PickUpHigh` entero y las manos llegan por IK.

### Pasos al girar en el lugar

El cuerpo entero gira con la mirada (`_apply_look()` rota el `CharacterBody3D`, que
lleva `BodyVisual`). `player.gd` mide esa velocidad angular: suma el giro que aplica la
mirada en cada tick y la suaviza (`turn_rate`, constante de 10/s, porque el mouse llega a
ráfagas). Parado en el piso (menos de 0,3 m/s, el umbral de `Idle`/`Walk`) y girando a
más de 1,5 rad/s pasa a `TurnInPlace`, y vuelve a `Idle` cuando baja de 0,8 rad/s
(`movement_state()`). El giro del camión en el que se viaja no cuenta: el piso gira con
los pies. Lo decide el dueño y viaja en `anim_state`, como `Walk`: no hay RPC ni
propiedades replicadas nuevas. Los one-shots (`Jump`, pickups) siguen bloqueando y
sentado manda `Sit`. Entre `Idle` y `TurnInPlace` el cruce dura 0,2 s.

## Correcciones del modelo (`model_fixes.py`)

- **Zapato rígido:** 100% del peso estaba en `foot`; el hueso `toe` no movía nada y
  la punta se hundía en el piso al despegar. La parte delantera pasa a `toe` con
  transición en el metatarso.
- **Rodilla:** la mezcla muslo/pantorrilla estaba centrada debajo de la
  articulación; en cuclillas se hundía el frente. Ahora centrada en la rodilla.
- **Panza:** el peso de pelvis caía de 0,17 a 0 en un solo anillo (z 1,40) y hacía
  una línea dentada al doblar la columna. Suavizado laplaciano del bajo de la camiseta.
- **Dobladillo y costura del cuello:** copian los pesos de la prenda que tienen debajo.
- Se sigue recortando la pierna dentro del short y la cintura del short bajo la camiseta.

## Rostro

Seis ojos y seis bocas combinables (`Personalización → Rostro`); **Sin ojos + Sin
boca** recupera la cabeza lisa. Los ojos **parpadean** cada 2,2–5,5 s (uno de cada
cinco, doble) y al aterrizar: `character_face.gd` comprime la textura en UV sobre la
línea de los ojos, así el párpado cierra sobre la superficie curva de la cabeza.
Los ojos `joyful` (ya cerrados, ^^) no parpadean. Cada par parpadea con su reloj;
no se replica nada.

## Cómo se verificó

Banco de pruebas en Blender (renders lateral/frente/¾ en tira, más mediciones),
con los mismos pesos y recortes que el export:

- **Brazos dentro de la camiseta:** 0 vértices de antebrazo/mano adentro en todos
  los clips (antes: 577 en `Sit`, 108 en `Walk`, 76 en `Jump`).
- **Suela bajo el piso:** 0 en `Walk`/`Stroll` (antes −0,10). En el despegue de
  `Jump` la punta baja del cero en la vista estática, pero el cuerpo ya subió.
- **Continuidad:** relación jerk máx/mediana ≤ 2 en `Walk`/`Stroll`/`Idle`; el pico
  que queda en `Jump` es el impacto (el cuerpo se detiene a 6,7 m/s) y es intencional.
- **Godot** (`test_character_motion`): bola del pie apoyado, deriva 8,7 mm en `Walk`
  y 0,8 mm en `Stroll`; balanceo de mano 0,44 m; `Jump` termina en `Idle`.

## Límites conocidos

- La caja viaja en línea recta de donde estaba hasta las manos (`player.gd`); si
  estaba lejos, se ve deslizarse.
- Sin IK de pies en pendientes.
- `TurnInPlace` no sabe hacia dónde gira: los pies se levantan y vuelven a apoyar en su
  lugar relativo al cuerpo, así que mientras están en el piso giran con él. Con giros
  rápidos se nota que pivotan; harían falta dos clips (izquierda/derecha) o IK de pies.
- Con las piernas levantadas en `Sit`, el tiro del short forma un pliegue en punta
  entre las rodillas, visible de frente.
- Las sombras de Workbench del banco de pruebas dibujan una línea falsa en algún
  cuadro del aterrizaje; sin sombras no aparece (no es geometría).
