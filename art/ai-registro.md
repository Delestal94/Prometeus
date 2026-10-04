# Registro de contenido generado con IA — Take My Package

Base para la declaración de contenido generado con IA que exige Steam. Una fila por imagen que se
conserve (las exploraciones descartadas no hace falta anotarlas).

Modelo local: Z-Image Turbo (Alibaba Tongyi, Apache 2.0) vía ComfyUI 0.37, `z_image_turbo_int8_convrot`
+ `qwen_3_4b_fp8_mixed` + `ae`, 8 pasos, CFG 1, res_multistep/simple, shift 3.
Script: `art/tools/comfy_generate.py`.

| Fecha | Archivo | Semilla | Uso | Prompt |
|---|---|---|---|---|
| 2026-09-23 | `art/concept/menu/menu_bg_seed11.png` → `assets/ui/backgrounds/tx_ui_menu_background_1920.png` | 11 | Fondo del menú principal (en el juego) | ver `art/concept/menu/prompt.txt` |
| 2026-09-23 | `assets/ui/backgrounds/tx_ui_boot_splash_1920.png` | 11 | Splash de arranque: el mismo fondo + título en texto (Arial Black, no generado) | idem |
| 2026-09-23 | `art/concept/icons/app_icon_seed8.png` → `icon.png`, `assets/ui/icons/tx_ui_app_icon_1024.png`, `app_icon.ico` | 8 | Ícono de la app y del .exe | ver `art/concept/icons/prompts.txt` |
| 2026-09-23 | `art/concept/icons/trap_*_seed9.png` → `assets/ui/icons/tx_ui_trap_*_256.png` | 9 | Íconos originales de las primeras 4 trampas | idem |
| 2026-09-27 | `assets/ui/icons/tx_ui_trap_liquid_256.png` | — (ChatGPT imagegen) | Ícono HUD de la trampa Líquido | Caja ámbar low-poly con botella de vidrio volcada y líquido turquesa derramándose; mismo ángulo, volumen y paleta que los cuatro íconos de referencia; fondo transparente, sin texto. |
| 2026-09-27 | `assets/ui/icons/tx_ui_trap_explosive_256.png` | — (ChatGPT imagegen) | Ícono HUD de la trampa Explosivo | Caja ámbar low-poly abierta con tres cohetes gruesos y un destello angular; mismo ángulo, volumen y paleta que los cuatro íconos de referencia; fondo transparente, sin texto. |
| 2026-09-27 | `assets/ui/icons/tx_ui_trap_hostile_256.png` | — (ChatGPT imagegen) | Ícono HUD de la trampa Hostil | Caja ámbar low-poly con mapache travieso de ojos ámbar y patas sobre la solapa; mismo ángulo, volumen y paleta que los cuatro íconos de referencia; fondo transparente, sin texto. |
| 2026-09-27 | `assets/ui/icons/tx_ui_trap_{fragile,balance,growing_weight,noisy}_256.png` | — (edición ChatGPT imagegen) | Normalización transparente de los cuatro íconos originales | Eliminar únicamente la placa verde petróleo, conservar el objeto low-poly y su sombra de contacto, centrarlo sin recortes sobre fondo transparente. |
| 2026-09-27 | `assets/ui/icons/tx_ui_action_{grab,drop,sit,bell,photo,horn,ping,open_box,use_card}_128.png` | — (ChatGPT imagegen) | Íconos de acción del HUD | Objetos de acción aislados, ilustración 3D-vectorial limpia, contorno marrón fino, cartón naranja y acentos menta; silueta legible a 42 px, fondo transparente, sin texto. |
| 2026-09-28 | `assets/ui/logo/tx_ui_logo_{wordmark,stacked}_2048.png` | — (ChatGPT imagegen) | Logo del menú y base para las cápsulas de Steam | Wordmark vectorial-raster transparente derivado de `UiTheme.logo()`: texto exacto “TAKE MY PACKAGE”, letras crema con contorno tinta y “PACKAGE” sobre cinta amarilla; versiones ancha y cuadrada apilada. |
| 2026-09-23 | `assets/textures/detail/tx_detail_*_512.png` (10 mapas) | 11-20 | Detalle de terreno y modelos (asfalto, pasto, tierra, grava, tablas, tejas, revoque, corteza, follaje, piedra); convertidos a gris y procesados (desde 2026-10-04, N-326: rehechos sin IA nueva desde los mismos crudos `art/concept/textures/tex_*_seed*.png` con `--from-raw`: componente periódico de Moisan, pasa-altos circular y fundido angosto en el borde de repetición) | ver `art/tools/make_detail_textures.py` (prompts en `TEXTURES`) |
| 2026-09-30 | `art/gel_character/referencia/proporciones.png` | — (edición ChatGPT imagegen) | Hoja anotada de proporciones S-311.2 | Reemplazada el 2026-10-01 por `annotate_reference.py`, que anota la foto real sin IA; el prompt queda en el historial de git |
| 2026-09-30 | `art/gel_character/concept/concept_sheet_imagegen_draft.png` | — (ChatGPT imagegen) | Borrador exploratorio y entrada de la guía S-311.6; no es la salida ComfyUI | ver `art/gel_character/concept/prompt.txt` |
| 2026-09-30 | `art/gel_character/concept/concept_sheet_guidance_v2.png` | — (edición ChatGPT imagegen) | Guía intermedia: manoplas y Flaca más fina; proporciones ilustrativas | ver `art/gel_character/concept/guidance_prompt.md`, edición v2 |
| 2026-09-30 | `art/gel_character/concept/concept_sheet_guidance_v3.png` | — (edición ChatGPT imagegen) | Guía de ComfyUI con talones y dorsos corregidos; derivada de v2 | ver `art/gel_character/concept/guidance_prompt.md`, edición v3 |
| 2026-09-30 | `art/gel_character/concept/comfy/guidance_v3/concept_guided_seed311071.png` | 311071 (Z-Image Turbo, ComfyUI 0.38.0, img2img denoise 0,15) | Hoja elegida S-311.6; guía imagegen v3, aprobación solo conceptual | ver `art/gel_character/concept/REPRODUCIR_COMFY.md`, `generate_guided.py` y JSON homónimo |
| 2026-09-30 | `art/gel_character/concept/comfy/guidance_v3/concept_guided_seed311072.png` | 311072 (Z-Image Turbo, ComfyUI 0.38.0, img2img denoise 0,15) | Variación comparada S-311.6; misma guía, no asset del juego | idem; JSON homónimo guarda prompt y workflow |
| 2026-09-30 | `art/gel_character/concept/comfy/guidance_v3/concept_guided_seed311073.png` | 311073 (Z-Image Turbo, ComfyUI 0.38.0, img2img denoise 0,15) | Variación comparada S-311.6; misma guía, no asset del juego | idem; JSON homónimo guarda prompt y workflow |
| 2026-10-01 | `art/concept/results/results_bg_r2_seed902.png` → `assets/ui/backgrounds/tx_ui_results_background_1920.png` | 902 (Z-Image Turbo, ComfyUI 0.37) | Fondo de la pantalla de resultados (S-307) | ver `art/concept/results/prompt.txt` |
| 2026-10-01 | `art/concept/results/results_bg_r3_seed1906.png`, `art/concept/results/results_bg_seed618.png` | 1906, 618 (Z-Image Turbo, ComfyUI 0.37) | Alternativas descartadas del fondo de resultados S-307; no son assets del juego | idem |

## Imágenes sin IA

Imágenes nuevas que no salieron de un generador. Se anotan para que la declaración de Steam pueda
decir de dónde vino cada una (agregadas por el mantenimiento del 2026-10-01).

| Fecha | Archivo | Origen | Uso |
|---|---|---|---|
| 2026-09-30 | `art/marketing/capturas/2026-09-30_{salida_deposito,curva_bosque,cruce_tren,puente_lluvia,casa_noche}.png` | Capturas del juego (`tests/render_store_shots.gd`, N-316, #121) | Capturas de tienda |
| 2026-10-01 | `assets/textures/characters/faces/{eyes,brows,mouth}_*.svg` | Dibujadas por código (`art/rounded_character/build_faces.py`, N-506, #151) | Caras del personaje |
| 2026-10-01 | `art/rounded_character/review/{customization_*,face_lineup_*}.png` | Capturas del juego (`tests/render_character_faces.gd`, N-506, #151) | Revisión; no son assets del juego |
| 2026-10-01 | `assets/textures/depot/tx_depot_{mural_brand,cork_photos,employee_month}.png` | Pillow + numpy (`assets/tools/depot_textures/`; las fotos del corcho son recortes de capturas del juego), N-319, #145 | Texturas del depósito |
| 2026-10-01 | `assets/textures/depot/tx_depot_{pictograms_512,cage_mesh_256}.png` | Dibujadas por código (`assets/tools/build_depot_props.py`), N-319, #145 | Texturas del depósito |
| 2026-10-01 | `art/concept/loading/loading_bg_seed1407.png` → `assets/ui/backgrounds/tx_ui_loading_background_1920.png` | 1407 (Z-Image Turbo, ComfyUI 0.37) | Fondo de la pantalla de carga (N-407) | ver `art/concept/loading/prompt.txt` |
