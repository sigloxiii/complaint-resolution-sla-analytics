# Resumen ejecutivo

**Proyecto:** complaint-resolution-sla-analytics | **Autor:** Ing. Rafael Cansigno Peláez | **English:** [`executive_summary.md`](executive_summary.md)

## Objetivo

Medir cuánto tiempo esperan los consumidores para la resolución de sus quejas contra proveedores de banda ancha fija en México, qué proveedores son los más lentos y cómo cambió esto con el tiempo, usando datos abiertos del gobierno. La PROFECO, la agencia de protección al consumidor, no tiene una meta oficial de nivel de servicio para el proceso de conciliación, así que las metas se tratan como parámetros y se evalúan con un análisis de sensibilidad.

## Datos y método

- **Fuentes:** 36,034 quejas de telecomunicaciones de la PROFECO (CC BY 4.0) y 592,281 filas de accesos de banda ancha fija del BIT de la CRT, usadas como denominadores.
- **Pipeline:** SQL Server en tres capas (`stg` → `clean` → `mart`), con scripts T-SQL documentados y re-ejecutables, banderas de calidad en lugar de filas eliminadas y un esquema en estrella con dos tablas de hechos (quejas y accesos) y seis dimensiones.
- **Reporte:** Power BI (modo Import) con 26 medidas DAX, cada una validada contra una consulta SQL independiente, y un reporte de seis páginas.
- **Alcance:** 13,358 quejas de banda ancha fija; 12,833 casos de conciliación con duración válida para los resultados de tiempo y de desenlace. El eje temporal es el año de ingreso (2022 a 2024 son cohortes completas).

## Hallazgos principales

1. **Telmex es el operador más lento:** mediana de 70 días para cerrar y P90 de 225, frente a medianas de 24 a 35 días en Megacable, Total Play e Izzi. En 60 días cierra el 44% de los casos de Telmex y entre 71% y 81% de los demás.
2. **Tres tipos de reclamo concentran el 92.5% de las quejas:** cobro indebido, entrega del producto o servicio y contratos.
3. **La tasa de conciliación cae de 68.1% (2022) a 60.2% (2025)**, por los desistimientos, que pasan de 24.8% a 34.8% de los casos. Entre los casos decididos, la proporción se mantiene cerca de 91%.
4. **Velocidad y resultado no van juntos:** Telmex es el más lento pero tiene una tasa de conciliación de 67.7%; Total Play cierra rápido y tiene la tasa más baja (60.2%).
5. **Las quejas por cada 100,000 accesos bajan de 16.60 (2022) a 9.33 (2024)** a nivel nacional.
6. **Total Play tuvo un pico de abril a julio de 2025** (503 casos frente a 200 un año antes), 91% en dos tipos de reclamo. Los datos no muestran la causa.

## Limitaciones

El archivo solo contiene casos cerrados, por lo que los meses recientes están incompletos; el estado es la oficina de la PROFECO y no el lugar del consumidor (el 58% de las quejas aparece en Ciudad de México); la tasa por 100,000 accesos es nacional y se limita a 2022 a 2024; la duración es la del procedimiento de la PROFECO, no el tiempo de reparación del proveedor; y los resultados describen asociaciones, no causas. El BIT no tiene una licencia explícita, por lo que solo se publican agregados.

## Entregables

| Elemento | Ubicación |
|---|---|
| Reporte (6 páginas, PDF) | `powerbi/complaint_sla_report.pdf` |
| Pipeline SQL (pasos 0 a 8) | `sql/` |
| Decisiones D1 a D16, bitácora con evidencia | `docs/decisions.md`, `docs/run_log.md` |
| Diccionario de datos y glosario | `data/data_dictionary.md`, `docs/glossary_of_terms.md` |
| README completo con pasos de reproducción | `README.md` ([Español](../README.es.md)) |

## Habilidades demostradas

Pipeline SQL por capas y limpieza de datos; modelado dimensional; DAX (medidas, contexto de filtro, relaciones inactivas, tablas de parámetros); validación de cada medida contra SQL; tratamiento honesto de la censura y de las limitaciones de los datos; documentación de decisiones y de licencias.