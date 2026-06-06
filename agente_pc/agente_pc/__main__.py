"""Permite `python -m agente_pc` desde la carpeta agente_pc/."""
import sys

from .daemon import main

sys.exit(main())
