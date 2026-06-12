"""Autorización OAuth de Spotify — se corre UNA sola vez, a mano, por el dueño.

Obtiene el SPOTIFY_REFRESH_TOKEN que el cerebro necesita para ORDENAR
reproducción real (PUT /v1/me/player/play, requiere cuenta Premium).

Pasos previos (5 minutos):
  1. Entra a https://developer.spotify.com/dashboard y crea una app
     (nombre libre, ej. "Matix").
  2. En la app: Settings → Redirect URIs → agrega EXACTO:
         http://127.0.0.1:8888/callback
  3. Copia el Client ID y el Client Secret.

Uso (PowerShell, desde la raíz del repo):
  $env:SPOTIFY_CLIENT_ID = "<client id>"
  $env:SPOTIFY_CLIENT_SECRET = "<client secret>"
  python tools/spotify_autorizar.py

El script abre tu navegador para que des consentimiento con TU cuenta de
Spotify, captura el código en localhost y te imprime el refresh token EN TU
CONSOLA (no se guarda en ningún archivo del repo). Luego configura las TRES
variables en Railway (servicio del cerebro) y opcionalmente en cerebro/.env:
  SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, SPOTIFY_REFRESH_TOKEN

Solo stdlib: corre con cualquier Python 3.10+.
"""
from __future__ import annotations

import base64
import http.server
import json
import os
import secrets
import sys
import urllib.parse
import urllib.request
import webbrowser

REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "user-modify-playback-state user-read-playback-state"


def main() -> int:
    cid = os.getenv("SPOTIFY_CLIENT_ID")
    sec = os.getenv("SPOTIFY_CLIENT_SECRET")
    if not cid or not sec:
        print("Falta SPOTIFY_CLIENT_ID y/o SPOTIFY_CLIENT_SECRET en el entorno.")
        print("Lee el docstring de este script para los pasos.")
        return 1

    estado = secrets.token_urlsafe(16)
    url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
        "client_id": cid,
        "response_type": "code",
        "redirect_uri": REDIRECT,
        "scope": SCOPES,
        "state": estado,
    })
    print("Abriendo el navegador para el consentimiento de Spotify...")
    print("(si no se abre solo, copia esta URL):\n" + url + "\n")
    webbrowser.open(url)

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
            self.wfile.write("<h2>Listo. Vuelve a la consola.</h2>".encode())

        def log_message(self, *a: object) -> None:  # silencio
            pass

    with http.server.HTTPServer(("127.0.0.1", 8888), _Callback) as srv:
        print("Esperando el callback en 127.0.0.1:8888 ...")
        while codigo[0] is None:
            srv.handle_request()

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
        print("Spotify no devolvió refresh_token:", {k: "..." for k in cuerpo})
        return 1
    print("\n=== TU REFRESH TOKEN (guárdalo como SPOTIFY_REFRESH_TOKEN) ===\n")
    print(refresh)
    print(
        "\nConfigúralo en Railway (variables del servicio del cerebro) junto a "
        "SPOTIFY_CLIENT_ID y SPOTIFY_CLIENT_SECRET, y redeploya. "
        "Opcional: también en cerebro/.env para pruebas locales."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
