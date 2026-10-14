# Bitácora de iteración contra la referencia

Referencia frontal: `referencia/referencia_frente.jpg`. La comparación aprobatoria se hizo con el render real de Godot a 832 × 1248, no con una captura de Blender. Cada ronda conserva `godot_render.png`, `godot_render_mask.png`, `side_by_side.png`, `difference.png`, `report.json` y `visual_review.json` dentro de `review_bloque_e/round_NN/`.

Umbrales: IoU de silueta ≥ 0,92; ΔE CIE76 medio ≤ 8 en cabeza, torso, brazos y piernas; revisión visual 12/12. Se ejecutaron 149 rondas sin fijar un tope; esta tabla resume los hitos que cambiaron la dirección del ajuste.

| Ronda | Lado a lado | IoU | ΔE cabeza | ΔE torso | ΔE brazos | ΔE piernas | Cambio realizado | Qué faltaba |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 1 | [comparación](review_bloque_e/round_01/side_by_side.png) | 0,609689 | 25,9546 | 17,0134 | 14,7611 | 16,8230 | Punto de partida: preset Delgada sin calibración y pose frontal inicial. | Corregir encuadre, pose, silueta y material completo. |
| 50 | [comparación](review_bloque_e/round_50/side_by_side.png) | 0,895818 | 11,1675 | 9,9546 | 8,4227 | 9,4375 | Cámara fijada en x −0,006, y 0,891, distancia 4,133 m; proporciones generales y brazos acercados a la referencia. | Cabeza, hombros, manos y piernas aún impedían IoU 0,92; todas las zonas fallaban color. |
| 84 | [comparación](review_bloque_e/round_84/side_by_side.png) | 0,914189 | 11,2568 | 9,7778 | 8,2664 | 9,4156 | Cabeza y manopla localizadas en los morphs; brazos a 89°/−15°/10° y hombros −0,55. | Cerrar aproximadamente 0,006 de IoU y corregir la iluminación. |
| 116 | [comparación](review_bloque_e/round_116/side_by_side.png) | 0,918866 | 11,2549 | 9,7957 | 8,1941 | 9,4253 | Hombro base estrechado y barrido fino del brazo superior; mejor pose en 88,5°. | Faltaban unas centenas de píxeles en brazos, pecho alto y piernas. |
| 132 | [comparación](review_bloque_e/round_132/side_by_side.png) | 0,921163 | 11,2627 | 9,7496 | 8,2221 | 9,3941 | Se combinó antebrazo −14°, pierna 0,99 y pecho −0,45. La silueta pasó por primera vez. | Mantener la silueta y bajar ΔE en las cuatro zonas. |
| 143 | [comparación](review_bloque_e/round_143/side_by_side.png) | 0,921163 | 7,3049 | 6,7602 | 7,4938 | 7,4252 | Envolvente subsuperficial 1,0 y contraluz 0,5: todas las zonas de color pasaron. | La revisión visual detectó facetas grandes en cabeza y torso. |
| 149 | [comparación final](review_bloque_e/round_149/side_by_side.png) | **0,920871** | **7,4700** | **6,0676** | **7,2972** | **7,0753** | LOD0 aumentado de 4.704 a 18.816 triángulos, pulgar compensado sólo en LOD0 y mapa de espesor regenerado para el nuevo atlas. | Ninguno: pasa silueta, color y revisión visual 12/12. |

## Valores aprobados

El preset `delgada.tres` conserva: `leg_length=0.99`, `arm_length=0.90`, `head_size=1.15`, `general_thickness=0.60`, `chest=-0.45`, `shoulders=-1.0`, `hips=0.35`, `arm_thickness=0.20`, `leg_thickness=0.55`, `hand_size=-0.70`, `foot_size=0.70`, `head_shape=0.50` y `neck_thickness=0.35`.

La captura aprobada usa brazos `88° / −14° / 10°`, color `#9c9da5`, brillo `0,85`, densidad de borde `0,5`, refracción `0,4`, mezcla de absorción `0,7`, envolvente subsuperficial `1,0` y contraluz `0,5`.

## Resultado final

- Silueta: **aprobada**, IoU 0,920871.
- Color: **aprobado**, las cuatro zonas están por debajo de ΔE 8.
- Revisión visual: **12/12 sí** en `review_bloque_e/round_149/visual_review.json`.
- Geometría: LOD0/1/2 = 18.816/2.248/794 triángulos; una sola componente cerrada y sombreado suave en todas las caras.
- El mapa de espesor final se volvió a medir con 18.816 rayos centrados en triángulos, sin muestras perdidas ni valores recortados.
