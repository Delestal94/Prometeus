# N-950: base del mapa urbano y escena independiente

Se agrega el módulo portable `modules/town_gen/`, con `TownPlan.generate(seed)`
(preload, sin clase global), y una escena independiente
`scenes/gameplay/town/town_prototype.tscn`. Produce los seis distritos en datos
y construye el primer barrio para inspección. No modifica firmas, RPC,
autoloads, niveles existentes, controles del camión ni guardados.

El plano es estable para una semilla/version: la futura progresión debe
filtrar accesibilidad, no regenerar geometría según el distrito desbloqueado.
El futuro guardado deberá conservar semilla y `generator_version`.

La escena utiliza cámara libre y geometría de prototipo. La conexión con
campaña, pedidos, jugador y camión sigue pendiente; no requiere cambios de
Slatex en este paso. Ver `docs/mapa-pueblo.md` para abrirla con F6.
