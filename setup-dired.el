(use-package dired-open
  :straight t
  :config
  ;; Doesn't work as expected!
  ;;(add-to-list 'dired-open-functions #'dired-open-xdg t)
  (setq dired-open-extensions '(("png" . "feh")
                                ("pdf" . "okular")
                                ("mkv" . "mpv")
                                ("mp4" . "mpv")
                                )))

(use-package dired-hide-dotfiles
  :straight t
  :hook (dired-mode . dired-hide-dotfiles-mode)
  :config
  (define-key dired-mode-map "h" #'dired-hide-dotfiles-mode)
  )


(setq dired-listing-switches "-alGhvF --group-directories-first") ; default: "-al"


(add-hook 'dired-mode-hook
          (lambda ()
            (dired-hide-details-mode)
            )
          )


(use-package ztree
  :straight t)

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
