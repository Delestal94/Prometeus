# S-311.6 — hojas de concepto ComfyUI

Fecha: 2026-09-30. Generador: Z-Image Turbo int8 convrot, encoder Qwen 3 4B
fp8 mixed, VAE `ae.safetensors`. Workflow de `art/tools/comfy_generate.py`:
8 pasos, CFG 1, `res_multistep` / `simple`, shift 3. Resolución 1344 × 768.
Tres semillas por hoja: **311061, 311062, 311063**.

La referencia original y sus medidas mandan sobre estas exploraciones generativas.
Delgada mide **3,68 diámetros de cabeza**, no cinco. Flaca conserva el objetivo
del ítem 21: aproximadamente seis cabezas, brazos/piernas 30 % más finos y cuello
visible. La dirección low-poly general se adapta aquí a la excepción explícita
S-311: superficies lisas y cero facetas, identidad original, sin imitar juegos.

Las cuatro esquinas de rango de la hoja de extremos son **objetivos conceptuales**,
no combinaciones ya comprobadas jugables. Solo el rango de alto 0,85–1,20 está
cerrado en el ítem 19; límites de los otros parámetros se verifican en B/C.

## Turnaround Delgada — prefijo `delgada_turnaround`

```text
Create an original stylized 3D game character production reference sheet, with exactly three full-body views of the SAME gelatin character, arranged left to right: straight front view, exact right-side profile looking to the right, straight back view. Orthographic camera, same scale, same standing relaxed A-pose and shared floor level in every view. The front and back must be visually different: on the back the heels are visible and the thumbs point outward, on the front the round toes are visible and thumbs point inward. Plain warm-white seamless studio background, soft warm even light and subtle pale contact shadows. Clean readable simple shapes for a cheerful delivery game, but fully smooth rounded surfaces, no visible polygon facets. This preset is Delgada: total standing height is only 3.68 spherical head diameters, a large perfectly spherical featureless head, a short neck 0.11 head diameters long blending smoothly into shoulders 1.08 head diameters wide, slim straight torso, legs about 38 percent of total height. Arms hang diagonally downward, mitten hands with one distinct thumb and no other fingers reach middle of thighs. Rounded boot-shaped feet with flat soles, NOT human toes; each foot is about 0.57 head diameters wide. The entire body is continuous milky translucent gelatin with a very subtle lavender-blue tint, denser pale rims, tiny low-contrast internal bubbles, background visible through head and limbs, torso slightly more opaque than limbs. Crisp soft rectangular window reflection on upper-left head, longitudinal highlights on arms and legs. Show all limbs uncropped and separated clearly. No eyes, no mouth, no nose, no face, no ears, no hair, no clothing, no accessories, no seams, no logos, no text, no watermark, no additional characters.
```

## Turnaround Flaca — prefijo `flaca_turnaround`

```text
Create an original stylized 3D game character production reference sheet, with exactly three full-body views of the SAME tall slender gelatin character, arranged left to right: straight front view, exact right-side profile looking to the right, straight back view. Orthographic camera, same scale, same standing relaxed A-pose and shared floor level in every view. The back shows heels, the front shows rounded toes; keep the side view strictly side-on, not three-quarter. Plain warm-white seamless studio background, soft warm even light, subtle pale contact shadows. Clean readable simple geometric shapes for a cheerful delivery game, but smooth rounded surfaces without visible polygon facets. This preset is Flaca, the slender variation of Delgada: approximately SIX spherical head diameters tall, a smooth perfectly spherical head with absolutely NO face, thin elongated torso, arms and legs approximately 30 percent thinner than the standard round gelatin character, longer legs, clearly visible narrow short neck continuously blended into shoulders, never a disconnected head. Relaxed arms end at mid-thigh, hands are rounded mittens with one distinct thumb and NO other fingers, feet remain chunky rounded boots with flat soles and one continuous toe cap. The entire continuous body is milky translucent gelatin with a subtle lavender-blue tint, denser pale rims, tiny faint internal bubbles, background visible through head and limbs, torso more opaque. Rectangular upper-left studio-window reflection on the head, smooth vertical highlights on limbs. Keep the silhouette slender rather than muscular or bony, and retain toy-like unisex anatomy. Three uncropped complete figures, no overlap. No eyes, mouth, nose, ears, hair, clothes, accessories, seams, text, logo or watermark.
```

## Extremos conceptuales — prefijo `extremos`

Orden de izquierda a derecha: Petisa/Rellena (alto 0,85), Larguirucha/Flaca
(alto 1,20), Cabezona (cabeza/manos/pies grandes), cabeza pequeña/cuerpo ancho
(hombros/cadera/cuello gruesos). Las formas extremas no autorizan proporciones
inseguras: se mantienen unión de cuello, manos separadas y apoyo plano.

```text
Create a four-character orthographic front-view lineup exploring safe proportion extremes of ONE original faceless translucent gelatin humanoid game character. Four complete figures spaced evenly across a plain warm-white studio board, standing in the same relaxed A-pose on a shared floor. Leftmost: short broad rounded character, height 85 percent of standard, plump belly, wide hips, short thick arms and legs, normal spherical head and narrow but continuous neck. Second: tall slender character, height 120 percent of standard, long fine legs and arms, narrow torso and small round head, visibly longer neck. Third: compact character with the largest spherical head, large mitten hands and big rounded boots, shorter limbs, neck thick enough to support the head. Fourth: broad-shouldered character with the smallest spherical head, broad chest and hips, thick neck, long arms, normal rounded boots and small mittens. All four have the same continuous simple rounded construction, no surface facets, no muscle definition, no sexual features, no facial features at all. Every hand has only one mitten mass and one clearly readable thumb, no fingers. Every foot is a rounded boot shape with a flat sole, no toes. Each figure is milky translucent gelatin with a faint lavender-blue tint, soft dense pale edges, fine faint bubbles, crisp upper-left rectangular window reflection on the head and soft vertical highlights on limbs; torso is more opaque than limbs. The background is visible through the heads and limbs. Soft warm studio light, pale soft contact shadows, legible silhouettes for a playful delivery game. These are proportion studies, not four different species. No eyes, mouth, nose, ears, hair, garments, accessories, seams, text, logo or watermark, no cropped limbs, no overlap.
```

## Delgada en seis colores — prefijo `delgada_colores`

Orden de lectura: leche-lavanda, frutilla, lima, uva, naranja, cielo. La variación
es únicamente de color/material; no cambia la geometría ni añade caras.

```text
Create a studio color-study reference sheet showing exactly SIX copies of the SAME original smooth faceless gelatin game character, a neatly spaced two-row by three-column grid of uncropped orthographic FRONT views in identical relaxed A-pose. The figure is only 3.68 spherical head diameters tall, with a big perfectly round featureless head, very short continuous neck, narrow shoulders about one head diameter wide, slim straight torso, legs about 38 percent of total height, diagonal hanging arms with mitten hands reaching mid-thigh. Hands are one round mitten mass with one distinct thumb, NO fingers; feet are rounded boot-shaped masses with flat soles, NO toes. The exact same silhouette, proportions, pose, scale and soft studio lighting in all six cells. Reading left to right top row, then left to right bottom row, colors are: translucent milky white with faint lavender tint; translucent pale strawberry pink; translucent lime green; translucent grape purple; translucent soft orange; translucent sky blue. Each color keeps milky translucent gelatin, dense lighter rims, background visible through head and limbs, fine faint internal bubbles, torso slightly more opaque, crisp rectangular upper-left window reflection on the head and continuous soft limb highlights. Smooth rounded surfaces, absolutely no visible polygon facets, no face, no eyes, no mouth, no nose, no ears, no hair, no clothing, no accessories. Plain warm-white seamless studio board with subtle pale ground shadows. Clean readable silhouettes and limited cheerful palette for an original cozy chaotic delivery game. No extra figures, no text, no labels, no logo, no watermark, no perspective distortion and no cropped limbs.
```

## Reproducción y selección

Extraer el bloque `text` del apartado correspondiente y pasarlo a `--prompt`:

```powershell
D:/Programas/comfy-venv/Scripts/python.exe art/tools/comfy_generate.py --prompt "<bloque completo de arriba>" --width 1344 --height 768 --seeds 311061 311062 311063 --out art/gel_character/concept/comfy --prefix <prefijo>
```

Las imágenes mantienen el nombre `<prefijo>_seed<semilla>.png`. La selección se
documentará después de inspeccionar las tres variantes de cada hoja: vistas y
conteo correctos, rasgos obligatorios, relación de cabeza y cuerpo, continuidad,
manoplas, botas, translucidez y consistencia entre figuras. Ninguna exploración
conceptual reemplaza la aprobación cuantitativa del render de Godot en el bloque E.
