# S-205 — manos al sostener la caja

Hecho el 2026-10-31 (rama `nacho/S-205-hold-hands`).

## Qué cambió

Mientras un jugador mantiene la acción primaria cuidando una caja (la tarjeta de cuidado), las manos de su gel
la agarran, y los demás peers lo ven. Sentado (caja en la falda o en el asiento) o ayudando a pie, los dos
brazos alcanzan los costados de la caja con `SkeletonIK3D` (las cadenas `Player.DRIVER_ARM_BONES`); cargándola,
la pose de carga ya la sostiene y las manos solo se aprietan unos 2,5 cm. Entra y sale en ~0,1 s. El conductor
(asiento `DriverEyePoint`), el celular en la mano, el ragdoll, el derretido y los emotes mandan sobre el agarre.

El cuerpo propio sigue fuera de la cámara de primera persona, así que quien sostiene ve el cambio en el
espejo del depósito; el valor es que el resto de la tripulación lo ve.

## Archivos

- Nuevo `scripts/gameplay/player/player_hold_pose.gd` (nodo `PlayerHoldPose` en `player.tscn`). `player.gd` **no
  se toca** (699 de 700 líneas, `test_player_split`). Fuente de "quién sostiene": el jugador local lee
  `PlayerHoldFeedback.holding` (mismo frame que el input, sin red); las copias remotas leen
  `care_state.held_by` / `helped_by` de las cajas (búsqueda cada 0,05 s).
- `scripts/gameplay/player/carry_pose.gd`: propiedad `squeeze` (0..1) que acerca las manos al costado de la caja.
- `scripts/gameplay/player/player_hold_feedback.gd`: solo el comentario (ya hay quien lee `holding`).
- `scripts/gameplay/package/package_rescue.gd` (compartido con Nacho): `steadying_peers()` calcula `held_by` (el
  tender, o quien trabaja la caja suelta) y `helped_by` (el ayudante) de las mismas muestras que deciden
  `steady`; `publish_care` los agrega a `care_state` y `_publish_hand_change` fuerza el publish en el tick en
  que cambian.
- `scenes/gameplay/player/player.tscn`: el nodo nuevo (sin propiedades replicadas nuevas).
- `scripts/core/network_manager.gd`: `PROTOCOL_VERSION` 62 -> 63 (entrada `## 63`).
- Test nuevo `tests/test_player_hold_pose.gd`.
- `docs/tareas/S-205.md`.

## Red

Sin RPC nuevo ni propiedad replicada nueva: `held_by` y `helped_by` (peer id, 0 si nadie) viajan dentro del
`care_state` que el host ya publica cada 0,1 s (0,2 s en una caja de empresa). Solo se adelanta un publish
cuando uno de los dos cambia (se aprieta o suelta el botón); sostener no agrega nada. Cambia el contenido de una
propiedad replicada, así que sube el protocolo. Cada peer decide solo cómo dibujar; el host no depende de ello.
Si tender y ayudante sostienen a la vez, se ven los dos (`held_by` + `helped_by`). `held_by` sale de la
muestra de la entrada, antes de que una trampa que no responde a las manos (Frágil) o el asistente de la
tripulación en solitario la anulen: las manos están en la caja igual, como el brillo local.

## Qué tiene que hacer Nacho

- Quien toque `package_rescue.gd`: `publish_care` ahora agrega dos claves a `care_state`; cualquier consumidor
  que compare el diccionario entero o lo cuente ve dos enteros más.
- La próxima versión de protocolo sale de 63.
- Si otra pose usa los brazos, `PlayerHoldPose.is_blocked()` es donde se decide quién gana.

## Pendiente

Mirada de `revisor-visual` (el headless no dibuja): dónde caen las manos sobre la caja y el codo está medido,
no visto. El caso de la caja del estante (a más de un brazo de distancia) apunta el brazo hacia ella en vez de
alcanzarla. Sin prueba en dos procesos con una caja replicada: lo cubre una prueba de un proceso que aplica
el `care_state` como lo haría un cliente.
