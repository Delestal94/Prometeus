# Aviso 2026-10-19 · revisión semanal: tareas que tocan el dominio de Slatex

Origen: rutina de revisión semanal (`.claude/rutinas/revision.md`), PR `docs: weekly review 2026-10-19`.
Solo cambian archivos de tareas; no se tocó código.

- **S-205** (heredada): ⏸ hasta que se cierre S-311. Veredicto de `critico-diseno`: lo que falta es la pose
  de manos (cuerpo). Al reabrirla, `medium` y solo una pose que lea `PlayerHoldFeedback.holding`.
- **N-311** (cosméticos): ⏸ post-lanzamiento junto con S-305.
- **N-977** (nueva): barra de atajos del HUD según el contexto, mínimo de 12 px a 720p y piso del fondo de
  texto. Va a tocar `scripts/ui/hud/hud_prompts.gd`, `hud.gd`, `care_prompt_view.gd` y `tutorial_panel.gd`.
- **N-975** (nueva): joiner tardío, gancho de rescate y casas ya entregadas. Va a tocar `run_manager.gd` y
  vistas de casas; probablemente sube `PROTOCOL_VERSION` a 36.

Preguntas para Slatex (no son tareas): en `docs/auditorias/2026-10-19-revision.md`, sección "Preguntas":
ragdoll sin consecuencia (`player.gd:614-617`), cara gel por defecto y caras vistas a la distancia real.
