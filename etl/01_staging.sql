-- =====================================================================
--  pos-sales-analytics · etl/01_staging.sql
--  EXTRACT: carga los archivos de data/raw/ TAL CUAL a tablas de staging.
--
--  Principio: en staging todo es texto (VARCHAR). Si un archivo trae
--  "$5,900.00" o "31/02/2026", se guarda así; la limpieza ocurre
--  después y queda documentada. Nada se pierde en la carga.
--
--  Cada fila conserva su número de línea en el archivo (columna fila)
--  para poder rastrear cualquier dato del dashboard hasta su origen.
--
--  Se ejecuta desde la raíz del repo con --local-infile=1
--  (ver etl/run_etl.sh).
-- =====================================================================

SET NAMES utf8mb4;

DROP DATABASE IF EXISTS pos_analytics;
CREATE DATABASE pos_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE pos_analytics;

-- ---------------------------------------------------------------------
-- Tablas de staging
-- ---------------------------------------------------------------------
CREATE TABLE stg_ventas (
  fila             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,   -- línea del archivo (sin encabezado)
  folio            VARCHAR(30),
  linea            VARCHAR(10),
  fecha            VARCHAR(30),
  rfc_cliente      VARCHAR(30),
  cliente          VARCHAR(200),
  estado           VARCHAR(60),
  almacen          VARCHAR(40),
  vendedor         VARCHAR(80),
  sku              VARCHAR(40),
  descripcion      VARCHAR(200),
  cantidad         VARCHAR(20),
  precio_unitario  VARCHAR(30),
  descuento        VARCHAR(20),
  moneda           VARCHAR(20)
) ENGINE=InnoDB COMMENT='ventas_erp.csv sin transformar';

CREATE TABLE stg_catalogo (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  archivo          VARCHAR(60),
  marca            VARCHAR(40),
  codigo           VARCHAR(40),
  descripcion      VARCHAR(200),
  categoria        VARCHAR(60),
  costo            VARCHAR(30),
  moneda           VARCHAR(10),
  precio_lista_mxn VARCHAR(30),
  vigente_desde    VARCHAR(20)
) ENGINE=InnoDB COMMENT='Listas de precios de proveedores (cp1252, ;)';

CREATE TABLE stg_equivalencias_sku (
  codigo_anterior  VARCHAR(40) PRIMARY KEY,
  sku              VARCHAR(40)
) ENGINE=InnoDB;

CREATE TABLE stg_tipo_cambio (
  fecha            VARCHAR(20),
  tc_usd_mxn       VARCHAR(20)
) ENGINE=InnoDB;

CREATE TABLE stg_inventario (
  fila             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  mes              VARCHAR(10),
  sku              VARCHAR(40),
  almacen          VARCHAR(20),
  existencia       VARCHAR(20)
) ENGINE=InnoDB;

CREATE TABLE stg_metas (
  marca            VARCHAR(40),
  mes              VARCHAR(10),
  meta_mxn         VARCHAR(30)
) ENGINE=InnoDB;

-- Conteos esperados por regla (solo existe porque los datos son sintéticos:
-- permite PROBAR que el ETL detecta exactamente lo que se inyectó)
CREATE TABLE stg_esperado_calidad (
  regla            VARCHAR(5) PRIMARY KEY,
  filas            INT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Carga (rutas relativas a la raíz del repositorio)
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/ventas_erp.csv'
  INTO TABLE stg_ventas
  CHARACTER SET utf8mb4
  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
  LINES TERMINATED BY '\n'
  IGNORE 1 LINES
  (folio, linea, fecha, rfc_cliente, cliente, estado, almacen, vendedor,
   sku, descripcion, cantidad, precio_unitario, descuento, moneda);

-- Listas de precios exportadas de Excel en Windows: cp1252, ';' y CRLF
LOAD DATA LOCAL INFILE 'data/raw/catalogo_proveedores_2024-10.csv'
  INTO TABLE stg_catalogo
  CHARACTER SET latin1                      -- latin1 de MySQL = cp1252
  FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"'
  LINES TERMINATED BY '\r\n'
  IGNORE 1 LINES
  (marca, codigo, descripcion, categoria, costo, moneda, precio_lista_mxn, vigente_desde)
  SET archivo = 'catalogo_proveedores_2024-10.csv';

LOAD DATA LOCAL INFILE 'data/raw/catalogo_proveedores_2026-04.csv'
  INTO TABLE stg_catalogo
  CHARACTER SET latin1
  FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"'
  LINES TERMINATED BY '\r\n'
  IGNORE 1 LINES
  (marca, codigo, descripcion, categoria, costo, moneda, precio_lista_mxn, vigente_desde)
  SET archivo = 'catalogo_proveedores_2026-04.csv';

LOAD DATA LOCAL INFILE 'data/raw/equivalencias_sku.csv'
  INTO TABLE stg_equivalencias_sku CHARACTER SET utf8mb4
  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/raw/tipo_cambio.csv'
  INTO TABLE stg_tipo_cambio CHARACTER SET utf8mb4
  FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/raw/inventario_mensual.csv'
  INTO TABLE stg_inventario CHARACTER SET utf8mb4
  FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES
  (mes, sku, almacen, existencia);

LOAD DATA LOCAL INFILE 'data/raw/metas_ventas.csv'
  INTO TABLE stg_metas CHARACTER SET utf8mb4
  FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/raw/_esperado_calidad.csv'
  INTO TABLE stg_esperado_calidad CHARACTER SET utf8mb4
  FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES;
