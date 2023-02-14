;; -*- lexical-binding: t; -*-

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
  (setq elm-mode-hook '(origami-mode ));;toggle-truncate-lines))
  (add-hook 'elm-mode-hook
            (lambda ()
              (eglot-ensure)
              (elm-format-on-save-mode)
              ))
  (add-hook 'elm-mode-hook 'outli-mode)
  )

(provide 'setup-elmLS)
;;; setup-elmLS.el ends here.
