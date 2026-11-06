-- =====================================================================
-- 04_catalogos.sql  |  Carga de catálogos (datos maestros)
-- Fuente: hoja "TABLA CODIGOS" del Excel y procedimiento P-MTO-22.
-- =====================================================================
SET search_path TO paros;

BEGIN;

-- 1. Áreas de impacto -------------------------------------------------
INSERT INTO area_impacto (nombre) VALUES
    ('Mantenimiento'),
    ('Producción'),
    ('Calidad'),
    ('Almacén de materias primas'),
    ('Paro programado');

-- 2. Códigos de paro (P-MTO-22) ---------------------------------------
INSERT INTO codigo_paro (id_codigo, nombre, id_area)
SELECT v.id_codigo, v.nombre, a.id_area
FROM (VALUES
    ( 1, 'Falla del sistema electromecánico y/o de control',            'Mantenimiento'),
    ( 2, 'Espera de soporte de mantenimiento',                          'Mantenimiento'),
    ( 3, 'Novedad en los sistemas de potencia (Aire, energía, vapor)',  'Mantenimiento'),
    ( 4, 'Mantenimiento preventivo',                                    'Mantenimiento'),
    ( 5, 'Ajuste operativo',                                            'Producción'),
    ( 6, 'Limpieza por derrame operativo',                              'Producción'),
    ( 7, 'Alistamiento de máquina / Cambio de referencia',              'Producción'),
    ( 8, 'Capacitación / Reunión',                                      'Producción'),
    ( 9, 'Falta de operario',                                           'Producción'),
    (10, 'Paro por ventaja/evacuación',                                 'Producción'),
    (11, 'Reproceso',                                                   'Producción'),
    (12, 'Materia prima defectuosa',                                    'Calidad'),
    (13, 'En espera por el aval del laboratorio de microbiología',      'Calidad'),
    (14, 'Falta de materia prima',                                      'Almacén de materias primas'),
    (15, 'Cambio de insumos (Roscadores, O''ring, Etiquetas)',          'Paro programado'),
    (16, 'Alimentación y aseo de la zona de trabajo y la máquina',      'Paro programado'),
    (17, 'Pausa activa',                                                'Paro programado'),
    (18, 'Desinfección',                                                'Paro programado')  -- área asumida: no figura en el Excel
) AS v (id_codigo, nombre, area)
JOIN area_impacto a ON a.nombre = v.area;

-- 3. Subcódigos (códigos 01, 03 y 05) ---------------------------------
INSERT INTO subcodigo_paro (id_codigo, clave, nombre) VALUES
    
    (1, '1.1',   'Falla mecánica'),
    (1, '1.1.A', 'Banda'),
    (1, '1.1.B', 'Motor'),
    (1, '1.1.C', 'Sensor'),
    (1, '1.2',   'Sistema de dosificación'),
    (1, '1.2.A', 'Cambio de racores'),
    (1, '1.2.B', 'Ajuste de sensor'),
    (1, '1.2.C', 'Cambio de válvula'),
    (1, '1.2.D', 'Retenedores'),
    (1, '1.2.E', 'O''Ring'),
    (1, '1.3',   'Sistema de banda de entrada'),
    (1, '1.3.A', 'Banda'),
    (1, '1.3.B', 'Motor'),
    (1, '1.4',   'Sistema de tapado'),
    (1, '1.4.A', 'Motor del transfer'),
    (1, '1.4.B', 'Pisador de tapa'),
    (1, '1.4.C', 'Sensor'),                      -- en el Excel figura como "1.4.3"
    (1, '1.5',   'Sistema de alimentación de tapa'),
    (1, '1.5.A', 'Banda'),
    (1, '1.5.B', 'Motor'),
    (1, '1.5.C', 'Sensor'),
    (1, '1.6',   'Sistema Video Jet'),
    (1, '1.6.A', 'Fotocelda'),
    (1, '1.6.B', 'Sensor'),
    (1, '1.7',   'Sistema de sujeción y roscadores'),
    (1, '1.7.A', 'Banda de sujeción'),
    (1, '1.7.B', 'Roscadores'),
    (1, '1.8',   'Sistema etiquetadora'),
    (1, '1.8.A', 'Banda'),
    (1, '1.8.B', 'Motor'),
    (1, '1.8.C', 'Sensor'),
    -- Código 03: novedad en sistemas de potencia
    (3, '3.1',   'Fallo en la subestación'),
    (3, '3.2',   'Fallo en la red pública'),
    (3, '3.3',   'Falla en la red neumática o el compresor'),
    (3, '3.4',   'Falla en la red de enfriamiento o el chiller'),
    (3, '3.5',   'Falla en la red de vapor o la caldera'),
    -- Código 05: ajuste operativo
    (5, '5.1',   'Sistema alimentador de envases'),
    (5, '5.2',   'Sistema de dosificación de pintura, frontal posterior'),
    (5, '5.3',   'Banda transportadora de entrada'),
    (5, '5.4',   'Banda transportadora de salida'),
    (5, '5.5',   'Transfer y pisador de tapa'),
    (5, '5.6',   'Sistema alimentador de tapa y tobogán'),
    (5, '5.7',   'Video Jet'),
    (5, '5.8',   'Banda de sujeción y roscadores'),
    (5, '5.9',   'Sistema de etiquetado'),
    (5, '5.10',  'Purga de color'),
    (5, '5.11',  'Lavado de boquilla');


UPDATE subcodigo_paro s
SET    id_padre = p.id_subcodigo
FROM   subcodigo_paro p
WHERE  s.clave ~ '^[0-9]+\.[0-9]+\.[A-Z]$'
  AND  p.id_codigo = s.id_codigo
  AND  p.clave = regexp_replace(s.clave, '\.[A-Z]$', '');

-- 4. Máquinas ---------------------------------------------------------
INSERT INTO maquina (nombre) VALUES
    ('Vinilos_1'), ('Vinilos_2'), ('Vinilos_3'), ('Vinilos_4');

-- 5. Turnos (variantes del Excel unificadas) --------------------------
INSERT INTO turno (nombre, hora_inicio, hora_fin) VALUES
    ('Turno 1 (6am-2pm)',    '06:00', '14:00'),
    ('Turno 2 (2pm-10pm)',   '14:00', '22:00'),
    ('Turno 3 (10pm-6am)',   '22:00', '06:00'),
    ('Especial (6am-4:30pm)','06:00', '16:30'),
    ('Especial (6am-6pm)',   '06:00', '18:00'),
    ('Especial (6pm-6am)',   '18:00', '06:00');

-- 6. Tipos de paro de jornada (catálogo antiguo y nuevo unificados) ---
INSERT INTO tipo_paro_jornada (nombre) VALUES
    ('Paro de máquina'),
    ('Paro de máquina por ventas'),
    ('Falta de programación (planeación)'),
    ('Paro por proceso anterior'),
    ('Materia prima o material de empaque no conforme'),
    ('Falta de materiales o materias primas'),
    ('En espera por el aval del laboratorio de microbiología'),
    ('Alistamiento / cambio de producto'),
    ('Ajuste eléctrico o de servicios (aire, caldera, gas)'),
    ('Limpieza no programada'),
    ('Ajuste de operación'),
    ('Falta de operario');

COMMIT;

-- ---------------------------------------------------------------------
-- Verificación: filas cargadas vs. esperadas
-- ---------------------------------------------------------------------
SELECT 'area_impacto' AS tabla, COUNT(*) AS filas,  5 AS esperadas FROM area_impacto
UNION ALL SELECT 'codigo_paro',       COUNT(*), 18 FROM codigo_paro
UNION ALL SELECT 'subcodigo_paro',    COUNT(*), 47 FROM subcodigo_paro
UNION ALL SELECT 'maquina',           COUNT(*),  4 FROM maquina
UNION ALL SELECT 'turno',             COUNT(*),  6 FROM turno
UNION ALL SELECT 'tipo_paro_jornada', COUNT(*), 12 FROM tipo_paro_jornada;

-- Subcódigos con padre asignado (esperado: 23 de tercer nivel, todos del código 1)
SELECT COUNT(*) AS subcodigos_con_padre FROM subcodigo_paro WHERE id_padre IS NOT NULL;