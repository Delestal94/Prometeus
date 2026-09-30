# Aviso: S-605, avisos de trampas y eventos con tono (2026-09-30)

Rama `nacho/S-605-trap-event-tone`. No toca ningún `.gd` de Slatex (`traps/`, `package/`, `interaction/`): solo cambia
**valores** de `translations/strings_ui.csv` (zona compartida) de los textos que esas trampas devuelven en
`hint_text()` y de los `prompt` de los eventos de ruta. Ninguna clave, formato de argumentos ni mecánica cambia.

## Qué cambió

- Los 24 textos `HUD_HINT_<TRAMPA>_*` (Frágil, Equilibrio, Explosivo, Peso creciente, Hostil, Líquido, Ruidoso)
  hablan de la situación con el tono de `docs/narrativa.md`, en máximo 6 palabras (es y en). Cada uno conserva el
  verbo de N-117 (Amortiguá, Contrapesá, Asegurá, Pedí el código, Abrazalo, Fregá) y, donde hace falta, "mantené"/"soltá".
- Los 10 textos de prompt de eventos (`HUD_EVENT_*_PROMPT`, `_IMPATIENT_HOUSE`, `_MIMIC_REVEALED`,
  `_MIXED_LABELS_SWAPPED`) siguen el mismo límite.
- Explosivo: `%02d s` pasó a `%02ds` en las dos pistas con cuenta regresiva (mismo argumento).
- `tests/test_ui_translations.gd` exige ahora <= 6 palabras (sin contar valores insertados) en esas claves.

## Qué tiene que hacer Slatex

Nada. Una trampa o evento nuevo debe respetar el límite de 6 palabras en su pista; el test lo verifica.
