# Aviso: galpón por defecto del modo Empresa y práctica de Entrega (D-0911 / D-0620, 2026-10-12)

Lo hizo Nacho (sesión a mano, tareas D-0911 y D-0620). Toca un archivo de Slatex: `scripts/gameplay/player/player_cargo_care.gd`.

- **Archivo de Slatex tocado** (`player_cargo_care.gd`): la tarjeta de práctica de Entrega ("Cómo cuidar la carga",
  termina con "subite a manejar para salir") ya no se crea si el jugador está en el grupo `company_crew` (constante
  local `COMPANY_GROUP`, como `EDGE_MARGIN`: no nombra `CompanyRoot`). Solo `CompanyRoot` mete jugadores en ese grupo;
  Entrega y Endless siguen igual (`test_modal_layers` lo comprueba). No se marca el consejo como visto: el perfil
  la sigue viendo en su primera Entrega.
- Lo demás es de Nacho: `DefaultShed` (`scripts/gameplay/business/default_shed.gd`), `data/shed/default_shed.tres`,
  `CompanyShed` (`scripts/gameplay/company_shed.gd`), `company_root.gd`, seis filas `WORLD_SHED_ZONE_*` en
  `strings_world.csv`, `test_company_default_layout` y ajustes a `test_company_root`, `bench_company` y
  `test_company_bench` (el galpón pasa de 48×32 m a 12×8 m, la etapa chica).
- Red: sin RPC nuevo ni cambio de `PROTOCOL_VERSION`. El host llena layout y stock de la empresa nueva antes de que
  `CompanyNet` copie el stock; los clientes dibujan lo que ya trae el snapshot. Cada pieza del layout gana una clave
  `uid` (`{id, x, z, turns, uid}`) que el snapshot y el guardado ya conservan.
- Slatex: nada que hacer.
