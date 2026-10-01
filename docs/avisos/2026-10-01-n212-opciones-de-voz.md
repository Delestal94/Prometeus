# Opciones de voz por proximidad en el panel de Opciones (N-212.3)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

- `scripts/ui/options_voice_section.gd` (nuevo, `class_name OptionsVoiceSection`): bloque de voz de Opciones, debajo de
  "Sonidos del juego". Casillas "Chat de voz" (`GameSettings.voice_chat_enabled`) y "Pulsar para hablar"
  (`GameSettings.voice_push_to_talk`, gris mientras la voz está apagada), aviso "solo en salas de Steam" y la lista
  "Voces de la tripulación": una fila por compañero conectado (sin uno mismo) con su color, "Silenciar"
  (`ProximityVoice.set_peer_muted`) y volumen 0-1 (`ProximityVoice.set_peer_volume`). Las filas salen de
  `CrewPanel.build_entries()` (mismo nombre y color que la tripulación del depósito) y se rearman al abrir Opciones y
  cuando cambia el roster con el panel abierto. Silencios y volúmenes duran lo que la sesión (así ya era en
  `SteamVoice`).
- `scripts/ui/options_panel.gd`: crea la sección, la sincroniza en `_sync_from_settings()` (Restablecer incluido),
  rearma la lista en `open()` y suma `voice_talk` ("Hablar (chat de voz)", Z) a las teclas reasignables.
- `scripts/core/game_settings.gd`: solo el comentario de `voice_chat_enabled`. Sigue apagada por defecto hasta probarla
  con Steam real.
- `translations/strings_ui.csv`: claves `UI_OPT_VOICE_CHAT`, `_PTT`, `_HINT`, `_CREW`, `_MUTE`, `_PEER_VOLUME`,
  `_NOBODY` y `UI_OPT_BIND_VOICE_TALK`.

Ninguna firma cambió; no hay RPC nuevo. Test `tests/test_voice_options.gd`.

## Qué tiene que hacer Slatex

Nada. Si rehacés Opciones, la voz vive en su propio nodo (`VoiceSection`): alcanza con moverlo.
