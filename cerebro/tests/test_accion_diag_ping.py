"""La pantalla de Diagnóstico manda 'diag-ping' como id en /rendicion-cuentas/
accion y /asistencia/accion para verificar la cadena botón→cerebro SIN tocar
datos del usuario.

Antes ese id reventaba en Postgres ('invalid input syntax for type uuid') y la
app mostraba HTTP 500 críptico. Ahora el cerebro lo reconoce y devuelve 200
limpio con `tipo=diag`."""
from __future__ import annotations

from app.routers.push import aplicar_accion, aplicar_asistencia, AccionAsistencia, AccionRendicionCuentas


class FakeDB:
    """No debería ser tocada por el diag-ping (lo verificamos)."""

    def __init__(self):
        self.gets = 0

    async def get(self, tabla, id_):  # pragma: no cover (no debe llamarse)
        self.gets += 1
        return None


def test_diag_ping_tareas_responde_200_sin_tocar_bd():
    import asyncio
    db = FakeDB()
    body = AccionRendicionCuentas(tarea_id="diag-ping", accion="hecho")
    res = asyncio.run(aplicar_accion(body, db))
    assert res == {"ok": True, "tipo": "diag", "accion": "hecho"}
    assert db.gets == 0  # NO tocó BD


def test_diag_ping_asistencia_responde_200_sin_tocar_bd():
    import asyncio
    db = FakeDB()
    body = AccionAsistencia(evento_id="diag-ping", accion="si_fui")
    res = asyncio.run(aplicar_asistencia(body, db))
    assert res == {"ok": True, "tipo": "diag", "accion": "si_fui"}
    assert db.gets == 0


def test_id_no_uuid_responde_404_limpio_no_500():
    """Un id que no es UUID (etiqueta, basura, lo que sea que no sea uuid):
    antes reventaba el wrapper de Postgrest con 500. Ahora respondemos 404
    limpio, sin tocar BD."""
    import asyncio

    from fastapi import HTTPException
    db = FakeDB()
    body = AccionRendicionCuentas(tarea_id="no-es-uuid", accion="hecho")
    try:
        asyncio.run(aplicar_accion(body, db))
        raise AssertionError("debió levantar 404")
    except HTTPException as e:
        assert e.status_code == 404
    assert db.gets == 0
