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
| 2026-09-23 | `art/concept/icons/trap_*_seed9.png` → `assets/ui/icons/tx_ui_trap_*_256.png` | 9 | Íconos de las 4 trampas (todavía sin integrar al HUD) | idem |
| 2026-09-23 | `assets/textures/detail/tx_detail_*_512.png` (10 mapas) | 11-20 | Detalle de terreno y modelos (asfalto, pasto, tierra, grava, tablas, tejas, revoque, corteza, follaje, piedra); convertidos a gris y procesados | ver `art/tools/make_detail_textures.py` (prompts en `TEXTURES`) |
