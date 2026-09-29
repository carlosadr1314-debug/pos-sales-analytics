-- =====================================================================
--  pos-sales-analytics · etl/03_funciones.sql
--  Funciones de limpieza reutilizables. Todas devuelven NULL cuando el
--  valor no se puede interpretar (nunca "adivinan" en silencio).
-- =====================================================================

SET NAMES utf8mb4;
USE pos_analytics;

DELIMITER $$

-- "$5,900.00" | "5,900.00" | " 5900 " | "5900.00"  ->  5900.00
DROP FUNCTION IF EXISTS fn_limpiar_monto $$
CREATE FUNCTION fn_limpiar_monto(p VARCHAR(40))
RETURNS DECIMAL(14,2)
DETERMINISTIC NO SQL
BEGIN
  DECLARE v VARCHAR(40);
  SET v = REPLACE(REPLACE(REPLACE(TRIM(COALESCE(p, '')), '$', ''), ',', ''), ' ', '');
  IF v REGEXP '^-?[0-9]+(\\.[0-9]+)?$' THEN
    RETURN CAST(v AS DECIMAL(14,2));
  END IF;
  RETURN NULL;
END $$

-- Formato europeo/latino de Excel: "1.234,56" -> 1234.56
DROP FUNCTION IF EXISTS fn_decimal_coma $$
CREATE FUNCTION fn_decimal_coma(p VARCHAR(40))
RETURNS DECIMAL(14,2)
DETERMINISTIC NO SQL
BEGIN
  RETURN fn_limpiar_monto(REPLACE(REPLACE(p, '.', ''), ',', '.'));
END $$

-- Acepta 'AAAA-MM-DD', 'DD/MM/AAAA' y 'D-mmm-AAAA' (mes en español).
-- Valida día/mes ANTES de construir la fecha: '31/02/2026' -> NULL.
DROP FUNCTION IF EXISTS fn_parse_fecha $$
CREATE FUNCTION fn_parse_fecha(p VARCHAR(30))
RETURNS DATE
DETERMINISTIC NO SQL
BEGIN
  DECLARE v VARCHAR(30) DEFAULT LOWER(TRIM(COALESCE(p, '')));
  DECLARE a, m, d INT DEFAULT NULL;

  IF v REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    SET a = SUBSTRING(v, 1, 4), m = SUBSTRING(v, 6, 2), d = SUBSTRING(v, 9, 2);
  ELSEIF v REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' THEN
    SET d = SUBSTRING_INDEX(v, '/', 1),
        m = SUBSTRING_INDEX(SUBSTRING_INDEX(v, '/', 2), '/', -1),
        a = SUBSTRING_INDEX(v, '/', -1);
  ELSEIF v REGEXP '^[0-9]{1,2}-[a-z]{3}-[0-9]{4}$' THEN
    SET d = SUBSTRING_INDEX(v, '-', 1),
        m = FIELD(SUBSTRING_INDEX(SUBSTRING_INDEX(v, '-', 2), '-', -1),
                  'ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'),
        a = SUBSTRING_INDEX(v, '-', -1);
  ELSE
    RETURN NULL;
  END IF;

  IF a NOT BETWEEN 2000 AND 2100 OR m NOT BETWEEN 1 AND 12 OR d < 1 THEN
    RETURN NULL;
  END IF;
  IF d > DAY(LAST_DAY(MAKEDATE(a, 1) + INTERVAL (m - 1) MONTH)) THEN
    RETURN NULL;                                   -- 31 de febrero, etc.
  END IF;
  RETURN MAKEDATE(a, 1) + INTERVAL (m - 1) MONTH + INTERVAL (d - 1) DAY;
END $$

-- '10%' | '0.10' | '10' | '' -> 10.00 (porcentaje)
DROP FUNCTION IF EXISTS fn_parse_descuento $$
CREATE FUNCTION fn_parse_descuento(p VARCHAR(20))
RETURNS DECIMAL(5,2)
DETERMINISTIC NO SQL
BEGIN
  DECLARE v VARCHAR(20) DEFAULT REPLACE(TRIM(COALESCE(p, '')), '%', '');
  DECLARE n DECIMAL(8,4);
  IF v = '' THEN RETURN 0; END IF;
  IF v NOT REGEXP '^[0-9]+(\\.[0-9]+)?$' THEN RETURN NULL; END IF;
  SET n = CAST(v AS DECIMAL(8,4));
  RETURN IF(n > 0 AND n < 1, n * 100, n);        -- 0.10 se interpreta como 10 %
END $$

-- ' abc-910718-c29 ' -> 'ABC910718C29'
DROP FUNCTION IF EXISTS fn_normalizar_rfc $$
CREATE FUNCTION fn_normalizar_rfc(p VARCHAR(30))
RETURNS VARCHAR(30)
DETERMINISTIC NO SQL
BEGIN
  RETURN UPPER(REPLACE(REPLACE(TRIM(COALESCE(p, '')), '-', ''), ' ', ''));
END $$

DROP FUNCTION IF EXISTS fn_rfc_valido $$
CREATE FUNCTION fn_rfc_valido(p VARCHAR(30))
RETURNS BOOLEAN
DETERMINISTIC NO SQL
BEGIN
  RETURN REGEXP_LIKE(COALESCE(p, ''), '^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$', 'c');
END $$

-- Nombres propios: 'RESTAURANTE CUMBRES S.A. DE C.V.' se deja como venga,
-- pero sin espacios repetidos ni en los extremos.
DROP FUNCTION IF EXISTS fn_limpiar_texto $$
CREATE FUNCTION fn_limpiar_texto(p VARCHAR(200))
RETURNS VARCHAR(200)
DETERMINISTIC NO SQL
BEGIN
  RETURN REGEXP_REPLACE(TRIM(COALESCE(p, '')), '[[:space:]]+', ' ');
END $$

DELIMITER ;
