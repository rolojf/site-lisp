(setq straight-base-dir "~/purcell/site-lisp/")
(setq straight-cache-autoloads 1)
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "site-lisp/straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)
;; (straight-use-package '(roc-mode :type git :host gitlab :repo "tad-lispy/roc-mode"))
;; (straight-use-package 'vterm)
;; (straight-use-package 'org-modern)

(provide 'setup-straight)
;;; setup-straight.el ends here
