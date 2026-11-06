
-- 03_vistas.sql  |  Vistas de negocio que reproducen los indicadores del Excel

SET search_path TO paros;

-- 1. Resumen por registro: horas de paro y productividad de cada turno.
CREATE OR REPLACE VIEW v_registro_resumen AS
SELECT r.id_registro,
       r.fecha,
       EXTRACT(YEAR  FROM r.fecha)::INT AS anio,
       EXTRACT(MONTH FROM r.fecha)::INT AS mes,
       m.nombre                         AS maquina,
       t.nombre                         AS turno,
       r.id_referencia,
       r.horas_trabajadas,
       COALESCE(p.minutos_paro, 0) / 60.0                          AS horas_paro,
       r.horas_trabajadas - COALESCE(p.minutos_paro, 0) / 60.0     AS horas_productivas,
       CASE WHEN r.horas_trabajadas > 0
            THEN ROUND((r.horas_trabajadas - COALESCE(p.minutos_paro, 0) / 60.0)
                       / r.horas_trabajadas * 100, 2)
       END                                                         AS productividad_pct,
       r.pacas_producidas
FROM registro_produccion r
JOIN maquina m       ON m.id_maquina = r.id_maquina
LEFT JOIN turno t    ON t.id_turno   = r.id_turno
LEFT JOIN (SELECT id_registro, SUM(minutos) AS minutos_paro
           FROM paro GROUP BY id_registro) p ON p.id_registro = r.id_registro;

-- 2. Productividad por máquina y mes (gráfico "Producción general / por máquina").
--    Misma fórmula que la tabla dinámica del Excel: 1 - SUM(horas de paro) / SUM(horas trabajadas),
--    sumando TODOS los registros (verificado contra TD_prodMaq: Vinilos_2, 2024).
CREATE OR REPLACE VIEW v_productividad_maquina_mes AS
SELECT anio, mes, maquina,
       SUM(horas_trabajadas)                                          AS horas_trabajadas,
       ROUND(SUM(horas_paro), 2)                                      AS horas_paro,
       ROUND(100 * SUM(horas_productivas) / NULLIF(SUM(horas_trabajadas), 0), 2) AS productividad_pct
FROM v_registro_resumen
GROUP BY anio, mes, maquina;

-- 3. Participación de cada código de paro sobre las horas trabajadas (gráfico "% Códigos de paro").
--    Verificado contra TD_prodCodigo (Vinilos_2, 2024): código 16 = 11,88 %, código 05 = 5,99 %.
CREATE OR REPLACE VIEW v_participacion_codigo AS
WITH base AS (
    SELECT EXTRACT(YEAR FROM fecha)::INT AS anio, id_maquina,
           SUM(horas_trabajadas) AS horas_trab
    FROM registro_produccion
    GROUP BY 1, 2
), paros AS (
    SELECT EXTRACT(YEAR FROM r.fecha)::INT AS anio, r.id_maquina, p.id_codigo,
           SUM(p.minutos) / 60.0 AS horas_paro
    FROM paro p
    JOIN registro_produccion r ON r.id_registro = p.id_registro
    GROUP BY 1, 2, 3
)
SELECT p.anio,
       m.nombre  AS maquina,
       c.id_codigo,
       c.nombre  AS codigo,
       ROUND(p.horas_paro, 2) AS horas_paro,
       ROUND(100 * p.horas_paro / NULLIF(b.horas_trab, 0), 2) AS pct_sobre_horas_trabajadas
FROM paros p
JOIN base b         ON b.anio = p.anio AND b.id_maquina = p.id_maquina
JOIN maquina m      ON m.id_maquina = p.id_maquina
JOIN codigo_paro c  ON c.id_codigo  = p.id_codigo;

-- 4. Detalle por subcódigo de los códigos 01, 03 y 05 (análisis detallado del P-MTO-22).
--    Los paros sin subcódigo aparecen como 'Sin especificar'. En el código 05 se separa por área.
CREATE OR REPLACE VIEW v_detalle_subcodigo AS
SELECT c.id_codigo,
       c.nombre                              AS codigo,
       COALESCE(s.clave,  'Sin especificar') AS subcodigo_clave,
       COALESCE(s.nombre, 'Sin especificar') AS subcodigo,
       p.area_atencion,
       COUNT(*)                              AS num_paros,
       ROUND(SUM(p.minutos) / 60.0, 2)       AS horas_paro,
       ROUND(100 * SUM(p.minutos) / SUM(SUM(p.minutos)) OVER (PARTITION BY c.id_codigo), 2) AS pct_del_codigo
FROM paro p
JOIN codigo_paro c           ON c.id_codigo = p.id_codigo
LEFT JOIN subcodigo_paro s   ON s.id_subcodigo = p.id_subcodigo
WHERE c.id_codigo IN (1, 3, 5)
GROUP BY c.id_codigo, c.nombre, s.clave, s.nombre, p.area_atencion;

-- 5. Control de calidad: registros cuyas horas de paro superan las horas trabajadas
--    (regla de negocio que no se puede expresar con un CHECK por involucrar varias filas).
CREATE OR REPLACE VIEW v_control_horas_paro AS
SELECT id_registro, fecha, maquina, turno, horas_trabajadas,
       ROUND(horas_paro, 2) AS horas_paro
FROM v_registro_resumen
WHERE horas_paro > horas_trabajadas;