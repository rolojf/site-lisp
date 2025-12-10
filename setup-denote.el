;;; setup-denote.el --- Denote configuration with custom journaling -*- lexical-binding: t -*-

;;; Commentary:
;;; This file configures denote.el and adds a custom journaling workflow.
;;; The workflow automatically moves unfinished tasks from the previous day's
;;; journal to the current one and integrates recent journals with Org Agenda.
;;; Journals are stored in the "diario" subdirectory.

;;; Code:

(when (maybe-require-package 'denote)
  (with-eval-after-load 'denote
    ;; Apply colours to Denote names in Dired.
    (add-hook 'dired-mode 'denote-dired-mode)
    ;; Hook for Dired integration.
    (add-hook 'dired-mode-hook #'denote-dired-mode-in-directories)
    ;; Standard Denote key bindings.
    ;; We will override C-c n g later with consult-denote.
    (define-key global-map (kbd "C-c n n") 'denote)
    (define-key global-map (kbd "C-c n d") 'denote-dired)
    (define-key global-map (kbd "C-c n l") 'denote-link)
    (define-key global-map (kbd "C-c n L") 'denote-add-links)
    (define-key global-map (kbd "C-c n b") 'denote-backlinks)
    (define-key global-map (kbd "C-c n q c") 'denote-query-contents-link)
    (define-key global-map (kbd "C-c n q f") 'denote-query-filenames-link)
    (define-key global-map (kbd "C-c n r") 'denote-rename-file)
    (define-key global-map (kbd "C-c n R") 'denote-rename-file-using-front-matter)

    ;; Key bindings specifically for Dired.
    (with-eval-after-load 'dired
      (define-key dired-mode-map (kbd "C-c C-d C-i") 'denote-dired-link-marked-notes)
      (define-key dired-mode-map (kbd "C-c C-d C-r") 'denote-dired-rename-files)
      (define-key dired-mode-map (kbd "C-c C-d C-k") 'denote-dired-rename-marked-files-with-keywords)
      (define-key dired-mode-map (kbd "C-c C-d C-R") 'denote-dired-rename-marked-files-using-front-matter))

    ;; The variables `denote-directory` and `denote-journal-directory` are
    ;; now defined globally below to avoid load-order errors.

    ;; Configuration for file naming and metadata.
    ;; WARNING: Removing %S from the format may lead to non-unique
    ;; identifiers if you create more than one note in the same minute.
    (setq denote-id-format "%Y%m%dT%H%M")
    (setq denote-id-regexp "\\([0-9]\\{8\\}\\)\\(T[0-9]\\{4\\}\\)")
    (setq denote-save-buffers nil)
    (setq denote-infer-keywords t)
    (setq denote-sort-keywords t)
    (setq denote-prompts '(title keywords))
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

(when (maybe-require-package 'denote-journal)
  (with-eval-after-load 'denote
    ;; :commands (denote-journal-new-entry denote-journal-new-or-existing-entry denote-journal-link-or-create-entry)
    (add-hook 'calendar-mode 'denote-journal-calendar-mode)
    ;; The `denote-journal-directory` is set globally below.
    (setq denote-journal-keyword "journal")
                                        ; Use default title format for custom functions.
    (setq denote-journal-title-format nil)))


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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; CUSTOM JOURNALING WORKFLOW WITH TASK MANAGEMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require 'cl-lib)
(require 'seq) ;; Required for seq-find

;; --- GLOBAL DEFINITIONS ---
;; These variables must be defined here, outside of any `use-package`
;; block, to ensure they are available when this file is loaded.
(setq denote-directory (expand-file-name "~/Documents/elemento/newkb/"))
(setq denote-journal-directory (expand-file-name "diario" denote-directory))


;; --- FUNCTION DEFINITIONS ---
;; All custom functions are defined here, before they are called by other code.

(defun journals_to_org_agenda ()
  "Get journal files from the last month for Org Agenda."
  (let* ((min-date (format-time-string "%Y%m%d"
                                       (encode-time
                                        (decoded-time-add (parse-time-string
                                                           (calendar-date-string
                                                            (calendar-current-date)))
                                                          (make-decoded-time :month (- 1))))))
         (all-journals (sort
                        (directory-files denote-journal-directory nil "^[0-9].*_journal.*org$")
                        #'string>))
         (out-list nil))
    (dolist (journal all-journals out-list)
      (when (string> (substring journal 0 8) min-date)
        (push (concat denote-journal-directory journal) out-list)))))

(defun journal-day-exists-p (target)
  "Check if a journal for a given day already exists. Target is papayaMMDD."
  (file-expand-wildcards (concat denote-journal-directory target "*_journal*.org")))

(defun find-previous-journal ()
  "Find the file name of the most recent journal before today."
  (let* ((today (format-time-string "%Y%m%d"))
         (all-journals (sort (directory-files denote-journal-directory nil "^[0-9].*_journal.*org$") #'string>))
         (previous-journal (seq-find (lambda (journal) (string< (substring journal 0 8) today))
                                     all-journals)))
    (if previous-journal
        (progn
          (message "Journaling: Found previous journal: %s" previous-journal)
          previous-journal)
      (message "Journaling: No previous journal file found."))))

(defun my-refile-tasks (file)
  "Refile all TODO and WAIT tasks to the specified FILE under '* TASKS'."
  (interactive "FFile to refile tasks to: ")
  ;; This is the definitive fix. We save the original values of the
  ;; dynamic variables, but ONLY if they are currently bound. This
  ;; avoids the `Symbol's value as variable is void' error.
  (let ((original-archive-location (if (boundp 'org-archive-location) org-archive-location))
        (original-save-context-info (if (boundp 'org-archive-save-context-info) org-archive-save-context-info)))
    (unwind-protect
        (progn
          (setq org-archive-location (concat file "::* TASKS"))
          (setq org-archive-save-context-info nil)
          ;; Ensure the target file has a "* TASKS" heading.
          (with-current-buffer (find-file-noselect file)
            (goto-char (point-min))
            (unless (re-search-forward "^\\* TASKS" nil t)
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (insert "* TASKS\n")))
          ;; Now, in the current buffer (the old journal), refile the tasks.
          (goto-char (point-max))
          (while (re-search-backward "^\\*\\* \\(TODO\\|WAIT\\|NEXT\\)" nil t)
            (org-archive-subtree)))
      ;; This part runs no matter what, restoring the original values.
      (setq org-archive-location original-archive-location)
      (setq org-archive-save-context-info original-save-context-info))))

(defun move-todos (todays-journal-path)
  "Move all TODOs from the previous day's journal to TODAYS-JOURNAL-PATH."
  (let ((previous-journal-name (find-previous-journal)))
    (if previous-journal-name
        (let ((previous-journal-path (file-name-concat denote-journal-directory previous-journal-name)))
          (if (and todays-journal-path (file-exists-p previous-journal-path))
              (progn
                (message "Journaling: Moving tasks from '%s' to '%s'"
                         (file-name-nondirectory previous-journal-path)
                         (file-name-nondirectory todays-journal-path))
                (with-current-buffer (find-file-noselect previous-journal-path)
                  (my-refile-tasks todays-journal-path))
                (kill-buffer (file-name-nondirectory previous-journal-path)))
            (message "Journaling: Could not move tasks. Target: %s. Previous: %s (exists: %s)"
                     todays-journal-path
                     previous-journal-path
                     (file-exists-p previous-journal-path))))
      (message "Journaling: No previous journal found to move tasks from."))))

(defun find-most-recent-journal ()
  "Find the file name of the most recent journal."
  (let* ((all-journals (sort (directory-files denote-journal-directory t "^[0-9].*_journal.*org$") #'string>)) ; Changed nil to t for full path
         (most-recent-journal (car all-journals)))
    (if most-recent-journal
        (progn
          (message "Journaling: Found most recent journal: %s" most-recent-journal)
          most-recent-journal)
      (message "Journaling: No journal file found."))))

(defun set-org-refile-targets-to-most-recent-journal ()
  "Sets `org-refile-targets` to the most recent journal file."
  (interactive)
  (let ((recent-journal-file (find-most-recent-journal)))
    (when recent-journal-file
      ;; Corrected structure: '(STRING) instead of '((STRING))
      (setq org-refile-targets `((,recent-journal-file . (:regexp . "TASKS"))))
      (message "Refile targets set to: %s" (car org-refile-targets)))))

(add-hook 'org-agenda-mode-hook #'set-org-refile-targets-to-most-recent-journal)


(defun my-denote-journal-today ()
  "Create or find today's journal and move tasks from the previous day."
  (interactive)
  (let* ((today (format-time-string "%Y%m%d"))
         (existing-file (car (journal-day-exists-p today)))
         (todays-journal-path
          (if existing-file
              ;; If file exists, get its full path
              (concat denote-journal-directory existing-file)
            ;; Otherwise, create a new one and get its path
            (denote
             (format-time-string "%Yw%W-%a %e %b") ; Title format
             '("journal")
             nil                        ; file-type
             denote-journal-directory))))

    ;; Now we have the definitive path to today's journal.
    ;; Ensure the buffer is open and has the required structure.
    (with-current-buffer (find-file-noselect todays-journal-path)
      (when (not existing-file)
        ;; It's a new file, so insert the template.
        (insert "* TASKS\n\n ** TODO [#B] Validar registrados los seguimientos y PREP de ayer\n** TODO [#B] Una respuesta a contacto de internet \n** TODO [#B] Un seguimiento a PREP\n** TODO [#B] Un Seg. a Cotizaciones enviadas\n** TODO [#B] Un seg. a prospecto de paneles\n")
        (save-buffer)))

    ;; Now that today's journal is guaranteed to exist, move the unfinished tasks.
    (move-todos todays-journal-path)

    ;; If we created a new file, refresh the agenda files list.
    (unless existing-file
      (setq org-agenda-files (append '("~/Documents/org/todo.org")
                                     (journals_to_org_agenda))))

    ;; Finally, make sure the user is in today's journal buffer.
    (switch-to-buffer (find-file-noselect todays-journal-path)))

  ;; After all journal operations are complete, update the refile target.
  (set-org-refile-targets-to-most-recent-journal)
  )

;; (defun my-denote-journal-date ()
;;   "Create or find a journal for a specific date."
;;   (declare (interactive-only t))
;;   (interactive)
;;   (let* ((date (org-read-date nil t))
;;          (filename (car (journal-day-exists-p (format-time-string "%Y%m%d" date)))))
;;     (if filename
;;         (find-file filename)
;;       (progn
;;         (denote
;;          (format-time-string "%Yw%W-%a %e %b" date)
;;          '("journal")
;;          nil
;;          denote-journal-directory)
;;         (insert "* TASKS\n\n ** TODO [#B] Validar registrados los seguimientos y PREP de ayer\\n** TODO [#B] Una respuesta a contacto de internet\nn** TODO [#B] Un seguimiento a PREP\n\n** TODO [#B] Un Seg. a Cotizaciones enviadas\n\n** TODO [#B] Un seg. a prospecto de paneles\n\n")
;;         ))))


;; --- CONFIGURATIONS USING CUSTOM FUNCTIONS ---

;; --- IMPORTANT ---
;; Change the path below to your main tasks file.
;; (setq org-agenda-files (append '("~/Documents/org/todo.org") (journals_to_org_agenda)))

;; New keybindings for the custom journaling workflow.
(let ((map global-map))
  (define-key map (kbd "C-c n j") #'my-denote-journal-today))
  ;; (define-key map (kbd "C-c n o") #'my-denote-journal-date))

(with-eval-after-load 'org (setq
                            org-agenda-files '("~/Documents/elemento/newkb/20220728T144545--todo__pend.org"
                                               "~/Documents/elemento/newkb/diario")))


(provide 'setup-denote)
;;; setup-denote.el ends here
