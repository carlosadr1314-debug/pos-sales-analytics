#!/usr/bin/env python3
"""
Genera los archivos fuente "sucios" de data/raw/ (solo biblioteca estándar).

Simula lo que llega de sistemas reales:
  - ventas_erp.csv              export del ERP (UTF-8, coma) con formatos mezclados
  - catalogo_proveedores_*.csv  listas de precios de proveedor (Excel "a la mexicana":
                                Windows-1252, punto y coma, coma decimal, CRLF)
  - equivalencias_sku.csv       códigos anteriores -> SKU vigente
  - tipo_cambio.csv             USD/MXN diario SIMULADO (solo días hábiles)
  - inventario_mensual.csv      fotos de existencias a fin de mes
  - metas_ventas.csv            metas mensuales por marca
  - _esperado_calidad.csv       cuántas filas se inyectaron con cada defecto
                                (lo usan las pruebas para verificar el ETL)

Los datos son SINTÉTICOS. Incluyen patrones de negocio plantados a propósito
(estacionalidad, alza de costos, devoluciones, sobreinventario, etc.) para
practicar el análisis. Semilla fija => mismos archivos en cualquier equipo.
"""
import csv
import math
import random
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

SEMILLA = 2026
INICIO = date(2024, 10, 1)
FIN = date(2026, 9, 27)
CAMBIO_LISTA = date(2026, 4, 1)          # entra en vigor la lista de precios 2026
RAIZ = Path(__file__).resolve().parents[1] / "data" / "raw"

rnd = random.Random(SEMILLA)

# (sku, id_marca, id_subcategoria, modelo, nombre, precio_lista_mxn_2024)
PRODUCTOS = [
    ('SUN-T2S', 1, 2, 'T2s', 'SUNMI T2s terminal POS de escritorio 15.6"', 14500.0),
    ('SUN-T2S-LITE', 1, 2, 'T2s Lite', 'SUNMI T2s Lite terminal POS de escritorio', 12300.0),
    ('SUN-T3-PRO', 1, 2, 'T3 PRO', 'SUNMI T3 PRO terminal POS de escritorio', 19900.0),
    ('SUN-D2-MINI', 1, 2, 'D2 mini', 'SUNMI D2 mini terminal POS compacta 10.1"', 9600.0),
    ('SUN-D3-MINI', 1, 2, 'D3 MINI', 'SUNMI D3 MINI terminal POS compacta', 10500.0),
    ('SUN-V2S', 1, 3, 'V2s', 'SUNMI V2s terminal portátil con impresora', 5900.0),
    ('SUN-V2-PRO', 1, 3, 'V2 PRO', 'SUNMI V2 PRO terminal portátil con impresora', 6900.0),
    ('SUN-V3', 1, 3, 'V3', 'SUNMI V3 terminal portátil con impresora', 7800.0),
    ('SUN-P2', 1, 4, 'P2', 'SUNMI P2 SmartPOS de pago', 7200.0),
    ('SUN-P2-PRO', 1, 4, 'P2 PRO', 'SUNMI P2 PRO SmartPOS de pago', 8400.0),
    ('SUN-P3', 1, 4, 'P3', 'SUNMI P3 SmartPOS de pago', 9400.0),
    ('SUN-L2S', 1, 7, 'L2s', 'SUNMI L2s computadora móvil rugerizada', 8100.0),
    ('SUN-L2K', 1, 7, 'L2K', 'SUNMI L2K computadora móvil rugerizada', 8800.0),
    ('SUN-M2', 1, 6, 'M2', 'SUNMI M2 computadora móvil', 5400.0),
    ('SUN-K2', 1, 17, 'K2', 'SUNMI K2 kiosco de autoservicio 24"', 36900.0),
    ('SUN-K2-MINI', 1, 17, 'K2 MINI', 'SUNMI K2 MINI kiosco de autoservicio de mostrador', 23700.0),
    ('SUN-NT311', 1, 14, 'NT311', 'SUNMI NT311 impresora de tickets en la nube', 3200.0),
    ('SUN-NT212', 1, 14, 'NT212', 'SUNMI NT212 impresora de tickets 58 mm', 2300.0),
    ('BB-EF501', 2, 6, 'EF501', 'Bluebird EF501 computadora móvil empresarial', 12400.0),
    ('BB-EF550', 2, 6, 'EF550', 'Bluebird EF550 computadora móvil empresarial', 14100.0),
    ('BB-VF550', 2, 7, 'VF550', 'Bluebird VF550 computadora móvil rugerizada', 16800.0),
    ('BB-HF550X', 2, 7, 'HF550X', 'Bluebird HF550X computadora móvil rugerizada', 18900.0),
    ('BB-S50', 2, 7, 'S50', 'Bluebird S50 computadora móvil rugerizada', 15200.0),
    ('BB-EF400', 2, 6, 'EF400', 'Bluebird EF400 computadora móvil compacta', 10400.0),
    ('BB-RFR901', 2, 12, 'RFR901', 'Bluebird RFR901 lector RFID UHF tipo sled', 14700.0),
    ('BB-RFR900', 2, 12, 'RFR900', 'Bluebird RFR900 lector RFID UHF portátil', 13100.0),
    ('BB-BP30', 2, 3, 'BP30', 'Bluebird BP30 terminal portátil con impresora', 9200.0),
    ('CL-RS35', 3, 6, 'RS35', 'CipherLab RS35 computadora móvil', 10200.0),
    ('CL-RS36', 3, 6, 'RS36', 'CipherLab RS36 computadora móvil', 11400.0),
    ('CL-RS38', 3, 6, 'RS38', 'CipherLab RS38 computadora móvil', 12500.0),
    ('CL-RS51', 3, 7, 'RS51', 'CipherLab RS51 computadora móvil rugerizada', 13700.0),
    ('CL-RK25', 3, 7, 'RK25', 'CipherLab RK25 computadora móvil rugerizada', 14600.0),
    ('CL-RK95', 3, 7, 'RK95', 'CipherLab RK95 computadora móvil ultra rugerizada', 22200.0),
    ('CL-1500P', 3, 9, '1500P', 'CipherLab 1500P lector alámbrico lineal', 990.0),
    ('CL-1504P', 3, 9, '1504P', 'CipherLab 1504P lector alámbrico 2D', 1490.0),
    ('CL-1564A', 3, 10, '1564A', 'CipherLab 1564A lector inalámbrico 2D', 2490.0),
    ('CL-2564', 3, 10, '2564', 'CipherLab 2564 lector inalámbrico 2D industrial', 5100.0),
    ('CL-1660', 3, 10, '1660', 'CipherLab 1660 lector de bolsillo Bluetooth', 2190.0),
    ('CL-RK95-RFID', 3, 12, 'RK95 UHF', 'CipherLab RK95 con módulo RFID UHF', 29700.0),
    ('URV-DT50', 4, 6, 'DT50', 'Urovo DT50 computadora móvil', 7800.0),
    ('URV-DT40', 4, 6, 'DT40', 'Urovo DT40 computadora móvil', 6900.0),
    ('URV-RT40', 4, 7, 'RT40', 'Urovo RT40 computadora móvil rugerizada', 11100.0),
    ('URV-DT50U', 4, 12, 'DT50U', 'Urovo DT50U computadora móvil con RFID UHF', 14900.0),
    ('URV-I9100', 4, 3, 'i9100', 'Urovo i9100 terminal portátil con impresora', 6200.0),
    ('URV-I9000S', 4, 4, 'i9000S', 'Urovo i9000S SmartPOS de pago', 6600.0),
    ('URV-SR5600', 4, 10, 'SR5600', 'Urovo SR5600 lector inalámbrico tipo anillo', 2850.0),
    ('URV-K319', 4, 14, 'K319', 'Urovo K319 impresora de tickets 80 mm', 2050.0),
    ('CUS-KUBE-II', 5, 15, 'KUBE II', 'Custom KUBE II impresora para kiosco 80 mm', 5900.0),
    ('CUS-VKP80III', 5, 15, 'VKP80III', 'Custom VKP80III impresora para kiosco 80 mm', 7100.0),
    ('CUS-TG2480H', 5, 15, 'TG2480-H', 'Custom TG2480-H impresora para kiosco 80 mm', 5400.0),
    ('CUS-Q3X', 5, 14, 'Q3X', 'Custom Q3X impresora de tickets 80 mm', 3500.0),
    ('CUS-KPM180H', 5, 15, 'KPM180H', 'Custom KPM180H impresora para kiosco', 4800.0),
    ('CUS-K3', 5, 14, 'K3', 'Custom K3 impresora de tickets', 2900.0),
    ('CUS-SILK', 5, 17, 'SILK', 'Custom SILK kiosco de autoservicio', 42900.0),
]

MARCAS = {1: "SUNMI", 2: "Bluebird", 3: "CipherLab", 4: "Urovo", 5: "Custom"}
MONEDA_COSTO = {1: "USD", 2: "USD", 3: "USD", 4: "USD", 5: "MXN"}

# subcategoría -> (categoría, subcategoría, margen objetivo)
SUBCAT = {
    2: ("Terminales POS", "Terminales POS de escritorio", 0.28),
    3: ("Terminales POS", "Terminales POS portátiles", 0.28),
    4: ("Terminales POS", "Terminales de pago SmartPOS", 0.26),
    6: ("Computadoras móviles", "Computadoras móviles empresariales", 0.31),
    7: ("Computadoras móviles", "Computadoras móviles rugerizadas", 0.30),
    9: ("Lectores de código de barras", "Lectores alámbricos", 0.44),
    10: ("Lectores de código de barras", "Lectores inalámbricos", 0.41),
    12: ("RFID", "Lectores RFID UHF", 0.33),
    14: ("Impresoras", "Impresoras de tickets", 0.38),
    15: ("Impresoras", "Impresoras para kiosco", 0.36),
    17: ("Kioscos", "Kioscos de autoservicio", 0.19),
}

# Cada proveedor nombra las categorías a su manera (se normalizan en el ETL)
CATEGORIA_PROVEEDOR = {
    1: {2: "Desktop POS", 3: "Handheld POS", 4: "Payment Terminal", 6: "Mobile Computer",
        7: "Rugged Handheld", 14: "Receipt Printer", 17: "Self-service Kiosk"},
    2: {3: "TERMINAL PORTATIL", 6: "COMPUTADORA MOVIL", 7: "COMPUTADORA MOVIL RUGGED",
        12: "RFID UHF"},
    3: {6: "Mobile Computer", 7: "Rugged Mobile Computer", 9: "Corded Scanner",
        10: "Cordless Scanner", 12: "RFID"},
    4: {3: "PDA con impresora", 4: "SmartPOS", 6: "PDA", 7: "PDA industrial",
        10: "Escáner inalámbrico", 12: "PDA RFID", 14: "Impresora térmica"},
    5: {14: "Stampanti POS", 15: "Stampanti Kiosk", 17: "Chioschi"},
}

ESTADOS = {  # estado: (región, peso, alias que aparecen en el ERP)
    "Ciudad de México": ("Centro", 26, ["Ciudad de México", "CDMX", "cdmx", "Ciudad de Mexico", "D.F.", "Distrito Federal"]),
    "Estado de México": ("Centro", 14, ["Estado de México", "Edo. Méx.", "EDOMEX", "Edo Mex"]),
    "Jalisco": ("Occidente", 13, ["Jalisco", "JAL", "jalisco"]),
    "Nuevo León": ("Noreste", 13, ["Nuevo León", "Nuevo Leon", "NL", "N.L."]),
    "Puebla": ("Centro", 6, ["Puebla", "PUE"]),
    "Querétaro": ("Bajío", 7, ["Querétaro", "Queretaro", "QRO"]),
    "Guanajuato": ("Bajío", 7, ["Guanajuato", "GTO"]),
    "Yucatán": ("Sureste", 5, ["Yucatán", "Yucatan", "YUC"]),
    "Veracruz": ("Sureste", 5, ["Veracruz", "VER"]),
    "Baja California": ("Noroeste", 4, ["Baja California", "BC", "B.C."]),
}
ALMACEN_POR_REGION = {"Centro": "CDMX", "Sureste": "CDMX", "Bajío": "GDL",
                      "Occidente": "GDL", "Noreste": "MTY", "Noroeste": "MTY"}
ALIAS_ALMACEN = {"CDMX": ["CEDIS CDMX", "CDMX", "CEDIS"],
                 "GDL": ["Guadalajara", "GDL", "Almacen GDL"],
                 "MTY": ["Monterrey", "MTY"]}

VENDEDORES = {  # región -> vendedores (nombres ficticios)
    "Centro": ["Ana Torres", "Luis Méndez", "Rodrigo Salas"],
    "Sureste": ["Luis Méndez"],
    "Bajío": ["Carla Ruiz"],
    "Occidente": ["Carla Ruiz", "Jorge Paredes"],
    "Noreste": ["Sofía Lara", "Marco Ibarra"],
    "Noroeste": ["Marco Ibarra"],
}
# Patrón plantado: un vendedor concede descuentos mucho mayores
DESCUENTOS_NORMAL = ([0, 5, 10, 15], [55, 25, 14, 6])
DESCUENTOS_ALTOS = ([0, 5, 10, 15, 20], [15, 20, 30, 20, 15])

ESTACIONALIDAD = {1: 0.78, 2: 0.84, 3: 0.95, 4: 0.94, 5: 1.00, 6: 0.96,
                  7: 0.95, 8: 1.00, 9: 1.00, 10: 1.05, 11: 1.38, 12: 1.24}
MESES_ES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]


# ---------------------------------------------------------------------------
# Tipo de cambio simulado: tramos lineales + ruido, solo días hábiles
# ---------------------------------------------------------------------------
def generar_tipo_cambio():
    anclas = [(date(2024, 9, 1), 19.70), (date(2025, 6, 30), 18.60),
              (date(2026, 1, 15), 17.90), (date(2026, 9, 30), 19.45)]
    tc, d, ruido = {}, anclas[0][0], 0.0
    while d <= anclas[-1][0]:
        if d.weekday() < 5:
            for (d0, v0), (d1, v1) in zip(anclas, anclas[1:]):
                if d0 <= d <= d1:
                    base = v0 + (v1 - v0) * (d - d0).days / (d1 - d0).days
            ruido = 0.85 * ruido + rnd.gauss(0, 0.06)
            tc[d] = round(base + ruido, 4)
        d += timedelta(days=1)
    return tc


def tc_del_dia(tc, d):
    while d not in tc:           # fin de semana -> último día hábil
        d -= timedelta(days=1)
    return tc[d]


# ---------------------------------------------------------------------------
# Catálogo con dos versiones de lista de precios
# ---------------------------------------------------------------------------
def construir_catalogo():
    cat = {}
    for sku, marca, sub, modelo, nombre, precio in PRODUCTOS:
        margen = SUBCAT[sub][2] + rnd.uniform(-0.03, 0.03)
        costo_mxn = precio * (1 - margen)
        costo_v1 = round(costo_mxn / 19.0, 2) if MONEDA_COSTO[marca] == "USD" else round(costo_mxn, 2)
        # Lista 2026: SUNMI y Bluebird suben costo en USD más que su precio de lista
        alza_costo = {1: 1.08, 2: 1.05, 5: 1.03}.get(marca, 1.00)
        alza_precio = {1: 1.04, 5: 1.03}.get(marca, 1.02)
        cat[sku] = dict(marca=marca, sub=sub, modelo=modelo, nombre=nombre,
                        precio_v1=precio, precio_v2=round(precio * alza_precio, -1),
                        costo_v1=costo_v1, costo_v2=round(costo_v1 * alza_costo, 2))
    return cat


def precio_vigente(cat, sku, d):
    return cat[sku]["precio_v2"] if d >= CAMBIO_LISTA else cat[sku]["precio_v1"]


# ---------------------------------------------------------------------------
# Clientes (distribución de Pareto: pocos clientes concentran la venta)
# ---------------------------------------------------------------------------
GIROS = ["Abarrotes", "Farmacia", "Papelería", "Ferretería", "Restaurante", "Cafetería",
         "Minisúper", "Boutique", "Taquería", "Distribuidora", "Óptica", "Librería",
         "Comercializadora", "Autoservicio", "Grupo Restaurantero", "Logística"]
NOMBRES = ["San José", "La Esperanza", "El Sol", "Santa Fe", "Del Valle", "La Paz",
           "Hermanos López", "Los Pinos", "Central", "Del Norte", "Guadalupe", "Las Palmas",
           "Reforma", "Del Bajío", "Azteca", "Medina", "Vértice", "Alameda", "Horizonte", "Cumbres"]
SOCIEDADES = ["S.A. de C.V.", "S. de R.L. de C.V.", "S.A.P.I. de C.V."]
LETRAS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def generar_clientes(n=900):
    estados = list(ESTADOS)
    pesos = [ESTADOS[e][1] for e in estados]
    clientes, rfcs = [], set()
    for i in range(n):
        while True:
            rfc = ("".join(rnd.choice(LETRAS) for _ in range(3))
                   + f"{rnd.randint(85, 99) if rnd.random() < .5 else rnd.randint(0, 22):02d}"
                   + f"{rnd.randint(1, 12):02d}{rnd.randint(1, 28):02d}"
                   + rnd.choice(LETRAS) + rnd.choice(LETRAS + "0123456789") + str(rnd.randint(0, 9)))
            if rfc not in rfcs:
                rfcs.add(rfc)
                break
        estado = rnd.choices(estados, pesos)[0]
        region = ESTADOS[estado][0]
        clientes.append(dict(
            rfc=rfc,
            nombre=f"{rnd.choice(GIROS)} {rnd.choice(NOMBRES)} {rnd.choice(SOCIEDADES)}",
            estado=estado, region=region,
            almacen=ALMACEN_POR_REGION[region] if rnd.random() < .9 else rnd.choice(["CDMX", "GDL", "MTY"]),
            vendedor=rnd.choice(VENDEDORES[region]),
            peso=1 / (i + 1) ** 0.9))
    rnd.shuffle(clientes)
    return clientes


# ---------------------------------------------------------------------------
# Ventas limpias (la "verdad") -> después se ensucian
# ---------------------------------------------------------------------------
def generar_ventas(cat, clientes, tc):
    skus = list(cat)
    popularidad = {s: rnd.paretovariate(1.3) for s in skus}
    pesos_cli = [c["peso"] for c in clientes]
    lineas, folio = [], 100000
    d = INICIO
    while d <= FIN:
        if d.weekday() == 6:                                  # domingo sin ventas
            d += timedelta(days=1)
            continue
        meses = (d.year - INICIO.year) * 12 + d.month - INICIO.month
        tendencia = 1 + 0.022 * meses                         # ~26 % anual
        base = 26 * tendencia * ESTACIONALIDAD[d.month] * (0.35 if d.weekday() == 5 else 1)
        for _ in range(max(0, round(rnd.gauss(base, math.sqrt(base))))):
            folio += 1
            cli = rnd.choices(clientes, pesos_cli)[0]
            moneda = "USD" if rnd.random() < 0.03 else "MXN"
            altos = cli["vendedor"] == "Rodrigo Salas"
            n_lineas = rnd.choices([1, 2, 3, 4, 5], [40, 30, 15, 10, 5])[0]
            pesos_sku = [popularidad[s] * (0.72 if cat[s]["marca"] == 2 and d.year == 2026 else 1)
                         for s in skus]                       # Bluebird cae en 2026
            elegidos = set()
            while len(elegidos) < n_lineas:
                elegidos.add(rnd.choices(skus, pesos_sku)[0])
            for num, sku in enumerate(sorted(elegidos), start=1):
                p = precio_vigente(cat, sku, d)
                cant = (rnd.randint(1, 2) if p > 15000 else rnd.randint(1, 5) if p > 5000
                        else rnd.randint(1, 15))
                desc = rnd.choices(*(DESCUENTOS_ALTOS if altos else DESCUENTOS_NORMAL))[0]
                precio = round(p / tc_del_dia(tc, d), 2) if moneda == "USD" else p
                lineas.append(dict(folio=f"F-{folio}", linea=num, fecha=d, cli=cli, sku=sku,
                                   cantidad=cant, precio=precio, desc=desc, moneda=moneda))
        d += timedelta(days=1)

    # Devoluciones (notas de crédito). Patrón plantado: URV-DT40 se devuelve mucho más.
    nc = 50000
    for ln in list(lineas):
        prob = 0.09 if ln["sku"] == "URV-DT40" else 0.012
        if ln["cantidad"] > 0 and rnd.random() < prob:
            f = ln["fecha"] + timedelta(days=rnd.randint(7, 40))
            if f <= FIN and f.weekday() != 6:
                nc += 1
                lineas.append(dict(ln, folio=f"NC-{nc}", linea=1, fecha=f,
                                   cantidad=-rnd.randint(1, ln["cantidad"])))
    lineas.sort(key=lambda x: (x["fecha"], x["folio"], x["linea"]))
    return lineas


# ---------------------------------------------------------------------------
# Ensuciar: formatos mezclados + defectos exclusivos contados
# ---------------------------------------------------------------------------
def fmt_fecha(d):
    r = rnd.random()
    if r < 0.70:
        return d.isoformat()
    if r < 0.90:
        return d.strftime("%d/%m/%Y")
    return f"{d.day}-{MESES_ES[d.month - 1]}-{d.year}"


def fmt_monto(x):
    r = rnd.random()
    if r < 0.40:
        return f"${x:,.2f}"
    if r < 0.70:
        return f"{x:.2f}"
    if r < 0.90:
        return f"{x:,.2f}"
    return f" {x:g} "


def fmt_desc(p):
    if p == 0:
        return rnd.choice(["", "", "0", "0%"])
    return rnd.choice([f"{p}%", f"{p / 100:.2f}", str(p)])


def fmt_rfc(r):
    x = rnd.random()
    if x < 0.12:
        return r.lower()
    if x < 0.17:
        return f"{r[:3]}-{r[3:9]}-{r[9:]}"
    if x < 0.20:
        return f" {r} "
    return r


def sku_anterior(cat, sku):
    return f"{MARCAS[cat[sku]['marca']].upper()}-{cat[sku]['modelo'].replace(' ', '').upper()}"


def ensuciar(lineas, cat):
    esperado = defaultdict(int)
    filas = []
    for ln in lineas:
        cli = ln["cli"]
        fila = {
            "folio": ln["folio"], "linea": str(ln["linea"]), "fecha": fmt_fecha(ln["fecha"]),
            "rfc_cliente": fmt_rfc(cli["rfc"]),
            "cliente": cli["nombre"].upper() if rnd.random() < .05 else cli["nombre"],
            "estado": rnd.choice(ESTADOS[cli["estado"]][2]),
            "almacen": rnd.choice(ALIAS_ALMACEN[cli["almacen"]]),
            "vendedor": cli["vendedor"].upper() if rnd.random() < .1 else cli["vendedor"],
            "sku": ln["sku"].lower() if rnd.random() < .06 else (f" {ln['sku']}" if rnd.random() < .03 else ln["sku"]),
            "descripcion": cat[ln["sku"]]["nombre"],
            "cantidad": str(ln["cantidad"]),
            "precio_unitario": fmt_monto(ln["precio"]),
            "descuento": fmt_desc(ln["desc"]),
            "moneda": rnd.choice(["USD", "usd", "Dólares"]) if ln["moneda"] == "USD"
                      else rnd.choice(["MXN", "MXN", "MXN", "mxn", "Pesos", "M.N."]),
        }
        defecto = None
        if ln["moneda"] == "MXN" and ln["cantidad"] > 0:
            r = rnd.random()
            if r < 0.004:
                defecto = "R02"
                fila["fecha"] = rnd.choice(["", "31/02/2026", "2025-13-05", "00/00/0000", "sin fecha"])
            elif r < 0.007:
                defecto = "R03"
                fila["sku"] = rnd.choice(["", "SUN-X9", "GENERICO", "ABC-123", "CL-9999"])
            elif r < 0.037:
                defecto = "R04"
                fila["sku"] = sku_anterior(cat, ln["sku"])
            elif r < 0.042:
                defecto = "R05"
                fila["cantidad"] = "0"
            elif r < 0.052:
                defecto = "R06"
                fila["precio_unitario"] = rnd.choice(["", "N/D", "-"])
            elif r < 0.055:
                defecto = "R07"
                fila["precio_unitario"] = fmt_monto(ln["precio"] * rnd.choice([10, 0.1]))
            elif r < 0.063:
                defecto = "R08"
                fila["rfc_cliente"] = rnd.choice(["", "XXX", "12345", "SIN RFC", cli["rfc"][:8]])
            elif r < 0.083:
                defecto = "R10"
                fila["moneda"] = ""
        if defecto:
            esperado[defecto] += 1
        if ln["moneda"] == "USD":
            esperado["R09"] += 1
        fila["_limpia"] = defecto is None and ln["moneda"] == "MXN"
        filas.append(fila)

    # R01: duplicados exactos (doble exportación) de filas sin otro defecto
    candidatas = [f for f in filas if f["_limpia"]]
    for f in rnd.sample(candidatas, round(len(filas) * 0.012)):
        pos = filas.index(f) + rnd.randint(1, 400)
        filas.insert(min(pos, len(filas)), dict(f))
        esperado["R01"] += 1
    for f in filas:
        f.pop("_limpia")
    return filas, esperado


# ---------------------------------------------------------------------------
# Inventario mensual y metas
# ---------------------------------------------------------------------------
def fin_de_mes(y, m):
    return (date(y + (m == 12), m % 12 + 1, 1) - timedelta(days=1))


def generar_inventario(lineas, cat):
    vendidas = defaultdict(int)          # (sku, almacén, año, mes) -> unidades
    for ln in lineas:
        if ln["cantidad"] > 0:
            vendidas[(ln["sku"], ln["cli"]["almacen"], ln["fecha"].year, ln["fecha"].month)] += ln["cantidad"]
    filas, y, m = [], 2024, 10
    while (y, m) <= (2026, 8):
        for sku in cat:
            for alm in ["CDMX", "GDL", "MTY"]:
                ult3 = []
                yy, mm = y, m
                for _ in range(3):
                    ult3.append(vendidas[(sku, alm, yy, mm)])
                    yy, mm = (yy, mm - 1) if mm > 1 else (yy - 1, 12)
                diaria = sum(ult3) / 90
                dias = rnd.uniform(35, 60)
                # Patrón plantado: Urovo se acumula en Monterrey durante 2026
                if cat[sku]["marca"] == 4 and alm == "MTY" and y == 2026:
                    dias = 60 + 28 * m
                exist = round(diaria * dias) if diaria > 0 else rnd.randint(0, 4)
                if rnd.random() < 0.01:          # fotos faltantes
                    continue
                filas.append({"mes": f"{y}-{m:02d}", "sku": sku, "almacen": alm, "existencia": exist})
        y, m = (y, m + 1) if m < 12 else (y + 1, 1)
    return filas


def generar_metas(lineas, cat, tc):
    real = defaultdict(float)            # (marca, año, mes) -> venta MXN
    for ln in lineas:
        mxn = ln["precio"] * (tc_del_dia(tc, ln["fecha"]) if ln["moneda"] == "USD" else 1)
        real[(MARCAS[cat[ln["sku"]]["marca"]], ln["fecha"].year, ln["fecha"].month)] += \
            ln["cantidad"] * mxn * (1 - ln["desc"] / 100)
    filas = []
    for marca in MARCAS.values():
        for y, m in [(2025, mm) for mm in range(1, 13)] + [(2026, mm) for mm in range(1, 10)]:
            if y == 2025:
                meta = real[(marca, y, m)] * rnd.uniform(0.95, 1.07)
            else:                                    # meta 2026 = mismo mes 2025 + 18 %
                meta = real[(marca, 2025, m)] * 1.18
            filas.append({"marca": marca, "mes": f"{y}-{m:02d}", "meta_mxn": int(round(meta, -3))})
    return filas


# ---------------------------------------------------------------------------
def escribir_csv(nombre, filas, campos, **kw):
    ruta = RAIZ / nombre
    enc = kw.pop("encoding", "utf-8")
    with open(ruta, "w", newline="", encoding=enc) as f:
        w = csv.DictWriter(f, fieldnames=campos, **kw)
        w.writeheader()
        w.writerows(filas)
    print(f"  {nombre:36s} {len(filas):>7,} filas")


def main():
    RAIZ.mkdir(parents=True, exist_ok=True)
    tc = generar_tipo_cambio()
    cat = construir_catalogo()
    clientes = generar_clientes()
    lineas = generar_ventas(cat, clientes, tc)
    filas, esperado = ensuciar(lineas, cat)

    print("Generando data/raw/ …")
    escribir_csv("ventas_erp.csv", filas, list(filas[0].keys()), lineterminator="\n")

    for version, desde, clave_costo, clave_precio in [
            ("2024-10", date(2024, 10, 1), "costo_v1", "precio_v1"),
            ("2026-04", CAMBIO_LISTA, "costo_v2", "precio_v2")]:
        filas_cat = [{
            "Marca": MARCAS[p["marca"]], "Codigo": sku, "Descripcion": p["nombre"],
            "Categoria": CATEGORIA_PROVEEDOR[p["marca"]][p["sub"]],
            "Costo": f"{p[clave_costo]:.2f}".replace(".", ","),
            "Moneda": MONEDA_COSTO[p["marca"]],
            "Precio_Lista_MXN": f"{p[clave_precio]:.2f}".replace(".", ","),
            "Vigente_Desde": desde.strftime("%d/%m/%Y")} for sku, p in cat.items()]
        escribir_csv(f"catalogo_proveedores_{version}.csv", filas_cat, list(filas_cat[0]),
                     delimiter=";", lineterminator="\r\n", encoding="cp1252")

    escribir_csv("equivalencias_sku.csv",
                 [{"codigo_anterior": sku_anterior(cat, s), "sku": s} for s in cat],
                 ["codigo_anterior", "sku"], lineterminator="\n")
    escribir_csv("tipo_cambio.csv",
                 [{"fecha": d.isoformat(), "tc_usd_mxn": f"{v:.4f}"} for d, v in sorted(tc.items())],
                 ["fecha", "tc_usd_mxn"], lineterminator="\n")
    escribir_csv("inventario_mensual.csv", generar_inventario(lineas, cat),
                 ["mes", "sku", "almacen", "existencia"], lineterminator="\n")
    escribir_csv("metas_ventas.csv", generar_metas(lineas, cat, tc),
                 ["marca", "mes", "meta_mxn"], lineterminator="\n")
    escribir_csv("_esperado_calidad.csv",
                 [{"regla": k, "filas": v} for k, v in sorted(esperado.items())],
                 ["regla", "filas"], lineterminator="\n")


if __name__ == "__main__":
    main()
