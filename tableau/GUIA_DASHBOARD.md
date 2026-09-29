# Guía: construir y publicar el dashboard en Tableau Public

Tiempo estimado: **2 a 3 horas**. Al terminar tendrás un enlace público para el README y el CV.

> Esta parte la construyes tú en Tableau, porque es justo la habilidad que el proyecto demuestra. El pipeline ya te deja los datos limpios y los cálculos difíciles resueltos en SQL.

## 0. Preparación

1. Descarga **Tableau Public** (gratis) de <https://public.tableau.com> y crea una cuenta.
2. Usa los CSV de `data/tableau/`. Ya vienen en el repo, así que no necesitas correr el ETL para esta parte.

| Archivo | Grano | Para qué |
|---|---|---|
| `ventas.csv` | línea de factura / nota de crédito | KPIs, tendencias, mapa, vendedores, devoluciones |
| `margen_mensual.csv` | mes × marca × categoría | margen vs. tipo de cambio |
| `tipo_cambio.csv` | día | panel del tipo de cambio |
| `inventario.csv` | fin de mes × SKU × almacén | días de inventario |
| `metas.csv` | mes × marca | real vs. meta |
| `calidad.csv` y `reconciliacion.csv` | regla / estado | página de calidad de datos |

**Conexión:** *Conectar → A un archivo → Archivo de texto* y elige `ventas.csv`. Después agrega cada archivo como **fuente de datos separada** (*Datos → Nueva fuente de datos*). No los unas: tienen granos distintos y un JOIN duplicaría montos.

> Tableau suele "limpiar" los nombres de campo (`venta_neta_mxn` → *Venta Neta Mxn*). En las fórmulas usa el nombre tal como aparezca en tu panel de datos.

## 1. Campos calculados (fuente `ventas`)

```
Margen %            SUM([margen_mxn]) / SUM([venta_neta_mxn])
Ticket promedio     SUM([venta_neta_mxn]) / COUNTD([folio])
Descuento %         SUM([descuento_mxn]) / SUM([venta_bruta_mxn])
Unidades vendidas   SUM(IF [cantidad] > 0 THEN [cantidad] END)
Unidades devueltas  -SUM(IF [cantidad] < 0 THEN [cantidad] END)
Tasa de devolución  [Unidades devueltas] / [Unidades vendidas]
```

Fuente `inventario`:
```
Días de inventario  SUM([valor_inventario_mxn]) / (SUM([costo_venta_3m]) / 91)
```

Fuente `metas`:
```
Avance vs meta      SUM([venta_real_mxn]) / SUM([meta_mxn])
```

Da formato de **porcentaje con 1 decimal** a los campos `%`, y de **moneda (MXN)** a los montos.

**Crecimiento anual:** en la hoja de tendencia, clic derecho sobre `SUM(venta_neta_mxn)` → *Cálculo rápido de tabla → Crecimiento año tras año*.

## 2. Hojas de trabajo

| # | Hoja | Construcción |
|---|---|---|
| H1 | **KPIs** | Cuatro números grandes: Venta neta, Margen %, Facturas (`COUNTD(folio)` filtrado a FACTURA) y Ticket promedio. Un texto por hoja o una hoja con *Nombres de medidas*. |
| H2 | **Venta mensual vs. meta** | Fuente `metas`. Columnas: `anio_mes`. Barras: `SUM(venta_real_mxn)`. Línea: `SUM(meta_mxn)` como **gráfico combinado en el mismo eje** (ambas en MXN; arrastra la meta al eje existente para que comparta escala). Filtra `mes_en_curso = 0`. |
| H3 | **Venta por marca** | Barras horizontales ordenadas por venta; color por marca. |
| H4 | **Mapa por estado** | Doble clic en `estado` → rol geográfico *Estado/Provincia*. Color por venta (una sola gama, claro → oscuro). Si "Ciudad de México" no se reconoce: *Mapa → Editar ubicaciones* y asígnalo a mano. |
| H5 | **Margen % por moneda de costo** | Fuente `margen_mensual`. Líneas: `anio_mes` × `Margen %`, color por `moneda_costo`. |
| H6 | **Tipo de cambio** | Fuente `tipo_cambio`, `fecha` por mes × `AVG(tc_usd_mxn)`. Ponla **debajo de H5** con el mismo rango de meses. **No uses doble eje:** dos escalas en una misma gráfica confunden. Dos gráficas alineadas cuentan mejor la historia. |
| H7 | **Heatmap de margen** | Filas: `categoria`. Columnas: `anio_mes`. Color: `Margen %`, una sola gama. |
| H8 | **Días de inventario** | Fuente `inventario`, filtro `anio_mes = 2026-08`. Barras `marca · almacen` ordenadas; resalta en otro color las que pasen de 120 días (campo calculado `[Días de inventario] > 120`). |
| H9 | **Descuento por vendedor** | Barras de `Descuento %` por `vendedor`, con `Margen %` en la etiqueta. |
| H10 | **Top devoluciones** | Tabla o barras de `Tasa de devolución` por `sku`, filtro `Unidades vendidas ≥ 100`, top 10. |
| H11 | **Calidad de datos** | Fuente `calidad`: barras de `filas` por `regla`, color por `accion`. Aparte, `reconciliacion` como tabla de 4 renglones. |

## 3. Dashboards

Tamaño fijo **1200 × 800** para que se vea igual en cualquier pantalla.

1. **Resumen ejecutivo:** H1 arriba, H2 al centro, H3 y H4 abajo. Filtros de `anio` y `region` en una sola fila arriba, aplicados a todas las hojas de la fuente (*Aplicar a hojas de trabajo → Todas las que usan esta fuente*). Agrega una **acción de filtro**: al hacer clic en una marca de H3 se filtra H4.
2. **Rentabilidad:** H5 sobre H6 (mismo ancho), H7 abajo y H9 a la derecha. Título: *"El tipo de cambio se come el margen de las marcas importadas"*.
3. **Inventario y devoluciones:** H8 y H10.
4. **Calidad de datos:** H11, con un texto que explique el flujo *staging → reglas → cuarentena*.

Opcional: únelos en una **Historia** (*Nueva historia*) con un punto por hallazgo de `docs/insights.md`.

**Estilo:**
- Colores fijos por marca, los mismos en todas las hojas (*Editar colores* en la leyenda):

  | Marca | Color |
  |---|---|
  | SUNMI | `#2a78d6` |
  | CipherLab | `#eb6834` |
  | Custom | `#1baf7a` |
  | Urovo | `#eda100` |
  | Bluebird | `#e87ba4` |

- Títulos que digan **la conclusión** (por ejemplo "Bluebird va al 82 % de su meta"), no solo "Ventas por marca".
- Cuadrícula tenue, sin bordes y con etiquetas solo donde aporten.

## 4. Publicar

1. *Archivo → Guardar en Tableau Public como…*, inicia sesión y ponle un nombre, por ejemplo **"POS Sales Analytics"**.
2. En tu perfil de Tableau Public, abre el libro y copia el enlace.
3. Toma una captura del dashboard de resumen, guárdala como `docs/img/dashboard.png` y agrégala al README con el enlace:

```markdown
[![Dashboard](docs/img/dashboard.png)](https://public.tableau.com/app/profile/TU_USUARIO/viz/POSSalesAnalytics/Resumen)
```

4. Pon el mismo enlace en tu CV y en LinkedIn (sección *Destacado*).

> Todo lo que publicas en Tableau Public es público. Estos datos son sintéticos, así que no hay problema, pero **nunca subas datos reales de una empresa** a Tableau Public.
