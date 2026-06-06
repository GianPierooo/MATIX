"""Canal cerebro ↔ agente local (Capa 6 · 6.0a).

El cerebro mantiene a lo sumo UNA conexión con el agente de la PC del usuario
(app privada de un solo usuario). El módulo `canal` enruta llamadas de acción
hacia esa conexión y correla las respuestas por id.
"""
