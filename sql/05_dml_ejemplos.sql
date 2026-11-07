-- =====================================================================
-- 05_dml_ejemplos.sql  |  INSERT, UPDATE y DELETE que evidencian las restricciones
-- =====================================================================
SET search_path TO paros;
BEGIN;

-- Datos de partida (valores esperados con la carga limpia: 8166 registros, 16482 paros)
SELECT (SELECT COUNT(*) FROM registro_produccion) AS registros,
       (SELECT COUNT(*) FROM paro)                AS paros;

-- =====================================================================
-- A. INSERT válidos
-- =====================================================================

-- A1. Nuevo registro de producción. No se indican horas_no_trabajadas ni observaciones:
--     toman el DEFAULT (0) y NULL.
INSERT INTO registro_produccion (fecha, id_maquina, id_turno, id_operario, id_referencia,
                                 horas_trabajadas, pacas_producidas)
SELECT DATE '2025-03-31', m.id_maquina, t.id_turno, e.id_empleado, r.id_referencia, 8, 120
FROM maquina m, turno t, empleado e, referencia r
WHERE m.nombre = 'Vinilos_1'
  AND t.nombre = 'Turno 1 (6am-2pm)'
  AND e.nombre = 'OPERARIO-001'
  AND r.nombre_original = 'Parchesitos 22cc (6 col)'
RETURNING id_registro, fecha, horas_trabajadas, horas_no_trabajadas AS default_horas_no_trab, observaciones;

CREATE TEMP TABLE _prueba AS
SELECT id_registro FROM registro_produccion WHERE fecha = DATE '2025-03-31';

-- A2. Dos paros del registro: uno del código 05 con subcódigo, área y persona 
INSERT INTO paro (id_registro, id_codigo, id_subcodigo, minutos, id_empleado, area_atencion)
SELECT p.id_registro, 5,
       (SELECT id_subcodigo FROM subcodigo_paro WHERE id_codigo = 5 AND clave = '5.2'),
       15,
       (SELECT MIN(id_empleado) FROM empleado WHERE tipo = 'MANTENIMIENTO'),
       'MANTENIMIENTO'
FROM _prueba p;

INSERT INTO paro (id_registro, id_codigo, minutos)
SELECT id_registro, 16, 20 FROM _prueba;

SELECT p.id_paro, p.id_codigo, s.clave AS subcodigo, p.minutos, p.area_atencion
FROM paro p LEFT JOIN subcodigo_paro s ON s.id_subcodigo = p.id_subcodigo
WHERE p.id_registro IN (SELECT id_registro FROM _prueba)
ORDER BY p.id_codigo;   -- esperado: 2 filas (código 5 / 5.2 / 15 min y código 16 / 20 min)

-- =====================================================================
-- B. UPDATE válidos
-- =====================================================================

-- B1. Corregir un dato digitado.
UPDATE registro_produccion
SET    pacas_producidas = 135,
       observaciones    = 'Corrección de digitación'
WHERE  id_registro IN (SELECT id_registro FROM _prueba)
RETURNING id_registro, pacas_producidas, observaciones;

-- B2. ON UPDATE CASCADE: si cambia la llave de un código, sus paros la siguen automáticamente.
INSERT INTO codigo_paro (id_codigo, nombre, id_area)
SELECT 99, 'Código de prueba', id_area FROM area_impacto WHERE nombre = 'Mantenimiento';

INSERT INTO paro (id_registro, id_codigo, minutos)
SELECT id_registro, 99, 5 FROM _prueba;

UPDATE codigo_paro SET id_codigo = 98 WHERE id_codigo = 99;

SELECT id_codigo AS codigo_del_paro_de_prueba   -- esperado: 98 (cambió solo, sin tocar la tabla paro)
FROM paro WHERE id_registro IN (SELECT id_registro FROM _prueba) AND minutos = 5;

-- =====================================================================
-- C. DELETE válidos
-- =====================================================================

-- C1. ON DELETE CASCADE: al borrar el registro desaparecen sus paros.
SELECT COUNT(*) AS paros_antes FROM paro WHERE id_registro IN (SELECT id_registro FROM _prueba);  -- esperado: 3

DELETE FROM registro_produccion WHERE id_registro IN (SELECT id_registro FROM _prueba);

SELECT COUNT(*) AS paros_despues FROM paro WHERE id_registro IN (SELECT id_registro FROM _prueba); -- esperado: 0

-- C2. ON DELETE SET NULL (derecho de supresión de datos personales): se borra a una persona y su
--     historial de producción se conserva, solo que sin operario asociado.
CREATE TEMP TABLE _op AS
SELECT id_operario, COUNT(*) AS registros
FROM registro_produccion WHERE id_operario IS NOT NULL
GROUP BY id_operario ORDER BY COUNT(*) DESC LIMIT 1;

SELECT (SELECT COUNT(*) FROM registro_produccion WHERE id_operario IS NULL) AS sin_operario_antes,
       (SELECT registros FROM _op)                                          AS registros_de_la_persona;

DELETE FROM empleado WHERE id_empleado = (SELECT id_operario FROM _op);

SELECT (SELECT COUNT(*) FROM registro_produccion WHERE id_operario IS NULL) AS sin_operario_despues,
       (SELECT COUNT(*) FROM registro_produccion)                           AS registros_totales;
-- esperado: sin_operario_despues = antes + registros_de_la_persona; registros_totales no cambia (8166)

-- =====================================================================
-- D. Operaciones que la base de datos DEBE RECHAZAR
-- =====================================================================

-- D1. CHECK: un paro no puede durar 0 minutos.
DO $$
BEGIN
    INSERT INTO paro (id_registro, id_codigo, minutos)
    VALUES ((SELECT MIN(id_registro) FROM registro_produccion), 16, 0);
    RAISE NOTICE 'D1 ERROR: la base NO rechazó minutos = 0';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'D1 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- D2. CHECK: no se pueden trabajar más de 24 horas en un registro.
DO $$
BEGIN
    INSERT INTO registro_produccion (fecha, id_maquina, horas_trabajadas)
    VALUES (DATE '2025-03-31', (SELECT MIN(id_maquina) FROM maquina), 30);
    RAISE NOTICE 'D2 ERROR: la base NO rechazó horas_trabajadas = 30';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'D2 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- D3. FK compuesta: el subcódigo 3.2 pertenece al código 03, no puede usarse en un paro del código 01.
DO $$
BEGIN
    INSERT INTO paro (id_registro, id_codigo, id_subcodigo, minutos)
    VALUES ((SELECT MIN(id_registro) FROM registro_produccion), 1,
            (SELECT id_subcodigo FROM subcodigo_paro WHERE clave = '3.2'), 10);
    RAISE NOTICE 'D3 ERROR: la base NO rechazó un subcódigo de otro código';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'D3 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- D4. CHECK entre columnas: área y persona solo se registran en paros del código 05.
DO $$
BEGIN
    INSERT INTO paro (id_registro, id_codigo, minutos, area_atencion)
    VALUES ((SELECT MIN(id_registro) FROM registro_produccion), 16, 10, 'OPERARIOS');
    RAISE NOTICE 'D4 ERROR: la base NO rechazó área_atencion en un código distinto de 05';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'D4 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- D5. UNIQUE: no puede haber dos máquinas con el mismo nombre.
DO $$
BEGIN
    INSERT INTO maquina (nombre) VALUES ('Vinilos_1');
    RAISE NOTICE 'D5 ERROR: la base NO rechazó una máquina duplicada';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'D5 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- D6. NOT NULL: la fecha es obligatoria.
DO $$
BEGIN
    INSERT INTO registro_produccion (id_maquina) VALUES ((SELECT MIN(id_maquina) FROM maquina));
    RAISE NOTICE 'D6 ERROR: la base NO rechazó un registro sin fecha';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'D6 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- D7. CHECK: fechas anteriores a 2020 se consideran errores de digitación.
DO $$
BEGIN
    INSERT INTO registro_produccion (fecha, id_maquina)
    VALUES (DATE '1999-01-01', (SELECT MIN(id_maquina) FROM maquina));
    RAISE NOTICE 'D7 ERROR: la base NO rechazó una fecha de 1999';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'D7 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- D8. ON DELETE RESTRICT: no se puede borrar una máquina que tiene registros.
DO $$
BEGIN
    DELETE FROM maquina WHERE nombre = 'Vinilos_1';
    RAISE NOTICE 'D8 ERROR: la base NO rechazó borrar una máquina con historial';
EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
    RAISE NOTICE 'D8 RECHAZADO (esperado) [%]: %', SQLSTATE, SQLERRM;
END $$;

-- =====================================================================
-- E. Se deshace todo: los datos migrados quedan intactos
-- =====================================================================
ROLLBACK;

SELECT (SELECT COUNT(*) FROM registro_produccion) AS registros,   -- esperado: 8166
       (SELECT COUNT(*) FROM paro)                AS paros,       -- esperado: 16482
       (SELECT COUNT(*) FROM empleado)            AS empleados;   -- esperado: 43
