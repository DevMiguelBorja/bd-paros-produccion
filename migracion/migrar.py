#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
migrar.py - Migración del Excel "SEGUIMIENTO TEMPERAS Y VINILOS" a PostgreSQL.

Estrategia (ETL en dos etapas):
  1. TRANSFORMAR (no necesita base de datos): lee la hoja "Base De Datos", la limpia
     y la convierte al modelo normalizado (registro_produccion, paro, empleado, referencia).
     Escribe CSV limpios en migracion/datos_limpios/ y un reporte en migracion/reportes/.
  2. CARGAR (opción --cargar): inserta los datos en el esquema "paros" con COPY, dentro de una
     sola transacción, y compara los totales de control contra el Excel.

Uso:
    python migracion/migrar.py                    # solo transforma y genera CSV + reporte
    python migracion/migrar.py --cargar           # además carga en PostgreSQL
    python migracion/migrar.py --cargar --limpiar # vacía antes las tablas transaccionales
    python migracion/migrar.py --conservar-duplicados

Requisitos previos: ejecutar sql/01_ddl.sql ... sql/04_catalogos.sql y colocar el Excel en
datos_originales/ (carpeta ignorada por Git).

Datos personales: los nombres reales NUNCA se escriben en los CSV públicos. Se reemplazan por
seudónimos (OPERARIO-001, MANTENIMIENTO-001...) y la correspondencia queda en
migracion/privado/ (ignorada por Git).
"""
from __future__ import annotations

import argparse
import getpass
import os
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

RAIZ = Path(__file__).resolve().parent.parent
DIR_ORIGINALES = RAIZ / "datos_originales"
SQL_CATALOGOS = RAIZ / "sql" / "04_catalogos.sql"
DIR_LIMPIOS = RAIZ / "migracion" / "datos_limpios"
DIR_REPORTES = RAIZ / "migracion" / "reportes"
DIR_PRIVADO = RAIZ / "migracion" / "privado"
EQUIVALENCIAS = DIR_PRIVADO / "equivalencias_personas.csv"

HOJA = "Base De Datos"
FILA_ENCABEZADO = 8          # el encabezado está en la fila 9 de Excel (índice 8)
PRIMERA_FILA_EXCEL = 10      # primera fila de datos en Excel

# --------------------------------------------------------------------------------------
# Reglas de limpieza (mapeos)
# --------------------------------------------------------------------------------------


def k(texto) -> str:
    """Clave de comparación: sin espacios repetidos y sin distinguir mayúsculas."""
    return " ".join(str(texto).split()).casefold()


def limpio(valor):
    """Texto recortado o None si está vacío / es NaN."""
    if valor is None or (isinstance(valor, float) and np.isnan(valor)):
        return None
    texto = str(valor).strip()
    return texto or None


# Turnos: se identifican por su rango horario (ignora "(Turno 1)" y variantes de escritura)
TURNOS = {
    "6am-2pm": "Turno 1 (6am-2pm)",
    "2pm-10pm": "Turno 2 (2pm-10pm)",
    "10pm-6am": "Turno 3 (10pm-6am)",
    "6am-4:30pm": "Especial (6am-4:30pm)",
    "6am-6pm": "Especial (6am-6pm)",
    "6pm-6am": "Especial (6pm-6am)",
}
RE_TURNO = re.compile(r"(\d{1,2}(?::\d{2})?[ap]m)\s*-\s*(\d{1,2}(?::\d{2})?[ap]m)", re.I)

# Tipo de paro de jornada: catálogo antiguo ("17. ...") y nuevo ("[18] ...") unificados.
# None = "No aplica" (se guarda como NULL).
TIPOS_PARO = {k(a): b for a, b in {
    "17. PARO DE MAQUINA": "Paro de máquina",
    "[18] Paro de maquina por ventas": "Paro de máquina por ventas",
    "9.FALTA DE PROGRAMACIÓN (PLANEACIÓN)": "Falta de programación (planeación)",
    "16.  PARO POR PROCESO ANTERIOR": "Paro por proceso anterior",
    "10. PARO POR MATERIA PRIMA O MATERIAL DE EMPAQUE NO CONFORME": "Materia prima o material de empaque no conforme",
    "[12] Materia prima defectuosa o material de empaque no conforme": "Materia prima o material de empaque no conforme",
    "6. FALTA DE MATERIALES O MATERIAS PRIMAS": "Falta de materiales o materias primas",
    "[14] Falta de materia prima": "Falta de materiales o materias primas",
    "15. APROBACION DE LABORATORIO (MICROBIOLOGIA)": "En espera por el aval del laboratorio de microbiología",
    "[13] En espera por el aval del laboratorio de microbiología": "En espera por el aval del laboratorio de microbiología",
    "[09] Falta de operario": "Falta de operario",
    "[05] Ajuste operativo": "Ajuste de operación",
    "4.AJUSTE DE OPERACIÓN": "Ajuste de operación",
    "5. AISLAMIENTO/CAMBIO DE PRODUCTO": "Alistamiento / cambio de producto",
    "[07] Alistamiento de máquina / Cambio de referencia": "Alistamiento / cambio de producto",
    "3. AJUSTE ELECTRICO O DE SERVICIOS (AIRE, CALDERA, GAS)": "Ajuste eléctrico o de servicios (aire, caldera, gas)",
    "[03] Novedad en los sistemas de potencia (Aire, energía, vapor)": "Ajuste eléctrico o de servicios (aire, caldera, gas)",
    "11. LIMPIEZA NO PROGRAMADA": "Limpieza no programada",
    "[19] No aplica": None,
}.items()}

AREAS = {"operarios": "OPERARIOS", "personal_de_mantenimiento": "MANTENIMIENTO"}

# Subcódigos. Las claves del Excel vienen escritas de muchas formas ("1.2D", "1.2.D", "1.2D  RETENEDORES"...).
# Se extrae la clave y se valida contra el catálogo (sql/04_catalogos.sql).
RE_CLAVE = re.compile(r"^(\d+\.\d+)\.?([A-Z])?(?=\s|$)")
# Numeración antigua del código 05 ("4.x") -> clave actual del catálogo. No es un simple +1:
# el catálogo nuevo agregó 5.4 "Banda transportadora de salida".
LEGADO_CODIGO5 = {"4.1": "5.1", "4.2": "5.2", "4.3": "5.3", "4.4": "5.5",
                  "4.5": "5.6", "4.6": "5.7", "4.7": "5.8", "4.8": "5.9"}
# Casos puntuales por texto exacto (en mayúsculas, sin espacios repetidos)
SUBCODIGO_EXCEPCIONES = {
    "1.4.3 SENSOR": "1.4.C",            # error de digitación: 3 en lugar de C
    "1.7A CAMBIO DE ROSCADORES": "1.7.B",  # el texto habla de roscadores (catálogo: 1.7.B)
}
SUBCODIGO_VACIOS = {"SIN ESPECIFICAR", "NO APLICA", ""}

MARCA_CORRECCIONES = {"Alocdor": "Alocolor", "Stilo Kids": "Estilo Kids"}
RE_REFERENCIA = re.compile(r"^(?P<marca>.+?)\s+(?P<vol>\d+)\s*cc(?:\s*\(\s*(?P<col>\d+)\s*col\s*\))?$", re.I)

MAQUINAS = {"Vinilos_1", "Vinilos_2", "Vinilos_3", "Vinilos_4"}
N_CODIGOS = 18

# --------------------------------------------------------------------------------------
# Funciones auxiliares
# --------------------------------------------------------------------------------------


def clave_turno(raw):
    texto = limpio(raw)
    if texto is None or k(texto) == "no aplica":
        return None, False
    m = RE_TURNO.search(texto.replace(" ", ""))
    if m:
        rango = f"{m.group(1)}-{m.group(2)}".lower()
        if rango in TURNOS:
            return TURNOS[rango], False
    return None, True


def clave_subcodigo(raw, codigo: int):
    """Devuelve (clave_normalizada | None, reconocida: bool)."""
    texto = limpio(raw)
    if texto is None:
        return None, True
    s = " ".join(texto.split()).upper()
    if s in SUBCODIGO_VACIOS:
        return None, True
    if s in SUBCODIGO_EXCEPCIONES:
        return SUBCODIGO_EXCEPCIONES[s], True
    m = RE_CLAVE.match(s)
    if not m:
        return None, False
    base, letra = m.groups()
    if codigo == 5 and letra is None and base in LEGADO_CODIGO5:
        base = LEGADO_CODIGO5[base]
    return base + (f".{letra}" if letra else ""), True


def claves_catalogo() -> set[tuple[int, str]]:
    """Lee (id_codigo, clave) de sql/04_catalogos.sql: una sola fuente de verdad."""
    if not SQL_CATALOGOS.exists():
        sys.exit(f"No se encontró {SQL_CATALOGOS}")
    texto = SQL_CATALOGOS.read_text(encoding="utf-8")
    bloque = texto.split("INSERT INTO subcodigo_paro", 1)[1].split(";", 1)[0]
    return {(int(c), cl) for c, cl in re.findall(r"\(\s*(\d+)\s*,\s*'([0-9.A-Z]+)'\s*,", bloque)}


def parsear_referencia(nombre: str):
    m = RE_REFERENCIA.match(nombre)
    if not m:
        return None, None, None
    marca = MARCA_CORRECCIONES.get(m.group("marca"), m.group("marca"))
    vol = int(m.group("vol"))
    col = int(m.group("col")) if m.group("col") else None
    return marca, vol, col


def cargar_equivalencias() -> dict[str, str]:
    if not EQUIVALENCIAS.exists():
        print("  (aviso) No existe migracion/privado/equivalencias_personas.csv: no se fusionan variantes de nombre.")
        return {}
    eq = pd.read_csv(EQUIVALENCIAS, dtype=str, encoding="utf-8")
    return {" ".join(o.split()): " ".join(d.split()) for o, d in zip(eq["origen"], eq["destino"])}


# Palabras que son apellidos pero también palabras comunes: no se enmascaran para no dañar el texto
PALABRAS_NO_ENMASCARAR = {"luz", "mercado", "valencia", "cordoba", "córdoba", "rios", "ríos", "pardo"}


def construir_mascara(nombres) -> re.Pattern:
    """Expresión regular que detecta nombres completos y nombres de pila/apellidos dentro de texto libre."""
    alternativas = set(nombres)
    for n in nombres:
        for t in re.split(r"[\s.]+", n):
            if len(t) >= 3 and t.casefold() not in PALABRAS_NO_ENMASCARAR:
                alternativas.add(t)
    alternativas = sorted(alternativas, key=len, reverse=True)
    return re.compile(r"(?<!\w)(" + "|".join(re.escape(a) for a in alternativas) + r")(?!\w)", re.I)


def _py(v):
    """Convierte tipos de numpy/pandas a tipos nativos de Python para COPY."""
    if v is None or v is pd.NA:
        return None
    if isinstance(v, (float, np.floating)):
        return None if np.isnan(v) else float(v)
    if isinstance(v, np.integer):
        return int(v)
    if isinstance(v, pd.Timestamp):
        return v.date()
    if v is pd.NaT:
        return None
    return v


def filas(df: pd.DataFrame):
    for tupla in df.itertuples(index=False, name=None):
        yield tuple(_py(v) for v in tupla)


# --------------------------------------------------------------------------------------
# Etapa 1: transformar
# --------------------------------------------------------------------------------------


def leer_excel(ruta: Path) -> pd.DataFrame:
    df = pd.read_excel(ruta, sheet_name=HOJA, header=FILA_ENCABEZADO, engine="openpyxl")
    df.columns = [str(c).replace("\n", " ").strip() for c in df.columns]
    esperadas = {"Fecha", "Maquina", "Operario", "Referencia", "Pacas producidas", "Horas trabajadas",
                 "Turno", "Horas no trabajadas", "Tipo de paro", "Observaciones de paro",
                 "Sub Codigo de paro 1", "Subcodigo 3", "Subcodigo 5",
                 "Área involucrada en subcodigo 5", "Personal involucrado", "Observaciones"}
    faltan = esperadas - set(df.columns)
    if faltan:
        sys.exit(f"Al Excel le faltan columnas esperadas: {sorted(faltan)}")
    return df


def transformar(df: pd.DataFrame, conservar_duplicados: bool) -> dict:
    ctx: dict = {"problemas": [], "avisos": []}
    ctx["filas_excel"] = len(df)
    df = df.copy()
    df["fila_excel"] = df.index + PRIMERA_FILA_EXCEL

    minutos_cols = [f"Codigo de paro {n}" for n in range(1, N_CODIGOS + 1)]
    M = df[minutos_cols].apply(pd.to_numeric, errors="coerce").fillna(0)
    df["_min_total"] = M.sum(axis=1)
    df["_n_paros"] = (M > 0).sum(axis=1)

    # --- Duplicados exactos (las 58 columnas iguales)
    es_dup = df.drop(columns=["fila_excel", "_min_total", "_n_paros"]).duplicated()
    ctx["duplicados_total"] = int(es_dup.sum())
    ctx["duplicados_con_paros"] = int((es_dup & (df["_n_paros"] > 0)).sum())
    ctx["duplicados_paros"] = int(df.loc[es_dup, "_n_paros"].sum())
    ctx["duplicados_minutos"] = float(df.loc[es_dup, "_min_total"].sum())
    ctx["duplicados_descartados"] = not conservar_duplicados
    ctx["descartes"] = df.loc[es_dup, ["fila_excel", "Fecha", "Maquina", "_n_paros", "_min_total"]].copy() \
        if not conservar_duplicados else pd.DataFrame()
    if not conservar_duplicados:
        df = df.loc[~es_dup]
    df = df.reset_index(drop=True)
    M = df[minutos_cols].apply(pd.to_numeric, errors="coerce").fillna(0)

    # --- Registros
    sin_turno, sin_tipo = Counter(), Counter()
    turnos = []
    for raw in df["Turno"]:
        nombre, raro = clave_turno(raw)
        if raro:
            sin_turno[str(raw)] += 1
        turnos.append(nombre)

    tipos = []
    for raw in df["Tipo de paro"]:
        texto = limpio(raw)
        if texto is None:
            tipos.append(None)
        elif k(texto) in TIPOS_PARO:
            tipos.append(TIPOS_PARO[k(texto)])
        else:
            sin_tipo[texto] += 1
            tipos.append(None)

    equiv = cargar_equivalencias()

    def canon(raw):
        t = limpio(raw)
        if t is None or k(t) in ("no", "no aplica"):
            return None
        t = " ".join(t.split())
        return equiv.get(t, t)

    referencias = [None if (limpio(r) is None or k(r) == "no aplica") else limpio(r) for r in df["Referencia"]]

    reg = pd.DataFrame({
        "id_registro": np.arange(1, len(df) + 1),
        "fecha": pd.to_datetime(df["Fecha"]).dt.date,
        "maquina": df["Maquina"].map(limpio),
        "turno": turnos,
        "operario_real": [canon(x) for x in df["Operario"]],
        "referencia": referencias,
        "horas_trabajadas": pd.to_numeric(df["Horas trabajadas"], errors="coerce").fillna(0).round(2),
        "horas_no_trabajadas": pd.to_numeric(df["Horas no trabajadas"], errors="coerce").fillna(0).round(2),
        "pacas_producidas": pd.to_numeric(df["Pacas producidas"], errors="coerce").fillna(0).round().astype(int),
        "tipo_paro": tipos,
        "observacion_paro": [limpio(x) for x in df["Observaciones de paro"]],
        "observaciones": [limpio(x) for x in df["Observaciones"]],
    })
    reg["fila_excel"] = df["fila_excel"].values

    # --- Paros: una fila por cada código con minutos > 0 (pivote de 18 columnas a filas)
    catalogo = claves_catalogo()
    sub_sin_mapear, legado_usado, excepciones_usadas = Counter(), 0, Counter()
    partes = []
    origen_sub = {1: "Sub Codigo de paro 1", 3: "Subcodigo 3", 5: "Subcodigo 5"}
    for n in range(1, N_CODIGOS + 1):
        mins = M[f"Codigo de paro {n}"]
        idx = mins[mins > 0].index
        if len(idx) == 0:
            continue
        p = pd.DataFrame({"id_registro": reg.loc[idx, "id_registro"].values, "id_codigo": n,
                          "minutos": mins[idx].round(1).values,
                          "fila_excel": df.loc[idx, "fila_excel"].values})
        claves, areas, personal = [], [], []
        for i in idx:
            clave = None
            if n in origen_sub:
                raw = df.at[i, origen_sub[n]]
                clave, ok = clave_subcodigo(raw, n)
                texto_up = " ".join(str(raw).split()).upper() if limpio(raw) else ""
                if texto_up in SUBCODIGO_EXCEPCIONES:
                    excepciones_usadas[texto_up] += 1
                if n == 5 and clave and re.match(r"^4\.\d", texto_up):
                    legado_usado += 1
                if (not ok) or (clave is not None and (n, clave) not in catalogo):
                    sub_sin_mapear[f"código {n}: {limpio(raw)}"] += 1
                    clave = None
            claves.append(clave)
            if n == 5:
                a = limpio(df.at[i, "Área involucrada en subcodigo 5"])
                areas.append(AREAS.get(k(a)) if a else None)
                personal.append(canon(df.at[i, "Personal involucrado"]))
            else:
                areas.append(None)
                personal.append(None)
        p["subcodigo_clave"], p["area_atencion"], p["personal_real"] = claves, areas, personal
        partes.append(p)
    paro = pd.concat(partes, ignore_index=True).sort_values(["id_registro", "id_codigo"], kind="stable")
    paro = paro.reset_index(drop=True)
    paro.insert(0, "id_paro", np.arange(1, len(paro) + 1))

    ctx["personal_sin_codigo5"] = int(sum(
        1 for i in df.index if limpio(df.at[i, "Personal involucrado"]) and M.at[i, "Codigo de paro 5"] <= 0))
    ctx["area_sin_codigo5"] = int(sum(
        1 for i in df.index if limpio(df.at[i, "Área involucrada en subcodigo 5"]) and M.at[i, "Codigo de paro 5"] <= 0))
    ctx["celdas_minutos_cero"] = int(((df[minutos_cols].apply(pd.to_numeric, errors="coerce") == 0).sum()).sum())

    # --- Personas: seudonimización (nombre real -> OPERARIO-001 / MANTENIMIENTO-001)
    eventos = [pd.DataFrame({"id_registro": reg["id_registro"], "orden": 0, "nombre": reg["operario_real"],
                             "rol": "OPERARIO"})]
    pp = paro[paro["personal_real"].notna()]
    eventos.append(pd.DataFrame({"id_registro": pp["id_registro"], "orden": 1, "nombre": pp["personal_real"],
                                 "rol": np.where(pp["area_atencion"] == "MANTENIMIENTO", "MANTENIMIENTO", "OPERARIO")}))
    ev = pd.concat(eventos).dropna(subset=["nombre"]).sort_values(["id_registro", "orden"], kind="stable")
    roles = ev.groupby("nombre")["rol"].agg(lambda s: Counter(s))
    tipo_de = {n: ("MANTENIMIENTO" if c["MANTENIMIENTO"] > c["OPERARIO"] else "OPERARIO") for n, c in roles.items()}
    contador = Counter()
    seudonimo = {}
    for nombre in ev["nombre"].drop_duplicates():          # orden de primera aparición
        t = tipo_de[nombre]
        contador[t] += 1
        seudonimo[nombre] = f"{t}-{contador[t]:03d}"
    reg["operario"] = reg["operario_real"].map(seudonimo)
    paro["empleado"] = paro["personal_real"].map(seudonimo)

    # Los textos libres también pueden nombrar personas: se enmascaran antes de escribir los CSV
    mascara = construir_mascara(list(seudonimo.keys()) + list(equiv.keys()))
    enmascaradas = 0
    for col in ("observaciones", "observacion_paro"):
        nuevos = []
        for t in reg[col]:
            if isinstance(t, str) and mascara.search(t):
                enmascaradas += 1
                t = mascara.sub("[persona]", t)
            nuevos.append(t if isinstance(t, str) else None)
        reg[col] = nuevos
    ctx["obs_enmascaradas"] = enmascaradas

    empleado = pd.DataFrame({"nombre": list(seudonimo.values()),
                             "tipo": [tipo_de[n] for n in seudonimo]})
    mapa_privado = pd.DataFrame({"seudonimo": list(seudonimo.values()), "nombre_real": list(seudonimo.keys()),
                                 "tipo": [tipo_de[n] for n in seudonimo]})

    # --- Referencias
    filas_ref = []
    for nombre in sorted(set(r for r in reg["referencia"] if isinstance(r, str))):
        marca, vol, col = parsear_referencia(nombre)
        filas_ref.append((nombre, marca, vol, col))
    referencia = pd.DataFrame(filas_ref, columns=["nombre_original", "marca", "volumen_cc", "num_colores"])
    ctx["referencias_sin_parsear"] = [r[0] for r in filas_ref if r[1] is None]

    # --- Validaciones previas a la carga (fallar aquí es mejor que fallar en la base de datos)
    problemas = ctx["problemas"]
    if reg["fecha"].isna().any():
        problemas.append("Hay registros sin fecha.")
    if not set(reg["maquina"]).issubset(MAQUINAS):
        problemas.append(f"Máquinas no reconocidas: {set(reg['maquina']) - MAQUINAS}")
    if (reg["horas_trabajadas"] < 0).any() or (reg["horas_trabajadas"] > 24).any():
        problemas.append("horas_trabajadas fuera de 0-24.")
    if (reg["horas_no_trabajadas"] < 0).any():
        problemas.append("horas_no_trabajadas negativas.")
    if (reg["pacas_producidas"] < 0).any():
        problemas.append("pacas_producidas negativas.")
    if (paro["minutos"] <= 0).any():
        problemas.append("Hay paros con minutos <= 0.")
    if reg["observaciones"].dropna().str.len().max() > 500:
        problemas.append("Observaciones superan 500 caracteres.")
    if reg["observacion_paro"].dropna().str.len().max() > 100:
        problemas.append("Observación de paro supera 100 caracteres.")
    if sin_turno:
        ctx["avisos"].append(f"Turnos no reconocidos (quedan en NULL): {dict(sin_turno)}")
    if sin_tipo:
        ctx["avisos"].append(f"Tipos de paro no reconocidos (quedan en NULL): {dict(sin_tipo)}")
    if sub_sin_mapear:
        ctx["avisos"].append(f"Subcódigos sin mapear (el paro se conserva sin subcódigo): {dict(sub_sin_mapear)}")

    ctx.update(reg=reg, paro=paro, empleado=empleado, referencia=referencia, mapa_privado=mapa_privado,
               sub_sin_mapear=sub_sin_mapear, legado_codigo5=legado_usado, excepciones=excepciones_usadas,
               turnos_nulos=int(reg["turno"].isna().sum()))
    ctx["control"] = {
        "registros": len(reg),
        "paros": len(paro),
        "minutos_paro": round(float(paro["minutos"].sum()), 1),
        "horas_trabajadas": round(float(reg["horas_trabajadas"].sum()), 2),
        "pacas": int(reg["pacas_producidas"].sum()),
        "empleados": len(empleado),
        "referencias": len(referencia),
        "paros_con_subcodigo": int(paro["subcodigo_clave"].notna().sum()),
    }
    return ctx


def escribir_csv(ctx: dict):
    DIR_LIMPIOS.mkdir(parents=True, exist_ok=True)
    DIR_REPORTES.mkdir(parents=True, exist_ok=True)
    DIR_PRIVADO.mkdir(parents=True, exist_ok=True)
    reg = ctx["reg"].drop(columns=["operario_real", "fila_excel"])
    paro = ctx["paro"].drop(columns=["personal_real", "fila_excel"])
    reg.to_csv(DIR_LIMPIOS / "registro_produccion.csv", index=False, encoding="utf-8")
    paro.to_csv(DIR_LIMPIOS / "paro.csv", index=False, encoding="utf-8")
    ctx["empleado"].to_csv(DIR_LIMPIOS / "empleado.csv", index=False, encoding="utf-8")
    ctx["referencia"].to_csv(DIR_LIMPIOS / "referencia.csv", index=False, encoding="utf-8")
    if len(ctx["descartes"]):
        d = ctx["descartes"].rename(columns={"Fecha": "fecha", "Maquina": "maquina", "_n_paros": "paros",
                                             "_min_total": "minutos"})
        d["fecha"] = pd.to_datetime(d["fecha"]).dt.date
        d.to_csv(DIR_REPORTES / "descartes_duplicados.csv", index=False, encoding="utf-8")
    ctx["mapa_privado"].to_csv(DIR_PRIVADO / "mapa_personas.csv", index=False, encoding="utf-8")


# --------------------------------------------------------------------------------------
# Etapa 2: cargar en PostgreSQL
# --------------------------------------------------------------------------------------


def cargar(ctx: dict, args) -> dict:
    try:
        import psycopg
    except ImportError:
        sys.exit("Falta la librería psycopg. Ejecute: pip install \"psycopg[binary]\"")

    password = os.environ.get("PGPASSWORD") or getpass.getpass(f"Contraseña de {args.user}@{args.host}: ")
    reg, paro, emp, ref = ctx["reg"], ctx["paro"], ctx["empleado"], ctx["referencia"]

    with psycopg.connect(host=args.host, port=args.port, dbname=args.db, user=args.user, password=password,
                         options="-c search_path=paros") as con:
        with con.cursor() as cur:
            existentes = cur.execute("SELECT COUNT(*) FROM registro_produccion").fetchone()[0]
            if existentes and not args.limpiar:
                sys.exit(f"La tabla registro_produccion ya tiene {existentes} filas. Use --limpiar para vaciarla.")
            if args.limpiar:
                cur.execute("TRUNCATE paro, registro_produccion, empleado, referencia RESTART IDENTITY CASCADE")

            ids_maquina = dict(cur.execute("SELECT nombre, id_maquina FROM maquina").fetchall())
            ids_turno = dict(cur.execute("SELECT nombre, id_turno FROM turno").fetchall())
            ids_tipo = dict(cur.execute("SELECT nombre, id_tipo_paro FROM tipo_paro_jornada").fetchall())
            ids_sub = {(c, cl): i for i, c, cl in
                       cur.execute("SELECT id_subcodigo, id_codigo, clave FROM subcodigo_paro").fetchall()}
            codigos = {r[0] for r in cur.execute("SELECT id_codigo FROM codigo_paro").fetchall()}
            if not (ids_maquina and ids_turno and ids_tipo and ids_sub and codigos):
                sys.exit("Los catálogos están vacíos. Ejecute primero sql/04_catalogos.sql.")
            if not set(paro["id_codigo"]).issubset(codigos):
                sys.exit("Hay códigos de paro que no existen en el catálogo.")

            with cur.copy("COPY empleado (nombre, tipo) FROM STDIN") as cp:
                for f in filas(emp[["nombre", "tipo"]]):
                    cp.write_row(f)
            ids_emp = dict(cur.execute("SELECT nombre, id_empleado FROM empleado").fetchall())

            with cur.copy("COPY referencia (nombre_original, marca, volumen_cc, num_colores) FROM STDIN") as cp:
                for f in filas(ref):
                    cp.write_row(f)
            ids_ref = dict(cur.execute("SELECT nombre_original, id_referencia FROM referencia").fetchall())

            r = pd.DataFrame({
                "id_registro": reg["id_registro"],
                "fecha": reg["fecha"],
                "id_maquina": reg["maquina"].map(ids_maquina).astype("Int64"),
                "id_turno": reg["turno"].map(ids_turno).astype("Int64"),
                "id_operario": reg["operario"].map(ids_emp).astype("Int64"),
                "id_referencia": reg["referencia"].map(ids_ref).astype("Int64"),
                "horas_trabajadas": reg["horas_trabajadas"],
                "horas_no_trabajadas": reg["horas_no_trabajadas"],
                "pacas_producidas": reg["pacas_producidas"],
                "id_tipo_paro": reg["tipo_paro"].map(ids_tipo).astype("Int64"),
                "observacion_paro": reg["observacion_paro"],
                "observaciones": reg["observaciones"],
            })
            cols_r = ("id_registro, fecha, id_maquina, id_turno, id_operario, id_referencia, horas_trabajadas, "
                      "horas_no_trabajadas, pacas_producidas, id_tipo_paro, observacion_paro, observaciones")
            with cur.copy(f"COPY registro_produccion ({cols_r}) FROM STDIN") as cp:
                for f in filas(r):
                    cp.write_row(f)

            sub_ids = [ids_sub.get((c, cl)) if isinstance(cl, str) else None
                       for c, cl in zip(paro["id_codigo"], paro["subcodigo_clave"])]
            p = pd.DataFrame({
                "id_paro": paro["id_paro"],
                "id_registro": paro["id_registro"],
                "id_codigo": paro["id_codigo"],
                "id_subcodigo": pd.Series(sub_ids, dtype="Int64"),
                "minutos": paro["minutos"],
                "id_empleado": paro["empleado"].map(ids_emp).astype("Int64"),
                "area_atencion": paro["area_atencion"],
            })
            cols_p = "id_paro, id_registro, id_codigo, id_subcodigo, minutos, id_empleado, area_atencion"
            with cur.copy(f"COPY paro ({cols_p}) FROM STDIN") as cp:
                for f in filas(p):
                    cp.write_row(f)

            # Las PK se insertaron con valores explícitos: se sincronizan las secuencias de identidad
            for tabla, col in (("registro_produccion", "id_registro"), ("paro", "id_paro")):
                cur.execute(f"SELECT setval(pg_get_serial_sequence('{tabla}', '{col}'), "
                            f"(SELECT MAX({col}) FROM {tabla}))")

            db = {
                "registros": cur.execute("SELECT COUNT(*) FROM registro_produccion").fetchone()[0],
                "paros": cur.execute("SELECT COUNT(*) FROM paro").fetchone()[0],
                "minutos_paro": float(cur.execute("SELECT COALESCE(SUM(minutos),0) FROM paro").fetchone()[0]),
                "horas_trabajadas": float(cur.execute("SELECT COALESCE(SUM(horas_trabajadas),0) FROM registro_produccion").fetchone()[0]),
                "pacas": int(cur.execute("SELECT COALESCE(SUM(pacas_producidas),0) FROM registro_produccion").fetchone()[0]),
                "empleados": cur.execute("SELECT COUNT(*) FROM empleado").fetchone()[0],
                "referencias": cur.execute("SELECT COUNT(*) FROM referencia").fetchone()[0],
                "paros_con_subcodigo": cur.execute("SELECT COUNT(*) FROM paro WHERE id_subcodigo IS NOT NULL").fetchone()[0],
            }
        con.commit()
    return db


# --------------------------------------------------------------------------------------
# Reporte
# --------------------------------------------------------------------------------------


def escribir_reporte(ctx: dict, db: dict | None, ruta_excel: Path):
    c = ctx["control"]
    L = []
    L.append("# Reporte de migración\n")
    L.append(f"Generado: {datetime.now():%Y-%m-%d %H:%M}  \nOrigen: hoja `{HOJA}` de `{ruta_excel.name}`\n")
    L.append("## 1. Del Excel a las filas migradas\n")
    L.append("| Concepto | Cantidad |\n|---|---|")
    L.append(f"| Filas en el Excel | {ctx['filas_excel']:,} |")
    L.append(f"| Duplicados exactos (58 columnas iguales) | {ctx['duplicados_total']} |")
    L.append(f"| Duplicados descartados | {ctx['duplicados_total'] if ctx['duplicados_descartados'] else 0} |")
    L.append(f"| **Registros a migrar** | **{c['registros']:,}** |")
    L.append(f"| Registros sin turno (días sin programación) | {ctx['turnos_nulos']:,} |")
    L.append(f"| Paros generados (códigos con minutos > 0) | {c['paros']:,} |")
    L.append(f"| Celdas de código con 0 minutos (no son paros) | {ctx['celdas_minutos_cero']} |")
    L.append(f"| Paros con subcódigo | {c['paros_con_subcodigo']:,} |")
    L.append(f"| Empleados (seudonimizados) | {c['empleados']} |")
    L.append(f"| Referencias | {c['referencias']} |\n")
    L.append("## 2. Decisiones de limpieza\n")
    L.append(f"- **Duplicados:** {ctx['duplicados_total']} filas idénticas en las 58 columnas. "
             f"{ctx['duplicados_con_paros']} de ellas contienen paros ({ctx['duplicados_paros']} paros, "
             f"{ctx['duplicados_minutos']:.0f} minutos). "
             + ("Se descartaron (ver `descartes_duplicados.csv`)." if ctx["duplicados_descartados"]
                else "Se conservaron por opción `--conservar-duplicados`."))
    L.append(f"- **Área y personal solo con código 05:** se descartó el área de {ctx['area_sin_codigo5']:,} filas "
             f"(valor por defecto de la macro, sin código 05) y el personal de {ctx['personal_sin_codigo5']} filas.")
    L.append(f"- **Numeración antigua del código 05 (4.x → 5.x):** {ctx['legado_codigo5']} paros reasignados.")
    for texto, n in ctx["excepciones"].items():
        L.append(f"- **Corrección puntual** `{texto}`: {n} paros.")
    L.append("- **\"Sin especificar\"** en subcódigos se guarda como NULL.")
    L.append("- **\"No aplica\"** (turno, operario, referencia, tipo de paro) se guarda como NULL.")
    L.append("- **Horas/pacas vacías** se guardan como 0 (días sin producción).")
    L.append("- **Nombres de personas** reemplazados por seudónimos; la correspondencia queda fuera del repositorio.")
    L.append(f"- **Textos libres:** {ctx['obs_enmascaradas']} observaciones nombraban personas y se enmascararon como `[persona]`.\n")
    if ctx["avisos"]:
        L.append("## 3. Avisos\n")
        L += [f"- {a}" for a in ctx["avisos"]]
        L.append("")
    L.append("## 4. Totales de control\n")
    if db is None:
        L.append("| Indicador | Esperado (Excel limpio) |\n|---|---|")
        for key, label in (("registros", "Registros"), ("paros", "Paros"), ("minutos_paro", "Minutos de paro"),
                           ("horas_trabajadas", "Horas trabajadas"), ("pacas", "Pacas producidas")):
            L.append(f"| {label} | {c[key]:,} |")
        L.append("\n_Aún no se ha cargado en la base de datos (ejecute con `--cargar`)._")
    else:
        L.append("| Indicador | Excel limpio | PostgreSQL | ¿Coincide? |\n|---|---|---|---|")
        todo_ok = True
        for key, label in (("registros", "Registros"), ("paros", "Paros"), ("minutos_paro", "Minutos de paro"),
                           ("horas_trabajadas", "Horas trabajadas"), ("pacas", "Pacas producidas"),
                           ("empleados", "Empleados"), ("referencias", "Referencias"),
                           ("paros_con_subcodigo", "Paros con subcódigo")):
            ok = abs(float(c[key]) - float(db[key])) < 0.05
            todo_ok &= ok
            L.append(f"| {label} | {c[key]:,} | {db[key]:,} | {'✅' if ok else '❌'} |")
        L.append(f"\n**Resultado: {'los datos llegaron íntegros' if todo_ok else 'HAY DIFERENCIAS, revisar'}.**")
    DIR_REPORTES.mkdir(parents=True, exist_ok=True)
    (DIR_REPORTES / "reporte_migracion.md").write_text("\n".join(L) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------------------
# Programa principal
# --------------------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description="Migra el Excel de paros de producción a PostgreSQL.")
    ap.add_argument("--excel", type=Path, help="Ruta del .xlsm (por defecto, el primero en datos_originales/)")
    ap.add_argument("--cargar", action="store_true", help="Cargar en PostgreSQL (si no, solo genera CSV y reporte)")
    ap.add_argument("--limpiar", action="store_true", help="Vaciar tablas transaccionales antes de cargar")
    ap.add_argument("--conservar-duplicados", action="store_true", help="No descartar los duplicados exactos")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--port", type=int, default=5432)
    ap.add_argument("--db", default="paros_produccion")
    ap.add_argument("--user", default="postgres")
    args = ap.parse_args()

    ruta = args.excel
    if ruta is None:
        candidatos = sorted(DIR_ORIGINALES.glob("*.xls*"))
        if not candidatos:
            sys.exit(f"Coloque el Excel en {DIR_ORIGINALES}")
        ruta = candidatos[0]
    print(f"[1/3] Leyendo {ruta.name} ...")
    df = leer_excel(ruta)

    print("[2/3] Transformando ...")
    ctx = transformar(df, args.conservar_duplicados)
    if ctx["problemas"]:
        print("\nSe encontraron problemas que impiden cargar:")
        for p in ctx["problemas"]:
            print("  -", p)
        sys.exit(1)
    escribir_csv(ctx)
    for a in ctx["avisos"]:
        print("  (aviso)", a)
    c = ctx["control"]
    print(f"      {ctx['filas_excel']:,} filas -> {c['registros']:,} registros, {c['paros']:,} paros, "
          f"{c['empleados']} empleados, {c['referencias']} referencias")

    db = None
    if args.cargar:
        print("[3/3] Cargando en PostgreSQL ...")
        db = cargar(ctx, args)
        print("      Carga completada.")
    else:
        print("[3/3] Carga omitida (use --cargar para insertar en PostgreSQL).")

    escribir_reporte(ctx, db, ruta)
    print(f"\nReporte: {DIR_REPORTES / 'reporte_migracion.md'}")


if __name__ == "__main__":
    main()