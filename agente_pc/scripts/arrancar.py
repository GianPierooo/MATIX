"""Lanzador del agente para el autostart (Tarea Programada de Windows).

Corre bajo `pythonw.exe` (sin consola) desde una Tarea Programada. Eso trae dos
problemas que este lanzador resuelve, ambos para que el autostart sea robusto y
DIAGNOSTICABLE:

1) Working directory no garantizado. El agente NO se instala como paquete
   (`[tool.uv] package = false`), asi que `import agente_pc` solo resuelve si la
   raiz esta en sys.path. La Tarea Programada no siempre aplica el "Start in".
   -> Calculamos la raiz desde __file__ y la metemos al sys.path.

2) stdout/stderr son None bajo pythonw. Sin consola, cualquier traceback de
   arranque y el logging del daemon (StreamHandler a stderr) se pierden en
   silencio: el proceso queda vivo pero "mudo", imposible de diagnosticar.
   -> Redirigimos stdout/stderr a `agente_autostart.log` ANTES de importar nada,
      y envolvemos el arranque para que CUALQUIER fallo quede escrito.
"""
import os
import sys
import traceback

_raiz = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _raiz not in sys.path:
    sys.path.insert(0, _raiz)

# Dale a pythonw un stdout/stderr REALES (un archivo). Append, line-buffered, asi
# se ve al instante. Es el diagnostico crudo del autostart; el log estructurado
# del daemon sigue en agente_runtime.log.
_diag = open(
    os.path.join(_raiz, "agente_autostart.log"),
    "a", encoding="utf-8", buffering=1,
)
sys.stdout = _diag
sys.stderr = _diag

codigo = 1
try:
    from agente_pc.daemon import main
    codigo = main()
except BaseException:  # noqa: BLE001 — registrar CUALQUIER fallo de arranque
    traceback.print_exc()
    _diag.flush()
    raise
finally:
    _diag.flush()

sys.exit(codigo)
