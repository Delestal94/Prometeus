# Decisión 2026-11-11 · El release prueba el modo Empresa y una corrida manual no deja builds

Tarea: D-2020. Roles: `empaquetador-release` e `ingeniero-ci`.

## Contexto

`release.yml` solo arrancaba la build de Linux hasta el menú: una build sin la expansión llegaba igual al borrador.
`tools/export/smoke-company.sh` (D-2019) ya probaba el modo Empresa, pero solo en la PC. Para probar el paso nuevo
en una rama hace falta una corrida manual, y esa corrida subía los zips como artefacto en un repo público.

## Decisión

1. **El paso corre el mismo script de la PC** sobre `builds/linux`, después del export y antes de los zips, y falla
   con cualquier última línea que no sea `Empresa OK` o con un estado distinto de 0. Un solo script para las dos
   plataformas, así no se separan.
2. **Guardia de 300 s en CI** (`SMOKE_GUARD_SECONDS`; 150 en la PC): un runner lento no es un cuelgue. El largo
   del arranque lo fija `--quit-after`, no la guardia.
3. **`--autostart-company`** en el script y la sonda: es la bandera que el README le da a los jugadores;
   `--mode=company` queda como alias en `main_menu.gd`.
4. **Una corrida manual no publica ni guarda builds**: `publish` solo con `push` de un tag, y el artefacto de zips solo
   con un tag o con `keep_builds`. Los logs de un smoke que falla sí se suben (no tienen la build).
