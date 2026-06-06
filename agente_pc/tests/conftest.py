"""Fixtures de los tests del agente.

`tmp_path` de pytest en Windows vive bajo `AppData\\Local\\Temp`, que el agente
bloquea a propósito (denylist). Para probar la lógica de allowlist necesitamos
un árbol en una base que NO esté denylisted: lo creamos bajo el home del
usuario y lo limpiamos al terminar.
"""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest


@pytest.fixture
def area(tmp_path):
    base = Path.home() / ".matix_agente_test" / tmp_path.name
    base.mkdir(parents=True, exist_ok=True)
    try:
        yield base
    finally:
        shutil.rmtree(base, ignore_errors=True)
