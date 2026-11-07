# D-0546: el dinero se muestra con el separador del idioma

- **Qué cambió** (archivos de Slatex, `scripts/ui/`):
  - `MoneyText.format(monto, locale = "")` nuevo en `scripts/ui/money_text.gd`: "$1.234" en español, "$1,234" en
    inglés, "-$1.500" para una pérdida, sin separador bajo 1000.
  - `CompanyShopPanel.money()` y `DaySummaryPanel.money()` lo usan; misma firma, otro texto desde 1000.
  - `CompanyDayHud` muestra el dinero por `DaySummaryPanel.money()`, así que la tira del día también dice "$1.250"
    (solo cambió su comentario).
  - El HUD de la entrega (`hud.gd`, `hud_notices.gd`) sigue con "$%d": no se tocó.
- **Qué tiene que hacer Slatex:** nada. Un texto de dinero nuevo en la UI pasa por `MoneyText.format()`; un test que
  compare dinero arma lo esperado con `MoneyText.format()` y no con `"$%d"` (`test_company_root`, `test_company_day_hud`).
