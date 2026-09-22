# Assets de Do Not Drop

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

## Personajes

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
