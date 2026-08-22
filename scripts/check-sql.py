#!/usr/bin/env python3
"""Valida la sintaxis de las migraciones contra la gramática real de PostgreSQL.

Las migraciones se corren a mano en el SQL Editor de Supabase, así que un error de sintaxis
se descubre a mitad del pegado, con media migración aplicada. Esto lo caza antes: usa
libpg_query (el parser del propio Postgres) para las sentencias y para los cuerpos plpgsql,
que el parser SQL trata como cadenas opacas.

Lo que NO valida: que las tablas y columnas existan, los tipos, o la RLS. Es sintaxis.

    python3 scripts/check-sql.py                 # todas las migraciones
    python3 scripts/check-sql.py migrations/076_skandi_dishes.sql
"""

import glob
import re
import sys

try:
    from pglast.parser import ParseError, get_postgresql_version, parse_plpgsql_json, parse_sql
except ImportError:
    print("Falta pglast. Instálalo con:  python3 -m pip install --user pglast")
    sys.exit(2)

FUNCTION = re.compile(r'create\s+or\s+replace\s+function.*?\$\$.*?\$\$\s*;', re.I | re.S)


def check(path):
    sql = open(path, encoding='utf-8').read()
    try:
        statements = parse_sql(sql)
    except ParseError as exc:
        print(f"✗ {path}: {exc}")
        return False

    ok = True
    bodies = 0
    for match in FUNCTION.finditer(sql):
        try:
            parse_plpgsql_json(match.group(0))
            bodies += 1
        except ParseError as exc:
            name = re.search(r'function\s+([\w.]+)', match.group(0), re.I)
            print(f"✗ {path} → {name.group(1) if name else '?'}: {exc}")
            ok = False

    if ok:
        print(f"✓ {path}: {len(statements)} sentencias, {bodies} funciones plpgsql")
    return ok


def main():
    paths = sys.argv[1:] or sorted(glob.glob('migrations/*.sql'))
    if not paths:
        print("No encontré migraciones que revisar.")
        return 1
    major, minor = get_postgresql_version()
    print(f"Parser PostgreSQL {major}.{minor} — {len(paths)} archivo(s)\n")
    failed = [p for p in paths if not check(p)]
    print()
    if failed:
        print(f"{len(failed)} archivo(s) con errores de sintaxis.")
        return 1
    print("Sintaxis correcta en todos.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
