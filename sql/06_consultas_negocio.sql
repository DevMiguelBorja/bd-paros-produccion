-- =====================================================================
-- 06_consultas_negocio.sql  |  Consultas que responden preguntas reales del negocio
-- Ejecutar cada consulta por separado (selecciónela y pulse Ctrl+Enter) conectado a paros_produccion.
-- Productividad = 1 - horas de paro / horas trabajadas (misma fórmula que las tablas dinámicas del Excel).
-- Los valores "esperado" corresponden a la carga LIMPIA (sin los 42 duplicados exactos).
--
-- Técnicas usadas:
--   JOIN interno ........ Q1, Q4, Q8, Q9, Q10, Q11, Q16, Q17
--   LEFT JOIN ........... Q4, Q13, Q14, Q17
--   CROSS JOIN .......... Q14
--   Autojoin ............ Q7
--   NOT EXISTS (anti) ... Q15
--   GROUP BY / HAVING ... Q1 a Q18 (HAVING en Q3, Q16)
--   Subconsultas ........ Q4 (escalar), Q12 (correlacionada), Q1/Q8/Q16 (derivada), CTE en Q2, Q9, Q10
--   Ventanas ............ Q4, Q6, Q7, Q9, Q10
--   Rangos de fechas .... Q1, Q2, Q14, Q15
-- =====================================================================
SET search_path TO paros;

-- ---------------------------------------------------------------------
-- Q1. ¿Cuál fue el % de productividad de cada máquina en cada mes de 2024?
-- Esperado Vinilos_2: 67.93, 57.57, 59.30, 44.39, 48.64, 45.72, 76.22, 74.88, 70.16, 72.21, 62.35, 58.59
-- (el Excel da 62.25 en noviembre porque cuenta dos veces un registro duplicado)
-- ---------------------------------------------------------------------
SELECT m.nombre                                   AS maquina,
       EXTRACT(MONTH FROM r.fecha)::INT           AS mes,
       SUM(r.horas_trabajadas)                    AS horas_trabajadas,
       ROUND(SUM(COALESCE(p.min_paro, 0)) / 60.0, 2) AS horas_paro,
       ROUND(100 * (1 - SUM(COALESCE(p.min_paro, 0)) / 60.0
                        / NULLIF(SUM(r.horas_trabajadas), 0)), 2) AS productividad_pct
FROM registro_produccion r
JOIN maquina m ON m.id_maquina = r.id_maquina
LEFT JOIN (SELECT id_registro, SUM(minutos) AS min_paro
           FROM paro GROUP BY id_registro) p ON p.id_registro = r.id_registro
WHERE r.fecha BETWEEN DATE '2024-01-01' AND DATE '2024-12-31'
GROUP BY 1, 2
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- Q2. Comparativo entre años: productividad general por mes, 2024 vs 2025.
-- Esperado: ene 73.91 / 70.31 / -3.60 ; feb 72.56 / 73.93 / 1.37 ; mar 66.31 / 60.69 / -5.62 ;
--           abr 69.53 / NULL (los datos de 2025 terminan el 28 de marzo)
-- ---------------------------------------------------------------------
WITH mensual AS (
    SELECT mes,
           100 * (1 - SUM(horas_paro) FILTER (WHERE anio = 2024)
                      / NULLIF(SUM(horas_trabajadas) FILTER (WHERE anio = 2024), 0)) AS prod_2024,
           100 * (1 - SUM(horas_paro) FILTER (WHERE anio = 2025)
                      / NULLIF(SUM(horas_trabajadas) FILTER (WHERE anio = 2025), 0)) AS prod_2025
    FROM v_registro_resumen
    WHERE fecha BETWEEN DATE '2024-01-01' AND DATE '2025-12-31'
    GROUP BY mes
)
SELECT mes,
       ROUND(prod_2024, 2)             AS prod_2024,
       ROUND(prod_2025, 2)             AS prod_2025,
       ROUND(prod_2025 - prod_2024, 2) AS dif_puntos
FROM mensual
ORDER BY mes;

-- ---------------------------------------------------------------------
-- Q3. Evolución anual de la productividad por máquina (2022 a 2025).
-- Esperado: Vinilos_1 89.71 / 76.09 / 65.64 / 74.14 ; Vinilos_2 81.43 / 69.59 / 62.49 / 57.15
--           Vinilos_3 88.80 / 82.36 / 76.16 / 67.59 ; Vinilos_4 87.52 / 81.58 / 76.91 / 73.70
-- ---------------------------------------------------------------------
SELECT maquina,
       ROUND(100 * SUM(horas_productivas) FILTER (WHERE anio = 2022) / NULLIF(SUM(horas_trabajadas) FILTER (WHERE anio = 2022), 0), 2) AS "2022",
       ROUND(100 * SUM(horas_productivas) FILTER (WHERE anio = 2023) / NULLIF(SUM(horas_trabajadas) FILTER (WHERE anio = 2023), 0), 2) AS "2023",
       ROUND(100 * SUM(horas_productivas) FILTER (WHERE anio = 2024) / NULLIF(SUM(horas_trabajadas) FILTER (WHERE anio = 2024), 0), 2) AS "2024",
       ROUND(100 * SUM(horas_productivas) FILTER (WHERE anio = 2025) / NULLIF(SUM(horas_trabajadas) FILTER (WHERE anio = 2025), 0), 2) AS "2025"
FROM v_registro_resumen
GROUP BY maquina
HAVING SUM(horas_trabajadas) > 0
ORDER BY maquina;

-- ---------------------------------------------------------------------
-- Q4. Participación porcentual de cada código de paro (todas las máquinas y años).
-- Se muestra sobre las horas trabajadas (como el gráfico del P-MTO-22) y sobre el total de paros.
-- Esperado: [16] 2000.22 h / 5.27 % / 23.72 % ; [05] 1813.69 / 4.78 / 21.51 ; [06] 1545.82 / 4.07 / 18.33 ;
--           [17] 713.15 / 1.88 / 8.46 ; [07] 620.81 / 1.64 / 7.36   (horas trabajadas totales: 37934.35)
-- ---------------------------------------------------------------------
SELECT c.id_codigo,
       c.nombre                                                            AS codigo,
       ROUND(SUM(COALESCE(p.minutos, 0)) / 60.0, 2)                        AS horas_paro,
       ROUND(100 * SUM(COALESCE(p.minutos, 0)) / 60.0
             / (SELECT SUM(horas_trabajadas) FROM registro_produccion), 2) AS pct_sobre_horas_trabajadas,
       ROUND(100 * SUM(COALESCE(p.minutos, 0))
             / SUM(SUM(COALESCE(p.minutos, 0))) OVER (), 2)                AS pct_del_total_de_paros
FROM codigo_paro c
LEFT JOIN paro p ON p.id_codigo = c.id_codigo
GROUP BY c.id_codigo, c.nombre
ORDER BY horas_paro DESC;

-- ---------------------------------------------------------------------
-- Q5. Participación por código en una máquina y año concretos (gráfico "% Códigos de paro").
-- Referencia del Excel (Vinilos_2, 2024): [16] 11.88 ; [06] 7.04 ; [05] 5.99 ; [07] 4.79
-- (con la carga limpia pueden variar en centésimas por los duplicados)
-- ---------------------------------------------------------------------
SELECT id_codigo, codigo, horas_paro, pct_sobre_horas_trabajadas
FROM v_participacion_codigo
WHERE maquina = 'Vinilos_2' AND anio = 2024
ORDER BY pct_sobre_horas_trabajadas DESC;

-- ---------------------------------------------------------------------
-- Q6. Detalle por subcódigo de los códigos 01, 03 y 05 (análisis detallado del P-MTO-22).
-- En el código 05 se separa por área (operarios / mantenimiento).
-- ---------------------------------------------------------------------
SELECT id_codigo, subcodigo_clave, subcodigo, area_atencion, num_paros, horas_paro, pct_del_codigo
FROM v_detalle_subcodigo
ORDER BY id_codigo, horas_paro DESC;

-- ---------------------------------------------------------------------
-- Q7. Código 01 agrupado por SISTEMA (autojoin: el componente 1.2.B se suma a su sistema 1.2).
-- Esperado: 1.2 Sistema de dosificación 116.67 h (36.34 %) ; 1.7 57.53 h (17.92 %) ;
--           1.4 36.53 h (11.38 %) ; 1.1 36.22 h (11.28 %)
-- ---------------------------------------------------------------------
SELECT COALESCE(pa.clave,  s.clave)  AS sistema_clave,
       COALESCE(pa.nombre, s.nombre) AS sistema,
       COUNT(*)                      AS num_paros,
       ROUND(SUM(p.minutos) / 60.0, 2) AS horas_paro,
       ROUND(100 * SUM(p.minutos) / SUM(SUM(p.minutos)) OVER (), 2) AS pct_codigo_01
FROM paro p
JOIN subcodigo_paro s       ON s.id_subcodigo = p.id_subcodigo
LEFT JOIN subcodigo_paro pa ON pa.id_subcodigo = s.id_padre
WHERE p.id_codigo = 1
GROUP BY COALESCE(pa.clave, s.clave), COALESCE(pa.nombre, s.nombre)
ORDER BY horas_paro DESC;

-- ---------------------------------------------------------------------
-- Q8. Comparación del desempeño entre turnos (solo registros con turno asignado).
-- Esperado (productividad): Turno 3 74.36 ; Turno 2 72.76 ; Turno 1 70.30 ; Especial 6am-4:30pm 60.26 ;
--                           Especial 6am-6pm 59.28 ; Especial 6pm-6am 67.93
-- ---------------------------------------------------------------------
SELECT t.nombre                           AS turno,
       COUNT(*)                           AS registros,
       SUM(r.horas_trabajadas)            AS horas_trabajadas,
       SUM(r.pacas_producidas)            AS pacas,
       ROUND(SUM(r.pacas_producidas) / NULLIF(SUM(r.horas_trabajadas), 0), 1) AS pacas_por_hora,
       ROUND(100 * (1 - SUM(COALESCE(p.min_paro, 0)) / 60.0
                        / NULLIF(SUM(r.horas_trabajadas), 0)), 2)             AS productividad_pct
FROM registro_produccion r
JOIN turno t ON t.id_turno = r.id_turno
LEFT JOIN (SELECT id_registro, SUM(minutos) AS min_paro
           FROM paro GROUP BY id_registro) p ON p.id_registro = r.id_registro
GROUP BY t.nombre
ORDER BY productividad_pct DESC;

-- ---------------------------------------------------------------------
-- Q9. Las 3 principales causas de paro de cada turno (función de ventana ROW_NUMBER).
-- ---------------------------------------------------------------------
WITH horas AS (
    SELECT t.nombre AS turno, c.nombre AS codigo, SUM(p.minutos) / 60.0 AS horas_paro
    FROM paro p
    JOIN registro_produccion r ON r.id_registro = p.id_registro
    JOIN turno t               ON t.id_turno    = r.id_turno
    JOIN codigo_paro c         ON c.id_codigo   = p.id_codigo
    GROUP BY t.nombre, c.nombre
), ranking AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY turno ORDER BY horas_paro DESC) AS puesto
    FROM horas
)
SELECT turno, puesto, codigo, ROUND(horas_paro, 2) AS horas_paro
FROM ranking
WHERE puesto <= 3
ORDER BY turno, puesto;

-- ---------------------------------------------------------------------
-- Q10. Pareto de causas: ¿qué códigos concentran el 80 % de las horas perdidas?
-- ---------------------------------------------------------------------
WITH causas AS (
    SELECT c.id_codigo, c.nombre, SUM(p.minutos) / 60.0 AS horas
    FROM paro p
    JOIN codigo_paro c ON c.id_codigo = p.id_codigo
    GROUP BY c.id_codigo, c.nombre
)
SELECT id_codigo, nombre AS codigo, ROUND(horas, 2) AS horas_paro,
       ROUND(100 * horas / SUM(horas) OVER (), 2)                              AS pct,
       ROUND(100 * SUM(horas) OVER (ORDER BY horas DESC) / SUM(horas) OVER (), 2) AS pct_acumulado
FROM causas
ORDER BY horas DESC;

-- ---------------------------------------------------------------------
-- Q11. Horas de paro por área de impacto y año: ¿quién "pierde" más tiempo?
-- Esperado (total): Producción 4595.7 ; Paro programado 2886.4 ; Mantenimiento 450.2 ;
--                   Almacén de materias primas 253.5 ; Calidad 245.8
-- ---------------------------------------------------------------------
SELECT a.nombre                          AS area,
       EXTRACT(YEAR FROM r.fecha)::INT   AS anio,
       ROUND(SUM(p.minutos) / 60.0, 1)   AS horas_paro
FROM paro p
JOIN registro_produccion r ON r.id_registro = p.id_registro
JOIN codigo_paro c         ON c.id_codigo   = p.id_codigo
JOIN area_impacto a        ON a.id_area     = c.id_area
GROUP BY a.nombre, 2
ORDER BY a.nombre, 2;

-- ---------------------------------------------------------------------
-- Q12. Meses de 2024 en que cada máquina estuvo por debajo de su propio promedio anual
-- (subconsulta correlacionada).
-- ---------------------------------------------------------------------
SELECT v.maquina, v.mes, v.productividad_pct,
       (SELECT ROUND(AVG(x.productividad_pct), 2)
        FROM v_productividad_maquina_mes x
        WHERE x.maquina = v.maquina AND x.anio = 2024) AS promedio_maquina_2024
FROM v_productividad_maquina_mes v
WHERE v.anio = 2024
  AND v.productividad_pct < (SELECT AVG(x.productividad_pct)
                             FROM v_productividad_maquina_mes x
                             WHERE x.maquina = v.maquina AND x.anio = 2024)
ORDER BY v.maquina, v.mes;

-- ---------------------------------------------------------------------
-- Q13. Registros sin horas trabajadas: ¿por qué no se produjo?
-- Esperado: 3425 registros con horas_trabajadas = 0, de los cuales 1855 tienen tipo de paro registrado.
-- ---------------------------------------------------------------------
SELECT COALESCE(t.nombre, 'Sin tipo registrado') AS tipo_paro_jornada,
       COUNT(*)                                  AS registros,
       ROUND(SUM(r.horas_no_trabajadas), 0)      AS horas_no_trabajadas
FROM registro_produccion r
LEFT JOIN tipo_paro_jornada t ON t.id_tipo_paro = r.id_tipo_paro
WHERE r.horas_trabajadas = 0
GROUP BY COALESCE(t.nombre, 'Sin tipo registrado')
ORDER BY registros DESC;

-- ---------------------------------------------------------------------
-- Q14. Matriz máquina x código de paro en 2024, incluyendo combinaciones SIN paros (CROSS JOIN + LEFT JOIN).
-- Se limita a los códigos 05, 06, 07 y 16 para que sea legible.
-- ---------------------------------------------------------------------
SELECT m.nombre AS maquina, c.id_codigo, c.nombre AS codigo,
       ROUND(COALESCE(x.horas, 0), 2) AS horas_paro
FROM maquina m
CROSS JOIN codigo_paro c
LEFT JOIN (SELECT r.id_maquina, p.id_codigo, SUM(p.minutos) / 60.0 AS horas
           FROM paro p
           JOIN registro_produccion r ON r.id_registro = p.id_registro
           WHERE r.fecha BETWEEN DATE '2024-01-01' AND DATE '2024-12-31'
           GROUP BY r.id_maquina, p.id_codigo) x
       ON x.id_maquina = m.id_maquina AND x.id_codigo = c.id_codigo
WHERE c.id_codigo IN (5, 6, 7, 16)
ORDER BY c.id_codigo, m.nombre;

-- ---------------------------------------------------------------------
-- Q15. ¿Qué códigos de paro NO ocurrieron en Vinilos_2 durante 2025? (anti-join con NOT EXISTS)
-- Esperado: códigos 02, 03, 04 y 13
-- ---------------------------------------------------------------------
SELECT c.id_codigo, c.nombre
FROM codigo_paro c
WHERE NOT EXISTS (
    SELECT 1
    FROM paro p
    JOIN registro_produccion r ON r.id_registro = p.id_registro
    JOIN maquina m             ON m.id_maquina  = r.id_maquina
    WHERE p.id_codigo = c.id_codigo
      AND m.nombre = 'Vinilos_2'
      AND r.fecha BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
)
ORDER BY c.id_codigo;

-- ---------------------------------------------------------------------
-- Q16. Rendimiento por marca: pacas por hora y productividad (solo marcas con al menos 500 horas).
-- ---------------------------------------------------------------------
SELECT ref.marca,
       COUNT(*)                                AS registros,
       ROUND(SUM(r.horas_trabajadas), 1)       AS horas_trabajadas,
       SUM(r.pacas_producidas)                 AS pacas,
       ROUND(SUM(r.pacas_producidas) / NULLIF(SUM(r.horas_trabajadas), 0), 1) AS pacas_por_hora,
       ROUND(100 * (1 - SUM(COALESCE(p.min_paro, 0)) / 60.0
                        / NULLIF(SUM(r.horas_trabajadas), 0)), 2)             AS productividad_pct
FROM registro_produccion r
JOIN referencia ref ON ref.id_referencia = r.id_referencia
LEFT JOIN (SELECT id_registro, SUM(minutos) AS min_paro
           FROM paro GROUP BY id_registro) p ON p.id_registro = r.id_registro
WHERE ref.marca IS NOT NULL
GROUP BY ref.marca
HAVING SUM(r.horas_trabajadas) >= 500
ORDER BY pacas_por_hora DESC;

-- ---------------------------------------------------------------------
-- Q17. Ajustes operativos (código 05): ¿quién los atiende? (las personas aparecen seudonimizadas)
-- Esperado por área: OPERARIOS 2090 paros / 1144.86 h ; MANTENIMIENTO 808 / 613.78 h ; sin área 178 / 55.05 h
-- ---------------------------------------------------------------------
-- 17a. Por área
SELECT COALESCE(area_atencion, '(sin área)') AS area,
       COUNT(*)                              AS paros,
       ROUND(SUM(minutos) / 60.0, 2)         AS horas_paro
FROM paro
WHERE id_codigo = 5
GROUP BY COALESCE(area_atencion, '(sin área)')
ORDER BY horas_paro DESC;

-- 17b. Las 5 personas con más horas de ajuste
SELECT e.nombre AS persona, e.tipo, COUNT(*) AS ajustes, ROUND(SUM(p.minutos) / 60.0, 2) AS horas
FROM paro p
JOIN empleado e ON e.id_empleado = p.id_empleado
WHERE p.id_codigo = 5
GROUP BY e.nombre, e.tipo
ORDER BY horas DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- Q18. Control de calidad de datos: registros cuyas horas de paro superan las horas trabajadas.
-- Esperado: 1388 registros "sin horas programadas" y 3 "mayor a las horas trabajadas".
-- Importante: el Excel (y por eso las vistas) resta esos paros de la productividad aunque no haya jornada.
-- ---------------------------------------------------------------------
SELECT CASE WHEN horas_trabajadas = 0
            THEN 'Paro en jornada sin horas programadas'
            ELSE 'Paro mayor a las horas trabajadas' END AS situacion,
       COUNT(*)                     AS registros,
       ROUND(SUM(horas_paro), 2)    AS horas_paro
FROM v_control_horas_paro
GROUP BY 1
ORDER BY registros DESC;