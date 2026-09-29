-- =====================================================================
--  pos-sales-analytics · etl/05_modelo_estrella.sql
--  TRANSFORM (2/2) + LOAD: modelo dimensional (esquema estrella).
--
--    dim_fecha  dim_producto (SCD tipo 2)  dim_cliente  dim_almacen  dim_vendedor
--                          \      |      /
--                    fact_ventas (grano: línea de documento)
--    fact_inventario_mensual (grano: sku × almacén × fin de mes)
--    fact_metas              (grano: marca × mes)
--
--  Solo entran filas con estado_carga OK o CORREGIDO.
-- =====================================================================

SET NAMES utf8mb4;
USE pos_analytics;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS fact_ventas, fact_inventario_mensual, fact_metas,
                     dim_fecha, dim_producto, dim_cliente, dim_almacen, dim_vendedor;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- dim_fecha: calendario completo (también días sin ventas)
-- ---------------------------------------------------------------------
CREATE TABLE dim_fecha (
  fecha_key      INT PRIMARY KEY COMMENT 'AAAAMMDD',
  fecha          DATE NOT NULL UNIQUE,
  anio           SMALLINT NOT NULL,
  trimestre      CHAR(2)  NOT NULL,
  mes            TINYINT  NOT NULL,
  nombre_mes     VARCHAR(12) NOT NULL,
  anio_mes       CHAR(7)  NOT NULL,
  semana_iso     TINYINT  NOT NULL,
  dia_semana     VARCHAR(10) NOT NULL,
  es_fin_semana  BOOLEAN  NOT NULL,
  temporada      VARCHAR(12) NOT NULL
) ENGINE=InnoDB;

SET SESSION cte_max_recursion_depth = 5000;

INSERT INTO dim_fecha
WITH RECURSIVE d AS (
  SELECT DATE '2024-01-01' AS f
  UNION ALL SELECT f + INTERVAL 1 DAY FROM d WHERE f < '2026-12-31'
)
SELECT CAST(DATE_FORMAT(f, '%Y%m%d') AS UNSIGNED),
       f, YEAR(f), CONCAT('T', QUARTER(f)), MONTH(f), m.nombre,
       DATE_FORMAT(f, '%Y-%m'), WEEK(f, 3),
       ELT(DAYOFWEEK(f), 'Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'),
       DAYOFWEEK(f) IN (1, 7),
       CASE WHEN MONTH(f) IN (11, 12) THEN 'Alta' WHEN MONTH(f) IN (1, 2) THEN 'Baja' ELSE 'Regular' END
FROM d
JOIN ref_mes_es m ON m.num = MONTH(f);

-- ---------------------------------------------------------------------
-- dim_producto como SCD tipo 2: una fila por VERSIÓN del producto.
-- Cuando cambia el costo o el precio de lista, se crea una nueva fila
-- con su vigencia. Así cada venta usa el costo que tenía EN SU FECHA
-- y el margen histórico no se reescribe.
-- ---------------------------------------------------------------------
CREATE TABLE dim_producto (
  producto_key   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  sku            VARCHAR(40)  NOT NULL,
  marca          VARCHAR(40)  NOT NULL,
  descripcion    VARCHAR(200) NOT NULL,
  categoria      VARCHAR(60)  NOT NULL,
  subcategoria   VARCHAR(60)  NOT NULL,
  moneda_costo   CHAR(3)      NOT NULL,
  costo_origen   DECIMAL(12,2) NOT NULL,
  precio_lista   DECIMAL(12,2) NOT NULL,
  vigente_desde  DATE NOT NULL,
  vigente_hasta  DATE NOT NULL,
  version        TINYINT NOT NULL,
  es_actual      BOOLEAN NOT NULL,
  UNIQUE KEY uq_producto_version (sku, vigente_desde)
) ENGINE=InnoDB;

INSERT INTO dim_producto (sku, marca, descripcion, categoria, subcategoria, moneda_costo,
                          costo_origen, precio_lista, vigente_desde, vigente_hasta, version, es_actual)
SELECT sku, marca, descripcion, categoria, subcategoria, moneda_costo,
       costo_origen, precio_lista, vigente_desde, vigente_hasta, version,
       vigente_hasta = '9999-12-31'
FROM int_catalogo
ORDER BY sku, vigente_desde;

-- ---------------------------------------------------------------------
-- dim_cliente: un registro por RFC. Nombre: la variante más frecuente
-- que no esté toda en mayúsculas. Estado: el de su compra más reciente.
-- ---------------------------------------------------------------------
CREATE TABLE dim_cliente (
  cliente_key    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  rfc            VARCHAR(13)  NOT NULL UNIQUE,
  razon_social   VARCHAR(200) NOT NULL,
  estado         VARCHAR(60)  NOT NULL,
  region         VARCHAR(20)  NOT NULL,
  primera_compra DATE NULL
) ENGINE=InnoDB;

INSERT INTO dim_cliente (rfc, razon_social, estado, region, primera_compra)
WITH cargadas AS (
  SELECT * FROM int_ventas WHERE estado_carga IN ('OK', 'CORREGIDO')
),
nombres AS (
  SELECT rfc, cliente,
         ROW_NUMBER() OVER (PARTITION BY rfc
                            ORDER BY BINARY cliente = BINARY UPPER(cliente), COUNT(*) DESC) AS rn
  FROM cargadas GROUP BY rfc, cliente
),
ubicacion AS (
  SELECT rfc, estado, region,
         ROW_NUMBER() OVER (PARTITION BY rfc ORDER BY fecha DESC, fila DESC) AS rn
  FROM cargadas
)
SELECT n.rfc, n.cliente,
       IF(n.rfc = 'XAXX010101000', 'Varios', u.estado),
       IF(n.rfc = 'XAXX010101000', 'Varios', u.region),
       (SELECT MIN(fecha) FROM cargadas c WHERE c.rfc = n.rfc AND c.cantidad > 0)
FROM nombres n
JOIN ubicacion u ON u.rfc = n.rfc AND u.rn = 1
WHERE n.rn = 1;

CREATE TABLE dim_almacen (
  almacen_key  TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo       CHAR(4) NOT NULL UNIQUE,
  nombre       VARCHAR(60) NOT NULL,
  ciudad       VARCHAR(60) NOT NULL
) ENGINE=InnoDB;

INSERT INTO dim_almacen (codigo, nombre, ciudad) SELECT codigo, nombre, ciudad FROM ref_almacen;

-- La collation _ai_ci ya agrupa 'LUIS MÉNDEZ' con 'Luis Méndez'
CREATE TABLE dim_vendedor (
  vendedor_key  TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre        VARCHAR(80) NOT NULL UNIQUE
) ENGINE=InnoDB;

INSERT INTO dim_vendedor (nombre)
SELECT MAX(IF(BINARY vendedor <> BINARY UPPER(vendedor), vendedor, NULL))
FROM int_ventas
WHERE estado_carga IN ('OK', 'CORREGIDO')
GROUP BY vendedor
ORDER BY 1;

-- ---------------------------------------------------------------------
-- fact_ventas
-- ---------------------------------------------------------------------
CREATE TABLE fact_ventas (
  venta_key          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fecha_key          INT NOT NULL,
  producto_key       INT UNSIGNED NOT NULL,
  cliente_key        INT UNSIGNED NOT NULL,
  almacen_key        TINYINT UNSIGNED NOT NULL,
  vendedor_key       TINYINT UNSIGNED NOT NULL,
  folio              VARCHAR(30) NOT NULL,
  linea              SMALLINT NOT NULL,
  tipo_documento     ENUM('FACTURA','NOTA DE CRÉDITO') NOT NULL,
  cantidad           INT NOT NULL COMMENT 'negativa en notas de crédito',
  precio_unitario_mxn DECIMAL(14,2) NOT NULL,
  descuento_pct      DECIMAL(5,2)  NOT NULL,
  venta_bruta_mxn    DECIMAL(16,2) NOT NULL,
  descuento_mxn      DECIMAL(16,2) NOT NULL,
  venta_neta_mxn     DECIMAL(16,2) NOT NULL,
  costo_unitario_mxn DECIMAL(14,2) NOT NULL,
  costo_total_mxn    DECIMAL(16,2) NOT NULL,
  margen_mxn         DECIMAL(16,2) NOT NULL,
  moneda_original    CHAR(3) NOT NULL,
  tipo_cambio        DECIMAL(10,4) NOT NULL COMMENT 'TC del día (costo USD y ventas USD)',
  fila_origen        INT UNSIGNED NOT NULL COMMENT 'línea de ventas_erp.csv (linaje)',
  fue_corregida      BOOLEAN NOT NULL,
  UNIQUE KEY uq_fact_documento (folio, linea),
  CONSTRAINT fk_fv_fecha    FOREIGN KEY (fecha_key)    REFERENCES dim_fecha (fecha_key),
  CONSTRAINT fk_fv_producto FOREIGN KEY (producto_key) REFERENCES dim_producto (producto_key),
  CONSTRAINT fk_fv_cliente  FOREIGN KEY (cliente_key)  REFERENCES dim_cliente (cliente_key),
  CONSTRAINT fk_fv_almacen  FOREIGN KEY (almacen_key)  REFERENCES dim_almacen (almacen_key),
  CONSTRAINT fk_fv_vendedor FOREIGN KEY (vendedor_key) REFERENCES dim_vendedor (vendedor_key)
) ENGINE=InnoDB;

-- Estadísticas frescas + STRAIGHT_JOIN: forzamos que el optimizador recorra
-- int_ventas una sola vez y busque cada dimensión por su índice. Sin esto,
-- con tablas recién creadas puede elegir un plan que tarda minutos.
ANALYZE TABLE int_ventas, int_tipo_cambio, dim_fecha, dim_producto, dim_cliente, dim_almacen, dim_vendedor;

INSERT INTO fact_ventas (fecha_key, producto_key, cliente_key, almacen_key, vendedor_key,
  folio, linea, tipo_documento, cantidad, precio_unitario_mxn, descuento_pct,
  venta_bruta_mxn, descuento_mxn, venta_neta_mxn, costo_unitario_mxn, costo_total_mxn,
  margen_mxn, moneda_original, tipo_cambio, fila_origen, fue_corregida)
SELECT STRAIGHT_JOIN
       f.fecha_key, p.producto_key, c.cliente_key, a.almacen_key, v.vendedor_key,
       i.folio, i.linea,
       IF(i.folio LIKE 'NC-%', 'NOTA DE CRÉDITO', 'FACTURA'),
       i.cantidad,
       i.precio_mxn,
       i.descuento_pct,
       x.bruta,
       x.bruta - x.neta,
       x.neta,
       x.costo_u,
       ROUND(i.cantidad * x.costo_u, 2),
       x.neta - ROUND(i.cantidad * x.costo_u, 2),
       i.moneda,
       tc.tc,
       i.fila,
       i.estado_carga = 'CORREGIDO'
FROM int_ventas i
JOIN dim_fecha f        ON f.fecha = i.fecha
JOIN dim_producto p     ON p.sku = i.sku AND i.fecha BETWEEN p.vigente_desde AND p.vigente_hasta
JOIN dim_cliente c      ON c.rfc = i.rfc
JOIN dim_almacen a      ON a.codigo = i.almacen
JOIN dim_vendedor v     ON v.nombre = i.vendedor
JOIN int_tipo_cambio tc ON tc.fecha = i.fecha
CROSS JOIN LATERAL (
  SELECT ROUND(i.cantidad * i.precio_mxn, 2)                                AS bruta,
         ROUND(i.cantidad * i.precio_mxn * (1 - i.descuento_pct / 100), 2)  AS neta,
         ROUND(p.costo_origen * IF(p.moneda_costo = 'USD', tc.tc, 1), 2)    AS costo_u
) x
WHERE i.estado_carga IN ('OK', 'CORREGIDO');

-- ---------------------------------------------------------------------
-- fact_inventario_mensual (foto de existencias a fin de mes)
-- ---------------------------------------------------------------------
CREATE TABLE fact_inventario_mensual (
  fecha_key           INT NOT NULL,
  producto_key        INT UNSIGNED NOT NULL,
  almacen_key         TINYINT UNSIGNED NOT NULL,
  existencia          INT NOT NULL,
  costo_unitario_mxn  DECIMAL(14,2) NOT NULL,
  valor_inventario_mxn DECIMAL(16,2) NOT NULL,
  PRIMARY KEY (fecha_key, producto_key, almacen_key),
  FOREIGN KEY (fecha_key)    REFERENCES dim_fecha (fecha_key),
  FOREIGN KEY (producto_key) REFERENCES dim_producto (producto_key),
  FOREIGN KEY (almacen_key)  REFERENCES dim_almacen (almacen_key)
) ENGINE=InnoDB;

INSERT INTO fact_inventario_mensual
SELECT STRAIGHT_JOIN f.fecha_key, p.producto_key, a.almacen_key, x.existencia, x.costo_u,
       ROUND(x.existencia * x.costo_u, 2)
FROM stg_inventario s
JOIN dim_fecha f        ON f.fecha = LAST_DAY(CONCAT(s.mes, '-01'))
JOIN dim_producto p     ON p.sku = UPPER(TRIM(s.sku)) AND f.fecha BETWEEN p.vigente_desde AND p.vigente_hasta
JOIN dim_almacen a      ON a.codigo = TRIM(s.almacen)
JOIN int_tipo_cambio tc ON tc.fecha = f.fecha
CROSS JOIN LATERAL (
  SELECT CAST(s.existencia AS SIGNED) AS existencia,
         ROUND(p.costo_origen * IF(p.moneda_costo = 'USD', tc.tc, 1), 2) AS costo_u
) x;

-- ---------------------------------------------------------------------
-- fact_metas
-- ---------------------------------------------------------------------
CREATE TABLE fact_metas (
  fecha_key  INT NOT NULL COMMENT 'primer día del mes',
  marca      VARCHAR(40) NOT NULL,
  meta_mxn   DECIMAL(16,2) NOT NULL,
  PRIMARY KEY (fecha_key, marca),
  FOREIGN KEY (fecha_key) REFERENCES dim_fecha (fecha_key)
) ENGINE=InnoDB;

INSERT INTO fact_metas
SELECT CAST(REPLACE(CONCAT(TRIM(mes), '-01'), '-', '') AS UNSIGNED), TRIM(marca),
       CAST(meta_mxn AS DECIMAL(16,2))
FROM stg_metas;
