;;; setup-outli.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

;; * Uno

(require-package 'outli)
(with-eval-after-load 'outli
  (define-key outli-mode-map (kbd "C-c C-p")
              (lambda ()
                (interactive)
                (outline-back-to-heading)))
  (add-hook 'prog-mode 'outli-mode)
  (add-to-list 'outli-heading-config '(elm-mode "-- " ?* nil nil))
  )

;; * Dos

(provide 'setup-outli)

;;; setup-outli.el ends here
