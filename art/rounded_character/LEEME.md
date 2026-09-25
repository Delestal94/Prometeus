# Personaje redondeado

Modelo basado en la referencia: cabeza lisa sin rostro, camiseta azul, short marrón,
manos tipo manopla con pulgar y zapatos redondeados. Creado en Blender 5.2.1.

## Archivos

- `personaje_redondeado.blend`: modelo editable, materiales, rig y estudio de render.
- `personaje_redondeado.glb`: personaje con esqueleto, pesos, morphs y respiración horneada.
- `preview_frente.png` y `preview_tres_cuartos.png`: renders de la pose neutra.
- `preview_pose_rig.png`: prueba de brazos flexionados y pie levantado con IK.
- `respaldo_sesion_anterior.blend`: copia de la escena que estaba abierta antes de cargar este personaje.

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
**3,47 unidades**; una escala uniforme de 0,5 da aproximadamente 1,74 m.
La malla tiene **31.897 vértices / 63.738 triángulos**, con hasta cuatro
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
```

La reconstrucción vuelve a generar los archivos de este directorio.
`verify_godot.gd` se ejecuta en un proyecto temporal vacío, pasando la ruta
absoluta del GLB después de `--`.
