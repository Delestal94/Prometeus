# D-1904: el menú principal elige la empresa (slots) y sus modificadores

- **Qué cambió:**
  - `scripts/core/company/company_save.gd` (dominio de Nacho): `write_options(options, slot, dir)` reescribe solo
    `company.options` de un slot guardado (limpio con `CompanyState.sanitize_options()`), como `mark_interrupted()`:
    no crea un slot que no existe ni toca un guardado de una versión más nueva. Es el "Opciones" del slot de
    `diseno/dificultad.md` §3 (siempre fuera de la partida).
  - `scripts/ui/main_menu.gd` y `scripts/ui/company_slots_page.gd`: "Modo Empresa" en Jugar abre una página nueva.
    Para jugar un slot deja `CompanyState` apagado (`reset()`) y pasa el slot por `CompanyRoot.launch_slot`, así que
    `CompanyRoot._add_net()` lo carga como con `--slot=`. Una empresa nueva llega a `CompanyRoot` **ya prendida**
    (`new_company(nombre)` + `options`) con un slot libre (`CompanySave.new_slot_id()`): `_add_net()` no carga nada
    y guarda su día 1 en ese slot. "Abrir sala para amigos" hace lo mismo con `_host_session(AUTO, COMPANY_SCENE)`.
  - `translations/strings_ui.csv`: `UI_MENU_PAGE_COMPANY`, `UI_COMPANY_SLOTS_*` y `UI_COMPANY_OPT_*` (nombre,
    descripción y chip de cada modificador).
- **Qué tiene que hacer Nacho:** nada. Si `CompanyRoot` deja de respetar una `CompanyState` ya prendida al arrancar
  (hoy solo carga el slot cuando está apagada), la empresa nueva del menú dejaría de llevar su nombre y sus
  modificadores: `tests/test_company_slots_menu.gd` cubre el lado del menú.
