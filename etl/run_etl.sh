#!/usr/bin/env bash
# =====================================================================
#  Ejecuta el pipeline completo:  data/raw  ->  MySQL  ->  data/tableau
#
#  Uso (desde cualquier carpeta):
#     MYSQL_PWD=tu_clave ./etl/run_etl.sh
#  Variables: MYSQL_HOST (127.0.0.1) MYSQL_PORT (3306) MYSQL_USER (root)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."            # las rutas de LOAD DATA son relativas a la raíz

export MYSQL_PWD="${MYSQL_PWD:-}"
MYSQL=(mysql -h "${MYSQL_HOST:-127.0.0.1}" -P "${MYSQL_PORT:-3306}" -u "${MYSQL_USER:-root}"
       --default-character-set=utf8mb4 --local-infile=1)

# LOAD DATA LOCAL requiere local_infile=ON en el servidor (MySQL 8 lo trae apagado)
"${MYSQL[@]}" -e "SET GLOBAL local_infile = 1" 2>/dev/null \
  || echo "⚠ No se pudo activar local_infile; si la carga falla, inicia MySQL con --local-infile=1"

inicio_total=$(date +%s)
for f in etl/0*.sql; do
  inicio=$(date +%s)
  printf '▶ %-32s' "$f"
  "${MYSQL[@]}" < "$f" > /dev/null
  printf 'ok (%ss)\n' "$(( $(date +%s) - inicio ))"
done

echo
echo "Reconciliación de ventas_erp.csv:"
"${MYSQL[@]}" -t pos_analytics -e "SELECT * FROM mart_reconciliacion ORDER BY FIELD(estado_carga,'OK','CORREGIDO','DESCARTADO','CUARENTENA')"
echo "Reglas de calidad:"
"${MYSQL[@]}" -t pos_analytics -e "SELECT regla, accion, filas, pct_del_archivo AS pct FROM mart_calidad"

./etl/exportar_tableau.sh
echo "✓ Pipeline completo en $(( $(date +%s) - inicio_total ))s"
