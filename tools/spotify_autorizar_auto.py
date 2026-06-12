"""OAuth de Spotify NO interactivo — guarda el refresh token sin imprimirlo.

Variante de spotify_autorizar.py para flujo automatizado (Claude/agente):
  1. Lee SPOTIFY_CLIENT_ID/SECRET y SUPABASE_URL/SERVICE_ROLE_KEY de
     cerebro/.env (gitignored) o del entorno.
  2. Levanta el callback en http://127.0.0.1:8888/callback e imprime SOLO la
     URL de autorización (no es secreta) para abrirla en el navegador.
  3. Al volver el code: lo canjea, y guarda el SPOTIFY_REFRESH_TOKEN
     directamente en cerebro/.env y en la tabla `secretos_runtime` de
     Supabase (RLS sin políticas; solo service role). También sube
     CLIENT_ID/SECRET a la tabla para que el cerebro en Railway los lea.
  4. Imprime únicamente estados (OK/FALLO) — JAMÁS los valores.

Solo stdlib. Uso: python tools/spotify_autorizar_auto.py
"""
from __future__ import annotations

import base64
import http.server
import json
import os
import secrets as pysecrets
import sys
import urllib.parse
import urllib.request
from pathlib import Path

REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "user-modify-playback-state user-read-playback-state"
RAIZ = Path(__file__).resolve().parent.parent
ENV_CEREBRO = RAIZ / "cerebro" / ".env"


def _leer_env_archivo(ruta: Path) -> dict[str, str]:
    datos: dict[str, str] = {}
    if not ruta.is_file():
        return datos
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        k, _, v = linea.partition("=")
        datos[k.strip()] = v.strip().strip('"').strip("'")
    return datos


def _valor(nombre: str, env_archivo: dict[str, str]) -> str | None:
    return os.getenv(nombre) or env_archivo.get(nombre)


def _poner_en_env(ruta: Path, nombre: str, valor: str) -> None:
    """Reemplaza o agrega `nombre=valor` en el .env, preservando el resto."""
    lineas: list[str] = []
    visto = False
    if ruta.is_file():
        for linea in ruta.read_text(encoding="utf-8").splitlines():
            if linea.split("=", 1)[0].strip() == nombre:
                lineas.append(f"{nombre}={valor}")
                visto = True
            else:
                lineas.append(linea)
    if not visto:
        lineas.append(f"{nombre}={valor}")
    ruta.write_text("\n".join(lineas) + "\n", encoding="utf-8")


def _upsert_secreto(url_supabase: str, service_key: str, clave: str, valor: str) -> bool:
    cuerpo = json.dumps({"clave": clave, "valor": valor}).encode()
    req = urllib.request.Request(
        f"{url_supabase}/rest/v1/secretos_runtime",
        data=cuerpo,
        method="POST",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status in (200, 201, 204)
    except Exception as e:  # noqa: BLE001
        print(f"  fallo al subir «{clave}» a secretos_runtime: {type(e).__name__}")
        return False


def main() -> int:
    env_archivo = _leer_env_archivo(ENV_CEREBRO)
    cid = _valor("SPOTIFY_CLIENT_ID", env_archivo)
    sec = _valor("SPOTIFY_CLIENT_SECRET", env_archivo)
    su_url = _valor("SUPABASE_URL", env_archivo)
    su_key = _valor("SUPABASE_SERVICE_ROLE_KEY", env_archivo)
    if not cid or not sec:
        print("FALTA: SPOTIFY_CLIENT_ID/SECRET en cerebro/.env o el entorno.")
        return 1

    estado = pysecrets.token_urlsafe(16)
    url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
        "client_id": cid,
        "response_type": "code",
        "redirect_uri": REDIRECT,
        "scope": SCOPES,
        "state": estado,
    })
    print("AUTORIZA_EN: " + url, flush=True)

    codigo: list[str | None] = [None]

    class _Callback(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if q.get("state", [None])[0] != estado:
                self.send_error(400, "state invalido")
                return
            codigo[0] = q.get("code", [None])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("<h2>Listo. Matix quedo autorizado.</h2>".encode())

        def log_message(self, *a: object) -> None:
            pass

    with http.server.HTTPServer(("127.0.0.1", 8888), _Callback) as srv:
        srv.timeout = 300
        print("esperando el callback (max 5 min)...", flush=True)
        while codigo[0] is None:
            srv.handle_request()

    if not codigo[0]:
        print("FALLO: no llego el code en el callback.")
        return 1

    basic = base64.b64encode(f"{cid}:{sec}".encode()).decode()
    datos = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": codigo[0],
        "redirect_uri": REDIRECT,
    }).encode()
    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token",
        data=datos,
        headers={"Authorization": f"Basic {basic}"},
    )
    with urllib.request.urlopen(req) as resp:
        cuerpo = json.load(resp)
    refresh = cuerpo.get("refresh_token")
    if not refresh:
        print("FALLO: Spotify no devolvio refresh_token.")
        return 1

    _poner_en_env(ENV_CEREBRO, "SPOTIFY_REFRESH_TOKEN", refresh)
    _poner_en_env(ENV_CEREBRO, "SPOTIFY_CLIENT_ID", cid)
    _poner_en_env(ENV_CEREBRO, "SPOTIFY_CLIENT_SECRET", sec)
    print("OK: refresh token guardado en cerebro/.env (sin imprimirlo).")

    if su_url and su_key:
        subidos = all(
            _upsert_secreto(su_url, su_key, clave, valor)
            for clave, valor in (
                ("SPOTIFY_CLIENT_ID", cid),
                ("SPOTIFY_CLIENT_SECRET", sec),
                ("SPOTIFY_REFRESH_TOKEN", refresh),
            )
        )
        print("OK: secretos subidos a secretos_runtime." if subidos
              else "PARCIAL: algun secreto no se pudo subir a secretos_runtime.")
    else:
        print("AVISO: sin SUPABASE_URL/SERVICE_ROLE_KEY; no se subio a la tabla.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
