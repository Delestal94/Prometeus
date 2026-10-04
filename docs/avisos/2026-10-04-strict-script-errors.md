# 2026-10-04 · CI marca FAIL un test que sale con 0 tras un SCRIPT ERROR (N-924.2)

`tests.yml` exporta `STRICT_SCRIPT_ERRORS=1` a `tools/run-tests.sh`: un test que imprime un `SCRIPT ERROR` de
ejecución (fuera del ruido conocido) ya no pasa en silencio. Se arreglaron los tres que lo hacían
(`test_hint_relay`, `test_interaction_highlight`, `test_seat_tending`; solo cambian los tests).

Qué cambia para vos: si tu test falla en CI con "SCRIPT ERROR", un chequeo estaba cortado y no corría. En un
`--script`, nombrar una clase que usa un autoload se compila antes que el autoload: usá `load()` en runtime.
