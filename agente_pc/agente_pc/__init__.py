"""Agente local de Matix (Capa 6 · 6.0a).

Daemon que corre en la PC del usuario y ejecuta acciones del registry dentro de
los rails de seguridad (allowlist/denylist). Abre una conexión saliente
persistente al cerebro sobre TLS; nunca abre puertos ni acepta entrantes.
"""

__version__ = "0.1.0"
