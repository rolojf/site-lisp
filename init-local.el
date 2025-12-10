(require 'setup-straight)
;; use-package
;;; (eval-when-compile (require 'use-package))
(setq use-package-enable-imenu-support t) ;; add imenu support for use-package declarations
;; (add-to-list 'package-archives '("org" . "https://elpa.nongnu.org/nongnu/") t)
;;
(require  'setup-chords)
(require  'setup-dired)
(require  'setup-org)
(require  'setup-spelling)
(require-package 'prettier-js)
(require  'setup-customFaces)
;; (require 'setup-webmode)
(require 'setup-elmLS)
;;(require 'setup-outshine)
(require 'setup-outli)
(require 'setup-nushell)
;; (require 'setup-gren)
;; (require 'setup-unison)
;; (require 'setup-asistant)
;; (require 'setup-gptel)
;; (require 'setup-org-ai)
;;(require 'setup-copilot)
;; (require 'setup-vterm)
;;(require  'dired+)
;; (require 'setup-roam)
;;(require  'setup-brain)
;; (require 'setup-roam2)
;; (require 'setup-howm)
(require 'setup-denote)
(require 'setup-gptel)
;; (require 'setup-gleam)
(require 'setup-wsl)
;; (require 'setup-pass)
;; (require 'setup-origami)
;; (require 'setup-atomic)
;;(require  'ocultar-clases)
;;(require 'notmuch)
;;(require 'notmuch-config)
(require 'ob-elm)

(setq projectile-switch-project-action #'projectile-dired)
(setq backup-directory-alist '(("." . "~/.emacs.d/backups")))
(setq delete-by-moving-to-trash t)
(setq reb-re-syntax 'string)
(defun file-size (filename)
  "Return size of file FILENAME in bytes.
    The size is converted to float for consistency.
    This doesn't recurse directories."
  (float
   (file-attribute-size ; might be int or float
    (file-attributes filename))))

(defun file-size-total (filename-list)
  "Return the sum of sizes of FILENAME-LIST in bytes."
  (apply '+
         (mapcar 'file-size
                 filename-list)))

(defun dired-size-of-marked-files ()
  "Print the total size of marked files in bytes."
  (interactive)
  (message "%.0f"
           (file-size-total (dired-get-marked-files))))

;; (define-key dired-mode-map (kbd "?") 'dired-size-of-marked-files)
;; (setq epa-pinentry-mode 'loopback)

;; (defun  rolo/open-line-with-reindent (n)
;;   "A version of `open-line' que inserta línea nueva desde
;; el ninicio"
;;   (interactive "*p")
;;   (move-beginning-of-line nil)
;;   (sanityinc/open-line-with-reindent n)
;;   )

(prefer-coding-system 'utf-8-unix)
(setq coding-system-for-read 'utf-8-unix)
(setq coding-system-for-write 'utf-8-unix)

(provide 'init-local)
