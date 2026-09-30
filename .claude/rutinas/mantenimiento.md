# Rutina: mantenimiento semanal

Lo que nadie hace porque no es una feature: docs al día, avisos que faltaron, red y código compartido
revisados después de mezclar (no hay revisión antes). Reglas comunes y sesión:
`.claude/rutinas/README.md` (leelo primero).

## 1. Qué entró

PRs mezclados en los últimos 7 días y su diff total:
`git log --since="7 days ago" --first-parent origin/main --format="%h %s"` y
`git diff <primer-hash>^..origin/main --stat`.

## 2. Pasadas (en este orden)

1. **`guardian-dominios`** sobre cada PR de la semana que tocó archivos del otro integrante o la zona
   compartida: ¿tiene su aviso en `docs/avisos/`? Los que falten los escribís vos (retroactivos, con el
   número de PR).
2. **`documentador`** con la lista de cambios: README (cómo probar), `docs/arquitectura.md`,
   `docs/convenciones-godot.md`, `docs/inventario-assets.md`, tareas marcadas sin hash. Arregla docs
   directamente.
3. **`auditor-red`** si algún cambio tocó red (`git diff ... | grep -E "rpc|MultiplayerSynchronizer|NetworkManager|multiplayer\."`):
   sobre esos archivos.
4. **`revisor-gdscript`** sobre el diff de la semana en la zona compartida (`file_domain` =
   `compartida`) y los 3 archivos que más cambiaron.
5. Chequeos baratos, directos: `bash tools/list-tests.sh --missing` vacío; `bash tools/lint.sh` sin
   errores nuevos respecto de `tools/lint-baseline.txt` (si la baseline se puede achicar, achicala);
   `.uid` sin trackear de archivos que sí están trackeados → agregalos.

## 3. Registrar

- Sin nada que arreglar ni reportar: sin PR.
- Si no, rama `rutina/mant-AAAA-MM-DD`:
  - docs y avisos arreglados directamente;
  - hallazgos de código (BUG / RIESGO de `auditor-red`, bugs reales de `revisor-gdscript`) →
    **`planificador-tareas`**, en la lista del dueño, prioridad según gravedad;
  - PR `chore: weekly maintenance AAAA-MM-DD` con auto-merge; cuerpo con lo arreglado y las tareas creadas.
- Esta rutina no arregla código del juego (salvo `.uid` faltantes y lint trivial).
