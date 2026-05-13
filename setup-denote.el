;;; setup-denote.el --- Denote configuration with custom journaling -*- lexical-binding: t -*-

;;; Commentary:
;;; This file configures denote.el and adds a custom journaling workflow.
;;; The workflow automatically moves unfinished tasks from the previous day's
;;; journal to the current one and integrates recent journals with Org Agenda.
;;; Journals are stored in the "diario" subdirectory.

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
(setq denote-directory (expand-file-name "~/newkb/"))
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
  "Refile every level-2 TODO/WAIT/NEXT subtree in the current buffer to FILE under '* TASKS'.
Headlines in other states (DONE, KILL, SDM, PROG, etc.) are left behind."
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
        (save-buffer)))

    ;; Now that today's journal is guaranteed to exist, move the unfinished tasks.
    (move-todos todays-journal-path)

    ;; If we created a new file, refresh the agenda files list.
    (unless existing-file
      (setq org-agenda-files (journals_to_org_agenda)))

    ;; Finally, make sure the user is in today's journal buffer.
    (switch-to-buffer (find-file-noselect todays-journal-path)))

  ;; After all journal operations are complete, update the refile target.
  (set-org-refile-targets-to-most-recent-journal)
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; COPIAR A TAREAS DIARIAS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun my--priads-file-p (path)
  "Return non-nil if PATH is a PRIADS .org file directly under `denote-directory'.
Subdirectories (e.g. diario/) and .org_archive files are excluded."
  (and path
       (string= (file-name-extension path) "org")
       (string= (file-name-as-directory
                 (file-name-directory (expand-file-name path)))
                (file-name-as-directory (expand-file-name denote-directory)))))

(defun my-copiar-a-tareas-diarias--do-copy ()
  "Copy every TODO subtree in the current buffer to the most recent diario.
Skips entries whose headline already exists in the diario and entries
whose ancestor headline is itself in the TODO state.
Returns `no-todos' or a cons (COPIED . SKIPPED).  Raises `user-error'
when the user cancels at the save prompt or when no diario exists."
  (unless (buffer-file-name)
    (user-error "Este buffer no visita un archivo"))
  (when (buffer-modified-p)
    (if (y-or-n-p "El archivo no está grabado. ¿Realmente quieres copiar tareas a diarias, este proceso? ")
        (save-buffer)
      (user-error "Cancelado")))
  (let ((target (find-most-recent-journal)))
    (unless target
      (user-error "No se encontró archivo diario reciente"))
    (let ((existing-titles (make-hash-table :test 'equal))
          (rfloc nil)
          (copied 0)
          (skipped 0))
      ;; Prepare diario: ensure `* TASKS', gather existing titles, build RFLOC.
      (with-current-buffer (find-file-noselect target)
        (org-with-wide-buffer
         (goto-char (point-min))
         (unless (re-search-forward "^\\* TASKS" nil t)
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert "* TASKS\n"))
         (goto-char (point-min))
         (re-search-forward "^\\* TASKS")
         (setq rfloc (list "TASKS" (buffer-file-name) nil
                           (line-beginning-position)))
         (org-map-entries
          (lambda ()
            (puthash (org-get-heading t t t t) t existing-titles)))))
      ;; Iterate TODO entries in the source buffer.
      (org-map-entries
       (lambda ()
         (let ((title (org-get-heading t t t t))
               (has-todo-ancestor
                (save-excursion
                  (catch 'found
                    (while (org-up-heading-safe)
                      (when (equal (org-get-todo-state) "TODO")
                        (throw 'found t)))
                    nil))))
           (cond
            (has-todo-ancestor)              ; pulled in by an ancestor copy
            ((gethash title existing-titles)
             (cl-incf skipped))
            (t
             (let ((org-refile-keep t)
                   (org-log-refile nil))
               (org-refile nil nil rfloc "Copy"))
             (puthash title t existing-titles)
             (cl-incf copied)))))
       "/TODO" 'file)
      (with-current-buffer (find-file-noselect target)
        (save-buffer))
      (if (and (= copied 0) (= skipped 0))
          'no-todos
        (message "Copiadas %d tareas, omitidas %d duplicadas hacia %s"
                 copied skipped (file-name-nondirectory target))
        (cons copied skipped)))))

(defun my-copiar-a-tareas-diarias ()
  "Copy TODO tasks from the current PRIADS buffer to the most recent diario, then kill the buffer."
  (interactive)
  (unless (my--priads-file-p (buffer-file-name))
    (user-error "Este buffer no visita un archivo PRIADS"))
  (my-copiar-a-tareas-diarias--do-copy)
  (kill-buffer (current-buffer)))

(defun my-copiar-a-tareas-diarias--maybe-on-kill ()
  "Run the copy-to-diario workflow when killing a PRIADS buffer.
Returns t so the kill proceeds normally; a `user-error' from
`my-copiar-a-tareas-diarias--do-copy' aborts the kill."
  (when (my--priads-file-p (buffer-file-name))
    (my-copiar-a-tareas-diarias--do-copy))
  t)

(add-hook 'kill-buffer-query-functions
          #'my-copiar-a-tareas-diarias--maybe-on-kill)

;; New keybindings for the custom journaling workflow.
(let ((map global-map))
  (define-key map (kbd "C-c n j") #'my-denote-journal-today)
  (define-key map (kbd "C-c n c") #'my-copiar-a-tareas-diarias)
  (define-key map (kbd "C-c n e") #'my-referir-pendientes))
  ;; (define-key map (kbd "C-c n o") #'my-denote-journal-date))

(with-eval-after-load 'org
  (setq org-agenda-files '("~/newkb/diario")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; REFERIR PENDIENTES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst my--priads-active-signature-regexp "==[pri]--"
  "Regex matching the signature segment of active PRIADS in Denote filenames.
Covers proyectos (p), responsabilidades (r), intereses (i).  Excludes
on-hold (sp/sr/si), archived (ap/ar/ai/ad), datos (d), some-day-maybe (s),
journals and legacy files without signature.")

(defun my--priads-active-files ()
  "Return absolute paths of active PRIADS files (signature p, r, or i)."
  (denote-directory-files my--priads-active-signature-regexp nil t))

(defun my--referir-find-headline (title)
  "Search active PRIADS files for a headline whose text equals TITLE.
Return (FILE . POSITION) of the first match, or nil if none found.
Buffers opened only for the search are killed before returning."
  (let ((files (my--priads-active-files))
        (result nil))
    (catch 'found
      (dolist (file files)
        (let* ((existing (get-file-buffer file))
               (buf (or existing (find-file-noselect file))))
          (unwind-protect
              (with-current-buffer buf
                (let ((pos
                       (org-with-wide-buffer
                        (goto-char (point-min))
                        (catch 'hit
                          (while (re-search-forward org-heading-regexp nil t)
                            (when (equal (org-get-heading t t t t) title)
                              (throw 'hit (line-beginning-position))))
                          nil))))
                  (when pos
                    (setq result (cons file pos))
                    (throw 'found result))))
            (unless (or existing result)
              (kill-buffer buf))))))
    result))

(defun my--referir-update-state (file pos new-state)
  "In FILE, move to POS and set the TODO state of that headline to NEW-STATE.
NEW-STATE is the string \"DONE\", \"KILL\", or \"SDM\".  Saves the buffer."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (goto-char pos)
     (org-todo new-state))
    (save-buffer)))

(defun my--referir-copy-to-completadas (target-file)
  "Copy the current source subtree to `* completadas' in TARGET-FILE.
Point must be on the source headline when called.  Creates the
`* completadas' headline if missing.  Skips silently if a headline with
the same title already exists under `* completadas'.  Returns t if the
subtree was copied, nil if skipped."
  (let* ((title (org-get-heading t t t t))
         (existing-titles (make-hash-table :test 'equal))
         (rfloc nil))
    (with-current-buffer (find-file-noselect target-file)
      (org-with-wide-buffer
       (goto-char (point-min))
       (unless (re-search-forward "^\\* completadas" nil t)
         (goto-char (point-max))
         (unless (bolp) (insert "\n"))
         (insert "* completadas\n"))
       (goto-char (point-min))
       (re-search-forward "^\\* completadas")
       (setq rfloc (list "completadas" (buffer-file-name) nil
                         (line-beginning-position)))
       (org-back-to-heading t)
       (let ((end (save-excursion (org-end-of-subtree t t))))
         (save-excursion
           (forward-line 1)
           (while (re-search-forward org-heading-regexp end t)
             (puthash (org-get-heading t t t t) t existing-titles))))))
    (cond
     ((gethash title existing-titles) nil)
     (t
      (let ((org-refile-keep t)
            (org-log-refile nil))
        (org-refile nil nil rfloc "Refer"))
      (with-current-buffer (find-file-noselect target-file)
        (save-buffer))
      t))))

(defun my-referir-pendientes ()
  "Refer DONE/KILL/SDM tasks from the current buffer to active PRIADS files.
Operates on the buffer the user invoked the command from — typically the
previous day's diario after rolling, but no automatic file discovery is
performed.  For each closed (DONE, KILL) or shelved (SDM) task:
- If an active PRIADS file has a headline with the same title, update its
  TODO state to match (DONE, KILL, or SDM).
- Otherwise, prompt (via `denote-file-prompt') to choose a PRIADS file;
  copy the subtree under `* completadas' there.  RET on an empty prompt
  skips the task."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Este buffer no está en org-mode"))
  (let ((updated 0) (copied 0) (skipped 0))
    (org-with-wide-buffer
     (org-map-entries
      (lambda ()
        (let ((state (org-get-todo-state)))
          (when (member state '("DONE" "KILL" "SDM"))
            (let* ((title (org-get-heading t t t t))
                   (hit (my--referir-find-headline title)))
              (cond
               (hit
                (my--referir-update-state (car hit) (cdr hit) state)
                (cl-incf updated))
               (t
                (let* ((files (my--priads-active-files))
                       (cands (append
                               '("(omitir)" "(crear nuevo PRIADS)")
                               (mapcar (lambda (f)
                                         (file-relative-name
                                          f denote-directory))
                                       files)))
                       (choice
                        (condition-case nil
                            (completing-read
                             (format "Referir \"%s\" a PRIADS: " title)
                             cands nil t nil nil "(omitir)")
                          (quit "(omitir)"))))
                  (cond
                   ((or (null choice) (string= choice "(omitir)"))
                    (cl-incf skipped))
                   ((string= choice "(crear nuevo PRIADS)")
                    (let* ((src-buf (current-buffer))
                           (src-pt (point))
                           (target (condition-case nil
                                       (call-interactively #'denote)
                                     (quit nil))))
                      (with-current-buffer src-buf
                        (save-excursion
                          (goto-char src-pt)
                          (if (and (stringp target) (file-exists-p target)
                                   (my--referir-copy-to-completadas target))
                              (cl-incf copied)
                            (cl-incf skipped))))))
                   (t
                    (let ((target (expand-file-name choice denote-directory)))
                      (if (my--referir-copy-to-completadas target)
                          (cl-incf copied)
                        (cl-incf skipped))))))))))))
      nil 'file))
    (message "Referir pendientes: %d actualizados, %d copiados, %d saltados"
             updated copied skipped)))


(provide 'setup-denote)
;;; setup-denote.el ends here
