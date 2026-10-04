# Sin electricidad ni enchufes como restricción del galpón (D-0912)

**Decisión:** en el galpón construible **no hay red eléctrica**: ninguna máquina ni objeto colocable
necesita un enchufe, un tablero ni una potencia. Se coloca donde la grilla lo permite y ya.

**Por qué:**
- D-0505 ya decidió "sin combustible ni energía; el costo operativo es el mantenimiento (D-0527)". Una red
  eléctrica sería un costo operativo por la puerta de atrás.
- Un enchufe sería una segunda restricción de colocación (además del choque de D-0902 y los caminos libres
  de D-0907) que obliga a dibujar cables, tableros y un overlay para entenderla; el modo construcción tiene
  que ser jugable con mando (D-0917) y sin leer un manual.
- Las máquinas de automatización (grupo 11) ya tienen su freno natural: precio, huella, mantenimiento y el
  presupuesto de objetos por etapa (D-0915).
- Costo de arte y red: cero. Un cable replicado por jugador es ancho de banda para nada.

**Qué queda igual:** la batería del carrito (D-1223) es del vehículo, no del galpón; se carga estacionándolo
en el galpón, sin enchufe colocable.

**Si el usuario lo quiere distinto:** sumar `needs_power: bool` y `power_range` a `PlaceableDefinition` y una
regla en `BuildGrid.validate` (D-0225). No hay nada construido que se rompa. Anotado en
`expansion-distritos/revisar/D-0912.md`.

**Afecta:** D-0904 (los 4 `.tres` no llevan campo de energía), D-0922 (decoración), grupo 11.
