# S-311.6 — selección visual de conceptos ComfyUI

Fecha: 2026-09-30. Modelo Z-Image Turbo int8 convrot + Qwen 3 4B fp8 mixed +
`ae.safetensors`. Workflow estándar `art/tools/comfy_generate.py`: 8 pasos,
CFG 1, sampler `res_multistep`, scheduler `simple`, shift 3, 1344 × 768.
En cada hoja se compararon las semillas **311061, 311062 y 311063**.

## Estado de la entrega

**Entrega conceptual aprobada: S-311.6.** La serie guiada v3 corrigió dedos,
orejas y vistas posteriores ambiguas sin añadir ropa ni rasgos faciales.
La revisión visual independiente inspeccionó las tres semillas y recomienda
**311071**, por el pulgar más legible en las manoplas de perfil.

| Semilla | Archivo | Revisión |
|---:|---|---|
| **311071** | `comfy/guidance_v3/concept_guided_seed311071.png` | Elegida: manoplas limpias, cabezas lisas, dorsos/talones reconocibles y gel continuo. |
| 311072 | `comfy/guidance_v3/concept_guided_seed311072.png` | Sin defectos bloqueantes; mano de perfil algo más lisa/alargada. |
| 311073 | `comfy/guidance_v3/concept_guided_seed311073.png` | Sin defectos bloqueantes; conserva dorsos y talones estrechos. |

Cada hoja contiene catorce figuras: Delgada frente/perfil/espalda, Flaca
frente/perfil/espalda, dos extremos conceptuales y seis Delgadas en colores.
Guía: `concept_sheet_guidance_v3.png` (edición imagegen, no salida ComfyUI).
Receta: `REPRODUCIR_COMFY.md`; denoise 0,15, 1664 × 960, mismo sampler de ocho
pasos. Cada semilla conserva el JSON del workflow enviado y el prompt exacto.

**Reservas:** Delgada generativa es más cabezona que la medida (aprox. tres
diámetros en vez de 3,68); Flaca es una dirección alta/fina, no una plantilla
numérica. El primer color es demasiado lavanda para usarlo como muestra de leche:
mandan los RGB de `material_objetivo.md`. Los extremos no son límites paramétricos
ya validados. La aprobación es conceptual, **no cierra E**, no demuestra transmisión
sobre checker ni presupuesto de rendimiento. El JPG y la tabla de `../LEEME.md`
siguen siendo la autoridad para modelar y comparar.

## Estudios históricos no seleccionados para la entrega final

| Estudio | Archivo relativo a este directorio | Semilla | Motivo |
|---|---|---:|---|
| Delgada, tres vistas | `comfy/delgada_turnaround_r3_seed311062.png` | 311062 | Cabeza sin orejas ni rasgos, cuerpo continuo, manopla de perfil como masa única, translucidez y reflejos. La cabeza está sobredimensionada (~3 cabezas de alto, no 3,68): no calcar la proporción generativa. |
| Leche-lavanda / frutilla / lima | `comfy/delgada_colores_a_r3_seed311062.png` | 311062 | Tres variantes distinguibles, geometría consistente, manoplas y material translúcido. El tinte de leche es exploratorio; usar las muestras reales del material objetivo. |
| Uva / naranja / cielo | `comfy/delgada_colores_b_r3_seed311062.png` | 311062 | Tres variantes adicionales, lectura de borde y centro, sin ropa ni caras. Misma reserva de proporción que la hoja anterior. |
| Extremos conceptuales | `comfy/extremos_r4_seed311061.png` | 311061 | Alturas y grosores realmente distintos, base común, siluetas legibles, continuidad y gel. Orden visual: baja/ancha, alta/fina, compacta, alta/ancha. No es una matriz de límites paramétricos ya validada. |

En R3 los seis colores se presentaron en **dos hojas de tres**, porque el modelo
convertía la solicitud de seis figuras en tres cuerpos multicolor. No hay
caras, prendas, peinados ni implementación de skins: son solo estudios de A.
Estas cuatro imágenes históricas quedaron archivadas localmente junto con las
descartadas; la entrega guiada posterior reúne las catorce figuras en una hoja.

## Comparación y rechazos

| Ronda / hoja | 311061 | 311062 | 311063 | Decisión |
|---|---|---|---|---|
| R1 Delgada | Orejas y guantes con puños; opaco | Orejas; opaco | Orejas, dedos en perfil | Rechazar las tres. |
| R1 Flaca | Orejas y dedos | Orejas y dedos | Orejas y dedos | Rechazar las tres. |
| R1 extremos | Puños/ropa; opaco | Puños/ropa; opaco | Puños/ropa; opaco | Rechazar la ronda. |
| R1 colores | Tres figuras multicolor con puños | Cuatro figuras multicolor con puños | Tres figuras multicolor con puños | No produce seis figuras monocromas; rechazar. |
| R2 Delgada | Orejas, puños y dedos | Orejas, puños y dedos | Orejas, puños y dedos | Transparencia mejor; anatomía falla. |
| R2 Flaca | Orejas y dedos | Orejas y dedos | Orejas y dedos | Rechazar las tres. |
| R2 extremos | Orejas/puños | Orejas/puños | Orejas/puños | Rechazar las tres. |
| R2 colores | Cinco figuras, orejas y puños | Cuatro figuras, orejas y puños | Cinco figuras, orejas y puños | Conteo y anatomía fallan; rechazar. |
| R3 Delgada | Orejas y puños | Mejor masa única y esfera; proporción aproximada | Orejas, puños y dedos | Conservar 311062 como concepto parcial. |
| R3 Flaca | Orejas y dedos en perfil | Sin orejas; dedos en perfil | Dedos en perfil | Ninguna aprobada. |
| R3 extremos | Siluetas variadas | Alturas casi iguales | Una vista lateral invade el estudio frontal | R4 comunica mejor los extremos. |
| R3 colores A | Contaminación de contorno en cabeza | Mejor continuidad y consistencia | Puños en brazos | Elegir 311062. |
| R3 colores B | Contaminación de contorno en cabeza | Mejor continuidad y consistencia | Puños en brazos | Elegir 311062. |
| R4 Delgada | Orejas | Dedos de perfil; no mejora proporción | Orejas y dedos | Mantener R3/311062, no aprobar R4. |
| R4 Flaca | Orejas y dedos | Cabeza menor (~5,3 cabezas) pero dedos | Dedos de perfil | Ninguna aprobada. |
| R4 extremos | Mejor diversidad y gel continuo | Puños visibles | Menor continuidad | Elegir 311061 como exploración de extremos. |
| R5 Delgada | Orejas y puños | Orejas y puños | Orejas y dedos | Rechazar las tres. |
| R5 Flaca | Orejas y dedos | Sin orejas; dedos de perfil | Puños y dedos | Ninguna aprobada. |

## Prompts reproducibles

- R1: `prompts_comfy.md`.
- R2: `prompts_comfy_r2.md` — material primero y menos texto.
- R3: `prompts_comfy_r3.md` — geometría afirmativa, sin conceptos negados que
  el modelo repetía; colores separados en dos hojas.
- R4: `prompts_comfy_r4.md` — porcentajes/centímetros, pies de dorso y distintas alturas.
- R5: `prompts_comfy_r5.md` — intento de mano cerrada como masa curva única.

Las rondas descartadas se conservan localmente en `.beads/concept_explorations/`
(sin versionar); las rutas históricas de las tablas identifican sus nombres.
Las rondas fallidas no son fuente de verdad de modelado ni
assets del juego. Esta bitácora de concepto no cuenta como las cinco rondas del
bloque E, que requieren comparar un **render de Godot** con el JPG original.
