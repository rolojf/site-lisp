;;; setup-roc.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package roc-ts-mode
  :ensure t
  :mode ("\\.roc\\'" . roc-ts-mode)
  :config
  (with-eval-after-load 'roc-ts-mode
    (require 'eglot)
    (add-to-list 'eglot-server-programs '(roc-ts-mode "roc_language_server"))
    (add-hook 'roc-ts-mode-hook #'eglot-ensure))
  )

;;; setup-roc.el ends here
