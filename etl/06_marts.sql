-- =====================================================================
--  pos-sales-analytics · etl/06_marts.sql
--  Capa de consumo: vistas planas ("marts") que se exportan a CSV para
--  Tableau. Tableau trabaja mejor con tablas anchas y ya unidas; toda
--  la lógica de negocio queda aquí, en SQL versionado, y no escondida
--  en campos calculados del dashboard.
-- =====================================================================

SET NAMES utf8mb4;
USE pos_analytics;

-- 1) Ventas a nivel línea con todas sus dimensiones ---------------------
CREATE OR REPLACE VIEW mart_ventas AS
SELECT d.fecha, d.anio, d.trimestre, d.mes, d.nombre_mes, d.anio_mes, d.dia_semana, d.temporada,
       f.folio, f.tipo_documento,
       p.sku, p.descripcion AS producto, p.marca, p.categoria, p.subcategoria, p.moneda_costo,
       c.rfc, c.razon_social AS cliente, c.estado, c.region,
       a.nombre AS almacen, v.nombre AS vendedor,
       f.cantidad, f.precio_unitario_mxn, f.descuento_pct,
       f.venta_bruta_mxn, f.descuento_mxn, f.venta_neta_mxn,
       f.costo_total_mxn, f.margen_mxn,
       f.moneda_original, f.tipo_cambio, f.fue_corregida
FROM fact_ventas f
JOIN dim_fecha d    USING (fecha_key)
JOIN dim_producto p USING (producto_key)
JOIN dim_cliente c  USING (cliente_key)
JOIN dim_almacen a  USING (almacen_key)
JOIN dim_vendedor v USING (vendedor_key);

-- 2) Margen mensual por marca vs. tipo de cambio ------------------------
CREATE OR REPLACE VIEW mart_margen_mensual AS
SELECT d.anio_mes, p.marca, p.categoria, p.moneda_costo,
       SUM(f.venta_neta_mxn)  AS venta_neta_mxn,
       SUM(f.costo_total_mxn) AS costo_mxn,
       SUM(f.margen_mxn)      AS margen_mxn,
       ROUND(100 * SUM(f.margen_mxn) / NULLIF(SUM(f.venta_neta_mxn), 0), 2) AS margen_pct,
       (SELECT ROUND(AVG(t.tc), 4) FROM int_tipo_cambio t
         WHERE DATE_FORMAT(t.fecha, '%Y-%m') = d.anio_mes AND t.es_publicado) AS tc_promedio_mes
FROM fact_ventas f
JOIN dim_fecha d    USING (fecha_key)
JOIN dim_producto p USING (producto_key)
GROUP BY d.anio_mes, p.marca, p.categoria, p.moneda_costo;

-- 3) Inventario: valor, días de inventario y rotación -------------------
--    días de inventario = valor del inventario / costo de venta diario
--    promedio de los últimos 3 meses (incluye el mes de la foto)
CREATE OR REPLACE VIEW mart_inventario AS
WITH costo_mensual AS (
  SELECT p.sku, f.almacen_key, d.anio, d.mes, SUM(f.costo_total_mxn) AS costo
  FROM fact_ventas f
  JOIN dim_fecha d    USING (fecha_key)
  JOIN dim_producto p USING (producto_key)
  GROUP BY p.sku, f.almacen_key, d.anio, d.mes
),
inventario AS (
  SELECT d.fecha, d.anio_mes, d.anio, d.mes, p.sku, p.marca, p.categoria, a.almacen_key,
         a.nombre AS almacen, i.existencia, i.valor_inventario_mxn,
         (SELECT COALESCE(SUM(cm.costo), 0) FROM costo_mensual cm
           WHERE cm.sku = p.sku AND cm.almacen_key = i.almacen_key
             AND (cm.anio * 12 + cm.mes) BETWEEN (d.anio * 12 + d.mes - 2) AND (d.anio * 12 + d.mes)
         ) AS costo_venta_3m
  FROM fact_inventario_mensual i
  JOIN dim_fecha d    USING (fecha_key)
  JOIN dim_producto p USING (producto_key)
  JOIN dim_almacen a  USING (almacen_key)
)
SELECT fecha AS fecha_corte, anio_mes, sku, marca, categoria, almacen,
       existencia, valor_inventario_mxn, costo_venta_3m,
       ROUND(valor_inventario_mxn / NULLIF(costo_venta_3m / 91, 0), 1) AS dias_inventario,
       ROUND((costo_venta_3m * 4) / NULLIF(valor_inventario_mxn, 0), 2) AS rotacion_anual
FROM inventario;

-- 4) Venta real vs. meta por marca y mes --------------------------------
CREATE OR REPLACE VIEW mart_metas AS
SELECT d.anio_mes, m.marca, m.meta_mxn,
       COALESCE(r.venta_neta_mxn, 0) AS venta_real_mxn,
       ROUND(100 * COALESCE(r.venta_neta_mxn, 0) / m.meta_mxn, 1) AS avance_pct,
       d.anio_mes = (SELECT MAX(anio_mes) FROM dim_fecha df
                      JOIN fact_ventas fv ON fv.fecha_key = df.fecha_key) AS mes_en_curso
FROM fact_metas m
JOIN dim_fecha d USING (fecha_key)
LEFT JOIN (
  SELECT d2.anio_mes, p.marca, SUM(f.venta_neta_mxn) AS venta_neta_mxn
  FROM fact_ventas f
  JOIN dim_fecha d2   USING (fecha_key)
  JOIN dim_producto p USING (producto_key)
  GROUP BY d2.anio_mes, p.marca
) r ON r.anio_mes = d.anio_mes AND r.marca = m.marca;

-- 5) Calidad de datos: resultado de cada regla --------------------------
CREATE OR REPLACE VIEW mart_calidad AS
SELECT r.regla, r.descripcion, r.accion,
       COUNT(d.id) AS filas,
       ROUND(100 * COUNT(d.id) / (SELECT COUNT(*) FROM stg_ventas), 2) AS pct_del_archivo
FROM dq_reglas r
LEFT JOIN dq_incidencias d USING (regla)
GROUP BY r.regla, r.descripcion, r.accion, r.prioridad
ORDER BY r.prioridad;

-- 6) Reconciliación: a dónde fue cada fila del archivo ------------------
CREATE OR REPLACE VIEW mart_reconciliacion AS
SELECT estado_carga,
       COUNT(*) AS filas,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM stg_ventas), 2) AS pct
FROM int_ventas
GROUP BY estado_carga;

-- 7) Tipo de cambio diario (para graficar contra el margen) -------------
CREATE OR REPLACE VIEW mart_tipo_cambio AS
SELECT fecha, tc AS tc_usd_mxn, es_publicado FROM int_tipo_cambio;
