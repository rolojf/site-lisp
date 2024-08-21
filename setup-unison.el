;;; setup-unison.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package unison-ts-mode
  :defer t
  :straight (:type git :host github :repo "fmguerreiro/unison-ts-mode")
  :init
  (add-to-list 'treesit-language-source-alist '(unison "https://github.com/kylegoetz/tree-sitter-unison"))
  :config
  (add-to-list 'eglot-server-programs '(unison-ts-mode . ("127.0.0.1" 5757)))
  (add-hook 'unison-ts-mode-hook 'eglot-ensure)
  )


(provide 'setup-unison)
;;; setup-unison.el ends here
