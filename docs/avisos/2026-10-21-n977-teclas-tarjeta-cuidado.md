# N-977.5: la tarjeta de cuidado y el tutorial leen las teclas reasignadas

Tocado en archivos del dominio de Slatex: `scripts/gameplay/player/player_cargo_care.gd`
(`control_names` recibe `settings` y devuelve también `walk`), `scripts/ui/hud/care_prompt_view.gd`
y `care_practice.gd` (las teclas dibujadas leen `walk` en vez de W/A/S/D fijas) y
`scripts/ui/tutorial_panel.gd` (páginas del conductor y del pasajero).

Sin `settings` (tests, un `--script` antes de los autoloads) `control_names` devuelve las teclas de fábrica.
`player_cargo_care.gd` sigue sin nombrar autoloads ni `Hud` (N-919).
