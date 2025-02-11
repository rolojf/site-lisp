;;; setup-org.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary: Sacado de lo mío y de init-org.el
;;; Code:
;; (use-package 'org)

(maybe-require-package 'org-cliplink)

(define-key global-map (kbd "C-c l") 'org-store-link)
(define-key global-map (kbd "C-c a") 'org-agenda)

(defvar sanityinc/org-global-prefix-map (make-sparse-keymap)
  "A keymap for handy global access to org helpers, particularly clocking.")

(define-key sanityinc/org-global-prefix-map (kbd "j") 'org-clock-goto)
(define-key sanityinc/org-global-prefix-map (kbd "l") 'org-clock-in-last)
(define-key sanityinc/org-global-prefix-map (kbd "i") 'org-clock-in)
(define-key sanityinc/org-global-prefix-map (kbd "o") 'org-clock-out)
(define-key global-map (kbd "C-c o") sanityinc/org-global-prefix-map)


;; Various preferences
(setq  org-edit-timestamp-down-means-later t
       org-export-coding-system 'utf-8
       ;; org-fast-tag-selection-single-key 'expert
       org-html-validation-link nil
       org-export-kill-product-buffer-when-displayed t
       org-hide-emphasis-markers t
       org-export-with-toc nil
       )

;; Re-align tags when window shape changes
(with-eval-after-load 'org-agenda
  (add-hook 'org-agenda-mode-hook
            (lambda () (add-hook 'window-configuration-change-hook 'org-agenda-align-tags nil t))))


(setq org-support-shift-select t)

;;; Capturing

(global-set-key (kbd "C-c c") 'org-capture)

(setq org-capture-templates
      `(("t" "todo" entry (file "")  ; "" => `org-default-notes-file'
         "* NEXT %?\n%U\n" :clock-resume t)
        ("n" "note" entry (file "")
         "* %? :NOTE:\n%U\n%a\n" :clock-resume t)
        ))



;;; Refiling

(setq org-refile-use-cache nil)

;; Targets include this file and any file contributing to the agenda - up to 5 levels deep
(setq org-refile-targets '((nil :maxlevel . 5) (org-agenda-files :maxlevel . 5)))

(with-eval-after-load 'org-agenda
  (add-to-list 'org-agenda-after-show-hook 'org-show-entry))

(advice-add 'org-refile :after (lambda (&rest _) (org-save-all-org-buffers)))

;; Exclude DONE state tasks from refile targets
(defun sanityinc/verify-refile-target ()
  "Exclude todo keywords with a done state from refile targets."
  (not (member (nth 2 (org-heading-components)) org-done-keywords)))
(setq org-refile-target-verify-function 'sanityinc/verify-refile-target)

(defun sanityinc/org-refile-anywhere (&optional goto default-buffer rfloc msg)
  "A version of `org-refile' which allows refiling to any subtree."
  (interactive "P")
  (let ((org-refile-target-verify-function))
    (org-refile goto default-buffer rfloc msg)))

(defun sanityinc/org-agenda-refile-anywhere (&optional goto rfloc no-update)
  "A version of `org-agenda-refile' which allows refiling to any subtree."
  (interactive "P")
  (let ((org-refile-target-verify-function))
    (org-agenda-refile goto rfloc no-update)))

;; Targets start with the file name - allows creating level 1 tasks
;;(setq org-refile-use-outline-path (quote file))
(setq org-refile-use-outline-path t)
(setq org-outline-path-complete-in-steps nil)

;; Allow refile to create parent tasks with confirmation
(setq org-refile-allow-creating-parent-nodes 'confirm)




;;; Org clock

;; Save the running clock and all clock history when exiting Emacs, load it on startup
(with-eval-after-load 'org
  (org-clock-persistence-insinuate))
(setq org-clock-persist t)
(setq org-clock-in-resume t)

;; Save clock data and notes in the LOGBOOK drawer
(setq org-clock-into-drawer t)
;; Save state changes in the LOGBOOK drawer
(setq org-log-into-drawer t)
;; Removes clocked tasks with 0:00 duration
(setq org-clock-out-remove-zero-time-clocks t)

;; Show clock sums as hours and minutes, not "n days" etc.
(setq org-time-clocksum-format
      '(:hours "%d" :require-hours t :minutes ":%02d" :require-minutes t))

;; Show the clocked-in task - if any - in the header line
(defun sanityinc/show-org-clock-in-header-line ()
  (setq-default header-line-format '((" " org-mode-line-string " "))))

(defun sanityinc/hide-org-clock-from-header-line ()
  (setq-default header-line-format nil))

(add-hook 'org-clock-in-hook 'sanityinc/show-org-clock-in-header-line)
(add-hook 'org-clock-out-hook 'sanityinc/hide-org-clock-from-header-line)
(add-hook 'org-clock-cancel-hook 'sanityinc/hide-org-clock-from-header-line)

(with-eval-after-load 'org-clock
  (define-key org-clock-mode-line-map [header-line mouse-2] 'org-clock-goto)
  (define-key org-clock-mode-line-map [header-line mouse-1] 'org-clock-menu))



;;; Archiving

(setq org-archive-mark-done nil)
(setq org-archive-location "%s_archive::* Archive")





;; (require-package 'org-pomodoro)
;; (setq org-pomodoro-keep-killed-pomodoro-time t)
;; (with-eval-after-load 'org-agenda
;;   (define-key org-agenda-mode-map (kbd "P") 'org-pomodoro))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-M-<up>") 'org-up-element)
  )

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-.") 'org-timestamp-inactive)
  )

(with-eval-after-load 'org
  (org-babel-do-load-languages
   'org-babel-load-languages
   (seq-filter
    (lambda (pair)
      (locate-library (concat "ob-" (symbol-name (car pair)))))
    '(;; (R . t)
      ;; (ditaa . t)
      ;; (dot . t)
      (emacs-lisp . t)
      (elm . t)
      (gnuplot . t)
      ;; (haskell . nil)
      ;; (latex . t)
      ;; (ledger . t)
      (mermaid . t)
      ;; (ocaml . nil)
      ;; (octave . t)
      ;; (plantuml . t)
      (python . t)
      ;; (ruby . t)
      (screen . nil)
      (sh . t) ;; obsolete
      (shell . t)
      (sql . t)
      (sqlite . t)))))



(setq
 org-agenda-files '("~/Documents/elemento/newkb/20240917T0952--inbox__pend.org"
                    )
 org-directory "~/Documents/elemento/newkb/"
 org-clock-into-drawer t
 org-startup-indented t
 ;; org-agenda-custom-commands '("p" "important tasks" tags "PRIORITY=\"A\"")
 ;; org-default-notes-file "~/Documents/elemento/newkb/inbox.org"
 ;; org-plantuml-jar-path "/usr/share/java/plantuml/plantuml.jar"
 org-html-doctype "html5"
 org-html-html5-fancy t
 org-log-done 'time
 org-tags-column 65
 org-refile-targets `((nil :regexp . ,(rx-to-string `(seq line-start
                                                          "** Terminados"
                                                          ))))
 org-todo-keywords  (quote ((sequence "TODO(t)" "....(.)" "|" "DONE(d)" "KILL(k)")
                            (sequence "PROY(p)" "WAIT(w)" "|"  "COMP(c)" "SDM(s)")
                            ))
 org-todo-repeat-to-state "TODO")

(add-hook 'org-mode-hook 'whitespace-cleanup-mode)
(add-hook 'org-mode-hook 'visual-line-mode)

(defun rolo/quita-tachado ()
  "Quitar el tachado del font face cuando completas algo en orgmode"
  (interactive)
  (set-face-attribute 'org-headline-done nil
                      :strike-through nil
                      :foreground "gray"))

(with-eval-after-load 'org
  (rolo/quita-tachado))

;; (setq org-todo-keyword-faces
;;       (quote (("...." :inherit warning)
;;               ("PROY" :inherit font-lock-string-face))))

;; (use-package ox-hugo
;;   :straight t          ;Auto-install the package from Melpa (optional)
;;   :after ox)

;;(require 'ox-slimhtml)

;; (require 'org-id)

(use-package literate-calc-mode
  :ensure t
  :defer t
  )

(use-package ob-mermaid
  :ensure t
  :config (setq ob-mermaid-cli-path "/home/a1rolo/.npm-global/bin/mmdc")
  )


(tool-bar-mode -1)


(provide 'setup-org)
;;; setup-org.el ends here
