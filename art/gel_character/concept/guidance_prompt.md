# Guía de imagen a imagen — S-311.6

Las guías se editaron con la herramienta integrada ChatGPT imagegen; no son
salidas de Z-Image Turbo. La hoja final se genera con ComfyUI a partir de la guía.
No hay semilla expuesta para estas ediciones. El JPG original sigue siendo la
autoridad de mediciones; ninguna hoja generativa sustituye el comparador del bloque E.

## Edición v2

Destino: `concept_sheet_guidance_v2.png`. Entradas: el borrador
`concept_sheet_imagegen_draft.png` como objetivo y `../referencia/referencia_frente.jpg`
como referencia de forma/material. Mantener catorce figuras y composición:
tres vistas de Delgada, tres de Flaca, dos extremos y seis colores frontales.
Corregir las manos a una manopla con un solo pulgar, continuidad del gel,
cabeza esférica sin cara ni orejas. Pedir Delgada 3,68 diámetros de cabeza y
Flaca más alta/fina con cabeza menor. Material leche-lavanda, reflejo rectangular,
motas y sombra suave. La proporción numérica solicitada no se obtuvo exactamente:
es dirección conceptual, no una plantilla geométrica para calcar.

## Edición de dorsos v3

Objetivo: v2. Cambiar solo la tercera y sexta figura de la fila superior a
una vista ortográfica posterior inequívoca. Pies orientados alejándose de cámara,
talones estrechos debajo de pantorrillas, sin punteras voluminosas hacia el
espectador. Espalda y transición sacra suaves; manos manopla con pulgar sin
dedos. Conservar las otras doce figuras, material, colores y composición.

Prompt enviado (inglés):

> Change ONLY TWO FIGURES: the THIRD figure in the TOP ROW (Delgada back view),
> and SIXTH figure in the TOP ROW (Flaca back view). Replace each with an
> unmistakable true orthographic REAR VIEW of exactly its preset. Camera behind
> the figure looking at its back. Feet point AWAY from camera; show flat narrow
> rounded heel faces directly below calves, NOT big bulbous toe boxes facing
> camera. Show smooth upper back and sacral/buttock transition with very subtle
> rear cleft where legs split, not a front belly. Thumbs should be hidden behind
> or project outward at this rear angle. Keep hands single mittens with one thumb,
> no separate fingers. Keep spherical featureless heads, continuous lavender
> milky translucent gelatin and highlights. Preserve the other twelve figures,
> their layout, colors, sizes and poses, white background and 14 total figure
> count. Do not alter head sizes or add text.

## ComfyUI

El helper `generate_guided.py` sube la guía, la escala a 1664 × 960 y codifica
sus píxeles con VAE antes del sampler estándar. Denoise 0,15 conserva anatomía
y composición. Cada JSON guarda el workflow completo, semilla, prompt y guía
realmente enviada. La guía no se presenta como contenido generado por ComfyUI.
