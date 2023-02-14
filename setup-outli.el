;;; setup-outli.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

;; * Uno

(use-package outli
  :load-path "~/purcell/site-lisp/straight/repos/outli"
  ;; :after lispy ; only if you use lispy; it also sets speed keys on headers!
  :bind (:map outli-mode-map ; convenience key to get back to containing heading
              ("C-c C-p" . (lambda () (interactive) (outline-back-to-heading))))
  :hook ((prog-mode) . outli-mode)
  :custom (outli-heading-config '((elm-mode "-- " ?* nil nil)
                                  (emacs-lisp-mode ";; " ?* nil nil)
                                  ))
  )
;; * Dos

(provide 'setup-outli)

;;; setup-outli.el ends here
