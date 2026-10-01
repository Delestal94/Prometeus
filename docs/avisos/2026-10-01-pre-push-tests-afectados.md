# El hook `pre-push` ya no corre la batería completa

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`.githooks/pre-push` sigue corriendo `tools/check_modules.py` y el lint en cada push (un segundo cada
uno). De los tests, ahora corre solo los **afectados por lo que se sube**:
- los tests que el push agrega o cambia (del juego o de un módulo);
- los tests que nombran un `.gd` cambiado, por nombre de archivo o por su `class_name`.

Si son más de 25 (un cambio ancho), corre solo los tests que cambiaron y el resto queda para CI.

**Por qué:** la batería completa tardaba unos 20 minutos en el push, contra 6 a 9 de CI, que la reparte
en cuatro runners y es la compuerta requerida para mergear. Mientras el push corría, `main` se movía y
había que rehacer el merge.

## Qué tiene que hacer Slatex

- Nada para seguir trabajando. `tools/setup-hooks.sh` no cambia.
- `FULL_TESTS=1 git push` corre la batería entera antes de subir; `SKIP_TESTS=1 git push` sigue
  salteando los tests (no el lint ni `check_modules`).
- `docs/colaboracion-equipo.md` (zona compartida), punto 2: la batería entera la corre CI.
