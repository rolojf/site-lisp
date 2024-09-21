;;; setup-nushell.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

;; (use-package nushell-ts-mode
;;   :config
;;   ;; (require 'nushell-ts-babel)
;;   (defun hfj/nushell/mode-hook ()
;;     (corfu-mode 1)
;;     (highlight-parentheses-mode 1)
;;     (electric-pair-local-mode 1)
;;     (electric-indent-local-mode 1))
;;   (add-hook 'nushell-ts-mode-hook 'hfj/nushell/mode-hook))

(use-package nushell-mode
  :ensure t
  )
(provide 'setup-nushell)
;;; setup-nushell.el ends here
