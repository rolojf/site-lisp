;;; setup-casual-calc.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require 'casual-calc) ;; optional
(keymap-set calc-mode-map "C-o" #'casual-calc-tmenu)
(keymap-set calc-alg-map "C-o" #'casual-calc-tmenu)

(provide 'setup-casual-calc)
;;; setup-casual-calc.el ends here
