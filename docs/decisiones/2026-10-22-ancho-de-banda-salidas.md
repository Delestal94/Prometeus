# 2026-10-22 · Ancho de banda con vehículos afuera: se exige con 4, se informa con 8 (D-2002.2)

**Decisión:** `test_company_bandwidth_budget` falla si con **4 jugadores** una salida afuera pasa 40 KB/s
por cliente o 2 vehículos lejos pasan 64 KB/s (el presupuesto de D-2002 es para 4 peers). Con **8** los dos
casos se miden e imprimen (`over_budget` con culpables) pero no hacen fallar el test hasta D-2002.4.

**Por qué:** con 4 entran con margen en el modelo (35,6 y 50,1) y medidos con ENet (23,1-23,6 y 33,2-33,7).
Con 8 entran medidos con ENet (26,0-30,3 y 38,3-42,7) pero no en el modelo, que pone un datagrama de Steam en
el techo alrededor de cada paquete (46,6 y 66,2). El primer culpable es la camioneta en movimiento, que manda
a ~60 por segundo (intervalo 0,0167). Bajarla a 30/s en el modo Empresa da 37,9 y 53,6 (estimado): entra,
pero cambia cómo se siente el manejo del conductor (predicción N-218) y conviene medir primero con el overlay
cuánto manda de verdad a 60 FPS. Eso es D-2002.4; no frena nada hoy porque el vehículo todavía no se maneja
en el mundo de la empresa (D-0302.2.b.2).

**Supuestos del peor caso:** la salida se mide cerca del galpón (los del galpón también reciben la camioneta
y su carga), con 2 a bordo y 7 cajas; los 2 vehículos lejos van juntos y cada uno a bordo recibe los dos.

**Otras salidas estimadas (no aplicadas):** filtrar jugadores por distancia (2 lejos 58,7), pasajeros a 15/s
(salida 41,6, no alcanza sola), keepalive que no despierte las cajas (−2,5), caja sin `hold_offset` si nadie
la tiene (−2,1).
