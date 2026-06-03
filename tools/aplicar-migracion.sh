#!/usr/bin/env bash
#
# Aplica una migración SQL a Supabase (prod) usando la Management API y el
# access token guardado en el archivo GITIGNORED tools/.env.prod.local.
#
#   uso:  bash tools/aplicar-migracion.sh supabase/migrations/00NN_xxx.sql
#
# - El token sale SOLO del env file (SUPABASE_ACCESS_TOKEN); NUNCA se imprime ni
#   se versiona. project ref en SUPABASE_PROJECT_REF.
# - Aplica el SQL tal cual (idóneo para `create table/column/index ... if not
#   exists`). NO ejecutes aquí operaciones destructivas (DROP/DELETE/TRUNCATE/
#   ALTER que borra) sin confirmación explícita del usuario.
# - Tras aplicar, deja el .sql commiteado en supabase/migrations/ y verifica el
#   esquema resultante (otra consulta a information_schema).
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$AQUI/.env.prod.local"
[ -f "$ENV_FILE" ] || { echo "Falta $ENV_FILE (con SUPABASE_ACCESS_TOKEN y SUPABASE_PROJECT_REF)"; exit 1; }
set -a; . "$ENV_FILE"; set +a
: "${SUPABASE_ACCESS_TOKEN:?falta SUPABASE_ACCESS_TOKEN en el env file}"
: "${SUPABASE_PROJECT_REF:?falta SUPABASE_PROJECT_REF en el env file}"

SQL_FILE="${1:-}"
[ -n "$SQL_FILE" ] || { echo "uso: bash tools/aplicar-migracion.sh <archivo.sql>"; exit 1; }
[ -f "$SQL_FILE" ] || { echo "No existe: $SQL_FILE"; exit 1; }

# Construimos el JSON con python (escapa el SQL correctamente).
PAYLOAD=$(python -c "import json,sys; print(json.dumps({'query': open(sys.argv[1], encoding='utf-8').read()}))" "$SQL_FILE")

# La respuesta + el código HTTP en la última línea (sin archivos temporales).
OUT=$(curl -s -w $'\n%{http_code}' \
  -X POST "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")
HTTP=$(printf '%s' "$OUT" | tail -n1)
BODY=$(printf '%s' "$OUT" | sed '$d')

echo "HTTP $HTTP"
echo "$BODY"
# La Management API devuelve 200 o 201 según la consulta; cualquier 2xx es OK.
if ! { [ "$HTTP" -ge 200 ] 2>/dev/null && [ "$HTTP" -lt 300 ] 2>/dev/null; }; then
  echo "FALLÓ al aplicar $SQL_FILE"
  exit 1
fi
echo "OK — migración aplicada: $SQL_FILE"
