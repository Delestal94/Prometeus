# S-304 — celular en la mano del personaje

Hecho el 2026-10-31 (rama `nacho/S-304-phone-hand`).

## Qué cambió

Mientras un jugador tiene abierta la cámara del celular (F), los demás peers ven su brazo derecho levantado
junto a la cara y el celular en la mano, con la pantalla hacia sus ojos. El cuerpo propio sigue fuera de la
cámara de primera persona y de la lente, así que quien saca la foto no ve nada distinto.

## Archivos

- Nuevo `scripts/gameplay/player/player_phone_prop.gd` (nodo `PlayerPhoneProp` en `player.tscn`): `SkeletonIK3D`
  `upper_arm.R`..`hand.R` y `BoneAttachment3D` en `hand.R` con `props/handheld/sm_prop_phone_refined.glb`.
  Se arma al levantar el celular y se libera al bajarlo. Se guarda al sentarse, en ragdoll, con una caja en
  las manos, en un emote o derretido.
- `scripts/gameplay/player/player.gd` (Slatex): `var phone_raised`, el nodo `PlayerPhoneProp` y su `setup`
  (5 líneas).
- `scenes/gameplay/player/player.tscn`: `phone_raised` replicada (propiedad 18, spawn + on change) y el nodo nuevo.
- `scripts/presentation/phone_camera.gd` (zona de Slatex): `_open()` y `_close()` ponen `phone_raised` en el
  jugador local (`_hold_phone`). Además la cámara se cierra si se suelta el mouse: en línea la pausa no pausa
  el árbol, y el menú se abría sobre el HUD oculto con el celular todavía levantado para el resto.
- `scripts/core/network_manager.gd`: `PROTOCOL_VERSION` 61 -> 62 (entrada `## 62` en el historial).
- Tests: nuevo `tests/test_player_phone_prop.gd`; `tests/net_pair_animation.gd` ahora comprueba en dos procesos
  que cada lado ve el celular del otro.
- `docs/tareas/S-304.md` y `docs/inventario-assets.md` (el celular pasa a ✅).

## Red

`phone_raised` la escribe solo el dueño (como `anim_clip`) y se replica con el estado de aparición, así que
quien entra tarde ve el celular ya levantado. No hay RPC nueva. Cualquier build anterior a 62 no se conecta.

## Qué tiene que hacer Nacho

Nada, salvo que toque la replicación del jugador: la próxima versión de protocolo sale de 62. Si agrega
otro uso del brazo derecho (otra pose o un objeto en la mano), `PlayerPhoneProp.is_blocked()` es donde se
decide quién gana.

## Pendiente

Mirada de `revisor-visual` (el headless no dibuja): la posición del celular y del codo está medida, no vista.
