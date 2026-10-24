# Revisión de animación S-311.83

Entrega reproducible del pulido de estudio de los 23 clips del cuerpo gelatinoso.
Las imágenes son capturas reales del LOD0 exportado y animado en Godot; no son
concept art ni imágenes generadas.

## Cómo leer las hojas

- Filas, de arriba abajo: **Delgada**, **Flaca** y **Extremo seguro**.
- Columnas de cada `s311_83_motion_*.png`: 18 %, 50 % y 82 % del clip.
- `s311_83_turntable.png`: ocho vistas separadas 45°, con el mismo orden de filas.
- `manifest.json` registra duraciones, muestras, valores del extremo y todos los archivos.

El extremo seguro mezcla límites adversos del editor: cuerpo corto, brazos largos,
cabeza grande, torso fino, vientre/pecho/caderas grandes y manos/pies máximos. Cumple
las restricciones cruzadas de cuello, hombros, manos y pies, por lo que sirve para
detectar arcos rotos o intersecciones sin probar una combinación inválida.

## Curvas

La fuente y el `.blend` derivado conservan una muestra exacta por cuadro a 60 Hz.
Entre muestras usan Bezier con asas `AUTO_CLAMPED`: suaviza la trayectoria subcuadro
sin crear máximos nuevos que hundan un pie o hagan rebotar un polo IK. El GLB se
hornea otra vez a 60 Hz para que Godot reproduzca exactamente esas poses. El informe
`gel_body_build_report.json` registra la cantidad de curvas y claves y exige cero
claves lineales en el archivo de autoría.

## Reproducción

```powershell
& '<Godot 4.7.2 console>' --path do-not-drop --rendering-method gl_compatibility `
  --audio-driver Dummy --resolution 320x240 --script res://tests/render_gel_animation_review.gd
```

El script termina por sí solo después de escribir todas las hojas; no requiere dejar
el editor ni un servidor de desarrollo abiertos.
