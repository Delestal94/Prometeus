# Verificación del bloque A — S-311.1–8

Fecha: 2026-09-30. Alcance: referencia, dirección visual y presupuesto;
no cambia el personaje del juego ni implementa los bloques B–O.

## Comprobaciones reproducibles

- `python art/gel_character/measure_reference.py`: PASS. Fuente 832×1248,
  caja inclusiva `(148,98)–(676,1135)`, H=1038, D=282, H/D=3,68.
  Las siete medianas RGB coinciden con `referencia/material_objetivo.md`.
- `python art/gel_character/validate_glb.py art/gel_character/gel_character_candidate.glb`:
  PASS de estructura, pesos normalizados y ocho animaciones existentes.
- Mismo comando con `--max-triangles 6000`: rechazo esperado y comprobado,
  `Triangle budget exceeded: 46552 > 6000`. Es una limitación del candidato
  histórico, no un resultado final aprobado. Sus 35 joints también exceden
  el objetivo de veinte exportados en total.
- `git diff --check`: sin errores de espacios.
- Revisión documental y de dominios: rutas verificadas nuevamente tras actualizar
  desde `origin/main` (`aed34dd`); solo arte/documentación propia o libre.
  No se modifican archivos de Nacho ni APIs compartidas: no corresponde aviso.

## Límites del cierre

La imagen anotada es generativa e ilustrativa: no se usa para medir ni comparar
la silueta. El JPG original y la tabla son la autoridad. Las cotas anteroposteriores
no son recuperables de una vista frontal y se definen como dirección de perfil,
no como mediciones de la foto. La aprobación cuantitativa de forma/material y
la prueba de presupuesto en Godot corresponden a B–E.

No corresponde un test GDScript nuevo porque no se cambian escenas, nodos,
parámetros del juego ni mecánicas. El script de medición verifica los datos de
referencia; la batería existente y las comprobaciones de integración se ejecutan
en CI del PR antes de integrar a `main`.

Revisión visual independiente: las tres variaciones guiadas ComfyUI v3
(311071/311072/311073) pasan la dirección conceptual; se elige 311071 por su
pulgar más legible en perfil. Se verifican catorce figuras, ambos turnarounds,
dos extremos y seis colores, sin dedos humanos ni orejas/caras. Las reservas de
proporción, color leche y extremos no paramétricos quedan en
`concept/seleccion_comfy.md`; esta aprobación no certifica el bloque E.

El helper guiado se ejecutó contra ComfyUI local, produjo tres PNG de 1664 × 960
y guardó los workflows. Una comprobación adicional de sus nodos verifica VAEEncode,
entrada latente, ocho pasos, ancho y denoise 0,15 sin encolar imágenes nuevas.
