# Base de datos de paros de producción: vinilos y témperas

Proyecto final de Bases de Datos I. Reemplaza el Excel con macros
(SEGUIMIENTO TEMPERAS Y VINILOS) por una base de datos relacional
normalizada para registrar los paros de producción de las líneas de
envasado Vinilos_1 a Vinilos_4.

## Autor
- Nombre Apellido: @DevMiguelBorja 

## Contexto y objetivo
Descripción breve del problema: proceso actual (formato "hora a hora"
→ Excel), por qué llegó a su límite y qué se busca (fuente única de
verdad que reproduzca y mejore los indicadores del procedimiento P-MTO-22).

## Motor y herramientas
- Motor: <PostgreSQL>
- Cliente: DBeaver
- Modelado: <Diagram.io>
- Migración: Python 3 (pandas)

## Estructura del repositorio
```
/docs         Secciones del informe (diagnóstico, reglas, normalización, diccionario)
/modelo       Diagramas MER y relacional
/sql          Scripts numerados, ejecutar en orden
/migracion    Script de limpieza y carga + validaciones
/consultas    Consultas de negocio
```

## Cómo reproducir la base de datos desde cero
1. Crear la base de datos vacía.
2. Ejecutar en orden:
   - `sql/01_ddl.sql` (esquema)
   - `sql/02_indices.sql`
   - `sql/03_vistas.sql`
   - `sql/04_catalogos.sql`
3. Migrar los datos históricos: `python migracion/migrar.py`
   (ver `migracion/README.md`).
4. Validar: `sql/05_validacion.sql` (conteos y totales vs. el Excel).

## Modelo de datos
Resumen del modelo y enlace a los diagramas en `/modelo`.

## Decisiones de diseño
- Granularidad del registro
- Tratamiento de días sin producción
- Normalización (hasta 3FN) y desnormalizaciones justificadas

## Manejo de datos personales
Cómo se tratan los nombres de operarios y personal de mantenimiento.

## Consultas de negocio
Lista de las consultas con una línea que explique qué pregunta responde.

## Estado del proyecto
- [x] Diagnóstico del Excel
- [x] Entidades y reglas de negocio
- [ ] Modelo conceptual (MER)
- [ ] Modelo relacional
- [ ] Normalización (1FN → 3FN)
- [ ] Diccionario de datos
- [ ] Script DDL, índices y vistas
- [ ] Carga de catálogos y migración
- [ ] Ejemplos INSERT / UPDATE / DELETE
- [ ] Consultas de negocio
- [ ] Informe PDF