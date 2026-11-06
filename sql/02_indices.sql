
SET search_path TO paros;

-- Productividad por mes/año: filtros por rango de fechas.
CREATE INDEX idx_registro_fecha ON registro_produccion (fecha);

-- Productividad por máquina en el tiempo y comparativos entre años.
CREATE INDEX idx_registro_maquina_fecha ON registro_produccion (id_maquina, fecha);

-- Comparación de desempeño entre turnos.
CREATE INDEX idx_registro_turno ON registro_produccion (id_turno);

-- Consultas por operario y borrado/actualización de empleado (FK ON DELETE SET NULL).
CREATE INDEX idx_registro_operario ON registro_produccion (id_operario) WHERE id_operario IS NOT NULL;

-- Rendimiento por referencia.
CREATE INDEX idx_registro_referencia ON registro_produccion (id_referencia) WHERE id_referencia IS NOT NULL;

-- Paros por motivo de jornada.
CREATE INDEX idx_registro_tipo_paro ON registro_produccion (id_tipo_paro) WHERE id_tipo_paro IS NOT NULL;

-- Join registro -> paros. INCLUDE permite sumar minutos sin leer la tabla (index-only scan)
CREATE INDEX idx_paro_registro ON paro (id_registro) INCLUDE (id_codigo, minutos);

-- Participación porcentual por código de paro (GROUP BY id_codigo, SUM(minutos)).
CREATE INDEX idx_paro_codigo ON paro (id_codigo) INCLUDE (minutos);

-- Detalle por subcódigo (códigos 01, 03 y 05). Parcial: la mayoría de paros no tiene subcódigo.
CREATE INDEX idx_paro_subcodigo ON paro (id_subcodigo) WHERE id_subcodigo IS NOT NULL;

-- Paros atendidos por persona (solo código 05) y FK ON DELETE SET NULL.
CREATE INDEX idx_paro_empleado ON paro (id_empleado) WHERE id_empleado IS NOT NULL;

-- Recorrido de la jerarquía de subcódigos.
CREATE INDEX idx_subcodigo_padre ON subcodigo_paro (id_padre) WHERE id_padre IS NOT NULL;

-- Agrupar códigos por área de impacto.
CREATE INDEX idx_codigo_area ON codigo_paro (id_area);