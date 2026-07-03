#!/usr/bin/env bash
#
# Keep-alive de Supabase: hace UNA query REAL y minúscula a la BD para que el
# free tier NO pause el proyecto por inactividad (~7 días sin requests). Lo corre
# el GitHub Action `.github/workflows/keepalive.yml` cada ~3 días.
#
# Reusa los MISMOS secrets del release (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY):
# no hace falta ningún secret nuevo. NUNCA imprime la key (solo el código HTTP).
set -euo pipefail
: "${SUPABASE_URL:?falta SUPABASE_URL}"
: "${SUPABASE_SERVICE_ROLE_KEY:?falta SUPABASE_SERVICE_ROLE_KEY}"

code=$(curl -s -o /dev/null -w "%{http_code}" \
  "$SUPABASE_URL/rest/v1/app_versions?select=id&limit=1" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY")

echo "keep-alive HTTP $code"
# 2xx = OK. 402 (cuota excedida) TAMBIÉN cuenta como actividad para el anti-pausa:
# no lo tratamos como fallo del keep-alive mientras la cuota se resuelve aparte.
case "$code" in
  2*|402) echo "OK — proyecto activo"; exit 0 ;;
  *) echo "keep-alive: respuesta inesperada ($code)" >&2; exit 1 ;;
esac
