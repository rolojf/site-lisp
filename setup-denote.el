;;; setup-denote.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary: solo cambién líneas 8 y 9 y de la 105 en adelante
;;; Code: del manual oficial de prot

(use-package denote
  :ensure t
  )

;; Remember to check the doc strings of those variables.
(setq denote-directory (expand-file-name "~/Documents/elemento/newkb/"))
(setq denote-id-format "%Y%m%dT%H%M")
(setq denote-id-regexp "\\([0-9]\\{8\\}\\)\\(T[0-9]\\{4\\}\\)")
;; (setq denote-id-regexp "\\([0-9]\\{8\\}\\)\\(T[0-9]\\{4\\}\\)")
(setq denote-known-keywords '("emacs" "nav" "expresión" "oración" "dirección"))
(setq denote-infer-keywords t)
(setq denote-sort-keywords t)
(setq denote-file-type nil) ; Org is the default, set others here
(setq denote-prompts '(title keywords))
(setq denote-excluded-directories-regexp nil)
(setq denote-excluded-keywords-regexp nil)
(setq denote-rename-confirmations '(rewrite-front-matter modify-file-name))

;; Pick dates, where relevant, with Org's advanced interface:
(setq denote-date-prompt-use-org-read-date t)
(use-package consult-denote
  :ensure t
  :config
  (consult-denote-mode)
  )

(setq denote-date-format nil) ; read doc string

;; By default, we do not show the context of links.  We just display
;; file names.  This provides a more informative view.
(setq denote-backlinks-show-context t)

;; Also see `denote-link-backlinks-display-buffer-action' which is a bit
;; advanced.

;; If you use Markdown or plain text files (Org renders links as buttons
;; right away)
(add-hook 'text-mode-hook #'denote-fontify-links-mode-maybe)

;; We use different ways to specify a path for demo purposes.
;; (setq denote-dired-directories
;;       (list denote-directory
;;             (thread-last denote-directory (expand-file-name "attachments"))
;;             (expand-file-name "~/Documents/books")))

;; Generic (great if you rename files Denote-style in lots of places):
;; (add-hook 'dired-mode-hook #'denote-dired-mode)
;;
;; OR if only want it in `denote-dired-directories':
(add-hook 'dired-mode-hook #'denote-dired-mode-in-directories)


;; Automatically rename Denote buffers using the `denote-rename-buffer-format'.
(denote-rename-buffer-mode 1)


(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c n c") #'denote-region) ; "contents" mnemonic
  (define-key org-mode-map (kbd "C-c n N") #'denote-type)
  (define-key org-mode-map (kbd "C-c n d") #'denote-date)
  (define-key org-mode-map (kbd "C-c n z") #'denote-signature) ; "zettelkasten" mnemonic
  (define-key org-mode-map (kbd "C-c n s") #'denote-subdirectory)
  (define-key org-mode-map (kbd "C-c n t") #'denote-template)
  (define-key org-mode-map (kbd "C-c n i") #'denote-link) ; "insert" mnemonic
  (define-key org-mode-map (kbd "C-c n I") #'denote-add-links)
  (define-key org-mode-map (kbd "C-c n b") #'denote-backlinks)
  (define-key org-mode-map (kbd "C-c n f f") #'denote-find-link)
  (define-key org-mode-map (kbd "C-c n f b") #'denote-find-backlink))

;; Note that `denote-rename-file' can work from any context, not just
;; Dired bufffers.  That is why we bind it here to the `global-map'.
(let ((map global-map))
  (define-key map (kbd "C-c n n") #'denote)
  (define-key map (kbd "C-c n r") #'denote-rename-file)
  (define-key map (kbd "C-c n R") #'denote-rename-file-using-front-matter))

;; Key bindings specifically for Dired.
(let ((map dired-mode-map))
  (define-key map (kbd "C-c C-d C-i") #'denote-link-dired-marked-notes)
  (define-key map (kbd "C-c C-d C-r") #'denote-dired-rename-files)
  (define-key map (kbd "C-c C-d C-k") #'denote-dired-rename-marked-files-with-keywords)
  (define-key map (kbd "C-c C-d C-R") #'denote-dired-rename-marked-files-using-front-matter))

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

;; Also check the commands `denote-link-after-creating',
;; `denote-link-or-create'.  You may want to bind them to keys as well.


;; If you want to have Denote commands available via a right click
;; context menu, use the following and then enable
;; `context-menu-mode'.
(add-hook 'context-menu-functions #'denote-context-menu)

(defun rolo-denote-journal ()
  "Create an entry tagged 'journal', while prompting for a title."
  (interactive)
  (denote
   (denote--title-prompt)
   '("journal")))



;; agregando lo de journal
(require 'denote-journal-extras)
(setq denote-journal-extras-directory nil)
(setq denote-journal-extras-title-format nil)
;; Denote DOES NOT define any key bindings.  This is for the user to
;; decide.  For example:
(let ((map global-map))
  ;; our custom command
  (define-key map (kbd "C-c n j") #'denote-journal-extras-new-entry)
  )

(provide 'setup-denote)
;;; setup-denote.el ends here
