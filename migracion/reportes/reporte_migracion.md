# Reporte de migración

Generado: 2026-11-06 15:08  
Origen: hoja `Base De Datos` de `SEGUIMIENTO TEMPERAS Y VINILOS Actividad.xlsm`

## 1. Del Excel a las filas migradas

| Concepto | Cantidad |
|---|---|
| Filas en el Excel | 8,208 |
| Duplicados exactos (58 columnas iguales) | 42 |
| Duplicados descartados | 42 |
| **Registros a migrar** | **8,166** |
| Registros sin turno (días sin programación) | 4,218 |
| Paros generados (códigos con minutos > 0) | 16,482 |
| Celdas de código con 0 minutos (no son paros) | 55 |
| Paros con subcódigo | 3,584 |
| Empleados (seudonimizados) | 43 |
| Referencias | 51 |

## 2. Decisiones de limpieza

- **Duplicados:** 42 filas idénticas en las 58 columnas. 24 de ellas contienen paros (50 paros, 1087 minutos). Se descartaron (ver `descartes_duplicados.csv`).
- **Área y personal solo con código 05:** se descartó el área de 5,000 filas (valor por defecto de la macro, sin código 05) y el personal de 7 filas.
- **Numeración antigua del código 05 (4.x → 5.x):** 940 paros reasignados.
- **Corrección puntual** `1.4.3 SENSOR`: 1 paros.
- **Corrección puntual** `1.7A CAMBIO DE ROSCADORES`: 7 paros.
- **"Sin especificar"** en subcódigos se guarda como NULL.
- **"No aplica"** (turno, operario, referencia, tipo de paro) se guarda como NULL.
- **Horas/pacas vacías** se guardan como 0 (días sin producción).
- **Nombres de personas** reemplazados por seudónimos; la correspondencia queda fuera del repositorio.
- **Textos libres:** 2 observaciones nombraban personas y se enmascararon como `[persona]`.

## 4. Totales de control

| Indicador | Excel limpio | PostgreSQL | ¿Coincide? |
|---|---|---|---|
| Registros | 8,166 | 8,166 | ✅ |
| Paros | 16,482 | 16,482 | ✅ |
| Minutos de paro | 505,892.1 | 505,892.1 | ✅ |
| Horas trabajadas | 37,934.35 | 37,934.35 | ✅ |
| Pacas producidas | 377,759 | 377,759 | ✅ |
| Empleados | 43 | 43 | ✅ |
| Referencias | 51 | 51 | ✅ |
| Paros con subcódigo | 3,584 | 3,584 | ✅ |

**Resultado: los datos llegaron íntegros.**
