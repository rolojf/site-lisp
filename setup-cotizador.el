;;; setup-cotizador.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:


(setq org-babel-default-header-args:python
      '((:results . "output drawer replace")
        (:prologue . "import os, sys
_p = os.path.expanduser('~/cotizador')
if _p not in sys.path:
    sys.path.insert(0, _p)
import math
import pint
import vent
uu = pint.get_application_registry()")))

(provide 'setup-cotizador)
;;; setup-cotizador.el ends here
