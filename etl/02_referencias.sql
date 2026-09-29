-- =====================================================================
--  pos-sales-analytics · etl/02_referencias.sql
--  Tablas de referencia: el "diccionario" que convierte los valores
--  sucios en valores estándar. Viven en tablas (no en CASE dentro del
--  código) para que negocio pueda agregar un alias nuevo sin tocar el ETL.
--
--  La base usa collation utf8mb4_0900_ai_ci (insensible a acentos y
--  mayúsculas): 'Queretaro' = 'Querétaro' y 'cdmx' = 'CDMX' ya son
--  iguales. Aquí solo van los alias que realmente son distintos.
-- =====================================================================

SET NAMES utf8mb4;
USE pos_analytics;

CREATE TABLE ref_estado_alias (
  alias    VARCHAR(60) PRIMARY KEY,
  estado   VARCHAR(60) NOT NULL,
  region   VARCHAR(20) NOT NULL
) ENGINE=InnoDB;

INSERT INTO ref_estado_alias (alias, estado, region) VALUES
  ('Ciudad de México','Ciudad de México','Centro'), ('CDMX','Ciudad de México','Centro'),
  ('D.F.','Ciudad de México','Centro'),             ('Distrito Federal','Ciudad de México','Centro'),
  ('Estado de México','Estado de México','Centro'), ('Edo. Méx.','Estado de México','Centro'),
  ('EDOMEX','Estado de México','Centro'),           ('Edo Mex','Estado de México','Centro'),
  ('Jalisco','Jalisco','Occidente'),                ('JAL','Jalisco','Occidente'),
  ('Nuevo León','Nuevo León','Noreste'),            ('NL','Nuevo León','Noreste'),
  ('N.L.','Nuevo León','Noreste'),
  ('Puebla','Puebla','Centro'),                     ('PUE','Puebla','Centro'),
  ('Querétaro','Querétaro','Bajío'),                ('QRO','Querétaro','Bajío'),
  ('Guanajuato','Guanajuato','Bajío'),              ('GTO','Guanajuato','Bajío'),
  ('Yucatán','Yucatán','Sureste'),                  ('YUC','Yucatán','Sureste'),
  ('Veracruz','Veracruz','Sureste'),                ('VER','Veracruz','Sureste'),
  ('Baja California','Baja California','Noroeste'),('BC','Baja California','Noroeste'),
  ('B.C.','Baja California','Noroeste');

CREATE TABLE ref_almacen (
  codigo   CHAR(4) PRIMARY KEY,
  nombre   VARCHAR(60) NOT NULL,
  ciudad   VARCHAR(60) NOT NULL
) ENGINE=InnoDB;

INSERT INTO ref_almacen VALUES
  ('CDMX','CEDIS Ciudad de México','Ciudad de México'),
  ('GDL', 'Almacén Guadalajara',  'Guadalajara'),
  ('MTY', 'Almacén Monterrey',    'Monterrey');

CREATE TABLE ref_almacen_alias (
  alias    VARCHAR(40) PRIMARY KEY,
  codigo   CHAR(4) NOT NULL,
  FOREIGN KEY (codigo) REFERENCES ref_almacen (codigo)
) ENGINE=InnoDB;

INSERT INTO ref_almacen_alias VALUES
  ('CEDIS CDMX','CDMX'), ('CDMX','CDMX'), ('CEDIS','CDMX'),
  ('Guadalajara','GDL'), ('GDL','GDL'),   ('Almacen GDL','GDL'),
  ('Monterrey','MTY'),   ('MTY','MTY');

CREATE TABLE ref_moneda_alias (
  alias    VARCHAR(20) PRIMARY KEY,
  moneda   CHAR(3) NOT NULL
) ENGINE=InnoDB;

INSERT INTO ref_moneda_alias VALUES
  ('MXN','MXN'), ('Pesos','MXN'), ('M.N.','MXN'), ('MN','MXN'),
  ('USD','USD'), ('Dólares','USD'), ('US$','USD');   -- 'Dolares' ya coincide por la collation

-- Cada proveedor nombra sus categorías distinto (inglés, italiano, mayúsculas…)
CREATE TABLE ref_categoria_alias (
  alias         VARCHAR(60) PRIMARY KEY,
  categoria     VARCHAR(60) NOT NULL,
  subcategoria  VARCHAR(60) NOT NULL
) ENGINE=InnoDB;

INSERT INTO ref_categoria_alias VALUES
  ('Desktop POS',             'Terminales POS','Terminales POS de escritorio'),
  ('Handheld POS',            'Terminales POS','Terminales POS portátiles'),
  ('TERMINAL PORTATIL',       'Terminales POS','Terminales POS portátiles'),
  ('PDA con impresora',       'Terminales POS','Terminales POS portátiles'),
  ('Payment Terminal',        'Terminales POS','Terminales de pago SmartPOS'),
  ('SmartPOS',                'Terminales POS','Terminales de pago SmartPOS'),
  ('Mobile Computer',         'Computadoras móviles','Computadoras móviles empresariales'),
  ('COMPUTADORA MOVIL',       'Computadoras móviles','Computadoras móviles empresariales'),
  ('PDA',                     'Computadoras móviles','Computadoras móviles empresariales'),
  ('Rugged Handheld',         'Computadoras móviles','Computadoras móviles rugerizadas'),
  ('COMPUTADORA MOVIL RUGGED','Computadoras móviles','Computadoras móviles rugerizadas'),
  ('Rugged Mobile Computer',  'Computadoras móviles','Computadoras móviles rugerizadas'),
  ('PDA industrial',          'Computadoras móviles','Computadoras móviles rugerizadas'),
  ('Corded Scanner',          'Lectores de código de barras','Lectores alámbricos'),
  ('Cordless Scanner',        'Lectores de código de barras','Lectores inalámbricos'),
  ('Escáner inalámbrico',     'Lectores de código de barras','Lectores inalámbricos'),
  ('RFID UHF',                'RFID','Lectores RFID UHF'),
  ('RFID',                    'RFID','Lectores RFID UHF'),
  ('PDA RFID',                'RFID','Lectores RFID UHF'),
  ('Receipt Printer',         'Impresoras','Impresoras de tickets'),
  ('Impresora térmica',       'Impresoras','Impresoras de tickets'),
  ('Stampanti POS',           'Impresoras','Impresoras de tickets'),
  ('Stampanti Kiosk',         'Impresoras','Impresoras para kiosco'),
  ('Self-service Kiosk',      'Kioscos','Kioscos de autoservicio'),
  ('Chioschi',                'Kioscos','Kioscos de autoservicio');

CREATE TABLE ref_mes_es (
  abrev  CHAR(3) PRIMARY KEY,
  num    TINYINT NOT NULL,
  nombre VARCHAR(12) NOT NULL
) ENGINE=InnoDB;

INSERT INTO ref_mes_es VALUES
  ('ene',1,'Enero'),('feb',2,'Febrero'),('mar',3,'Marzo'),('abr',4,'Abril'),
  ('may',5,'Mayo'),('jun',6,'Junio'),('jul',7,'Julio'),('ago',8,'Agosto'),
  ('sep',9,'Septiembre'),('oct',10,'Octubre'),('nov',11,'Noviembre'),('dic',12,'Diciembre');

-- ---------------------------------------------------------------------
-- Catálogo de reglas de calidad de datos
-- ---------------------------------------------------------------------
CREATE TABLE dq_reglas (
  regla        CHAR(3) PRIMARY KEY,
  descripcion  VARCHAR(200) NOT NULL,
  accion       ENUM('DESCARTADO','CUARENTENA','CORREGIDO') NOT NULL,
  prioridad    TINYINT NOT NULL COMMENT '1 = se evalúa primero / gana'
) ENGINE=InnoDB;

INSERT INTO dq_reglas VALUES
  ('R01','Fila duplicada exacta (doble exportación del ERP)',                          'DESCARTADO', 1),
  ('R05','Cantidad igual a cero o no numérica',                                        'DESCARTADO', 2),
  ('R02','Fecha vacía o inválida',                                                      'CUARENTENA', 3),
  ('R03','SKU inexistente en catálogo y sin equivalencia',                              'CUARENTENA', 4),
  ('R07','Precio atípico: menor a 50 % o mayor a 200 % del precio de lista vigente',    'CUARENTENA', 5),
  ('R04','SKU con código anterior: se reemplaza por el vigente (equivalencias_sku)',   'CORREGIDO',  6),
  ('R06','Precio faltante: se imputa el precio de lista vigente a la fecha',           'CORREGIDO',  7),
  ('R08','RFC inválido: se asigna a PÚBLICO EN GENERAL (XAXX010101000)',               'CORREGIDO',  8),
  ('R09','Venta en USD: se convierte a MXN con el tipo de cambio del día',             'CORREGIDO',  9),
  ('R10','Moneda vacía: se asume MXN',                                                 'CORREGIDO', 10);
