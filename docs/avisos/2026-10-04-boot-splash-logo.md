# El splash de arranque lleva el logo real (N-328)

**Fecha:** 2026-10-04 · **De:** Nacho (sesión de arte de la PC) · **Para:** Slatex

## Qué cambió

Solo la imagen del splash, en `assets/ui/` (tu dominio); el código de UI no cambia.

- `assets/ui/backgrounds/tx_ui_boot_splash_1920.png`: el mismo fondo del menú con el wordmark de S-306
  (`assets/ui/logo/tx_ui_logo_wordmark_2048.png`) en la caja donde lo dibuja el menú: 630×315 en (96, 72) a
  1920×1080, que es (64, 48) 420×210 en la base de 1280×720. Antes llevaba el título en Arial Black y el
  subtítulo "DELIVERY COOPERATIVO", solo en español. Así, al pasar del splash al menú el logo no salta.
- Sale de `art/tools/make_boot_splash.py` (Pillow, sin IA nueva; `--check` avisa si quedó viejo).
- `tests/test_boot_splash.gd` comprueba que el logo esté en esa caja y que el resto sea igual al fondo del menú.

## Qué tenés que saber

Si movés o agrandás el logo en `main_menu.gd` `_build_brand` (o en `loading_screen.gd` `_build_logo`), o
cambiás el fondo del menú, corré `make_boot_splash.py` con la caja nueva. Si no, el splash salta y el test
falla.
