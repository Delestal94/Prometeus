# D-1909: menú de pausa del modo Empresa (con D-0253.a)

- **Qué cambió:** el modo Empresa tiene menú de pausa (`scripts/ui/company_pause_menu.gd`, `CompanyPauseMenu`):
  Continuar, Cerrar el día, Opciones, Volver al menú y Salir. Dibuja `DayClose.button()` y
  `DayClose.exit_warning()`, como pedía D-0253.a.
- **Archivo de Nacho tocado:** `scripts/gameplay/company_solo_pause.gd`. El cartel "EN PAUSA" pasa a ser este
  menú. `toggle()`, `resume()`, `can_pause()` y `EventBus.pause_requested` hacen lo mismo que antes. Es nuevo:
  - `open_menu()` y `close_menu()`: con más gente conectada, o en un cliente, Esc abre el menú sin pausar, y
    el mouse libre deja al jugador sin input;
  - `menu_open()` y `menu()`.
- **Textos nuevos** en `strings_ui.csv`: `UI_COMPANY_EXIT_ANYWAY`, `UI_COMPANY_PAUSE_BODY` y
  `UI_COMPANY_SOFT_PAUSE_BODY`.
- **Qué tiene que hacer Nacho:** nada. `company_root.gd` no cambió. Cuando exista el HUD de la Empresa, su pausa
  puede seguir emitiendo `EventBus.pause_requested` o llamar a `open_menu()`.
