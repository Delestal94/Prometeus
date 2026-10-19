# Auditoría 2026-10-19: la cara gel replicada necesita subir el protocolo

Para Slatex. La auditoría integral del 2026-10-19 (A-D.1) encontró que #475 (S-311.61) agregó
`GelFaceReactions:base_face_id` al `MultiplayerSynchronizer` de `player.tscn` sin subir
`PROTOCOL_VERSION`, que sigue en 34 (`docs/convenciones-godot.md` §6).

- **La tarea:** N-972 la sube a 35 en `network_manager.gd`, que es zona compartida, y deja otro aviso
  cuando entre.
- **Revisión de red:** `auditor-red` va a revisar el setter de `base_face_id` en
  `gel_face_reactions.gd:18-22`.
- **Para lo que venga:** todo cambio a un sincronizador o a un RPC lleva su número de protocolo.

La auditoría también sugiere un `AGENTS.md` para que Codex siga las reglas de avisos, protocolo y
`.uid` (pregunta 3 del informe `docs/auditorias/2026-10-19-integral.md`).
