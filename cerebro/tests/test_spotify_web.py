"""Spotify Web API (spotify_web) + pipeline de pc_reproducir_spotify.

Todo PURO: httpx.MockTransport para la API y canal falso para el agente.
Cubre: credenciales ausentes (degrada limpio), búsqueda elige el más popular,
playback apunta al dispositivo Computer, y la HONESTIDAD del handler (dice
«sonando» solo si se midió; sin credenciales narra el muro con los NOMBRES
de las variables)."""
from __future__ import annotations

import httpx
import pytest

from app.matix import secretos, spotify_web, tools


@pytest.fixture(autouse=True)
def _sin_env(monkeypatch):
    for v in ("SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET", "SPOTIFY_REFRESH_TOKEN",
              "SUPABASE_SERVICE_ROLE_KEY"):
        monkeypatch.delenv(v, raising=False)
    spotify_web._limpiar_cache()
    secretos._limpiar_cache()
    yield
    spotify_web._limpiar_cache()
    secretos._limpiar_cache()


def _cliente(rutas: dict[str, httpx.Response]) -> httpx.AsyncClient:
    """Cliente con transporte mock: la clave es '<METODO> <path>'."""

    def manejar(req: httpx.Request) -> httpx.Response:
        clave = f"{req.method} {req.url.path}"
        if clave in rutas:
            return rutas[clave]
        return httpx.Response(404, json={"error": f"sin ruta {clave}"})

    return httpx.AsyncClient(transport=httpx.MockTransport(manejar))


def _con_creds(monkeypatch, refresh: bool = False) -> None:
    monkeypatch.setenv("SPOTIFY_CLIENT_ID", "cid-test")
    monkeypatch.setenv("SPOTIFY_CLIENT_SECRET", "sec-test")
    if refresh:
        monkeypatch.setenv("SPOTIFY_REFRESH_TOKEN", "rt-test")


_TOKEN_OK = httpx.Response(200, json={"access_token": "tok", "expires_in": 3600})


# ── Credenciales y muro ──────────────────────────────────────────────────────


async def test_sin_credenciales_nada_disponible():
    assert not await spotify_web.busqueda_disponible()
    assert not await spotify_web.playback_disponible()
    falta = await spotify_web.que_falta_para_playback()
    # Nombra las variables (solo NOMBRES) y el cómo conseguirlas.
    assert "SPOTIFY_CLIENT_ID" in falta and "SPOTIFY_REFRESH_TOKEN" in falta
    assert "spotify_autorizar" in falta


async def test_con_credenciales_pero_sin_refresh(monkeypatch):
    _con_creds(monkeypatch)
    assert await spotify_web.busqueda_disponible()
    assert not await spotify_web.playback_disponible()
    falta = await spotify_web.que_falta_para_playback()
    assert "SPOTIFY_REFRESH_TOKEN" in falta and "SPOTIFY_CLIENT_ID" not in falta


# ── OAuth authorization-code (conectar desde la app) ─────────────────────────


async def test_url_de_autorizacion(monkeypatch):
    _con_creds(monkeypatch)
    url = await spotify_web.url_de_autorizacion("estado123")
    assert url.startswith("https://accounts.spotify.com/authorize?")
    assert "client_id=cid-test" in url
    assert "response_type=code" in url
    assert "user-modify-playback-state" in url
    assert "user-read-playback-state" in url
    assert "state=estado123" in url
    # Redirect al endpoint público del cerebro.
    assert "spotify%2Fcallback" in url or "spotify/callback" in url


async def test_url_de_autorizacion_sin_creds_lanza(monkeypatch):
    with pytest.raises(RuntimeError):
        await spotify_web.url_de_autorizacion("x")


async def test_intercambiar_code_guarda_refresh(monkeypatch):
    _con_creds(monkeypatch)
    guardado = {}

    async def fake_guardar(clave, valor, cliente=None):
        guardado[clave] = valor
        return True

    monkeypatch.setattr(spotify_web.secretos, "guardar", fake_guardar)
    cli = _cliente({"POST /api/token": httpx.Response(200, json={
        "access_token": "ac", "refresh_token": "EL-REFRESH", "expires_in": 3600,
    })})
    ok = await spotify_web.intercambiar_code("code-abc", cliente=cli)
    assert ok is True
    # El refresh quedó guardado y la conexión pasa a disponible.
    assert guardado.get("SPOTIFY_REFRESH_TOKEN") == "EL-REFRESH"
    assert await spotify_web.conectado() is True
    assert await spotify_web.playback_disponible() is True


async def test_intercambiar_code_sin_refresh_en_respuesta(monkeypatch):
    _con_creds(monkeypatch)
    cli = _cliente({"POST /api/token": httpx.Response(200, json={"access_token": "ac"})})
    assert await spotify_web.intercambiar_code("code-abc", cliente=cli) is False


async def test_intercambiar_code_error_api(monkeypatch):
    _con_creds(monkeypatch)
    cli = _cliente({"POST /api/token": httpx.Response(400, json={"error": "invalid_grant"})})
    assert await spotify_web.intercambiar_code("code-malo", cliente=cli) is False


# ── Fallback de credenciales en Supabase (secretos_runtime) ──────────────────


async def test_secretos_fallback_en_supabase(monkeypatch):
    # Sin env vars de Spotify, pero con la tabla secretos_runtime poblada:
    # las credenciales llegan igual (env PRIMERO, DB después, cacheado).
    monkeypatch.setenv("SUPABASE_URL", "https://fake.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "srk-test")
    pedidos = []

    valores = {"SPOTIFY_CLIENT_ID": "cid-db", "SPOTIFY_CLIENT_SECRET": "sec-db",
               "SPOTIFY_REFRESH_TOKEN": "rt-db"}

    def manejar(req: httpx.Request) -> httpx.Response:
        clave = req.url.params.get("clave", "").removeprefix("eq.")
        pedidos.append(clave)
        v = valores.get(clave)
        return httpx.Response(200, json=([{"valor": v}] if v else []))

    cli = httpx.AsyncClient(transport=httpx.MockTransport(manejar))
    for clave, esperado in valores.items():
        assert await secretos.obtener(clave, cliente=cli) == esperado
    # Cacheado: una segunda lectura no vuelve a la red.
    n = len(pedidos)
    assert await secretos.obtener("SPOTIFY_CLIENT_ID", cliente=cli) == "cid-db"
    assert len(pedidos) == n


async def test_secretos_env_gana_sobre_db(monkeypatch):
    monkeypatch.setenv("SPOTIFY_CLIENT_ID", "cid-env")

    def explota(req: httpx.Request) -> httpx.Response:
        raise AssertionError("no debe tocar la red si la env var existe")

    cli = httpx.AsyncClient(transport=httpx.MockTransport(explota))
    assert await secretos.obtener("SPOTIFY_CLIENT_ID", cliente=cli) == "cid-env"


async def test_secretos_sin_service_role_devuelve_none(monkeypatch):
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)
    assert await secretos.obtener("SPOTIFY_CLIENT_ID") is None


async def test_buscar_sin_creds_devuelve_none():
    assert await spotify_web.buscar_mejor_track("Michael Jackson") is None


# ── Búsqueda: elige el track MÁS POPULAR ─────────────────────────────────────


async def test_buscar_elige_el_mas_popular(monkeypatch):
    _con_creds(monkeypatch)
    items = [
        {"id": "a", "uri": "spotify:track:a", "name": "Rara", "popularity": 10,
         "artists": [{"name": "MJ"}]},
        {"id": "b", "uri": "spotify:track:b", "name": "Billie Jean", "popularity": 92,
         "artists": [{"name": "Michael Jackson"}]},
    ]
    cli = _cliente({
        "POST /api/token": _TOKEN_OK,
        "GET /v1/search": httpx.Response(200, json={"tracks": {"items": items}}),
    })
    t = await spotify_web.buscar_mejor_track("Michael Jackson", cliente=cli)
    assert t["id"] == "b" and t["nombre"] == "Billie Jean"
    assert t["artista"] == "Michael Jackson"


async def test_buscar_api_caida_degrada_a_none(monkeypatch):
    _con_creds(monkeypatch)
    cli = _cliente({"POST /api/token": _TOKEN_OK,
                    "GET /v1/search": httpx.Response(500)})
    assert await spotify_web.buscar_mejor_track("x", cliente=cli) is None


# ── Playback: apunta al dispositivo Computer ─────────────────────────────────


async def test_reproducir_elige_computer_y_da_play(monkeypatch):
    _con_creds(monkeypatch, refresh=True)
    visto = {}

    def manejar(req: httpx.Request) -> httpx.Response:
        if req.url.path == "/api/token":
            return _TOKEN_OK
        if req.url.path == "/v1/me/player/devices":
            return httpx.Response(200, json={"devices": [
                {"id": "cel", "type": "Smartphone", "name": "Telefono"},
                {"id": "pc1", "type": "Computer", "name": "MI-PC"},
            ]})
        if req.url.path == "/v1/me/player/play":
            visto["device"] = req.url.params.get("device_id")
            visto["cuerpo"] = req.read().decode()
            return httpx.Response(204)
        return httpx.Response(404)

    cli = httpx.AsyncClient(transport=httpx.MockTransport(manejar))
    r = await spotify_web.reproducir_en_pc("spotify:track:abc", cliente=cli)
    assert r["ok"] and r["dispositivo"] == "MI-PC"
    assert visto["device"] == "pc1"
    assert "spotify:track:abc" in visto["cuerpo"] and "uris" in visto["cuerpo"]


async def test_reproducir_prefiere_el_device_por_nombre(monkeypatch):
    # Con laptop Y pc como "Computer", gana el que coincide con
    # SPOTIFY_DEVICE_NAME (case-insensitive) — nunca la laptop por accidente.
    _con_creds(monkeypatch, refresh=True)
    monkeypatch.setenv("SPOTIFY_DEVICE_NAME", "gp")
    visto = {}

    def manejar(req: httpx.Request) -> httpx.Response:
        if req.url.path == "/api/token":
            return _TOKEN_OK
        if req.url.path == "/v1/me/player/devices":
            return httpx.Response(200, json={"devices": [
                {"id": "lap", "type": "Computer", "name": "LAPTOP-X"},
                {"id": "pc1", "type": "Computer", "name": "GP"},
            ]})
        if req.url.path == "/v1/me/player/play":
            visto["device"] = req.url.params.get("device_id")
            return httpx.Response(204)
        return httpx.Response(404)

    cli = httpx.AsyncClient(transport=httpx.MockTransport(manejar))
    r = await spotify_web.reproducir_en_pc("spotify:track:abc", cliente=cli)
    assert r["ok"] and visto["device"] == "pc1"


async def test_reproducir_sin_dispositivos(monkeypatch):
    _con_creds(monkeypatch, refresh=True)
    cli = _cliente({
        "POST /api/token": _TOKEN_OK,
        "GET /v1/me/player/devices": httpx.Response(200, json={"devices": []}),
    })
    r = await spotify_web.reproducir_en_pc("spotify:track:abc", cliente=cli)
    assert not r["ok"] and r["tipo"] == "sin_dispositivo"


async def test_reproducir_sin_oauth_no_revienta():
    r = await spotify_web.reproducir_en_pc("spotify:track:abc")
    assert not r["ok"] and r["tipo"] == "sin_oauth"


# ── Handler pc_reproducir_spotify: directo y HONESTO ─────────────────────────


async def test_handler_suena_de_una_en_el_cliente(monkeypatch):
    # El agente abre el track y mide que SÍ suena → estado sonando, sin Web API.
    async def fake_enviar(nombre, args, **kw):
        assert nombre == "reproducir_spotify"
        return {"ok": True, "tipo": "spotify_abierto", "uri": args.get("uri"),
                "sonando": True, "reproduciendo": "MJ - Billie Jean"}

    monkeypatch.setattr(tools.canal, "enviar_accion", fake_enviar)
    res = await tools.ejecutar_tool(None, "pc_reproducir_spotify",
                                    {"uri": "spotify:track:abc"})
    assert res["ok"] and res["datos"]["estado"] == "sonando"
    assert "accion_dispositivo" not in res["datos"]  # DIRECTO, sin confirmación


async def test_handler_honesto_sin_credenciales(monkeypatch):
    # Sin Web API: abre el track, NO suena → estado honesto + nombra el muro.
    async def fake_enviar(nombre, args, **kw):
        return {"ok": True, "tipo": "spotify_abierto", "uri": args.get("uri"),
                "sonando": False, "reproduciendo": None}

    monkeypatch.setattr(tools.canal, "enviar_accion", fake_enviar)
    res = await tools.ejecutar_tool(None, "pc_reproducir_spotify",
                                    {"uri": "spotify:track:abc"})
    assert res["ok"] and res["datos"]["estado"] == "abierto_sin_sonar"
    assert "SPOTIFY_REFRESH_TOKEN" in res["datos"]["mensaje"]  # el muro, claro


async def test_handler_resuelve_consulta_y_da_play_por_api(monkeypatch):
    # VÍA GARANTIZADA completa: busca el top track, el device de ESTA PC está
    # listo, play por la Web API, re-verifica audio y recién ahí dice «puse X».
    _con_creds(monkeypatch, refresh=True)
    llamadas = []

    async def fake_buscar(consulta, cliente=None):
        return {"id": "b", "uri": "spotify:track:b", "nombre": "Billie Jean",
                "artista": "Michael Jackson"}

    async def fake_device(cliente=None):
        return {"id": "pc1", "name": "GP", "type": "Computer"}

    async def fake_play(uri, cliente=None):
        llamadas.append(("play", uri))
        return {"ok": True, "dispositivo": "GP"}

    async def fake_enviar(nombre, args, **kw):
        llamadas.append((nombre, args))
        if nombre == "verificar_spotify":
            return {"ok": True, "sonando": True,
                    "reproduciendo": "Michael Jackson - Billie Jean"}
        raise AssertionError(f"acción inesperada: {nombre}")

    monkeypatch.setattr(tools.spotify_web, "buscar_mejor_track", fake_buscar)
    monkeypatch.setattr(tools.spotify_web, "dispositivo_objetivo", fake_device)
    monkeypatch.setattr(tools.spotify_web, "reproducir_en_pc", fake_play)
    monkeypatch.setattr(tools.canal, "enviar_accion", fake_enviar)
    res = await tools.ejecutar_tool(None, "pc_reproducir_spotify",
                                    {"consulta": "Michael Jackson"})
    assert res["ok"] and res["datos"]["estado"] == "sonando"
    assert ("play", "spotify:track:b") in llamadas
    assert res["datos"]["reproduciendo"] == "Michael Jackson - Billie Jean"
    assert "Billie Jean" in res["datos"]["mensaje"]
    # Con la API confirmando, NO se cae al fallback de abrir el cliente.
    assert not any(n == "reproducir_spotify" for n, _ in llamadas)


async def test_handler_play_por_api_pero_sin_sonido_es_honesto(monkeypatch):
    # La API CONFIRMÓ el play pero el medidor local no detecta audio: el estado
    # lo dice exacto (orden confirmada, sin audio local) — nunca fingir éxito.
    _con_creds(monkeypatch, refresh=True)

    async def fake_device(cliente=None):
        return {"id": "pc1", "name": "GP", "type": "Computer"}

    async def fake_play(uri, cliente=None):
        return {"ok": True, "dispositivo": "GP"}

    async def fake_enviar(nombre, args, **kw):
        assert nombre == "verificar_spotify"
        return {"ok": True, "sonando": False, "reproduciendo": None}

    monkeypatch.setattr(tools.spotify_web, "dispositivo_objetivo", fake_device)
    monkeypatch.setattr(tools.spotify_web, "reproducir_en_pc", fake_play)
    monkeypatch.setattr(tools.canal, "enviar_accion", fake_enviar)
    res = await tools.ejecutar_tool(None, "pc_reproducir_spotify",
                                    {"uri": "spotify:track:abc"})
    assert res["datos"]["estado"] == "reproduccion_ordenada"
    assert "CONFIRMÓ" in res["datos"]["mensaje"]
    assert "volumen" in res["datos"]["mensaje"]


async def test_handler_abre_spotify_si_no_hay_device_y_espera(monkeypatch):
    # Spotify cerrado: no hay device → lo ABRE vía el agente, espera (acotado)
    # a que se registre y recién entonces ordena el play.
    _con_creds(monkeypatch, refresh=True)
    monkeypatch.setattr(tools, "_ESPERA_DISPOSITIVO_S", 0.0)
    estado = {"intentos": 0}
    llamadas = []

    async def fake_device(cliente=None):
        estado["intentos"] += 1
        if estado["intentos"] < 3:
            return None  # recién abierto: aún no se registra
        return {"id": "pc1", "name": "GP", "type": "Computer"}

    async def fake_play(uri, cliente=None):
        llamadas.append(("play", uri))
        return {"ok": True, "dispositivo": "GP"}

    async def fake_enviar(nombre, args, **kw):
        llamadas.append((nombre, args))
        if nombre == "abrir_app":
            assert args == {"nombre": "spotify"}
            return {"ok": True, "tipo": "app_abierta", "app": "spotify"}
        if nombre == "verificar_spotify":
            return {"ok": True, "sonando": True, "reproduciendo": "X - Y"}
        raise AssertionError(f"acción inesperada: {nombre}")

    monkeypatch.setattr(tools.spotify_web, "dispositivo_objetivo", fake_device)
    monkeypatch.setattr(tools.spotify_web, "reproducir_en_pc", fake_play)
    monkeypatch.setattr(tools.canal, "enviar_accion", fake_enviar)
    res = await tools.ejecutar_tool(None, "pc_reproducir_spotify",
                                    {"uri": "spotify:track:abc"})
    assert res["datos"]["estado"] == "sonando"
    assert ("abrir_app", {"nombre": "spotify"}) in llamadas
    assert ("play", "spotify:track:abc") in llamadas


async def test_handler_causa_exacta_si_el_device_nunca_aparece(monkeypatch):
    # Si ni abriendo Spotify se registra el device, cae al fallback (abrir y
    # medir) y el mensaje trae la CAUSA exacta, sin loops infinitos.
    _con_creds(monkeypatch, refresh=True)
    monkeypatch.setattr(tools, "_ESPERA_DISPOSITIVO_S", 0.0)
    monkeypatch.setattr(tools, "_INTENTOS_DISPOSITIVO", 2)

    async def fake_device(cliente=None):
        return None

    async def fake_enviar(nombre, args, **kw):
        if nombre == "abrir_app":
            return {"ok": True, "tipo": "app_abierta", "app": "spotify"}
        if nombre == "reproducir_spotify":
            return {"ok": True, "tipo": "spotify_abierto", "sonando": False}
        raise AssertionError(f"acción inesperada: {nombre}")

    monkeypatch.setattr(tools.spotify_web, "dispositivo_objetivo", fake_device)
    monkeypatch.setattr(tools.canal, "enviar_accion", fake_enviar)
    res = await tools.ejecutar_tool(None, "pc_reproducir_spotify",
                                    {"uri": "spotify:track:abc"})
    assert res["datos"]["estado"] == "abierto_sin_sonar"
    assert "no llegó a registrarse" in res["datos"]["mensaje"]


async def test_token_invalido_se_distingue_de_credenciales_faltantes(monkeypatch):
    # Con las 3 credenciales puestas pero el refresh REVOCADO (Spotify devuelve
    # 400 al renovar): el mensaje dice «vencido/revocado», no «falta configurar».
    _con_creds(monkeypatch, refresh=True)
    cli = _cliente({"POST /api/token": httpx.Response(400, json={"error": "invalid_grant"})})
    r = await spotify_web.reproducir_en_pc("spotify:track:abc", cliente=cli)
    assert not r["ok"] and r["tipo"] == "sin_oauth"
    assert "vencido o revocado" in r["mensaje"]
    assert "spotify_autorizar_auto" in r["mensaje"]
