# Ciudad: secundarias y cordones (zona compartida)

N-950, Nacho. `modules/town_gen` añade `town_blocks.gd`; `town_plan.generate`
usa v3 por defecto y conserva v1/v2 explícitas y las parcelas base. Secundarias
8 m con cruces reales; infill prioriza sus frentes y conserva reservas verdes.

`town_walkways.generate` añade `corner_paths`, `heights` y `vehicle_access`.
Aceras 16 cm sobre asfalto y cordón vertical; rebajes sólo para vehículos y
esquinas. Puntos consecutivos iguales representan un cambio vertical:
ignorarlos al crear plataformas. Consumidores: admitir corner_paths y anchos
por segmento. Hacer pull antes de continuar el módulo. Tests de 100 semillas,
versiones, reservas, anchos y superficies. Campaña/guardado pendientes.
