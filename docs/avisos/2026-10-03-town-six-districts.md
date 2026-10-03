# N-950 · Escenas de los seis distritos

Nuevas escenas `town_city.tscn` (inspección) y `town_city_delivery.tscn`
(conducción/reparto offline). Abren los seis distritos sobre el mismo plano.
`town_delivery.built_districts` selecciona construcción y GPS; la escena
anterior conserva `[0,1]`. Seis clientes, direcciones y controles intactos.

`town_art` perfila almacenes, farmhouses y cabañas/pinos con modelos existentes.
`town_landmarks` reutiliza torre/molino en huecos libres. `town_dresser` reserva
los landmarks y aplica zonas rurales/bosque para Campo/Sierra. `town_terrain`
indexa plataformas y completa la envolvente real de suelo entre los distritos
sin cambiar el grafo. Pruebas/capturas de ambas semillas y geometría física.

Campaña, menú, guardado y sincronización no se conectan en estas escenas.
Puerto aún no tiene costa/muelles; Sierra todavía no incorpora nieve.
Actualizar antes de continuar cambios en el spike.
