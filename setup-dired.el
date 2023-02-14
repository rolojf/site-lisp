;; (use-package dired-open
;;   :straight t
;;   :config
;;   ;; Doesn't work as expected!
;;   ;;(add-to-list 'dired-open-functions #'dired-open-xdg t)
;;   (setq dired-open-extensions '(("png" . "feh")
;;                                 ("mkv" . "mpv"))))

(crafted-package-install-package 'dired-hide-dotfiles)
(defun my-dired-mode-hook ()
  "My `dired' mode hook."
  ;; To hide dot-files by default
  (dired-hide-dotfiles-mode))

(eval-after-load "dired" '(progn
  (define-key dired-mode-map (kbd "b") 'my-dired-mode-hook) ))


(setq dired-listing-switches "-alGhvF --group-directories-first") ; default: "-al"


(add-hook 'dired-mode-hook
          (lambda ()
            (dired-hide-details-mode)
            )
          )

;; dired-find-file-or-do-async-shell-command ()

;;   "If there is a default command defined for this file type, run it asynchronously.If not, open it in Emacs."

;;   (interactive)

;;   (let (

;;         ;; get the default for the file type,
;;         ;; putting the string into a list because dired-guess-default throws an error otherwise.
;;         (default (dired-guess-default (cons (dired-get-filename) '())))

;;         ;; put the file name into a list so dired-shell-stuff-it will accept it
;;         (file-list (cons (dired-get-filename) '())))

;;     (if (null default)

;;         ;; if no default found for file, open in Emacs
;;         (dired-find-file)

;;       ;; if default is found for file, run command asynchronously
;;       (dired-run-shell-command (dired-shell-stuff-it (concat default " &") file-list nil)))))

;; ;; This function is bound to the Return key in dired-mode to replace the default behavior on Return

;; (define-key dired-mode-map (kbd "<return>") #'dired-find-file-or-do-async-shell-command)

;; ;; For added convenience: Don't open a new Async Shell Command window

;; (add-to-list 'display-buffer-alist(cons "\\*Async Shell Command\\*.*" (cons #'display-buffer-no-window nil)))

;; ;; Always open a new buffer if default is occupied.

;; (setq async-shell-command-buffer 'new-buffer)

(provide 'setup-dired)
