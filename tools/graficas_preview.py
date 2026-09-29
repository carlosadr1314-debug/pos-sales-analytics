#!/usr/bin/env python3
"""
Genera las gráficas de vista previa de docs/img/ a partir de data/tableau/*.csv.
Son una referencia estática para el README; el dashboard real vive en Tableau.

Requiere: pip install matplotlib
"""
import csv
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

RAIZ = Path(__file__).resolve().parents[1]
DATOS = RAIZ / "data" / "tableau"
SALIDA = RAIZ / "docs" / "img"

# Paleta categórica validada (orden fijo) + tokens de texto/superficie
AZUL, NARANJA, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
GRIS = "#b9b8b3"
SUPERFICIE, TEXTO, TEXTO_2, REJILLA = "#fcfcfb", "#0b0b0b", "#52514e", "#e6e5e1"

plt.rcParams.update({
    "figure.facecolor": SUPERFICIE, "axes.facecolor": SUPERFICIE,
    "axes.edgecolor": REJILLA, "axes.labelcolor": TEXTO_2, "text.color": TEXTO,
    "xtick.color": TEXTO_2, "ytick.color": TEXTO_2, "font.size": 10,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.color": REJILLA, "grid.linewidth": 0.8,
    "axes.titleweight": "bold", "axes.titlesize": 12, "axes.titlelocation": "left",
})


def leer(nombre):
    with open(DATOS / f"{nombre}.csv", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def millones(x, _):
    return f"${x / 1e6:,.0f} M"


def guardar(fig, nombre):
    fig.tight_layout()
    fig.savefig(SALIDA / nombre, dpi=160)
    plt.close(fig)
    print(f"  docs/img/{nombre}")


# 1) Venta real vs. meta -------------------------------------------------
def venta_vs_meta():
    real, meta = defaultdict(float), defaultdict(float)
    for r in leer("metas"):
        if r["mes_en_curso"] == "0":
            real[r["anio_mes"]] += float(r["venta_real_mxn"])
            meta[r["anio_mes"]] += float(r["meta_mxn"])
    meses = sorted(real)
    x = range(len(meses))
    fig, ax = plt.subplots(figsize=(10, 4.2))
    ax.bar(x, [real[m] for m in meses], width=0.7, color=AZUL, label="Venta real", zorder=2)
    ax.plot(x, [meta[m] for m in meses], color=NARANJA, linewidth=2, marker="o",
            markersize=5, label="Meta", zorder=3)
    ax.set_xticks(list(x), [m[2:] for m in meses], rotation=0, fontsize=8)
    ax.yaxis.set_major_formatter(FuncFormatter(millones))
    ax.grid(axis="x", visible=False)
    ax.set_title("Venta neta mensual vs. meta (todas las marcas)")
    ax.legend(frameon=False, loc="upper left")
    guardar(fig, "venta_vs_meta.png")


# 2) Margen por moneda de costo y tipo de cambio (dos paneles, un eje c/u)
def margen_vs_tc():
    venta, margen = defaultdict(float), defaultdict(float)
    tc = {}
    for r in leer("margen_mensual"):
        k = (r["anio_mes"], r["moneda_costo"])
        venta[k] += float(r["venta_neta_mxn"])
        margen[k] += float(r["margen_mxn"])
        tc[r["anio_mes"]] = float(r["tc_promedio_mes"])
    meses = sorted(tc)
    x = range(len(meses))
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(10, 5.6), sharex=True,
                                 gridspec_kw={"height_ratios": [3, 2]})
    for moneda, color, etiqueta in [("MXN", AQUA, "Costo en MXN (Custom)"),
                                    ("USD", AZUL, "Costo en USD (SUNMI, Bluebird, CipherLab, Urovo)")]:
        serie = [100 * margen[(m, moneda)] / venta[(m, moneda)] for m in meses]
        a1.plot(x, serie, color=color, linewidth=2, label=etiqueta)
        a1.annotate(f"{serie[-1]:.1f} %", (len(meses) - 1, serie[-1]), xytext=(6, 0),
                    textcoords="offset points", va="center", color=TEXTO, fontsize=9)
    a1.axvline(meses.index("2026-04"), color=GRIS, linestyle="--", linewidth=1)
    a1.text(meses.index("2026-04") + 0.2, a1.get_ylim()[0] + 0.5, "Lista de precios 2026",
            color=TEXTO_2, fontsize=8)
    a1.set_ylabel("Margen bruto %")
    a1.set_title("El margen de las marcas con costo en dólares cae cuando sube el tipo de cambio")
    a1.legend(frameon=False, loc="lower left", fontsize=9)
    a2.plot(x, [tc[m] for m in meses], color=NARANJA, linewidth=2)
    a2.set_ylabel("TC USD/MXN")
    a2.set_xticks(list(x), [m[2:] for m in meses], fontsize=8)
    guardar(fig, "margen_vs_tipo_cambio.png")


# 3) Días de inventario (agosto 2026) ------------------------------------
def dias_inventario():
    valor, costo = defaultdict(float), defaultdict(float)
    for r in leer("inventario"):
        if r["anio_mes"] == "2026-08":
            k = f"{r['marca']} · {r['almacen'].replace('Almacén ', '').replace('CEDIS ', '')}"
            valor[k] += float(r["valor_inventario_mxn"])
            costo[k] += float(r["costo_venta_3m"] or 0)
    dias = {k: valor[k] / (costo[k] / 91) for k in valor if costo[k] > 0}
    orden = sorted(dias, key=dias.get)[-10:]
    fig, ax = plt.subplots(figsize=(8, 4.4))
    colores = [NARANJA if dias[k] > 120 else GRIS for k in orden]
    ax.barh(orden, [dias[k] for k in orden], color=colores, height=0.65, zorder=2)
    for i, k in enumerate(orden):
        ax.text(dias[k] + 4, i, f"{dias[k]:.0f} días", va="center", fontsize=9, color=TEXTO)
    ax.grid(axis="y", visible=False)
    ax.set_xlabel("Días de inventario (valor / costo de venta diario, últimos 3 meses)")
    ax.set_title("Urovo en Monterrey: ~6 veces más inventario que el resto")
    guardar(fig, "dias_inventario.png")


# 4) Calidad de datos ----------------------------------------------------
def calidad():
    filas = leer("calidad")
    colores = {"DESCARTADO": NARANJA, "CUARENTENA": AZUL, "CORREGIDO": AQUA}
    filas = sorted(filas, key=lambda r: int(r["filas"]))
    fig, ax = plt.subplots(figsize=(8, 4.4))
    corto = {"R01": "Fila duplicada", "R02": "Fecha inválida", "R03": "SKU inexistente",
             "R04": "SKU con código anterior", "R05": "Cantidad en cero", "R06": "Precio faltante",
             "R07": "Precio atípico", "R08": "RFC inválido", "R09": "Venta en USD",
             "R10": "Moneda vacía"}
    etiquetas = [f"{r['regla']} · {corto[r['regla']]}" for r in filas]
    ax.barh(etiquetas, [int(r["filas"]) for r in filas],
            color=[colores[r["accion"]] for r in filas], height=0.65, zorder=2)
    for i, r in enumerate(filas):
        ax.text(int(r["filas"]) + 12, i, f"{int(r['filas']):,}", va="center", fontsize=9, color=TEXTO)
    ax.grid(axis="y", visible=False)
    ax.set_xlim(0, max(int(r["filas"]) for r in filas) * 1.12)
    from matplotlib.patches import Patch
    ax.legend(handles=[Patch(color=c, label=a.capitalize()) for a, c in colores.items()],
              frameon=False, loc="lower right")
    ax.set_title("Incidencias detectadas en ventas_erp.csv (38,873 filas)")
    guardar(fig, "calidad_datos.png")


if __name__ == "__main__":
    SALIDA.mkdir(parents=True, exist_ok=True)
    print("Generando gráficas:")
    venta_vs_meta()
    margen_vs_tc()
    dias_inventario()
    calidad()
