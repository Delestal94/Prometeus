# Entrega final de estudio del personaje gelatinoso

Esta carpeta reúne la presentación reproducible de S-311.100. Todos los
fotogramas proceden del personaje LOD0 real, su material y sus animaciones en
Godot; no son concept art ni imágenes generadas.

## Entrega S-311.100

### Turntable de seis presets en seis colores

Cada lámina mide 1760 × 1080. Sus filas, de arriba abajo, son **Delgada**,
**Flaca**, **Rellena**, **Petisa**, **Cabezona** y **Larguirucha**. Las ocho
columnas recorren 0°, 45°, 90°, 135°, 180°, 225°, 270° y 315°.

| Archivo | Color |
| --- | --- |
| `s311_100_turntable_mint.png` | Menta `#83e2ba` |
| `s311_100_turntable_amber.png` | Ámbar `#f4c562` |
| `s311_100_turntable_coral.png` | Coral `#f47e6d` |
| `s311_100_turntable_sky.png` | Cielo `#6db3d6` |
| `s311_100_turntable_lilac.png` | Lila `#c9a0e0` |
| `s311_100_turntable_cobalt.png` | Cobalto `#5f7fd0` |

### Editor y reel

- `s311_100_editor_sliders.avi`: 12,9 segundos a 24 FPS y 1280 × 720. Abre
  la pantalla real de personalización, recorre cuatro presets y mueve Altura,
  Grosor, Cabeza, Hombros y Caderas. Usa un perfil temporal dentro de `tests/`
  que elimina al terminar; no modifica el perfil del jugador.
- `s311_100_animation_reel.avi`: 29,3 segundos a 24 FPS y 1280 × 720. Incluye
  base (`Idle`, `Walk`, `Run`, `Jump`), graciosas (`Point`, `ShakeLikeDog`,
  `BlowBubble`, `BallBounce`), bailes (`SimpleStep`, `Robot`, `Disco`,
  `FloorWorm`, `VictoryDance`, `Conga`) y muertes (`Pancake`,
  `MeltAndReturn`, `Defeat`, `SplitAndJoin`).
- `s311_100_editor_preview.png` y `s311_100_animation_reel_preview.png` son
  fotogramas de control extraídos durante las mismas grabaciones.
- `s311_100_manifest.json` registra colores, orden, ángulos, resolución,
  velocidad, categorías y todos los archivos principales.

Este bloque **no modifica la selección del personaje por defecto**. Esa decisión
de producto queda separada y requiere el visto bueno explícito del usuario.

## Reproducción

Las láminas se generan con:

```powershell
& '<Godot 4.7.2 console>' --path do-not-drop --rendering-method gl_compatibility `
  --audio-driver Dummy --script res://tests/render_gel_final_turntables.gd
```

Los videos se generan con MovieWriter:

```powershell
& '<Godot 4.7.2 console>' --path do-not-drop --rendering-method gl_compatibility `
  --audio-driver Dummy --fixed-fps 24 --resolution 1280x720 `
  --write-movie ../art/gel_character/review/s311_100_editor_sliders.avi `
  --script res://tests/record_gel_editor.gd

& '<Godot 4.7.2 console>' --path do-not-drop --rendering-method gl_compatibility `
  --audio-driver Dummy --fixed-fps 24 --resolution 1280x720 `
  --write-movie ../art/gel_character/review/s311_100_animation_reel.avi `
  --script res://tests/record_gel_animation_reel.gd
```

Cada script termina por sí solo y no deja Godot ni servidores abiertos. En
Windows, MovieWriter muestra su ventana mientras graba; esos dos comandos deben
ejecutarse únicamente cuando no interrumpan a quien está usando el escritorio.

## Material de revisión S-311.83

Las hojas `s311_83_motion_*.png`, `s311_83_turntable.png` y `manifest.json`
conservan la revisión anterior de los 23 clips. En las hojas de movimiento, las
filas son Delgada, Flaca y Extremo seguro; las columnas muestran 18 %, 50 % y
82 % del clip. El extremo seguro combina los límites adversos válidos del
editor para detectar arcos rotos e intersecciones.

La fuente y el `.blend` derivado conservan una muestra exacta por cuadro a
60 Hz con asas Bezier `AUTO_CLAMPED`. El GLB vuelve a hornearse a 60 Hz y
`gel_body_build_report.json` exige cero claves lineales en el archivo de autoría.
