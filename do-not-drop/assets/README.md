# Assets de Take My Package

Assets propios del juego. El proyecto usa Godot 4.x y renderer GL Compatibility;
por eso los modelos base son escenas nativas `.tscn` compuestas por mallas
low-poly, sin depender de un importador externo. Cada escena se puede instanciar
desde una ruta o nivel y se mantiene separada de la lógica y las colisiones.

## Convenciones

- `models/<familia>/sm_<familia>_<nombre>.tscn`: **s**tatic **m**esh, origen en
  el centro de su base, escala Godot en metros, nombres en `snake_case`.
- `textures/<familia>/tx_<familia>_<nombre>_<tamano>.png`: texturas raster
  cuadradas, sRGB, en píxeles. Son patrones de color plano, no material PBR
  fotorealista.
- Los materiales viven dentro de cada escena mientras son específicos del asset;
  las texturas compartidas se referencian mediante `res://assets/...`.
- Los modelos visuales no llevan colisión: quien los coloque decide si requiere
  `StaticBody3D` y usa la capa `environment` ya definida por el proyecto.

## Primer lote reutilizable

Entorno base: árbol, poste eléctrico, señal de advertencia, módulo de cerca y
tacho. El bosque del primer mapa está en `models/environment/forest/`: seis
formas de árbol (roble, abedul, pino alto, arce, árbol seco y pino joven) y
siete piezas de sotobosque. Arquitectura: las tres casas de entrega GLB viven
en `models/architecture/`; tienen materiales low-poly embebidos y se alternan
en la ruta sin cambiar su colisión o timbre.

`tools/build_lowpoly_glb_assets.py` es el script fuente para regenerar las
veintisiete piezas GLB con Blender 5.2. Además de casas y bosque, incluye
`models/cargo/` (cuatro siluetas de paquete por trampa), `models/vehicles/`
(dos vehículos estacionados) y `models/environment/props/` (conos, barrera,
mailbox, farol y banco). No hace falta ejecutarlo para abrir el
proyecto: Godot importa directamente los `.glb` ya exportados.

## Segundo lote (2026-09-23)

`tools/build_lowpoly_glb_assets_batch2.py` (helpers compartidos en `tools/lowpoly_kit.py`)
genera 31 piezas más, sin volver a exportar el primer lote:

- `models/environment/signs/`: una señal por tipo de tramo (curva, lomo de burro, puente
  angosto, ripio, obras) y el cartel "entrega adelante". Se leen de frente mirando a −Z.
- `models/environment/props/`: guardarraíl (4 m), baranda de puente (6 m), fardo, cajón,
  pallet, hidrante, parada de colectivo y mojón.
- `models/environment/yard/`: cerca de estacas, maceta, enano de jardín, cucha y felpudo.
- `models/architecture/`: casa de dos pisos, casa de campo con galería y granero.
- `models/environment/landmarks/`: tanque de agua y molino (`WindmillRotor` gira sobre su Z local en Godot).
- `models/environment/sky/`: tres nubes y el anillo de montañas del horizonte (radio 450 m).
- `models/props/handheld/sm_prop_phone.glb` y `models/characters/sm_char_viewmodel_glove_*.glb`
  (origen en la muñeca; la manga usa el material `PlayerTint` para teñirla por jugador).

```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup     --python do-not-drop/assets/tools/build_lowpoly_glb_assets_batch2.py
```

Todos quedan por debajo de 600 triángulos. Qué está integrado y qué no está en
`docs/inventario-assets.md`.

## Modelos refinados (2026-09-23)

`tools/build_lowpoly_refined.py` pasó a ser la fuente de casas y granero, todo el bosque,
señales, mobiliario de ruta y jardín: techos a dos aguas cerrados con alero, ventanas con
marco y postigos, porches con baranda, cabaña de troncos, copas de árbol irregulares, pinos
con pisos caídos, símbolos de señal como contornos extruidos y guardarraíl de doble onda.
Sobrescribe las mismas rutas y nombres de material, así que el juego no cambió.

```
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup     --python do-not-drop/assets/tools/build_lowpoly_refined.py -- houses trees plants signs props yard
```

## Paquetes abribles (2026-09-23)

Dos pasos, los dos reproducibles:

```
D:/Programas/comfy-venv/Scripts/python.exe art/tools/make_cargo_textures.py
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup     --python do-not-drop/assets/tools/build_cargo_packages.py -- boxes contents
```

1. `make_cargo_textures.py` (PIL) pinta un atlas 2048 por caja con la impresión de marca
   (logo, símbolos de manejo ISO, código de barras, sello del fondo, cinta amarilla) y escribe
   `tools/cargo_layout.json` con medidas y rectángulos UV. Es la única fuente de las medidas.
2. `build_cargo_packages.py` arma `models/cargo/sm_cargo_box_*.glb` (84 triángulos: cuerpo con
   interior, cuatro solapas con el origen en la bisagra, media cinta en cada solapa exterior) y
   `models/cargo/contents/sm_cargo_content_*.glb` (1000-2000 triángulos, nodos `Filler`,
   `Intact`, `Damage`, `Ruined`).

Para sumar un contenido nuevo: una función en `build_cargo_packages.py`, un
`data/contents/<id>.tres` (`PackageContent`) y agregarlo a `contents` de la trampa.

## Texturas de detalle (`textures/detail/`)

Mapas en gris que solo modulan el brillo (el color sale de la paleta): asfalto, tierra, pasto
y grava para el terreno; tablas, tejas, revoque, corteza, follaje y piedra para los modelos,
aplicados por `scripts/presentation/lowpoly_materials.gd` según el nombre del material.
Se regeneran con `art/tools/make_detail_textures.py`. Las de `textures/terrain/` quedaron
en desuso.

## Fauna (`models/environment/wildlife/`)

- `sm_env_animal_stag_rigged.glb`: "Stag" del *Animated Animal Pack* de **Quaternius**,
  licencia **CC0 1.0** (dominio público, uso comercial libre, sin atribución obligatoria;
  la dejamos igual). Fuente: https://poly.pizza/m/tQdzbZ1Cmw. Trae esqueleto y animaciones
  (`Gallop`, `Walk`, `Idle`, `Idle_2`, `Idle_Headlow`, `Eating`, `Idle_HitReact_*`...);
  `scripts/presentation/wildlife_animal.gd` lo gira, lo escala a 0.4 y elige la animación.
- `sm_env_animal_dog_rigged.glb` (2026-09-25): "Shiba Inu" del mismo *Animated Animal Pack*
  de **Quaternius**, **CC0 1.0**. Fuente: https://poly.pizza/m/y4wdQpg767. Es el perro que
  persigue al camión (`chasing_dog.gd`); `wildlife_animal.gd` lo gira, lo escala a 0.26
  (~0,55 m a la cruz) y elige `Idle`/`Walk`/`Gallop` según la velocidad a la que se mueve de
  verdad, con el clip acompasado a esa velocidad. Reemplaza al perro articulado propio, que
  quedó sin usar (`sm_env_animal_dog.glb`).
- Conejo, rana, pájaro y el cartel de cruce: propios, generados por
  `tools/build_wildlife.py` (piezas con pivote en cada articulación, animadas por código).
- `sm_env_animal_sheep.glb` (oveja, ~0,75 m a la cruz) y `sm_env_animal_dog.glb` (perro de
  campo, ~0,55 m a la cruz): propios, mismo script (`sheep()`, `dog()`; se regeneran solos con
  `... --python tools/build_wildlife.py -- sheep dog`). Raíz `Sheep` / `Dog`; pivotes
  `Legs_Front`, `Legs_Back`, `Head`, `Tail` y, en el perro, `Ears` colgando de `Head`.

## Timbre (`models/environment/props/sm_env_prop_doorbell_panel.glb`)

- Propio, `tools/build_doorbell.py` (tareas de Nacho N-302): placa de 12×26 cm con la
  ventanita del número, rejilla de portero, botón con aro, tarjeta y tornillos. A diferencia
  del resto, el origen es el centro del dorso de la placa (va colgado en una pared). Cada
  pieza es un nodo: `delivery_house.gd` busca `Button` y `NumberPlate` para encenderlos y
  escribe el número de la casa sobre `NumberPlate`.

## Tipografías (`fonts/`)

Lilita One (títulos) y Nunito variable (texto), ambas de Google Fonts con licencia SIL Open
Font License 1.1 (`*-OFL.txt` al lado): se pueden usar y distribuir en un juego comercial.
Las carga `scripts/ui/ui_theme.gd`.

## Interfaz (`ui/`)

Imágenes generadas con ComfyUI + Z-Image Turbo (Apache 2.0), registradas en
`art/ai-registro.md`: fondo del menú, splash de arranque, ícono de la app (`.png` y `.ico`)
e íconos de las cuatro trampas.

## Personajes

**Rostro personalizable (2026-09-24):** `textures/characters/faces/` contiene
dibujos vectoriales propios de ojos y bocas. `art/rounded_character/build_faces.py`
los reproduce. `face_catalog.gd` define IDs estables; `character_face.gd` coloca dos
mallas curvas con transparencia sobre el hueso `head` del personaje redondeado.
Las mismas texturas se componen en `face_preview.gd` para la vista 2D del vestuario.
No requiere Decal ni SubViewport por jugador; funciona en GL Compatibility.
El perfil guarda `selected_eyes`/`selected_mouth`; cada jugador replica
`face_eyes`/`face_mouth`, incluidos los valores de entrada tardía.

`models/characters/sm_char_player_rounded.glb` (2026-09-24): **el cuerpo del
jugador**. Es el personaje redondeado de Astra (cabeza lisa, camiseta, short,
zapatos; fuente en `art/rounded_character/`), exportado para el juego por
`art/rounded_character/build_game_export.py`, que parte del `.blend` de Astra sin
modificarlo:

- una sola malla con skin, diezmada a ~19k triángulos (el original tiene 64k),
  sin morphs (la respiración va con huesos). Superficies por material con nombre
  ASCII: `Shirt` es la 0 y `player.gd` le pone el color del equipo; `ShirtTrim`
  toma el mismo color, un poco más oscuro. Además vienen `Skin`, `Shorts`,
  `ShortsHem`, `Shoe` y `Sole`;
- 26 huesos deformables en glTF (`pelvis/spine/chest/neck/head`, `belly`,
  `clavicle/upper_arm/forearm/hand/thumb/grip` y `thigh/shin/foot/toe` por lado,
  con sufijos `.L`/`.R` desde el punto de vista del personaje). `grip.L/R` sirven
  de anclaje para agarrar cosas;
- mira hacia −Z y mide ~1,74 m: la escala 0,5 y el giro de 180° están en el nodo
  del esqueleto;
- clips (60 Hz, generados por `art/rounded_character/animation_library.py`; brazos en
  FK, piernas con IK horneado): `Idle` 6 s en loop (respiración, cambio de peso,
  mirada), `Walk` 0,33 s en loop (trote corto a 6 pasos/s, autorado a 3,6 m/s),
  `Stroll` 0,6 s en loop (caminata real a 1,5 m/s, para el stick a medias),
  `Jump` 1,6 s (`player.gd` lo recorre según la velocidad vertical; aterriza en el
  primer cuadro de `Idle`), `PickUpPackage` 1,6 s (sincronizado con la caja:
  agarre a 0,42 s, sube hasta 1,3 s), `PickUpHigh` 1,6 s (la misma agarrada para una
  caja a la cintura, sin sentadilla, con los mismos tiempos: `player.gd` mezcla los dos
  según la altura de la caja), `Sit` 4 s en loop (pelvis 0,5 m más abajo,
  manos sobre la panza, pies que se balancean) y `TurnInPlace` 0,8 s en loop (dos
  pasitos que reacomodan los pies; `player.gd` lo usa al girar parado). `player.gd` ubica el cuerpo sobre
  cada asiento con `_seat_body_offset()`, medido con `tests/render_player_character.gd`.
  Los loops se marcan en `player.gd`. `art/rounded_character/model_fixes.py` corrige
  pesos (rodilla, punta del zapato que se dobla en el metatarso, bajo de la camiseta)
  y recorta la pierna dentro del short y la cintura del short bajo la camiseta.

Para cambiar poses o sumar clips, editá `animation_library.py` y volvé a correr
`build_game_export.py` (el comando está en su encabezado; con `-- --preview`
renderiza cada pose en `PREVIEW_DIR`). `art/rounded_character/REFINAMIENTO.md`
explica los criterios y las mediciones.

`models/characters/sm_char_player_lowpoly.glb` sigue en uso para los NPC
(operarios del depósito y vecinos de las casas) y el ragdoll arma sus propias
piezas.

`models/characters/sm_char_player_lowpoly.glb` (2026-09-22): personaje
low-poly estilo PEAK, cuerpo hecho con formas simples redondeadas (esferas +
cilindros, shading suave, dos materiales planos: piel y traje). Trae un
`Skeleton3D` completo con 20 huesos (`Root → Hips → Spine → Chest → Neck →
Head`, más brazos `Shoulder/UpperArm/LowerArm/Hand` y piernas
`UpperLeg/LowerLeg/Foot` por lado) y la malla ya está *skinned* con pesos
automáticos de Blender — se puede instanciar directo en Godot y animar por
hueso sin retocar nada. Trae 5 animaciones (`AnimationPlayer` con 5 clips,
verificado importando y reproduciendo en Godot):

| Clip | Duración | Loop |
|---|---|---|
| `Idle` | 2.5s | Sí (marcar Loop en el `AnimationPlayer` de Godot, el glTF no trae el flag) |
| `Walk` | 1.0s | Sí (idem) |
| `Jump` | 1.67s | No — anticipación, despegue, ápice, aterrizaje |
| `Die` | 1.33s | No — colapsa hacia atrás pivotando en `Root`, queda tendido |
| `PickUpPackage` | 1.67s | No — agachada, alcance, agarre y vuelta a pararse sosteniendo la caja |

El importador de Godot no trae marcado qué clips deben loopear (eso se
configura una vez en el editor, seleccionando `Idle`/`Walk` en el
`AnimationPlayer` y tildando *Loop*). Fuente editable en
`tools/char_player_lowpoly_source.blend` (Blender 5.2) para ajustar poses o
sumar más animaciones sin rehacer el rig desde cero.
