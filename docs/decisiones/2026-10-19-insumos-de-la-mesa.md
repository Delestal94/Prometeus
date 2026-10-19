# Decisión: insumos de la mesa de armado (D-0718)

- **Qué:** cada mesa lleva su stock de cajas (por tamaño), cinta y relleno (`StationSupplies`,
  `CompanyTuning.SUPPLY_CAPACITY`: 6/6/4/3 cajas, 10 cintas, 30 de relleno). Usarlos gasta stock; sin stock el
  paso se rechaza.
- **Reponer no cuesta plata**, cuesta el tiempo de quien se queda en la mesa. El dinero sigue cobrándose al
  usar cada insumo (D-0504), así que no hay doble cobro.
- **Por qué:** `diseno/referencias-logistica.md` pide "cajas e insumos que se gastan y se reponen: tarea del que
  se queda". Es el trabajo para el rol que no arma ni maneja, sin sumar una pantalla de compras.
- **Se cambia en:** `CompanyTuning.SUPPLY_CAPACITY` y `SUPPLY_LOW_RATIO`, nada más.
