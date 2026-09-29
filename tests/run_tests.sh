#!/usr/bin/env bash
# Ejecuta tests/validaciones.sql y falla (exit 1) si alguna prueba no pasa.
# Requiere haber corrido antes ./etl/run_etl.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export MYSQL_PWD="${MYSQL_PWD:-}"
MYSQL=(mysql -h "${MYSQL_HOST:-127.0.0.1}" -P "${MYSQL_PORT:-3306}" -u "${MYSQL_USER:-root}"
       --default-character-set=utf8mb4)

"${MYSQL[@]}" < tests/validaciones.sql

"${MYSQL[@]}" -t pa_tests -e "
  SELECT suite, SUM(ok) AS aprobadas, SUM(NOT ok) AS fallidas, COUNT(*) AS total
    FROM resultados GROUP BY suite ORDER BY MIN(id);"

FALLIDAS=$("${MYSQL[@]}" -N pa_tests -e "SELECT COUNT(*) FROM resultados WHERE NOT ok")
TOTAL=$("${MYSQL[@]}" -N pa_tests -e "SELECT COUNT(*) FROM resultados")

if [ "$FALLIDAS" -gt 0 ]; then
  echo "✗ $FALLIDAS de $TOTAL pruebas fallaron:"
  "${MYSQL[@]}" -t pa_tests -e "SELECT suite, prueba, detalle FROM resultados WHERE NOT ok"
  exit 1
fi
echo "✓ $TOTAL pruebas aprobadas"
