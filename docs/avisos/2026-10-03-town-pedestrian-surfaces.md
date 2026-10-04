# N-950: aceras físicas y entradas a parques/plazas

`town_prototype.gd` conecta el nuevo plan peatonal portable a una malla
agrupada con colisión. Las aceras siguen diagonales y cruces con rampas;
reemplazan los accesos asfaltados de los lotes. Depósito/taller tienen suelo
físico en su patio. Césped y centro pavimentado de áreas verdes reciben
colisión y rampas, con caminos de entrada y árboles/mobiliario apartados.

Se amplían `test_town_prototype`, `test_town_delivery` y las capturas del
Centro. El controlador real cruza desde asfalto por una acera al acceso sin
saltar; los tests verifican apoyo continuo en entradas verdes. No cambia
el código del jugador, timbres, pedidos ni RPC/protocolo. La escena mantiene
su alcance offline y los dos distritos abiertos. Actualizar antes de seguir
con el adaptador del pueblo. Detalles y límites en `docs/mapa-pueblo.md`.
