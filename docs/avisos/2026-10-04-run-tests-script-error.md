# 2026-10-04 · run-tests.sh lista los tests que pasan con SCRIPT ERROR (N-924.2)

Tooling común: `tools/run-tests.sh` ahora avisa, después del resumen, de los tests que salieron con código 0 pero
imprimieron un `SCRIPT ERROR` de ejecución (línea "pasaron con SCRIPT ERROR"). No cambia el resultado: sigue en PASS.
Con `STRICT_SCRIPT_ERRORS=1` esos tests cuentan como FAIL. Cuando aparezca esa línea en un run de CI, es un test
que no está probando lo que dice (como `test_net_session_rejoin` antes de N-924.1): arreglalo o avisá.
