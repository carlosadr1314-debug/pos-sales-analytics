-- =====================================================================
--  pos-sales-analytics · analysis/analisis.sql
--  Preguntas de negocio que responde el data warehouse. Los hallazgos
--  están resumidos en docs/insights.md.
-- =====================================================================

USE pos_analytics;

-- A1) Crecimiento: 1-ene al día de corte de 2026 vs. mismo periodo de 2025
SELECT d.anio,
       ROUND(SUM(f.venta_neta_mxn) / 1e6, 1)                           AS venta_mdp,
       ROUND(100 * SUM(f.margen_mxn) / SUM(f.venta_neta_mxn), 1)       AS margen_pct,
       COUNT(DISTINCT IF(f.tipo_documento = 'FACTURA', f.folio, NULL)) AS facturas
FROM fact_ventas f JOIN dim_fecha d USING (fecha_key)
WHERE d.anio IN (2025, 2026)
  AND DAYOFYEAR(d.fecha) <= (SELECT DAYOFYEAR(MAX(fecha)) FROM dim_fecha JOIN fact_ventas USING (fecha_key))
GROUP BY d.anio;

-- A2) Estacionalidad: índice de cada mes vs. el promedio mensual de 2025
SELECT d.mes, d.nombre_mes,
       ROUND(SUM(f.venta_neta_mxn) / (SELECT SUM(venta_neta_mxn) / 12 FROM mart_ventas WHERE anio = 2025), 2) AS indice
FROM fact_ventas f JOIN dim_fecha d USING (fecha_key)
WHERE d.anio = 2025
GROUP BY d.mes, d.nombre_mes ORDER BY d.mes;

-- A3) Margen de marcas con costo en USD vs. MXN, por trimestre, contra el tipo de cambio
SELECT CONCAT(d.anio, '-', d.trimestre) AS periodo, p.moneda_costo,
       ROUND(100 * SUM(f.margen_mxn) / SUM(f.venta_neta_mxn), 1) AS margen_pct,
       ROUND(AVG(f.tipo_cambio), 2) AS tc_promedio
FROM fact_ventas f
JOIN dim_fecha d USING (fecha_key) JOIN dim_producto p USING (producto_key)
GROUP BY periodo, p.moneda_costo ORDER BY periodo, p.moneda_costo;

-- A4) Margen de SUNMI antes y después de la lista de precios de abril 2026
SELECT p.marca, IF(d.fecha < '2026-04-01', 'Ene-Mar 2026', 'Abr-Sep 2026') AS periodo,
       ROUND(100 * SUM(f.margen_mxn) / SUM(f.venta_neta_mxn), 1) AS margen_pct,
       ROUND(AVG(f.tipo_cambio), 2) AS tc_promedio
FROM fact_ventas f
JOIN dim_fecha d USING (fecha_key) JOIN dim_producto p USING (producto_key)
WHERE d.anio = 2026
GROUP BY p.marca, periodo ORDER BY p.marca, periodo DESC;

-- A5) Cumplimiento de metas 2026 por marca (meses cerrados)
SELECT marca, ROUND(SUM(venta_real_mxn) / 1e6, 1) AS real_mdp, ROUND(SUM(meta_mxn) / 1e6, 1) AS meta_mdp,
       ROUND(100 * SUM(venta_real_mxn) / SUM(meta_mxn), 1) AS avance_pct
FROM mart_metas
WHERE anio_mes BETWEEN '2026-01' AND '2026-08'
GROUP BY marca ORDER BY avance_pct;

-- A6) Descuento promedio ponderado por vendedor y su efecto en el margen
SELECT v.nombre AS vendedor,
       ROUND(100 * SUM(f.descuento_mxn) / SUM(f.venta_bruta_mxn), 1) AS descuento_pct,
       ROUND(100 * SUM(f.margen_mxn) / SUM(f.venta_neta_mxn), 1)     AS margen_pct,
       ROUND(SUM(f.venta_neta_mxn) / 1e6, 1)                          AS venta_mdp
FROM fact_ventas f JOIN dim_vendedor v USING (vendedor_key)
WHERE f.tipo_documento = 'FACTURA'
GROUP BY v.nombre ORDER BY descuento_pct DESC;

-- A7) Tasa de devolución por producto (unidades devueltas / vendidas)
SELECT p.sku, p.marca,
       SUM(IF(f.cantidad > 0, f.cantidad, 0))  AS vendidas,
       -SUM(IF(f.cantidad < 0, f.cantidad, 0)) AS devueltas,
       ROUND(100 * -SUM(IF(f.cantidad < 0, f.cantidad, 0)) / SUM(IF(f.cantidad > 0, f.cantidad, 0)), 1) AS tasa_pct
FROM fact_ventas f JOIN dim_producto p USING (producto_key)
GROUP BY p.sku, p.marca
HAVING vendidas >= 100
ORDER BY tasa_pct DESC LIMIT 5;

-- A8) Días de inventario por marca y almacén (agosto 2026) y dinero inmovilizado
SELECT marca, almacen,
       ROUND(SUM(valor_inventario_mxn) / 1e6, 2) AS inventario_mdp,
       ROUND(SUM(valor_inventario_mxn) / NULLIF(SUM(costo_venta_3m) / 91, 0), 0) AS dias_inventario
FROM mart_inventario
WHERE anio_mes = '2026-08'
GROUP BY marca, almacen
ORDER BY dias_inventario DESC LIMIT 6;

-- A9) Concentración de clientes (Pareto)
WITH por_cliente AS (
  SELECT c.rfc, SUM(f.venta_neta_mxn) AS venta
  FROM fact_ventas f JOIN dim_cliente c USING (cliente_key)
  WHERE c.rfc <> 'XAXX010101000'
  GROUP BY c.rfc
),
ranking AS (
  SELECT venta,
         ROW_NUMBER() OVER (ORDER BY venta DESC) AS lugar,
         COUNT(*) OVER () AS total,
         SUM(venta) OVER (ORDER BY venta DESC) / SUM(venta) OVER () AS acumulado
  FROM por_cliente
)
SELECT total AS clientes,
       ROUND(100 * MAX(IF(lugar <= total * 0.2, acumulado, 0)), 1) AS pct_venta_top20pct_clientes,
       MIN(IF(acumulado >= 0.8, lugar, NULL)) AS clientes_para_80pct
FROM ranking GROUP BY total;

-- A10) Venta y margen por categoría (últimos 12 meses)
SELECT p.categoria,
       ROUND(SUM(f.venta_neta_mxn) / 1e6, 1) AS venta_mdp,
       ROUND(100 * SUM(f.venta_neta_mxn) / SUM(SUM(f.venta_neta_mxn)) OVER (), 1) AS participacion_pct,
       ROUND(100 * SUM(f.margen_mxn) / SUM(f.venta_neta_mxn), 1) AS margen_pct
FROM fact_ventas f
JOIN dim_fecha d USING (fecha_key) JOIN dim_producto p USING (producto_key)
WHERE d.fecha > (SELECT MAX(fecha) FROM mart_ventas) - INTERVAL 12 MONTH
GROUP BY p.categoria ORDER BY venta_mdp DESC;
