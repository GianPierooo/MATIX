"""Lógica pura de operación: monitoreo de costo, rotación de backup y el
wrapper de jobs del scheduler. Sin BD ni red."""
from __future__ import annotations

import asyncio
from datetime import date

from app.matix import backup, costos
from app.matix.recordatorios import correr_job


# ── Costo ────────────────────────────────────────────────────────────────────

def test_delta_proceso_normal_y_reinicio():
    # Crecimiento normal: delta = actual - ultimo.
    assert costos.delta_proceso(1.5, 1.0) == 0.5
    # Sin avance.
    assert costos.delta_proceso(1.0, 1.0) == 0.0
    # Reinicio del medidor (actual < ultimo): cuenta el actual como nuevo.
    assert costos.delta_proceso(0.2, 1.0) == 0.2
    assert costos.delta_proceso(0.0, 1.0) == 0.0


def test_cruza_umbral():
    assert costos.cruza_umbral(1.2, 1.0) is True
    assert costos.cruza_umbral(1.0, 1.0) is True  # igual = cruza
    assert costos.cruza_umbral(0.9, 1.0) is False
    assert costos.cruza_umbral(5.0, 0) is False   # umbral 0 = sin umbral


def test_total_mes_y_clave_mes():
    filas = [{"gasto_usd": 0.5}, {"gasto_usd": 1.25}, {"gasto_usd": "0.25"}]
    assert costos.total_mes(filas) == 2.0
    assert costos.total_mes([]) == 0
    assert costos.clave_mes(date(2026, 6, 4)) == "2026-06"
    assert costos.clave_mes(date(2026, 12, 31)) == "2026-12"


# ── Backup ───────────────────────────────────────────────────────────────────

def test_nombre_backup():
    assert backup.nombre_backup(date(2026, 6, 4)) == "matix-backup-2026-06-04.json"


def test_a_rotar_conserva_los_n_mas_recientes():
    nombres = [
        "matix-backup-2026-06-01.json",
        "matix-backup-2026-06-02.json",
        "matix-backup-2026-06-03.json",
        "otro-archivo.json",  # ajeno: se ignora
    ]
    # Retener 2 → borra el más viejo (2026-06-01).
    assert backup.a_rotar(nombres, 2) == ["matix-backup-2026-06-01.json"]
    # Retener 5 → nada que borrar.
    assert backup.a_rotar(nombres, 5) == []
    # Desordenado: igual ordena por fecha (nombre ISO).
    desordenado = [
        "matix-backup-2026-06-03.json",
        "matix-backup-2026-06-01.json",
        "matix-backup-2026-06-02.json",
    ]
    assert backup.a_rotar(desordenado, 1) == [
        "matix-backup-2026-06-01.json",
        "matix-backup-2026-06-02.json",
    ]


# ── correr_job (aislamiento de jobs del scheduler) ───────────────────────────

def test_correr_job_aisla_fallos_y_no_propaga():
    async def boom():
        raise ValueError("explotó")

    async def bien():
        return None

    # Un job que falla NO propaga: devuelve False (y loguea).
    assert asyncio.run(correr_job("prueba", boom())) is False
    # Un job que termina bien devuelve True.
    assert asyncio.run(correr_job("prueba", bien())) is True
