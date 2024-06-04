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


(use-package elm-mode
  :straight t
  :defer t
  :chords (
           ("wr" . eglot-rename)
           ("wa" . eglot-code-actions)
           ("wf" . xref-find-references)
           ("wc" . consult-eglot-symbols)
           )
  :bind (:map elm-mode-map
              ("M-o" . origami-recursively-toggle-node )
              ("M-O" . origami-toggle-all-nodes)
              ("<C-tab>" . completion-at-point)
              )
  :config
  (setq elm-mode-hook '(origami-mode )) ;;toggle-truncate-lines
  ;; (setq elm-tags-on-save t)
  (setq elm-tags-exclude-elm-stuff nil)
  ;; (defun jsonrpc--log-event (connection message &optional type))
  (fset #'jsonrpc--log-event #'ignore)
  (setq eglot-events-buffer-size 0)
  (add-hook 'elm-mode-hook
            (lambda ()
              (eglot-ensure)
              (elm-format-on-save-mode)
              (flycheck-mode nil)
              (flymake-mode nil)
              ))
  (add-hook 'elm-mode-hook 'outli-mode)
  (maybe-require-package 'elm-test-runner)
  )

(use-package eglot-booster
  :straight '(eglot-booster :type git :host github :repo "jdtsmith/eglot-booster")
  :after eglot
  )

(require 'roc-mode)

(provide 'setup-elmLS)
;;; setup-elmLS.el ends here.
