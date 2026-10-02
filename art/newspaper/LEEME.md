# Estudio visual del diario — 2026-10-01

Dirección de arte y decisiones: `docs/diario-final.md`, sección «Estudio visual de la escena».
Capturas reales de Godot con assets del juego (no son imágenes generadas). Es un estudio de planos,
no la cinemática N-606.3: textos, pueblo y resultados son de ejemplo.

| Captura (`review/`) | Qué permite revisar |
|---|---|
| `01_oficina.png` | General: set, luz, el Jefe (camisa y bigote) y la tapa del diario. |
| `02_leyendo.png` | Pose de lectura, agarre y caída de las hojas. |
| `03_sobre_hombro.png` | El Jefe y la doble página. |
| `04_diario_completo.png` | Papel, diagramación de diario y manos en las esquinas. |
| `05_noticia_gallina.png` | Noticia principal entera: titular, bajada, foto, pie y cuerpo. |
| `06_noticia_espejo.png` | Noticia secundaria. |
| `07_clasificados.png` | Clasificados y avisos chicos. |
| `08_diario_final.png` | Regreso a la doble página. |
| `09_reaccion.png` | Baja el diario y reacciona. |
| `10_resultados.png` | Cierre con la cara despejada y la tarjeta de resultados. |

## Reproducir

Con GPU (sin `--headless`), después de importar el proyecto con Godot 4.7.2. `APPDATA` apunta a una
carpeta temporal para que los autoloads no toquen el perfil habitual.

```powershell
$env:APPDATA = 'D:/tmp/diario-review/profile'
& '<godot>.exe' --path do-not-drop --resolution 1920x1080 `
    --script res://scripts/tools/newspaper_concept/render_newspaper_concept.gd -- `
    --out=<carpeta absoluta>
```

El script falla (sale con 2) si un texto no entra en su caja, si un bloque de noticia queda cortado en
su primer plano o si la letra de una noticia queda por debajo de 24 px a 720p.

Con `--animate` además exporta el recorrido de 30 s como PNG numerados (`frames/`), para codificar a
30 fps con FFmpeg. Ni los cuadros ni el video van al repositorio.
