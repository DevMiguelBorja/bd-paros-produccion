# Migración del Excel a PostgreSQL

`migrar.py` convierte la hoja `Base De Datos` del Excel original al modelo normalizado y lo carga en el esquema `paros`.

## Requisitos
1. Base creada y scripts `sql/01` a `sql/04` ejecutados (esquema y catálogos).
2. Excel original en `datos_originales/` (carpeta ignorada por Git, el archivo contiene nombres reales).
3. Entorno Python: `pip install -r requirements.txt`.
4. (Opcional, privado) `migracion/privado/equivalencias_personas.csv` con columnas `origen,destino` para fusionar variantes de un mismo nombre. Esta carpeta está en `.gitignore`.

## Uso
```
python migracion/migrar.py                     # solo transforma: genera CSV y reporte
python migracion/migrar.py --cargar            # además carga en PostgreSQL (pide la contraseña)
python migracion/migrar.py --cargar --limpiar  # vacía las tablas transaccionales antes de cargar
python migracion/migrar.py --conservar-duplicados
```
Parámetros de conexión: `--host localhost --port 5432 --db paros_produccion --user postgres`.

## Qué hace
| Etapa | Descripción |
|---|---|
| Leer | Hoja `Base De Datos` (8.208 filas, 58 columnas) |
| Limpiar | Unifica turnos, tipos de paro y subcódigos; valida las claves contra `sql/04_catalogos.sql`; descarta duplicados exactos; "No aplica" y "Sin especificar" pasan a NULL |
| Pivotar | Las 18 columnas `Codigo de paro N` pasan a filas de `paro` (solo minutos > 0) |
| Proteger | Nombres reales -> seudónimos (OPERARIO-001...); nombres dentro de textos libres -> `[persona]` |
| Cargar | `COPY` en una sola transacción; sincroniza las secuencias de identidad |
| Validar | Compara registros, paros, minutos, horas y pacas entre el Excel limpio y PostgreSQL |

## Salidas
- `datos_limpios/*.csv`: datos ya seudonimizados (se pueden versionar).
- `reportes/reporte_migracion.md`: decisiones de limpieza y totales de control (evidencia para el informe).
- `reportes/descartes_duplicados.csv`: filas descartadas.
- `privado/mapa_personas.csv`: seudónimo <-> nombre real. **No se versiona.**
