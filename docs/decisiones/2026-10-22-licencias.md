# Licencias de la empresa (D-0124) — 2026-10-22

## Decisión
Diseño en la sección "Las licencias" de `docs/expansion-distritos/diseno/hitos.md`:
- Cinco licencias, **compra única de la empresa** en la tienda, ofrecidas por su hito: náutica 650, 4x4 600,
  vuelo 1 000, alta montaña 1 000, volcánica 1 000 (4 250 en toda la campaña).
- Sin examen, sin vencimiento ni renovación (D-0537 sigue recortada) y no se pierden con la quiebra.
- Son de la empresa, no de un jugador: maneja cualquiera, también los empleados.
- Se guardan como claves `license_*` de `CompanyState.equipment` (sin campo nuevo en save, snapshot ni red);
  `ShopItem` suma el tipo `license` y `requires` pasa a valer para vehículos; los bloqueos las piden con
  `GateRequirement.equipment` (`gate_puerto` cambia el hito por la licencia). Lo construye D-0407.
- El primer vuelo después de comprar la avioneta es guiado y salteable (D-1418), no un examen.

## Por qué
- 650 para la náutica: cuatro jugadores ganan el hito el día 5 y cierran con 790; con 650 quedan 140, arriba
  del piso de 100 de caja, sin contar el premio del hito. `gate_puerto` pide la licencia en lugar del hito. Las demás quedan en los 1 000 con que `hitos.md` estimó los días; la
  4x4 en 600 porque no abre zonas.
- De la empresa y para siempre: en un coop de 1 a 8, una licencia por jugador deja varado al resto cuando el
  "habilitado" se va de la sala, y perderla con la quiebra castiga dos veces.
- En `equipment`: la tienda, el save, el snapshot y `GateRequirement` ya la manejan; un campo aparte suma
  versión de esquema y una parte de red sin cambiar nada de lo que se juega.

## Alternativas
- Examen o prueba de manejo para cada licencia: un sistema nuevo por licencia (R3 de la crítica de alcance).
- Licencia por jugador: rompe el coop con gente que entra y sale.
- Campo `CompanyState.licenses`: más limpio de leer, pero duplica lo que `equipment` ya hace.
- Sacar alta montaña y volcánica (el equipo ya cierra esas zonas): el usuario las nombró; quedan, baratas
  frente al equipo.
