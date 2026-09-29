-- =====================================================================
--  Pruebas del pipeline: reconciliación, calidad, modelo y funciones.
--  Cada prueba registra su resultado en pa_tests.resultados.
--  Ejecutar con tests/run_tests.sh después de etl/run_etl.sh
-- =====================================================================

SET NAMES utf8mb4;
DROP DATABASE IF EXISTS pa_tests;
CREATE DATABASE pa_tests CHARACTER SET utf8mb4;

CREATE TABLE pa_tests.resultados (
  id       INT AUTO_INCREMENT PRIMARY KEY,
  suite    VARCHAR(30)  NOT NULL,
  prueba   VARCHAR(160) NOT NULL,
  ok       BOOLEAN      NOT NULL,
  detalle  VARCHAR(300) NULL
);

DELIMITER $$
CREATE PROCEDURE pa_tests.assert_igual(p_suite VARCHAR(30), p_nombre VARCHAR(160), p_esperado TEXT, p_real TEXT)
BEGIN
  INSERT INTO pa_tests.resultados (suite, prueba, ok, detalle)
  VALUES (p_suite, p_nombre, p_esperado <=> p_real,
          CONCAT('esperado=', COALESCE(p_esperado, 'NULL'), ' · real=', COALESCE(p_real, 'NULL')));
END $$
DELIMITER ;

USE pos_analytics;

-- ---------------------------------------------------------------------
-- Reconciliación: ninguna fila se pierde
-- ---------------------------------------------------------------------
CALL pa_tests.assert_igual('reconciliacion', 'Toda fila de staging tiene su fila tipada',
  (SELECT COUNT(*) FROM stg_ventas), (SELECT COUNT(*) FROM int_ventas));

CALL pa_tests.assert_igual('reconciliacion', 'Toda fila tiene estado de carga',
  '0', (SELECT COUNT(*) FROM int_ventas WHERE estado_carga IS NULL));

CALL pa_tests.assert_igual('reconciliacion', 'fact_ventas = filas OK + CORREGIDO',
  (SELECT COUNT(*) FROM int_ventas WHERE estado_carga IN ('OK','CORREGIDO')),
  (SELECT COUNT(*) FROM fact_ventas));

CALL pa_tests.assert_igual('reconciliacion', 'Cada hecho apunta a una fila válida del archivo (linaje)',
  '0', (SELECT COUNT(*) FROM fact_ventas f
         LEFT JOIN int_ventas i ON i.fila = f.fila_origen AND i.estado_carga IN ('OK','CORREGIDO')
         WHERE i.fila IS NULL));

CALL pa_tests.assert_igual('reconciliacion', 'Venta total: mart_ventas = fact_ventas',
  (SELECT CAST(SUM(venta_neta_mxn) AS CHAR) FROM fact_ventas),
  (SELECT CAST(SUM(venta_neta_mxn) AS CHAR) FROM mart_ventas));

CALL pa_tests.assert_igual('reconciliacion', 'Venta total: mart_margen_mensual = fact_ventas',
  (SELECT CAST(SUM(venta_neta_mxn) AS CHAR) FROM fact_ventas),
  (SELECT CAST(SUM(venta_neta_mxn) AS CHAR) FROM mart_margen_mensual));

CALL pa_tests.assert_igual('reconciliacion', 'Inventario: toda foto del archivo llegó al hecho',
  (SELECT COUNT(*) FROM stg_inventario), (SELECT COUNT(*) FROM fact_inventario_mensual));

CALL pa_tests.assert_igual('reconciliacion', 'Metas: toda meta del archivo llegó al hecho',
  (SELECT COUNT(*) FROM stg_metas), (SELECT COUNT(*) FROM fact_metas));

-- ---------------------------------------------------------------------
-- Calidad: el ETL detecta EXACTAMENTE los defectos inyectados
-- ---------------------------------------------------------------------
CALL pa_tests.assert_igual('calidad', 'R01 duplicados detectados = inyectados',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R01'), (SELECT filas FROM mart_calidad WHERE regla='R01'));
CALL pa_tests.assert_igual('calidad', 'R02 fechas inválidas detectadas = inyectadas',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R02'), (SELECT filas FROM mart_calidad WHERE regla='R02'));
CALL pa_tests.assert_igual('calidad', 'R03 SKU desconocidos detectados = inyectados',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R03'), (SELECT filas FROM mart_calidad WHERE regla='R03'));
CALL pa_tests.assert_igual('calidad', 'R04 SKU anteriores detectados = inyectados',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R04'), (SELECT filas FROM mart_calidad WHERE regla='R04'));
CALL pa_tests.assert_igual('calidad', 'R05 cantidades en cero detectadas = inyectadas',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R05'), (SELECT filas FROM mart_calidad WHERE regla='R05'));
CALL pa_tests.assert_igual('calidad', 'R06 precios faltantes detectados = inyectados',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R06'), (SELECT filas FROM mart_calidad WHERE regla='R06'));
CALL pa_tests.assert_igual('calidad', 'R07 precios atípicos detectados = inyectados',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R07'), (SELECT filas FROM mart_calidad WHERE regla='R07'));
CALL pa_tests.assert_igual('calidad', 'R08 RFC inválidos detectados = inyectados',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R08'), (SELECT filas FROM mart_calidad WHERE regla='R08'));
CALL pa_tests.assert_igual('calidad', 'R09 ventas en USD detectadas = generadas',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R09'), (SELECT filas FROM mart_calidad WHERE regla='R09'));
CALL pa_tests.assert_igual('calidad', 'R10 monedas vacías detectadas = inyectadas',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R10'), (SELECT filas FROM mart_calidad WHERE regla='R10'));

CALL pa_tests.assert_igual('calidad', 'Ninguna fila cargada quedó sin estado, almacén, moneda o vendedor',
  '0', (SELECT COUNT(*) FROM int_ventas WHERE estado_carga IN ('OK','CORREGIDO')
          AND (estado IS NULL OR almacen IS NULL OR moneda IS NULL OR vendedor IS NULL)));

CALL pa_tests.assert_igual('calidad', 'Filas con RFC inválido se asignan a PÚBLICO EN GENERAL',
  (SELECT filas FROM stg_esperado_calidad WHERE regla='R08'),
  (SELECT COUNT(*) FROM fact_ventas f JOIN dim_cliente c USING (cliente_key) WHERE c.rfc = 'XAXX010101000'));

CALL pa_tests.assert_igual('calidad', 'Ventas en USD convertidas con el TC del día',
  '0', (SELECT COUNT(*) FROM int_ventas WHERE moneda = 'USD' AND estado_carga = 'CORREGIDO'
          AND precio_mxn <> ROUND(precio_original * tipo_cambio, 2)));

-- ---------------------------------------------------------------------
-- Modelo dimensional
-- ---------------------------------------------------------------------
CALL pa_tests.assert_igual('modelo', 'SCD2: ningún SKU tiene vigencias traslapadas',
  '0', (SELECT COUNT(*) FROM dim_producto a JOIN dim_producto b
          ON a.sku = b.sku AND a.producto_key < b.producto_key
         AND a.vigente_desde <= b.vigente_hasta AND b.vigente_desde <= a.vigente_hasta));

CALL pa_tests.assert_igual('modelo', 'SCD2: exactamente una versión actual por SKU',
  '0', (SELECT COUNT(*) FROM (SELECT sku FROM dim_producto GROUP BY sku HAVING SUM(es_actual) <> 1) x));

CALL pa_tests.assert_igual('modelo', 'SCD2: ventas previas a abril 2026 usan la versión 1 del costo',
  '0', (SELECT COUNT(*) FROM fact_ventas f JOIN dim_producto p USING (producto_key)
          JOIN dim_fecha d USING (fecha_key) WHERE d.fecha < '2026-04-01' AND p.version <> 1));

CALL pa_tests.assert_igual('modelo', 'SCD2: ventas desde abril 2026 usan la versión 2 del costo',
  '0', (SELECT COUNT(*) FROM fact_ventas f JOIN dim_producto p USING (producto_key)
          JOIN dim_fecha d USING (fecha_key) WHERE d.fecha >= '2026-04-01' AND p.version <> 2));

CALL pa_tests.assert_igual('modelo', 'dim_fecha es continua (sin huecos)',
  (SELECT CAST(DATEDIFF(MAX(fecha), MIN(fecha)) + 1 AS CHAR) FROM dim_fecha),
  (SELECT COUNT(*) FROM dim_fecha));

CALL pa_tests.assert_igual('modelo', 'Tipo de cambio disponible para todos los días',
  '0', (SELECT COUNT(*) FROM int_tipo_cambio WHERE tc IS NULL));

CALL pa_tests.assert_igual('modelo', 'margen = venta neta - costo en cada línea',
  '0', (SELECT COUNT(*) FROM fact_ventas WHERE margen_mxn <> venta_neta_mxn - costo_total_mxn));

CALL pa_tests.assert_igual('modelo', 'venta neta = venta bruta - descuento en cada línea',
  '0', (SELECT COUNT(*) FROM fact_ventas WHERE venta_neta_mxn <> venta_bruta_mxn - descuento_mxn));

CALL pa_tests.assert_igual('modelo', 'Notas de crédito tienen cantidad negativa',
  '0', (SELECT COUNT(*) FROM fact_ventas
         WHERE (tipo_documento = 'NOTA DE CRÉDITO') <> (cantidad < 0)));

CALL pa_tests.assert_igual('modelo', 'Un solo registro por RFC en dim_cliente',
  '0', (SELECT COUNT(*) - COUNT(DISTINCT rfc) FROM dim_cliente));

-- ---------------------------------------------------------------------
-- Funciones de limpieza (pruebas unitarias)
-- ---------------------------------------------------------------------
CALL pa_tests.assert_igual('funciones', "fn_parse_fecha('2026-03-05')",  '2026-03-05', fn_parse_fecha('2026-03-05'));
CALL pa_tests.assert_igual('funciones', "fn_parse_fecha('05/03/2026')",  '2026-03-05', fn_parse_fecha('05/03/2026'));
CALL pa_tests.assert_igual('funciones', "fn_parse_fecha('5-mar-2026')",  '2026-03-05', fn_parse_fecha('5-mar-2026'));
CALL pa_tests.assert_igual('funciones', "fn_parse_fecha('31/02/2026') es NULL", NULL, fn_parse_fecha('31/02/2026'));
CALL pa_tests.assert_igual('funciones', "fn_parse_fecha('2026-02-29') es NULL (no bisiesto)", NULL, fn_parse_fecha('2026-02-29'));
CALL pa_tests.assert_igual('funciones', "fn_parse_fecha('29/02/2024') válido (bisiesto)", '2024-02-29', fn_parse_fecha('29/02/2024'));
CALL pa_tests.assert_igual('funciones', "fn_parse_fecha('sin fecha') es NULL", NULL, fn_parse_fecha('sin fecha'));
CALL pa_tests.assert_igual('funciones', "fn_limpiar_monto('$5,900.00')", '5900.00', fn_limpiar_monto('$5,900.00'));
CALL pa_tests.assert_igual('funciones', "fn_limpiar_monto(' 5900 ')",    '5900.00', fn_limpiar_monto(' 5900 '));
CALL pa_tests.assert_igual('funciones', "fn_limpiar_monto('N/D') es NULL", NULL, fn_limpiar_monto('N/D'));
CALL pa_tests.assert_igual('funciones', "fn_decimal_coma('1.234,56')",   '1234.56', fn_decimal_coma('1.234,56'));
CALL pa_tests.assert_igual('funciones', "fn_parse_descuento('0.10') = 10 %", '10.00', fn_parse_descuento('0.10'));
CALL pa_tests.assert_igual('funciones', "fn_parse_descuento('15%') = 15 %",  '15.00', fn_parse_descuento('15%'));
CALL pa_tests.assert_igual('funciones', "fn_parse_descuento('') = 0",        '0.00',  fn_parse_descuento(''));
CALL pa_tests.assert_igual('funciones', "fn_normalizar_rfc(' abc-910718-c29 ')", 'ABC910718C29', fn_normalizar_rfc(' abc-910718-c29 '));
CALL pa_tests.assert_igual('funciones', "fn_rfc_valido('XAXX010101000')", '1', fn_rfc_valido('XAXX010101000'));
CALL pa_tests.assert_igual('funciones', "fn_rfc_valido('12345') es falso", '0', fn_rfc_valido('12345'));
