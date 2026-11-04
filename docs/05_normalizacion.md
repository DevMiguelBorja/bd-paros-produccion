
# 05. Normalización

Se parte de la estructura original del Excel (hoja `Base De Datos`, 58 columnas) y se llega a 3FN.
Una clave natural razonable para una fila original es (Fecha, Máquina, Turno, Referencia).

## 0FN: estructura original

```
BASE_DATOS(Fecha, Mes, Año, Maquina, Operario, Referencia, Unidades_por_minuto,
  Unidad_por_display, Display_por_paca, Pacas_producidas, Horas_trabajadas, Turno,
  Horas_no_trabajadas, Tipo_de_paro, Observaciones_de_paro,
  Codigo_paro_1, Subcodigo_1, Codigo_1_en_horas,
  Codigo_paro_2, Codigo_2_en_horas,
  Codigo_paro_3, Subcodigo_3, Codigo_3_en_horas,
  ... (hasta Codigo_paro_18 y Codigo_18_en_horas),
  Area_involucrada_subcodigo_5, Personal_involucrado, Tiempo_de_paro, Observaciones)
```

Problemas: grupo repetitivo de 18 códigos con sus tiempos, columnas derivadas, texto libre
inconsistente, columnas vacías.

## 1FN: valores atómicos y sin grupos repetitivos

**Qué se elimina:** el grupo repetitivo `Codigo_paro_N` / `Codigo_N_en_horas` (N = 1..18), que repite la misma
idea en columnas.
**Anomalías que causaba:**
- Inserción: agregar un código 19 exige modificar la estructura de la tabla.
- Consulta: "total por código" obliga a sumar 18 columnas distintas.
- Desperdicio: la mayoría de las celdas quedan vacías (por ejemplo, el código 4 tiene 8.200 nulos de 8.208 filas).

**Resultado:**
```
REGISTRO(Fecha, Mes, Año, Maquina, Operario, Referencia, Pacas, Horas_trabajadas, Turno,
         Horas_no_trabajadas, Tipo_de_paro, Observaciones_de_paro, Observaciones)
PARO(Fecha, Maquina, Turno, Referencia, Codigo, Subcodigo, Minutos, Area_involucrada, Personal_involucrado)
```
Una fila por paro en lugar de una columna por código. También se eliminan las columnas totalmente vacías
(`Unidades_por_minuto`, `Display_por_paca`) y se corrige `Unidad_por_display`, que contenía datos de turno.

## 2FN: sin dependencias parciales

Aplica a tablas con clave compuesta. En REGISTRO la clave es (Fecha, Maquina, Turno, Referencia).

| Dependencia parcial | Por qué viola 2FN | Solución |
|---|---|---|
| Fecha → Mes, Año | Depende solo de una parte de la clave | Se eliminan y se calculan con funciones sobre `fecha` |
| Codigo → Nombre_codigo, Area | En PARO la clave incluye Codigo, pero el nombre solo depende de él | Tabla CODIGO_PARO |
| Subcodigo → Nombre_subcodigo | Mismo caso | Tabla SUBCODIGO_PARO |

**Anomalías eliminadas:**
- Actualización: renombrar un código exigía corregirlo en miles de filas.
- Inconsistencia: `Mes` y `Año` podían contradecir a `Fecha`; además `Año` estaba guardado como texto.

Para simplificar las llaves foráneas se introduce una clave sustituta `id_registro`, y la clave natural queda como
UNIQUE candidata a validar durante la migración.

## 3FN: sin dependencias transitivas

Un atributo no clave no debe depender de otro atributo no clave.

| Dependencia transitiva | Solución |
|---|---|
| id_registro → Maquina → (nombre, línea) | MAQUINA |
| Turno (texto) → hora_inicio, hora_fin | TURNO (además unifica 6 variantes de escritura) |
| Referencia (texto) → marca, volumen, colores | REFERENCIA |
| Operario / Personal (texto) → tipo de cargo | EMPLEADO (unifica "Erika" / "Erika H.", etc.) |
| Codigo → Area_de_impacto | AREA_IMPACTO + CODIGO_PARO |
| Subcodigo → Codigo, Subcodigo_padre | SUBCODIGO_PARO con autorreferencia (1.2 → 1.2.B) |
| Tipo_de_paro (texto) → categoría | TIPO_PARO_JORNADA (unifica el catálogo viejo "17. PARO DE MAQUINA" y el nuevo "[18] ...") |

**Anomalías eliminadas:**
- Inserción: no se podía registrar un código o referencia nuevo sin tener un paro o registro que lo use.
- Borrado: eliminar el último registro de una referencia borraba su información.
- Actualización: corregir el nombre de una persona o de una referencia implicaba tocar muchas filas.

## ¿BCNF?

Todos los determinantes de las tablas finales son llaves candidatas (PK o UNIQUE), por lo que el esquema
también cumple BCNF.

## Desnormalización intencional

| Decisión | Justificación |
|---|---|
| `REFERENCIA.nombre_original` se conserva junto a marca, volumen y colores | Trazabilidad: permite auditar el parseo del texto original y reconstruir la etiqueta exacta del formato "hora a hora" |
| `REGISTRO.horas_no_trabajadas` se almacena | Es un dato digitado que no se puede derivar de otras columnas |

No se almacenan: mes, año, horas de paro por código, tiempo total de paro ni productividad. Se obtienen con
vistas y consultas, para no reintroducir redundancia.
