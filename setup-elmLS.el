;; -*- lexical-binding: t; -*-

;; Keybinding   Description
;; C-c M-t      Generate a TAGS file for the current project.
;; M-.          Jump to tag at point.
;; M-,          Jump to previous location after visiting a tag.
;; C-c C-a      Add missing type annotations to the current buffer.
;; C-u C-c C-a  Add missing type annotations to the current buffer, prompting before each change.
;; C-c C-r      Clean up imports in the current buffer.
;; C-c C-d      View a function's documentation in a browser.
;; C-c C-s      Sort the imports in the current file.
;; C-c C-f      Automatically format the current buffer.
;; C-c C-v      Run the test suite for the current project.
;; C-h .        eldoc-doc-buffer

;;; Elm tree-sitter + eglot configuration

;; Register grammar source (for `treesit-install-language-grammar' if needed)
(with-eval-after-load 'treesit
  (add-to-list 'treesit-language-source-alist
               '(elm . ("https://github.com/elm-tooling/tree-sitter-elm.git"))))

;; Install elm-ts-mode so that init-treesitter.el can remap elm-mode -> elm-ts-mode
;; (the auto-remap fires only when elm-ts-mode is fboundp and the grammar .so exists)
(maybe-require-package 'elm-ts-mode)

;; Register elm-language-server for both elm-mode and elm-ts-mode
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((elm-mode elm-ts-mode) . ("elm-language-server" "--stdio"))))

;; Start eglot automatically (hooks cover both modes; only one will be active)
(add-hook 'elm-mode-hook #'eglot-ensure)
(add-hook 'elm-ts-mode-hook #'eglot-ensure)

;; Key-chord bindings for eglot commands in elm-mode
(with-eval-after-load 'elm-mode
  (key-chord-define elm-mode-map "wr" #'eglot-rename)
  (key-chord-define elm-mode-map "wa" #'eglot-code-actions)
  (key-chord-define elm-mode-map "wf" #'xref-find-references)
  (key-chord-define elm-mode-map "wc" #'consult-eglot-symbols))

;; Key-chord bindings for eglot commands in elm-ts-mode
(with-eval-after-load 'elm-ts-mode
  (key-chord-define elm-ts-mode-map "wr" #'eglot-rename)
  (key-chord-define elm-ts-mode-map "wa" #'eglot-code-actions)
  (key-chord-define elm-ts-mode-map "wf" #'xref-find-references)
  (key-chord-define elm-ts-mode-map "wc" #'consult-eglot-symbols))

;; Silence JSONRPC event logging for better performance
(fset #'jsonrpc--log-event #'ignore)
(setq eglot-events-buffer-size 0)

(provide 'setup-elmLS)
;;; setup-elmLS.el ends here.
