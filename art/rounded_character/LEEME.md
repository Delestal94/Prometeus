# Personaje redondeado

Personaje cartoon gordito (rehecho el 2026-09-27 a partir de la referencia original de
cabeza lisa): cabeza grande con papada y cachetes, nariz de botón, orejitas, pelo corto con
flequillo en mechones y un rulo, panza redonda que empuja la camiseta por delante del
short, brazos y piernas regordetes, manos tipo manopla con pulgar y zapatos grandes y
blandos. Creado en Blender 5.2.1.

La forma de la cabeza vive en `head_shape.py` (elipsoide, papada, cachetes y línea del
pelo): la usan `build_character.py` para esculpirla y `render_review.py` para apoyar la
cara, y `character_face.gd` en el juego repite el elipsoide y la papada (`HEAD_*`). Si se
cambia uno, hay que cambiar los tres; `test_player_character` avisa si la cara queda
enterrada o flotando.

## Archivos

- `personaje_redondeado.blend`: modelo editable, materiales, rig y estudio de render.
- `personaje_redondeado.glb`: personaje con esqueleto, pesos, morphs y respiración horneada.
- `preview_frente.png` y `preview_tres_cuartos.png`: renders de la pose neutra.
- `preview_pose_rig.png`: prueba de brazos flexionados y pie levantado con IK.
- `respaldo_sesion_anterior.blend`: copia de la escena que estaba abierta antes de cargar este personaje.
- `render_review.py`: renders de revisión en Cycles con la cara puesta (frente, ¾ y primer
  plano en `review/`), opcionalmente en un cuadro de un clip (`--pose Walk:10`). Rasteriza
  los SVG de la cara con PyMuPDF del Python del sistema (`python -m pip install pymupdf`).
- `check_clearance.py`: cuenta cuántos vértices de antebrazo y mano quedan dentro de la
  camiseta en cada clip (la panza es grande); guarda `clearance_check` en `validation.json`.
- `vertex_shading.py`: oclusión suave y rubor (cachetes, nariz, orejas) horneados en color
  de vértice al exportar; Godot los multiplica en el material.

## Posar en Blender

El archivo abre con el rig seleccionado en **Pose Mode**. Frame 1 es la pose neutra.
Los huesos `.L` y `.R` se nombran desde el punto de vista del personaje.

| Control | Uso |
| --- | --- |
| `CTRL_root` | Mover todo el personaje. |
| `pelvis`, `spine`, `chest` | Mover la pelvis y rotar la columna. |
| `head` | Rotar la cabeza desde la base del cuello. |
| `CTRL_hand_IK.L/R` | G para mover manos; R para orientarlas. |
| `CTRL_foot_IK.L/R` | G para apoyar o levantar pies; R para orientarlos. |
| `CTRL_elbow.L/R`, `CTRL_knee.L/R` | Ajustar la dirección de flexión. |
| `belly` | Deformación secundaria manual de barriga. |
| `thumb.L/R` | Pulgares, dentro de la colección de huesos auxiliares. |
| `grip.L/R` | Huesos de anclaje que siguen las manos y se exportan. |

En las propiedades personalizadas del objeto rig, `IK_brazo.L/R` e
`IK_pierna.L/R` valen 1 para IK y 0 para FK. Para usar FK, mostrar la colección
de huesos **FK · articulaciones**. El cambio no incluye ajuste automático de
pose entre IK/FK: conviene hacerlo en reposo antes de animar.

La camiseta tiene shape keys **Respirar** y **Barriga_blanda**. Hay una
respiración de ejemplo en los frames 1–90 a 30 fps. Si querés editar manualmente
la barriga sin animación, desvinculá temporalmente sus acciones o usá frame 1.
El hueso de barriga no es una simulación física automática.

La colección **ESTUDIO** está oculta en viewport para facilitar la selección,
pero se mantiene visible en los renders. No forma parte del GLB.

## Exportación a Godot

Importación comprobada con Godot **4.7.2**: 26 huesos, 16 mallas con skin,
ambos morphs y respiración animada. El `.blend` conserva 35 huesos en total,
incluyendo los controles que no se exportan. La animación de exportación
combina el movimiento de barriga y el morph en un único clip.

Frente en Blender: **−Y**; en el GLB importado: **+Z**. Altura aproximada:
**3,46 unidades** hasta la coronilla (3,68 con el rulo); una escala uniforme de 0,5 da
aproximadamente 1,73 m (1,84 m con el rulo).
La malla tiene **50.946 vértices / 101.622 triángulos** (el GLB del juego, ~23.500), con hasta cuatro
influencias por vértice. No incluye UVs pintados: usa materiales de color sólido.

Los controles IK de Blender no se convierten en controles IK de Godot.
El archivo incluye el esqueleto deformable y anclajes de mano; el ragdoll,
colisionadores, límites articulares, agarres y jiggle reactivo al terreno
requieren configuración en el motor. La integración en el jugador existente
no está realizada.

## Comprobaciones y reconstrucción

`validation.json` registra pesos normalizados, ausencia de vértices sin peso,
alineación en reposo y seguimiento de controles en una pose flexionada.
`godot_validation.json` registra la importación real y el muestreo de respiración.

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python art/rounded_character/build_character.py
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python art/rounded_character/check_deformation.py
# Solo el tiro del short en los clips (sin el render de Cycles):
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python art/rounded_character/check_deformation.py -- --crotch-only
# Brazos contra la panza en cada clip:
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python art/rounded_character/check_clearance.py
# Renders de revisión con cara (SAMPLES y RES por variable de entorno):
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python art/rounded_character/render_review.py -- classic smile --pose Walk:10
```

`build_character.py` acepta `SAMPLES` (muestras de Cycles de los previews, 40 por
defecto) y en modo `--background` no toca la vista del editor (Blender 5.2.1 se cuelga
al actualizarla sin interfaz).

La reconstrucción vuelve a generar los archivos de este directorio.
`verify_godot.gd` se ejecuta en un proyecto temporal vacío, pasando la ruta
absoluta del GLB después de `--`.
