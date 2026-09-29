#!/usr/bin/env bash
# =====================================================================
#  Exporta cada vista mart_* a data/tableau/<nombre>.csv (UTF-8, coma,
#  comillas solo donde hace falta). Son las fuentes del dashboard.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

export MYSQL_PWD="${MYSQL_PWD:-}"
MYSQL=(mysql -h "${MYSQL_HOST:-127.0.0.1}" -P "${MYSQL_PORT:-3306}" -u "${MYSQL_USER:-root}"
       --default-character-set=utf8mb4 -B pos_analytics)

mkdir -p data/tableau

# mysql -B entrega columnas separadas por tabulador; awk las convierte en
# CSV válido: NULL -> vacío y comillas en campos con coma o comillas.
a_csv() {
  awk -F'\t' 'BEGIN { OFS = "," }
    {
      $1 = $1                      # fuerza a reconstruir la línea con OFS=","
      for (i = 1; i <= NF; i++) {
        if ($i == "NULL") $i = ""
        if ($i ~ /[,"]/) { gsub(/"/, "\"\"", $i); $i = "\"" $i "\"" }
      }
      print
    }'
}

echo
echo "Exportando marts para Tableau:"
# Orden fijo = archivos idénticos en cada corrida (diffs limpios en git).
# Se usa una función y no un arreglo asociativo para que funcione con
# el bash 3.2 que trae macOS.
orden_de() {
  case "$1" in
    mart_ventas)         echo "fecha, folio, sku" ;;
    mart_margen_mensual) echo "anio_mes, marca, categoria" ;;
    mart_inventario)     echo "fecha_corte, sku, almacen" ;;
    mart_metas)          echo "anio_mes, marca" ;;
    mart_calidad)        echo "regla" ;;
    mart_reconciliacion) echo "estado_carga" ;;
    mart_tipo_cambio)    echo "fecha" ;;
  esac
}

for vista in mart_ventas mart_margen_mensual mart_inventario mart_metas \
             mart_calidad mart_reconciliacion mart_tipo_cambio; do
  archivo="data/tableau/${vista#mart_}.csv"
  "${MYSQL[@]}" -e "SELECT * FROM $vista ORDER BY $(orden_de "$vista")" | a_csv > "$archivo"
  printf '  %-36s %8s filas\n' "$archivo" "$(( $(wc -l < "$archivo") - 1 ))"
done
