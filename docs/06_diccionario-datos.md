# 06. Diccionario de datos

**Motor de referencia:** PostgreSQL (tipos y sintaxis).
Las longitudes y rangos se dimensionaron con los valores máximos reales del Excel (ver sección "Evidencia de dimensionamiento").

Convenciones: nombres en `snake_case` y singular; PK sustituta con `IDENTITY` salvo en `codigo_paro`, cuya llave es el código de negocio (1 a 18).

---

## 1. area_impacto
Catálogo de las áreas de la empresa a las que se atribuye un paro (Mantenimiento, Producción, Calidad, Almacén de materias primas, Paro programado).

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_area | SMALLINT | - | NO | IDENTITY | PK | Identificador del área |
| nombre | VARCHAR | 40 | NO | - | UNIQUE | Nombre del área de impacto |

## 2. codigo_paro
Catálogo de los 18 códigos de paro definidos en el procedimiento P-MTO-22.

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_codigo | SMALLINT | - | NO | - | PK; CHECK (id_codigo BETWEEN 1 AND 99) | Número del código tal como lo usa la planta (01 a 18) |
| nombre | VARCHAR | 100 | NO | - | UNIQUE | Descripción del código, p. ej. "Ajuste operativo" |
| id_area | SMALLINT | - | NO | - | FK → area_impacto(id_area) ON UPDATE CASCADE ON DELETE RESTRICT | Área a la que se atribuye el paro |

## 3. subcodigo_paro
Catálogo jerárquico de subcódigos. Solo existen para los códigos 01 (falla electromecánica), 03 (potencia) y 05 (ajuste operativo). La jerarquía es sistema → componente (1.2 → 1.2.B).

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_subcodigo | SMALLINT | - | NO | IDENTITY | PK | Identificador del subcódigo |
| id_codigo | SMALLINT | - | NO | - | FK → codigo_paro(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT; CHECK (id_codigo IN (1,3,5)) | Código al que pertenece |
| clave | VARCHAR | 10 | NO | - | UNIQUE (id_codigo, clave) | Clave jerárquica, p. ej. "1.2.B" |
| nombre | VARCHAR | 100 | NO | - | - | Descripción, p. ej. "Ajuste de sensor" |
| id_padre | SMALLINT | - | SÍ | NULL | FK → subcodigo_paro(id_subcodigo) ON UPDATE CASCADE ON DELETE RESTRICT; CHECK (id_padre <> id_subcodigo) | Subcódigo de nivel superior (NULL si es un sistema de primer nivel) |

Restricción adicional: UNIQUE (id_codigo, id_subcodigo), necesaria para la FK compuesta de `paro`.

## 4. maquina
Líneas de envasado de la planta (Vinilos_1 a Vinilos_4).

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_maquina | SMALLINT | - | NO | IDENTITY | PK | Identificador de la máquina |
| nombre | VARCHAR | 30 | NO | - | UNIQUE | Nombre de la línea, p. ej. "Vinilos_3" |

## 5. turno
Franjas de trabajo. Se unifican las variantes de escritura del Excel ("6am-2pm (Turno 1)", "6am-2pm", etc.).

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_turno | SMALLINT | - | NO | IDENTITY | PK | Identificador del turno |
| nombre | VARCHAR | 30 | NO | - | UNIQUE | Nombre del turno, p. ej. "Turno 1 (6am-2pm)" |
| hora_inicio | TIME | - | NO | - | - | Hora de inicio |
| hora_fin | TIME | - | NO | - | - | Hora de fin. No se exige que sea mayor que el inicio porque el turno 3 cruza la medianoche |

## 6. empleado
Personas que aparecen como operarias/os o como personal de mantenimiento. Es la única tabla con datos personales (ver `09_datos-personales.md`; el campo `nombre` se podrá sustituir por un código seudónimo).

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_empleado | INTEGER | - | NO | IDENTITY | PK | Identificador del empleado |
| nombre | VARCHAR | 80 | NO | - | UNIQUE (nombre, tipo) | Nombre o seudónimo |
| tipo | VARCHAR | 15 | NO | - | CHECK (tipo IN ('OPERARIO','MANTENIMIENTO')) | Cargo con el que participa |

## 7. referencia
Productos que se envasan (marca, volumen y número de colores del kit).

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_referencia | INTEGER | - | NO | IDENTITY | PK | Identificador de la referencia |
| nombre_original | VARCHAR | 60 | NO | - | UNIQUE | Texto tal como se registra en el formato (p. ej. "Parchesitos 22cc (6 col)"); se conserva por trazabilidad |
| marca | VARCHAR | 40 | SÍ | NULL | - | Marca o línea (p. ej. "Parchesitos"); NULL si no se pudo extraer |
| volumen_cc | SMALLINT | - | SÍ | NULL | CHECK (volumen_cc > 0) | Volumen por envase en cc |
| num_colores | SMALLINT | - | SÍ | NULL | CHECK (num_colores > 0) | Número de colores del kit |

## 8. tipo_paro_jornada
Clasificación del motivo cuando la jornada completa (o buena parte) no se trabajó. Unifica el catálogo antiguo ("17. PARO DE MAQUINA") y el nuevo ("[18] Paro de máquina por ventas").

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_tipo_paro | SMALLINT | - | NO | IDENTITY | PK | Identificador del tipo |
| nombre | VARCHAR | 100 | NO | - | UNIQUE | Descripción del tipo de paro de jornada |

## 9. registro_produccion
Un registro por máquina, fecha, turno y referencia: lo que la operaria diligencia en el formato "hora a hora". Incluye los días sin producción (horas trabajadas = 0).

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_registro | INTEGER | - | NO | IDENTITY | PK | Identificador del registro |
| fecha | DATE | - | NO | - | CHECK (fecha >= DATE '2020-01-01') | Día de producción (de aquí se derivan mes y año) |
| id_maquina | SMALLINT | - | NO | - | FK → maquina ON UPDATE CASCADE ON DELETE RESTRICT | Máquina utilizada |
| id_turno | SMALLINT | - | SÍ | NULL | FK → turno ON UPDATE CASCADE ON DELETE RESTRICT | Turno; NULL en días sin programación |
| id_operario | INTEGER | - | SÍ | NULL | FK → empleado ON UPDATE CASCADE ON DELETE SET NULL | Operaria/o responsable |
| id_referencia | INTEGER | - | SÍ | NULL | FK → referencia ON UPDATE CASCADE ON DELETE RESTRICT | Producto envasado; NULL si no hubo producción |
| horas_trabajadas | NUMERIC | (5,2) | NO | 0 | CHECK (horas_trabajadas BETWEEN 0 AND 24) | Horas programadas de trabajo, base del cálculo de productividad |
| horas_no_trabajadas | NUMERIC | (5,2) | NO | 0 | CHECK (horas_no_trabajadas >= 0) | Horas de la jornada que no se trabajaron (p. ej. 8, 16, 24) |
| pacas_producidas | INTEGER | - | NO | 0 | CHECK (pacas_producidas >= 0) | Pacas producidas en el registro |
| id_tipo_paro | SMALLINT | - | SÍ | NULL | FK → tipo_paro_jornada ON UPDATE CASCADE ON DELETE RESTRICT | Motivo cuando hubo paro de jornada |
| observacion_paro | VARCHAR | 100 | SÍ | NULL | - | Explicación breve del paro de jornada |
| observaciones | VARCHAR | 500 | SÍ | NULL | - | Comentarios libres del registro |

## 10. paro
Un paro individual dentro de un registro: qué código lo causó, cuántos minutos duró y, si aplica, subcódigo, área y persona involucrada. Reemplaza las 18 columnas de código y sus columnas de horas.

| Columna | Tipo | Long. | Nulo | Default | Restricciones | Descripción de negocio |
|---|---|---|---|---|---|---|
| id_paro | INTEGER | - | NO | IDENTITY | PK | Identificador del paro |
| id_registro | INTEGER | - | NO | - | FK → registro_produccion ON UPDATE CASCADE ON DELETE CASCADE | Registro al que pertenece; sin registro no hay paro |
| id_codigo | SMALLINT | - | NO | - | FK → codigo_paro ON UPDATE CASCADE ON DELETE RESTRICT | Código de paro (01 a 18) |
| id_subcodigo | SMALLINT | - | SÍ | NULL | FK compuesta (id_codigo, id_subcodigo) → subcodigo_paro(id_codigo, id_subcodigo) ON UPDATE CASCADE ON DELETE RESTRICT | Subcódigo; debe pertenecer al código indicado |
| minutos | NUMERIC | (6,1) | NO | - | CHECK (minutos > 0) | Duración del paro en minutos; las horas se calculan dividiendo entre 60 |
| id_empleado | INTEGER | - | SÍ | NULL | FK → empleado ON UPDATE CASCADE ON DELETE SET NULL | Persona involucrada (solo código 05) |
| area_atencion | VARCHAR | 15 | SÍ | NULL | CHECK (area_atencion IN ('OPERARIOS','MANTENIMIENTO')) | Área que atendió el ajuste (solo código 05) |

Restricción adicional: CHECK (id_codigo = 5 OR (id_empleado IS NULL AND area_atencion IS NULL)), porque el procedimiento registra área y personal únicamente para el subcódigo 5.

---

## Políticas de llaves foráneas (resumen)

| Política | Dónde | Por qué |
|---|---|---|
| ON DELETE RESTRICT | Catálogos (máquina, código, subcódigo, referencia, turno, tipo, área) | No se puede borrar un catálogo que tenga historial asociado |
| ON DELETE CASCADE | paro → registro_produccion | Un paro no tiene sentido sin su registro |
| ON DELETE SET NULL | registro/paro → empleado | Permite eliminar a una persona (derecho de supresión de datos) sin perder el historial de producción |
| ON UPDATE CASCADE | Todas | Si cambia una llave, se propaga |

## Evidencia de dimensionamiento (valores reales del Excel)

| Dato | Máximo observado | Tamaño elegido |
|---|---|---|
| Máquina | 9 caracteres | VARCHAR(30) |
| Turno | 18 | VARCHAR(30) |
| Referencia | 25 | VARCHAR(60) |
| Operario / personal | 32 | VARCHAR(80) |
| Tipo de paro (texto antiguo) | 63 | VARCHAR(100) |
| Subcódigo | 57 | VARCHAR(100) |
| Observaciones de paro | 48 | VARCHAR(100) |
| Observaciones | 278 | VARCHAR(500) |
| Minutos por paro | 900 (dos valores con decimal: 219.6 y 160.5) | NUMERIC(6,1) |
| Horas trabajadas | 16 | NUMERIC(5,2) |
| Horas no trabajadas | 32 (un caso atípico) | NUMERIC(5,2), solo CHECK >= 0 |
| Pacas producidas | 9.417 | INTEGER |

