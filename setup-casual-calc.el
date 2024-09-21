;;; setup-casual-calc.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package casual-calc
  :ensure t
  ) ;; optional
(keymap-set calc-mode-map "C-o" #'casual-calc-tmenu)
(keymap-set calc-alg-map "C-o" #'casual-calc-tmenu)

(provide 'setup-casual-calc)
;;; setup-casual-calc.el ends here
