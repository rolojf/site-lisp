;;; setup-denote.el --- Denote package configuration -*- lexical-binding: t -*-

;;; Commentary:
;;; Basic Denote setup: package activation, standard key bindings, file
;;; naming and metadata, dired/consult/org-capture integrations, and the
;;; root `denote-directory'.  The journaling workflow that builds on top
;;; of Denote lives in `setup-journaling'.

;;; Code:

(when (maybe-require-package 'denote)
  ;; Standard Denote key bindings.
  (define-key global-map (kbd "C-c n n") 'denote)
  (define-key global-map (kbd "C-c n l") 'denote-link)
  (define-key global-map (kbd "C-c n L") 'denote-add-links)
  (define-key global-map (kbd "C-c n b") 'denote-backlinks)
  (define-key global-map (kbd "C-c n q c") 'denote-query-contents-link)
  (define-key global-map (kbd "C-c n q f") 'denote-query-filenames-link)
  (with-eval-after-load 'denote
    (define-key global-map (kbd "C-c n r") 'denote-rename-file)
    (define-key global-map (kbd "C-c n R") 'denote-rename-file-using-front-matter)
    ;; Apply colours to Denote names in Dired.
    (add-hook 'dired-mode 'denote-dired-mode)
    ;; Hook for Dired integration.
    (add-hook 'dired-mode-hook #'denote-dired-mode-in-directories)
    ;; Key bindings specifically for Dired.
    (with-eval-after-load 'dired
      (define-key global-map (kbd "C-c n d") 'denote-dired)
      (define-key dired-mode-map (kbd "C-c C-d C-i") 'denote-dired-link-marked-notes)
      (define-key dired-mode-map (kbd "C-c C-d C-r") 'denote-dired-rename-files)
      (define-key dired-mode-map (kbd "C-c C-d C-k") 'denote-dired-rename-marked-files-with-keywords)
      (define-key dired-mode-map (kbd "C-c C-d C-R") 'denote-dired-rename-marked-files-using-front-matter))

    ;; Configuration for file naming and metadata.
    ;; WARNING: Removing %S from the format may lead to non-unique
    ;; identifiers if you create more than one note in the same minute.
    (setq denote-id-format "%Y%m%dT%H%M")
    (setq denote-id-regexp "\\([0-9]\\{8\\}\\)\\(T[0-9]\\{4\\}\\)")
    (setq denote-save-buffers nil)
    (setq denote-infer-keywords t)
    (setq denote-sort-keywords t)
    (setq denote-prompts '(signature title keywords))
    (setq denote-file-type nil)           ; Org is the default.
    (setq denote-date-prompt-use-org-read-date t)
    (denote-rename-buffer-mode 1)
    )
  )


(when (maybe-require-package 'consult-denote)
  (with-eval-after-load 'denote
    ;; Bind consult-denote commands.
    (define-key global-map (kbd "C-c n f") #'consult-denote-find)
    (define-key global-map (kbd "C-c n g") #'consult-denote-grep)
    (consult-denote-mode 1)))


;; Org Capture integration for Denote.
(with-eval-after-load 'org-capture
  (setq denote-org-capture-specifiers "%l\n%i\n%?")
  (add-to-list 'org-capture-templates
               '("n" "New note (with denote.el)" plain
                 (file denote-last-path)
                 #'denote-org-capture
                 :no-save t
                 :immediate-finish nil
                 :kill-buffer t
                 :jump-to-captured t)))

;; --- GLOBAL DEFINITIONS ---
;; Defined here, outside any `use-package` block, so the variable is
;; available to setup-journaling.el and any other file that depends on
;; Denote regardless of load order.
(setq denote-directory (expand-file-name "~/newkb/"))


(provide 'setup-denote)
;;; setup-denote.el ends here
