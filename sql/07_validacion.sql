-- =====================================================================
-- 07_validacion.sql  |  Evidencia de que los datos llegaron íntegros y de que el diseño se cumple
-- =====================================================================
SET search_path TO paros;

-- ---------------------------------------------------------------------
-- A. Chequeos automáticos (resultado OK / REVISAR)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS _chequeos;
CREATE TEMP TABLE _chequeos AS
SELECT orden, categoria, chequeo, esperado, obtenido,
       CASE WHEN ABS(obtenido - esperado) < 0.05 THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM (VALUES
    -- Conteos de filas
    ( 1, 'Conteo', 'registro_produccion (8208 filas Excel - 42 duplicados)',  8166::numeric, (SELECT COUNT(*) FROM registro_produccion)::numeric),
    ( 2, 'Conteo', 'paro (códigos con minutos > 0)',                         16482::numeric, (SELECT COUNT(*) FROM paro)::numeric),
    ( 3, 'Conteo', 'empleado (32 operarios + 11 mantenimiento)',                43::numeric, (SELECT COUNT(*) FROM empleado)::numeric),
    ( 4, 'Conteo', 'referencia',                                                51::numeric, (SELECT COUNT(*) FROM referencia)::numeric),
    ( 5, 'Conteo', 'area_impacto',                                               5::numeric, (SELECT COUNT(*) FROM area_impacto)::numeric),
    ( 6, 'Conteo', 'codigo_paro',                                               18::numeric, (SELECT COUNT(*) FROM codigo_paro)::numeric),
    ( 7, 'Conteo', 'subcodigo_paro',                                            47::numeric, (SELECT COUNT(*) FROM subcodigo_paro)::numeric),
    ( 8, 'Conteo', 'maquina',                                                    4::numeric, (SELECT COUNT(*) FROM maquina)::numeric),
    ( 9, 'Conteo', 'turno',                                                      6::numeric, (SELECT COUNT(*) FROM turno)::numeric),
    (10, 'Conteo', 'tipo_paro_jornada',                                         12::numeric, (SELECT COUNT(*) FROM tipo_paro_jornada)::numeric),
    -- Totales de control (sumas)
    (11, 'Total',  'minutos de paro',                                       505892.1::numeric, (SELECT SUM(minutos) FROM paro)),
    (12, 'Total',  'horas trabajadas',                                       37934.35::numeric, (SELECT SUM(horas_trabajadas) FROM registro_produccion)),
    (13, 'Total',  'horas no trabajadas',                                    41343.85::numeric, (SELECT SUM(horas_no_trabajadas) FROM registro_produccion)),
    (14, 'Total',  'pacas producidas',                                         377759::numeric, (SELECT SUM(pacas_producidas) FROM registro_produccion)::numeric),
    (15, 'Total',  'paros con subcódigo',                                        3584::numeric, (SELECT COUNT(*) FROM paro WHERE id_subcodigo IS NOT NULL)::numeric),
    (16, 'Total',  'paros con persona involucrada (solo código 05)',             1754::numeric, (SELECT COUNT(*) FROM paro WHERE id_empleado IS NOT NULL)::numeric),
    (17, 'Total',  'paros con área de atención (solo código 05)',                2898::numeric, (SELECT COUNT(*) FROM paro WHERE area_atencion IS NOT NULL)::numeric),
    (18, 'Total',  'registros sin turno',                                        4218::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE id_turno IS NULL)::numeric),
    (19, 'Total',  'registros sin operario',                                     4236::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE id_operario IS NULL)::numeric),
    (20, 'Total',  'registros con 0 horas trabajadas',                           3425::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE horas_trabajadas = 0)::numeric),
    -- Distribución por máquina y por año
    (21, 'Máquina', 'registros Vinilos_1',                                       1867::numeric, (SELECT COUNT(*) FROM registro_produccion r JOIN maquina m ON m.id_maquina = r.id_maquina WHERE m.nombre = 'Vinilos_1')::numeric),
    (22, 'Máquina', 'registros Vinilos_2',                                       1249::numeric, (SELECT COUNT(*) FROM registro_produccion r JOIN maquina m ON m.id_maquina = r.id_maquina WHERE m.nombre = 'Vinilos_2')::numeric),
    (23, 'Máquina', 'registros Vinilos_3',                                       2479::numeric, (SELECT COUNT(*) FROM registro_produccion r JOIN maquina m ON m.id_maquina = r.id_maquina WHERE m.nombre = 'Vinilos_3')::numeric),
    (24, 'Máquina', 'registros Vinilos_4',                                       2571::numeric, (SELECT COUNT(*) FROM registro_produccion r JOIN maquina m ON m.id_maquina = r.id_maquina WHERE m.nombre = 'Vinilos_4')::numeric),
    (25, 'Año', 'registros 2022',                                                1651::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE fecha BETWEEN DATE '2022-01-01' AND DATE '2022-12-31')::numeric),
    (26, 'Año', 'registros 2023',                                                2872::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE fecha BETWEEN DATE '2023-01-01' AND DATE '2023-12-31')::numeric),
    (27, 'Año', 'registros 2024',                                                3109::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE fecha BETWEEN DATE '2024-01-01' AND DATE '2024-12-31')::numeric),
    (28, 'Año', 'registros 2025 (hasta el 28 de marzo)',                          534::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE fecha BETWEEN DATE '2025-01-01' AND DATE '2025-12-31')::numeric),
    -- Integridad y reglas de negocio (todos deben dar 0)
    (29, 'Integridad', 'paros sin registro (huérfanos)',                            0::numeric, (SELECT COUNT(*) FROM paro p LEFT JOIN registro_produccion r ON r.id_registro = p.id_registro WHERE r.id_registro IS NULL)::numeric),
    (30, 'Integridad', 'registros sin máquina',                                     0::numeric, (SELECT COUNT(*) FROM registro_produccion r LEFT JOIN maquina m ON m.id_maquina = r.id_maquina WHERE m.id_maquina IS NULL)::numeric),
    (31, 'Integridad', 'paros con subcódigo de otro código',                        0::numeric, (SELECT COUNT(*) FROM paro p JOIN subcodigo_paro s ON s.id_subcodigo = p.id_subcodigo WHERE s.id_codigo <> p.id_codigo)::numeric),
    (32, 'Integridad', 'subcódigos cuyo padre es de otro código',                   0::numeric, (SELECT COUNT(*) FROM subcodigo_paro h JOIN subcodigo_paro pa ON pa.id_subcodigo = h.id_padre WHERE pa.id_codigo <> h.id_codigo)::numeric),
    (33, 'Integridad', 'paros con minutos <= 0',                                    0::numeric, (SELECT COUNT(*) FROM paro WHERE minutos <= 0)::numeric),
    (34, 'Integridad', 'registros con horas trabajadas fuera de 0-24',              0::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE horas_trabajadas < 0 OR horas_trabajadas > 24)::numeric),
    (35, 'Integridad', 'persona o área registradas fuera del código 05',            0::numeric, (SELECT COUNT(*) FROM paro WHERE id_codigo <> 5 AND (id_empleado IS NOT NULL OR area_atencion IS NOT NULL))::numeric),
    (36, 'Integridad', 'fechas fuera del rango 2022-01-01 a 2025-03-28',            0::numeric, (SELECT COUNT(*) FROM registro_produccion WHERE fecha < DATE '2022-01-01' OR fecha > DATE '2025-03-28')::numeric),
    (37, 'Integridad', 'empleados sin seudónimo (datos personales expuestos)',      0::numeric, (SELECT COUNT(*) FROM empleado WHERE nombre !~ '^(OPERARIO|MANTENIMIENTO)-[0-9]{3}$')::numeric),
    (38, 'Integridad', 'empleados cuyo seudónimo no coincide con su tipo',          0::numeric, (SELECT COUNT(*) FROM empleado WHERE (tipo = 'OPERARIO' AND nombre NOT LIKE 'OPERARIO-%') OR (tipo = 'MANTENIMIENTO' AND nombre NOT LIKE 'MANTENIMIENTO-%'))::numeric),
    (39, 'Integridad', 'empleados sin ningún registro ni paro asociado',            0::numeric, (SELECT COUNT(*) FROM empleado e WHERE NOT EXISTS (SELECT 1 FROM registro_produccion r WHERE r.id_operario = e.id_empleado) AND NOT EXISTS (SELECT 1 FROM paro p WHERE p.id_empleado = e.id_empleado))::numeric),
    (40, 'Integridad', 'referencias sin ningún registro asociado',                  0::numeric, (SELECT COUNT(*) FROM referencia f WHERE NOT EXISTS (SELECT 1 FROM registro_produccion r WHERE r.id_referencia = f.id_referencia))::numeric)
) AS t (orden, categoria, chequeo, esperado, obtenido);

SELECT orden, categoria, chequeo, esperado, obtenido, resultado
FROM _chequeos
ORDER BY orden;

-- Resumen: debe dar 40 chequeos, 40 OK, 0 por revisar
SELECT COUNT(*)                                       AS chequeos,
       COUNT(*) FILTER (WHERE resultado = 'OK')       AS ok,
       COUNT(*) FILTER (WHERE resultado = 'REVISAR')  AS por_revisar
FROM _chequeos;

DROP TABLE _chequeos;

-- ---------------------------------------------------------------------
-- B. Los indicadores de la BD reproducen los del Excel (tablas dinámicas TD_prodMaq y TD_prodCodigo)
-- ---------------------------------------------------------------------
-- B1. Productividad mensual de Vinilos_2 en 2024.
--     Esperado: 11 meses COINCIDE y noviembre DIFIERE en 0.10 puntos (62.35 vs 62.25), porque el Excel
--     cuenta dos veces un registro duplicado que la migración descartó.
WITH excel (mes, prod_excel) AS (
    VALUES (1, 67.935), (2, 57.572), (3, 59.299), (4, 44.392), (5, 48.640), (6, 45.721),
           (7, 76.223), (8, 74.877), (9, 70.158), (10, 72.210), (11, 62.249), (12, 58.591)
)
SELECT e.mes,
       e.prod_excel,
       v.productividad_pct                              AS prod_bd,
       ROUND(v.productividad_pct - e.prod_excel, 2)     AS dif_puntos,
       CASE WHEN ABS(v.productividad_pct - e.prod_excel) <= 0.01
            THEN 'COINCIDE' ELSE 'DIFIERE (duplicado descartado)' END AS estado
FROM excel e
JOIN v_productividad_maquina_mes v
  ON v.mes = e.mes AND v.maquina = 'Vinilos_2' AND v.anio = 2024
ORDER BY e.mes;

-- B2. Participación de los códigos de paro (Vinilos_2, 2024). Esperado: los 4 COINCIDEN (tolerancia 0.02).
WITH excel (id_codigo, pct_excel) AS (
    VALUES (16, 11.88), (6, 7.04), (5, 5.99), (7, 4.79)
)
SELECT e.id_codigo,
       v.codigo,
       e.pct_excel,
       v.pct_sobre_horas_trabajadas AS pct_bd,
       CASE WHEN ABS(v.pct_sobre_horas_trabajadas - e.pct_excel) <= 0.02 THEN 'COINCIDE' ELSE 'DIFIERE' END AS estado
FROM excel e
JOIN v_participacion_codigo v
  ON v.id_codigo = e.id_codigo AND v.maquina = 'Vinilos_2' AND v.anio = 2024
ORDER BY e.pct_excel DESC;

-- ---------------------------------------------------------------------
-- C. Inventario del diseño implementado
-- Esperado: 10 tablas, 5 vistas, 12 índices propios, 10 PK, 12 FK, 9 UNIQUE, 13 CHECK
-- ---------------------------------------------------------------------
SELECT objeto, cantidad
FROM (
    SELECT 1 AS orden, 'tablas'  AS objeto, COUNT(*) AS cantidad
      FROM information_schema.tables WHERE table_schema = 'paros' AND table_type = 'BASE TABLE'
    UNION ALL
    SELECT 2, 'vistas', COUNT(*) FROM information_schema.views WHERE table_schema = 'paros'
    UNION ALL
    SELECT 3, 'índices propios (idx_*)', COUNT(*) FROM pg_indexes WHERE schemaname = 'paros' AND indexname LIKE 'idx\_%'
    UNION ALL
    SELECT 4, 'llaves primarias (PK)', COUNT(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
      WHERE n.nspname = 'paros' AND c.contype = 'p'
    UNION ALL
    SELECT 5, 'llaves foráneas (FK)', COUNT(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
      WHERE n.nspname = 'paros' AND c.contype = 'f'
    UNION ALL
    SELECT 6, 'restricciones UNIQUE', COUNT(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
      WHERE n.nspname = 'paros' AND c.contype = 'u'
    UNION ALL
    SELECT 7, 'restricciones CHECK', COUNT(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
      WHERE n.nspname = 'paros' AND c.contype = 'c'
) t
ORDER BY orden;

-- ---------------------------------------------------------------------
-- D. Registros con atributos idénticos: ¿son duplicados?
-- Esperado: 385 grupos / 923 filas; en 383 grupos las filas se diferencian por sus paros (el Excel guarda
-- una fila por cada captura de subcódigo, botón "Ingreso subcódigo"), por eso NO existe un UNIQUE sobre
-- (fecha, máquina, turno, referencia). Solo 2 grupos son residuales.
-- ---------------------------------------------------------------------
WITH firma AS (
    SELECT r.fecha, r.id_maquina, r.id_turno, r.id_operario, r.id_referencia,
           r.horas_trabajadas, r.horas_no_trabajadas, r.pacas_producidas,
           r.id_tipo_paro, r.observacion_paro, r.observaciones,
           COALESCE((SELECT string_agg(p.id_codigo || ':' || COALESCE(p.id_subcodigo::text, '-') || ':' || p.minutos,
                                       ',' ORDER BY p.id_codigo, p.id_subcodigo, p.minutos)
                     FROM paro p WHERE p.id_registro = r.id_registro), 'sin paros') AS paros
    FROM registro_produccion r
), grupos AS (
    SELECT COUNT(*) AS filas, COUNT(DISTINCT paros) AS firmas_distintas
    FROM firma
    GROUP BY fecha, id_maquina, id_turno, id_operario, id_referencia, horas_trabajadas,
             horas_no_trabajadas, pacas_producidas, id_tipo_paro, observacion_paro, observaciones
    HAVING COUNT(*) > 1
)
SELECT COUNT(*)                                          AS grupos_identicos,
       SUM(filas)                                        AS filas_involucradas,
       COUNT(*) FILTER (WHERE firmas_distintas > 1)      AS grupos_con_paros_distintos,
       COUNT(*) FILTER (WHERE firmas_distintas = 1)      AS grupos_residuales
FROM grupos;

-- ---------------------------------------------------------------------
-- E. Uso de índices (evidencia para la sección de índices)
-- Con tablas pequeñas el planificador puede preferir un recorrido secuencial. Para mostrar que el índice
-- es utilizable se desactiva el recorrido secuencial SOLO dentro de esta transacción.
-- Buscar en el plan: "Index Scan using idx_registro_maquina_fecha" y "idx_paro_registro".
-- ---------------------------------------------------------------------
VACUUM (ANALYZE) registro_produccion;
VACUUM (ANALYZE) paro;

BEGIN;
SET LOCAL enable_seqscan = off;

EXPLAIN (ANALYZE, BUFFERS)
SELECT fecha, horas_trabajadas
FROM registro_produccion
WHERE id_maquina = (SELECT id_maquina FROM maquina WHERE nombre = 'Vinilos_2')
  AND fecha BETWEEN DATE '2024-01-01' AND DATE '2024-12-31';

EXPLAIN (ANALYZE, BUFFERS)
SELECT SUM(minutos) FROM paro WHERE id_registro = 1000;

ROLLBACK;
