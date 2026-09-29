-- =====================================================================
--  pos-sales-analytics · etl/04_limpieza_calidad.sql
--  TRANSFORM (1/2): tipado, normalización y reglas de calidad.
--
--  Resultado:
--    int_catalogo      catálogo tipado con vigencia por versión
--    int_tipo_cambio   un tipo de cambio para CADA día (fines de semana
--                      toman el último día hábil)
--    int_ventas        cada fila de stg_ventas, ya tipada, con su
--                      estado_carga: OK | CORREGIDO | DESCARTADO | CUARENTENA
--    dq_incidencias    bitácora: fila, regla, valor original y corregido
--
--  Regla de oro: ninguna fila desaparece sin dejar rastro. Lo que no
--  entra al data warehouse queda en DESCARTADO o CUARENTENA con motivo.
-- =====================================================================

SET NAMES utf8mb4;
USE pos_analytics;

-- ---------------------------------------------------------------------
-- Catálogo tipado (2 versiones de lista de precios)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS int_catalogo;
CREATE TABLE int_catalogo (
  sku            VARCHAR(40)  NOT NULL,
  marca          VARCHAR(40)  NOT NULL,
  descripcion    VARCHAR(200) NOT NULL,
  categoria      VARCHAR(60)  NOT NULL,
  subcategoria   VARCHAR(60)  NOT NULL,
  costo_origen   DECIMAL(12,2) NOT NULL,
  moneda_costo   CHAR(3)      NOT NULL,
  precio_lista   DECIMAL(12,2) NOT NULL,
  vigente_desde  DATE         NOT NULL,
  vigente_hasta  DATE         NOT NULL,
  version        TINYINT      NOT NULL,
  PRIMARY KEY (sku, vigente_desde)
) ENGINE=InnoDB;

INSERT INTO int_catalogo
SELECT sku, marca, descripcion, categoria, subcategoria, costo_origen, moneda_costo,
       precio_lista, vigente_desde,
       -- la versión vence un día antes de que entre la siguiente
       COALESCE(LEAD(vigente_desde) OVER w - INTERVAL 1 DAY, '9999-12-31'),
       ROW_NUMBER() OVER w
FROM (
  SELECT UPPER(TRIM(c.codigo))              AS sku,
         TRIM(c.marca)                      AS marca,
         fn_limpiar_texto(c.descripcion)    AS descripcion,
         a.categoria,
         a.subcategoria,
         fn_decimal_coma(c.costo)           AS costo_origen,
         UPPER(TRIM(c.moneda))              AS moneda_costo,
         fn_decimal_coma(c.precio_lista_mxn) AS precio_lista,
         fn_parse_fecha(c.vigente_desde)    AS vigente_desde
  FROM stg_catalogo c
  JOIN ref_categoria_alias a ON a.alias = TRIM(c.categoria)
) t
WINDOW w AS (PARTITION BY sku ORDER BY vigente_desde);

-- ---------------------------------------------------------------------
-- Tipo de cambio diario con relleno hacia adelante
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS int_tipo_cambio;
CREATE TABLE int_tipo_cambio (
  fecha        DATE PRIMARY KEY,
  tc           DECIMAL(10,4) NOT NULL,
  es_publicado BOOLEAN NOT NULL COMMENT 'FALSE = tomado del último día hábil'
) ENGINE=InnoDB;

SET SESSION cte_max_recursion_depth = 5000;

INSERT INTO int_tipo_cambio
WITH RECURSIVE dias AS (
  SELECT MIN(CAST(fecha AS DATE)) AS d FROM stg_tipo_cambio
  UNION ALL
  SELECT d + INTERVAL 1 DAY FROM dias
   WHERE d < (SELECT MAX(CAST(fecha AS DATE)) FROM stg_tipo_cambio)
),
calendario AS (
  SELECT dias.d,
         CAST(t.tc_usd_mxn AS DECIMAL(10,4)) AS tc,
         -- "islas": cada día publicado abre un grupo; los días sin dato
         -- (fines de semana) caen en el grupo del último día publicado
         COUNT(t.tc_usd_mxn) OVER (ORDER BY dias.d) AS grupo
  FROM dias
  LEFT JOIN stg_tipo_cambio t ON CAST(t.fecha AS DATE) = dias.d
)
SELECT d,
       FIRST_VALUE(tc) OVER (PARTITION BY grupo ORDER BY d),   -- relleno hacia adelante
       tc IS NOT NULL
FROM calendario;

-- ---------------------------------------------------------------------
-- Ventas tipadas + banderas de cada regla
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS int_ventas;
CREATE TABLE int_ventas (
  fila             INT UNSIGNED PRIMARY KEY,
  folio            VARCHAR(30),
  linea            SMALLINT,
  fecha            DATE,
  rfc              VARCHAR(13),
  cliente          VARCHAR(200),
  estado           VARCHAR(60),
  region           VARCHAR(20),
  almacen          CHAR(4),
  vendedor         VARCHAR(80),
  sku              VARCHAR(40),
  cantidad         INT,
  precio_original  DECIMAL(14,2) COMMENT 'en la moneda del documento',
  moneda           CHAR(3),
  tipo_cambio      DECIMAL(10,4),
  precio_mxn       DECIMAL(14,2),
  precio_lista     DECIMAL(12,2),
  descuento_pct    DECIMAL(5,2),
  -- banderas de calidad
  r01_duplicado    BOOLEAN, r02_fecha     BOOLEAN, r03_sku_desconocido BOOLEAN,
  r04_sku_anterior BOOLEAN, r05_cantidad  BOOLEAN, r06_precio_faltante BOOLEAN,
  r07_precio_atipico BOOLEAN, r08_rfc     BOOLEAN, r09_usd BOOLEAN, r10_moneda_vacia BOOLEAN,
  estado_carga     ENUM('OK','CORREGIDO','DESCARTADO','CUARENTENA'),
  KEY idx_int_estado (estado_carga),
  KEY idx_int_folio (folio, linea)
) ENGINE=InnoDB;

INSERT INTO int_ventas
WITH base AS (
  SELECT s.fila,
         TRIM(s.folio)                               AS folio,
         CAST(NULLIF(TRIM(s.linea), '') AS UNSIGNED) AS linea,
         fn_parse_fecha(s.fecha)                     AS fecha,
         fn_normalizar_rfc(s.rfc_cliente)            AS rfc_norm,
         fn_limpiar_texto(s.cliente)                 AS cliente,
         ea.estado, ea.region,
         aa.codigo                                   AS almacen,
         fn_limpiar_texto(s.vendedor)                AS vendedor,
         UPPER(TRIM(s.sku))                          AS sku_norm,
         IF(TRIM(s.cantidad) REGEXP '^-?[0-9]+$', CAST(TRIM(s.cantidad) AS SIGNED), NULL) AS cantidad,
         fn_limpiar_monto(s.precio_unitario)         AS precio_original,
         ma.moneda                                   AS moneda_norm,
         TRIM(s.moneda) = ''                         AS moneda_vacia,
         fn_parse_descuento(s.descuento)             AS descuento_pct,
         -- R01: la segunda (y siguientes) aparición de una fila idéntica
         ROW_NUMBER() OVER (PARTITION BY s.folio, s.linea, s.fecha, s.rfc_cliente, s.cliente,
                                         s.estado, s.almacen, s.vendedor, s.sku, s.descripcion,
                                         s.cantidad, s.precio_unitario, s.descuento, s.moneda
                            ORDER BY s.fila) > 1     AS r01
  FROM stg_ventas s
  LEFT JOIN ref_estado_alias  ea ON ea.alias = TRIM(s.estado)
  LEFT JOIN ref_almacen_alias aa ON aa.alias = TRIM(s.almacen)
  LEFT JOIN ref_moneda_alias  ma ON ma.alias = TRIM(s.moneda)
),
con_sku AS (
  SELECT b.*,
         CASE WHEN EXISTS (SELECT 1 FROM int_catalogo c WHERE c.sku = b.sku_norm) THEN b.sku_norm
              ELSE (SELECT e.sku FROM stg_equivalencias_sku e WHERE e.codigo_anterior = b.sku_norm)
         END AS sku,
         NOT EXISTS (SELECT 1 FROM int_catalogo c WHERE c.sku = b.sku_norm)
           AND EXISTS (SELECT 1 FROM stg_equivalencias_sku e WHERE e.codigo_anterior = b.sku_norm) AS r04
  FROM base b
),
con_precio AS (
  SELECT x.*,
         COALESCE(x.moneda_norm, IF(x.moneda_vacia, 'MXN', NULL)) AS moneda,
         c.precio_lista,
         tc.tc
  FROM con_sku x
  LEFT JOIN int_catalogo c     ON c.sku = x.sku AND x.fecha BETWEEN c.vigente_desde AND c.vigente_hasta
  LEFT JOIN int_tipo_cambio tc ON tc.fecha = x.fecha
)
SELECT fila, folio, linea, fecha,
       IF(fn_rfc_valido(rfc_norm), rfc_norm, 'XAXX010101000'),
       IF(fn_rfc_valido(rfc_norm), cliente, 'PÚBLICO EN GENERAL'),
       estado, region, almacen, vendedor, sku, cantidad,
       precio_original, moneda,
       IF(moneda = 'USD', tc, 1),
       -- precio en MXN: convertido si es USD, imputado si falta
       CASE WHEN precio_original IS NULL THEN precio_lista
            WHEN moneda = 'USD'          THEN ROUND(precio_original * tc, 2)
            ELSE precio_original END,
       precio_lista,
       COALESCE(descuento_pct, 0),
       r01,
       fecha IS NULL,                                               -- R02
       sku IS NULL,                                                 -- R03
       r04,                                                         -- R04
       cantidad IS NULL OR cantidad = 0,                            -- R05
       precio_original IS NULL,                                     -- R06
       precio_original IS NOT NULL AND precio_lista IS NOT NULL     -- R07
         AND (IF(moneda = 'USD', precio_original * tc, precio_original) < precio_lista * 0.5
           OR IF(moneda = 'USD', precio_original * tc, precio_original) > precio_lista * 2),
       NOT fn_rfc_valido(rfc_norm),                                 -- R08
       moneda = 'USD',                                              -- R09
       moneda_vacia,                                                -- R10
       NULL
FROM con_precio;

-- Con varias banderas, gana la acción más severa
UPDATE int_ventas
   SET estado_carga = CASE
         WHEN r01_duplicado OR r05_cantidad                                THEN 'DESCARTADO'
         WHEN r02_fecha OR r03_sku_desconocido OR r07_precio_atipico       THEN 'CUARENTENA'
         WHEN r04_sku_anterior OR r06_precio_faltante OR r08_rfc
              OR r09_usd OR r10_moneda_vacia                               THEN 'CORREGIDO'
         ELSE 'OK' END;

-- ---------------------------------------------------------------------
-- Bitácora de incidencias (una fila por fila-regla)
--   Una fila DESCARTADA por duplicado solo reporta R01: sus demás
--   defectos ya se reportaron en la fila original.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dq_incidencias;
CREATE TABLE dq_incidencias (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fila             INT UNSIGNED NOT NULL,
  regla            CHAR(3)      NOT NULL,
  campo            VARCHAR(30)  NOT NULL,
  valor_original   VARCHAR(200) NULL,
  valor_corregido  VARCHAR(200) NULL,
  KEY idx_dq_regla (regla),
  FOREIGN KEY (regla) REFERENCES dq_reglas (regla)
) ENGINE=InnoDB;

INSERT INTO dq_incidencias (fila, regla, campo, valor_original, valor_corregido)
SELECT i.fila, 'R01', 'fila completa', CONCAT(s.folio, ' / línea ', s.linea), NULL
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r01_duplicado
UNION ALL
SELECT i.fila, 'R02', 'fecha', s.fecha, NULL
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r02_fecha AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R03', 'sku', s.sku, NULL
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r03_sku_desconocido AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R04', 'sku', s.sku, i.sku
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r04_sku_anterior AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R05', 'cantidad', s.cantidad, NULL
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r05_cantidad AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R06', 'precio_unitario', s.precio_unitario, CAST(i.precio_mxn AS CHAR)
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r06_precio_faltante AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R07', 'precio_unitario', s.precio_unitario, CONCAT('lista: ', i.precio_lista)
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r07_precio_atipico AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R08', 'rfc_cliente', s.rfc_cliente, i.rfc
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r08_rfc AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R09', 'moneda', CONCAT(s.moneda, ' ', s.precio_unitario),
       CONCAT('MXN ', i.precio_mxn, ' (TC ', i.tipo_cambio, ')')
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r09_usd AND NOT i.r01_duplicado
UNION ALL
SELECT i.fila, 'R10', 'moneda', s.moneda, 'MXN'
  FROM int_ventas i JOIN stg_ventas s USING (fila) WHERE i.r10_moneda_vacia AND NOT i.r01_duplicado;

-- Vista de cuarentena: lo que alguien de negocio debe revisar a mano
CREATE OR REPLACE VIEW vw_cuarentena AS
SELECT s.*, GROUP_CONCAT(d.regla ORDER BY d.regla) AS reglas,
       GROUP_CONCAT(r.descripcion ORDER BY d.regla SEPARATOR ' | ') AS motivo
FROM int_ventas i
JOIN stg_ventas s     USING (fila)
JOIN dq_incidencias d USING (fila)
JOIN dq_reglas r      ON r.regla = d.regla AND r.accion = 'CUARENTENA'
WHERE i.estado_carga = 'CUARENTENA'
GROUP BY s.fila;

-- Normalizaciones de formato (no son errores, pero conviene medirlas)
CREATE OR REPLACE VIEW vw_normalizaciones AS
SELECT 'fecha en formato distinto a AAAA-MM-DD' AS normalizacion,
       SUM(s.fecha NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND i.fecha IS NOT NULL) AS filas
  FROM stg_ventas s JOIN int_ventas i USING (fila)
UNION ALL
SELECT 'RFC con minúsculas, guiones o espacios',
       SUM(BINARY s.rfc_cliente <> BINARY i.rfc AND NOT i.r08_rfc)
  FROM stg_ventas s JOIN int_ventas i USING (fila)
UNION ALL
SELECT 'estado escrito con abreviatura o variante',
       SUM(BINARY TRIM(s.estado) <> BINARY i.estado)
  FROM stg_ventas s JOIN int_ventas i USING (fila)
UNION ALL
SELECT 'precio con signo $ o separador de miles',
       SUM(s.precio_unitario REGEXP '[$,]')
  FROM stg_ventas s
UNION ALL
SELECT 'descuento en formato % o fracción',
       SUM(s.descuento REGEXP '%|^0\\.')
  FROM stg_ventas s
UNION ALL
SELECT 'SKU en minúsculas o con espacios',
       SUM(BINARY s.sku <> BINARY UPPER(TRIM(s.sku)))
  FROM stg_ventas s;
