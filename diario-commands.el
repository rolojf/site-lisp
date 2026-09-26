;;; diario-commands.el --- Diario command integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Denote discovery and interactive migration around the isolated diario engine.
;; Loading this module does not install hooks, keys, or agenda settings.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'org-refile)
(require 'diario-rollover)
(require 'diario-migrate)
(require 'diario-focus)

(defvar denote-journal-directory)

(defconst my-dc--journal-name
  "\\`[0-9]\\{8\\}T[0-9]\\{4\\}\\(?:[0-9]\\{2\\}\\)?\\(?:==[a-z]+\\)?--[^/]+__\\(?:[[:alnum:]-]+_\\)*journal\\(?:_[[:alnum:]-]+\\)*\\.org\\'"
  "Denote journal filenames, directly inside the configured diario directory.")

(defconst my-dc--refile-regexp
  "^\\(?:\\* \\(?:DEEP\\|SHALLOW\\)\\|\\*\\* \\(?:Empresa\\|Contratista\\)\\)\\(?:[ \t]+:[^ \t\n]+:\\)?[ \t]*$"
  "Task lists and tagged or untagged OT buckets for native Org refile.")

(defvar my-dc--base-refile-verify nil
  "Org's verifier before diario refile destinations were installed.")

(defun my-dc--later ()
  "Return the configured absolute LUEGO path."
  (expand-file-name "LUEGO.org" denote-journal-directory))

(defun my-dc--journal-p (path)
  "Return non-nil if PATH is a real Denote journal directly in diario/."
  (and (stringp path)
       (equal (file-name-as-directory (file-name-directory (expand-file-name path)))
              (file-name-as-directory (expand-file-name denote-journal-directory)))
       (string-match-p my-dc--journal-name (file-name-nondirectory path))
       (file-regular-p path)
       (not (file-symlink-p path))))

(defun my-dc--files ()
  "List eligible diario files newest first, without searching other directories."
  (if (file-directory-p denote-journal-directory)
      (sort (cl-remove-if-not #'my-dc--journal-p
                              (directory-files denote-journal-directory t
                                               my-dc--journal-name))
            #'string>)
    nil))

(defun my-dc--day-files (date)
  "Return diario files for YYYYMMDD DATE, newest first."
  (my-diario--date date)
  (cl-remove-if-not (lambda (file)
                      (string= (substring (file-name-nondirectory file) 0 8) date))
                    (my-dc--files)))

(defun my-dc--day (date)
  "Find the unique diario on DATE, or signal an ambiguous same-day choice."
  (let ((files (my-dc--day-files date)))
    (when (cdr files)
      (user-error "Hay varios diarios para %s; elija uno manualmente" date))
    (car files)))

(defun my-dc--previous (date)
  "Find the latest diario strictly before YYYYMMDD DATE."
  (my-diario--date date)
  (cl-find-if (lambda (file)
                (string< (substring (file-name-nondirectory file) 0 8) date))
              (my-dc--files)))

(defun my-diario-current (&optional date)
  "Return today's diario or the latest prior one, never a future snapshot."
  (let ((date (or date (format-time-string "%Y%m%d"))))
    (or (my-dc--day date) (my-dc--previous date))))

(defun my-diario-agenda-files (&optional date)
  "Return the current diario and existing LUEGO for the active-work agenda."
  (let ((current (my-diario-current date))
        (later (my-dc--later)))
    (append (when current (list current))
            (when (and (file-regular-p later) (not (file-symlink-p later)))
              (list later)))))

(defun my-diario-refresh-agenda ()
  "Use only the current diario and parked work for the default agenda."
  (interactive)
  (setq org-agenda-files (my-diario-agenda-files)))

(defun my-dc--refile-verify ()
  "Accept only managed task lists or a job bucket directly under OT."
  (and (or (not my-dc--base-refile-verify)
           (funcall my-dc--base-refile-verify))
       (let ((level (org-outline-level))
             (title (org-get-heading t t t t)))
         (or (and (= level 1) (member title my-dmig--lists))
             (and (= level 2) (member title my-dmig--jobs)
                  (save-excursion
                    (and (org-up-heading-safe)
                         (= (org-outline-level) 1)
                         (equal (org-get-heading t t t t) my-dmig--ot))))))))

(defun my-diario-refile-targets ()
  "Offer managed lists and OT buckets of the current diario for Org refile.
Return the configured target alist, or nil when there is no current diario."
  (interactive)
  (let ((current (my-diario-current)))
    (setq org-refile-targets
          (when current `((,current . (:regexp . ,my-dc--refile-regexp)))))
    (if current
        (progn
          (unless (eq org-refile-target-verify-function #'my-dc--refile-verify)
            (setq my-dc--base-refile-verify org-refile-target-verify-function))
          (setq org-refile-target-verify-function #'my-dc--refile-verify))
      (when (eq org-refile-target-verify-function #'my-dc--refile-verify)
        (setq org-refile-target-verify-function my-dc--base-refile-verify)))
    org-refile-targets))

(defun my-diario-activate-focus ()
  "Enable the diario-local focus key in this saved journal buffer only."
  (interactive)
  (if (and (derived-mode-p 'org-mode)
           (my-dc--journal-p (buffer-file-name)))
      (my-diario-focus-mode 1)
    (when (called-interactively-p 'interactive)
      (user-error "Abra un diario Org guardado dentro de denote-journal-directory"))))

(defun my-dc--layout (path)
  "Check PATH's saved three-list layout before the engine may edit it."
  (when-let* ((live (find-buffer-visiting path)))
    (with-current-buffer live
      (when (and (derived-mode-p 'org-mode)
                 (save-excursion (org-with-wide-buffer
                                  (my-dmig--heading my-dmig--legacy))))
        (user-error "Clasifique TASKS: my-diario-prepare, my-diario-classify y my-diario-finish; luego guarde %s" path))))
  (let ((text (my-diario--read path)))
    (my-diario--with-text text
      (when (my-dmig--heading my-dmig--legacy)
        (user-error "Clasifique TASKS: my-diario-prepare, my-diario-classify y my-diario-finish; luego guarde %s" path))
      (my-diario--scan)))
  t)

(defun my-dc--later-ready ()
  "Reject legacy LUEGO before creating or changing a diario."
  (let ((later (my-dc--later)))
    (when (file-symlink-p later)
      (user-error "LUEGO no puede ser un enlace simbólico: %s" later))
    (when-let* ((text (my-diario--read later)))
      (condition-case err
          (my-diario--with-text text (my-diario--later-scan))
        (user-error
         (user-error "%s; ejecute my-diario-reconcile-luego y guarde LUEGO"
                     (error-message-string err)))))))

(defun my-dc--pending-p (source target)
  "Check on disk for explicit roll receipts addressed to TARGET in SOURCE."
  (when source
    (my-diario--with-text (my-diario--read-disk source)
      (let (pending)
        (org-map-entries
         (lambda ()
           (when (equal (org-entry-get nil "DIARIO_ROLL_TO" nil) target)
             (setq pending t))) nil 'file)
        pending))))

(defun my-dc--fresh-target-p (path text date)
  "Return non-nil if TEXT is untouched Denote metadata for PATH and DATE."
  (let* ((name (file-name-nondirectory path))
         (case-fold-search t)
         (id (when (string-match
                    "\\`\\([0-9]\\{8\\}T[0-9]\\{4\\}\\(?:[0-9]\\{2\\}\\)?\\)" name)
               (match-string 1 name))))
    (and id (string= (substring id 0 8) date)
         (my-diario--fresh-p text)
         (string-match-p (concat "^#\\+identifier:[ \t]*"
                                 (regexp-quote id) "[ \t]*$") text)
         (string-match-p (concat "^#\\+date:[ \t]*\\["
                                 (my-diario--iso date) "\\b") text))))

(defun my-dc--created (date)
  "Create DATE's diario using Denote and verify its newly saved frontmatter."
  (unless (fboundp 'denote)
    (user-error "Denote no está disponible para crear el diario"))
  (let ((path (denote (format-time-string "%Yw%W-%a %e %b")
                      '("journal") nil denote-journal-directory)))
    (unless (and (stringp path)
                 (string-match-p my-dc--journal-name (file-name-nondirectory path))
                 (string= (substring (file-name-nondirectory path) 0 8) date)
                 (equal (file-name-as-directory (file-name-directory (expand-file-name path)))
                        (file-name-as-directory (expand-file-name denote-journal-directory))))
      (user-error "Denote no creó un diario nuevo para %s en diario/" date))
    ;; Denote may leave its new metadata in a modified visiting buffer.
    (let ((buffer (or (find-buffer-visiting path)
                      (when (file-exists-p path) (find-file-noselect path)))))
      (unless buffer (user-error "Denote no devolvió un diario editable: %s" path))
      (with-current-buffer buffer
        (when (buffer-modified-p) (save-buffer))))
    (unless (my-dc--journal-p path)
      (user-error "Denote no guardó un archivo diario regular: %s" path))
    (unless (my-dc--fresh-target-p path (my-diario--read path) date)
      (user-error "El diario creado no tiene metadatos Denote frescos/coherentes: %s" path))
    path))

(defun my-dc--initialize (target)
  "Initialize a fresh Denote TARGET with the three empty managed lists."
  (let* ((text (my-diario--read target))
         (prepared (my-diario--with-text text
                     (my-diario-prepare)
                     (buffer-string))))
    (my-diario--save target text prepared)
    (my-dc--layout target)))

(defun my-dc--run (target date kind)
  "Process TARGET on DATE; KIND is `new' or `existing'."
  (unless (and (my-dc--journal-p target)
               (equal (substring (file-name-nondirectory target) 0 8) date))
    (user-error "Se requiere un diario existente de %s" date))
  (let* ((source (my-dc--previous date))
         (text (my-diario--read target))
         (fresh (my-diario--fresh-p text))
         (resume (and (eq kind 'existing) (my-dc--pending-p source target)))
         (later (my-dc--later)))
    (my-dc--later-ready)
    (when (and fresh (not (my-dc--fresh-target-p target text date)))
      (user-error "El diario sin contenido no tiene metadatos Denote coherentes: %s" target))
    (when (and (eq kind 'new) (not fresh))
      (user-error "El diario recién creado ya contiene cambios; no se sobrescribirá"))
    (unless fresh (my-dc--layout target))
    (if (and source (or fresh resume))
        (progn
          (my-dc--layout source)
          (my-diario-roll source target later date))
      (when fresh (my-dc--initialize target))
      (list :mode kind
            :returned (plist-get (my-diario-return target later date) :returned)))))

;;;###autoload
(defun my-diario-today ()
  "Open today's diario, rolling fresh metadata or resuming receipted work.
Validate source/LUEGO before Denote creates a file.  An initialized day
is never recopied: without source receipts it only retrieves due COLD work."
  (interactive)
  (let* ((date (format-time-string "%Y%m%d"))
         (existing (my-dc--day date))
         (source (unless existing (my-dc--previous date))))
    (unless existing
      (when source (my-dc--layout source))
      (my-dc--later-ready))
    (let* ((target (or existing (my-dc--created date)))
           (result (my-dc--run target date (if existing 'existing 'new))))
      (my-diario-refresh-agenda)
      (my-diario-refile-targets)
      (switch-to-buffer (find-file-noselect target))
      (my-diario-activate-focus)
      (message "Diario %s (%s): %d OT, %d movidas, %d aparcadas, %d retornadas"
               (file-name-nondirectory target) (plist-get result :mode)
               (or (plist-get result :copied-ot) 0)
               (or (plist-get result :moved) 0)
               (or (plist-get result :parked) 0)
               (or (plist-get result :returned) 0))
      (append (list :target target) result))))

;;;###autoload
(defun my-diario-finish ()
  "Finish explicit TASKS classification here, without saving the diario.
Only remove an empty TASKS root; keep remaining prose under a notes heading.
Subheadings still under TASKS require deliberate classification/removal first."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Finalizar requiere un buffer Org"))
  (org-with-wide-buffer
   (let ((root (my-dmig--heading my-dmig--legacy)))
     (unless root (user-error "No existe * TASKS para finalizar"))
     (goto-char root)
     (let ((end (save-excursion (org-end-of-subtree t t)))
           (body-start (min (point-max) (1+ (line-end-position)))))
       (save-excursion
         (goto-char body-start)
         (when (re-search-forward org-heading-regexp end t)
           (user-error "TASKS aún tiene subencabezados; use my-diario-classify antes de my-diario-finish")))
       (undo-boundary)
       (atomic-change-group
         (if (string-empty-p (string-trim (buffer-substring-no-properties body-start end)))
             (delete-region root end)
           (org-edit-headline "Notas (antes TASKS)")))
       (undo-boundary)))))

;;;###autoload
(defun my-diario-reconcile-luego (&optional path date)
  "Explicitly classify legacy COLD entries in LUEGO; never save the file.
Prompt for each unknown original list/bucket.  Preserve dated subtrees;
missing schedules become DATE + 14 days.  PATH defaults to LUEGO.org and
DATE to today.  The user must inspect and save the undoable buffer edits."
  (interactive)
  (let* ((path (or path (my-dc--later)))
         (date (or date (format-time-string "%Y%m%d"))))
    (my-diario--date date)
    (unless (and (equal (expand-file-name path) (my-dc--later))
                 (file-regular-p path) (not (file-symlink-p path)))
      (user-error "Abra el LUEGO.org regular de denote-journal-directory"))
    (with-current-buffer (find-file-noselect path)
      (unless (derived-mode-p 'org-mode)
        (user-error "LUEGO debe ser un buffer Org"))
      (org-with-wide-buffer
       (let (root root-name choices)
         (unwind-protect
             (progn
               ;; Reject ambiguous roots/partial metadata before asking for origins.
               (goto-char (point-min))
               (while (re-search-forward org-heading-regexp nil t)
                 (beginning-of-line)
                 (pcase (org-outline-level)
                   (1 (let ((name (org-get-heading t t t t)))
                        (unless (and (not root) (member name '("TASKS" "LUEGO")))
                          (user-error "Raíz LUEGO ambigua: %s" name))
                        (setq root (copy-marker (point)) root-name name)))
                   (2 (unless root (user-error "Entrada LUEGO sin raíz"))
                      (unless (equal (org-get-todo-state) "COLD")
                        (user-error "LUEGO requiere COLD; corrija el estado manualmente"))
                      (let ((origin (org-entry-get nil "DIARIO_LIST"))
                            (bucket (org-entry-get nil "DIARIO_BUCKET"))
                            (hash (org-entry-get nil "DIARIO_ORIGIN_HASH"))
                            (schedule (org-entry-get nil "SCHEDULED")))
                        (when (and schedule (not (org-get-scheduled-time (point))))
                          (user-error "Fecha SCHEDULED inválida en LUEGO; corrija manualmente"))
                        (if (or origin bucket hash)
                            (unless (and origin hash (org-entry-get nil "DIARIO_KEY"))
                              (user-error "Metadatos de origen parciales en LUEGO; revise manualmente"))
                          (push (copy-marker (point)) choices))))
                   (_ (unless root (user-error "Encabezado LUEGO huérfano"))))
                 (forward-line 1))
               (unless root (user-error "Falta la raíz TASKS/LUEGO"))
               (setq choices (nreverse choices))
               (setq choices
                     (mapcar (lambda (marker)
                               (cons marker
                                     (completing-read
                                      (format "Origen de %s: "
                                              (save-excursion
                                                (goto-char marker)
                                                (org-get-heading t t t t)))
                                      my-dmig--choices nil t)))
                             choices))
               (when (or (equal root-name "TASKS") choices)
                 (undo-boundary)
                 (atomic-change-group
                   (when (equal root-name "TASKS")
                     (goto-char root)
                     (org-edit-headline "LUEGO"))
                   (dolist (choice choices)
                     (goto-char (car choice))
                     (let* ((destination (cdr choice))
                            (ot (string-prefix-p "OT " destination))
                            (list-name (if ot (car my-diario--lists) destination))
                            (bucket (when ot (substring destination 3)))
                            (key (or (org-entry-get nil "DIARIO_KEY")
                                     (let ((org-id-method 'uuid)) (org-id-new)))))
                       (org-entry-put nil "DIARIO_KEY" key)
                       (org-entry-put nil "DIARIO_LIST" list-name)
                       (when bucket (org-entry-put nil "DIARIO_BUCKET" bucket))
                       (org-entry-put nil "DIARIO_ORIGIN_HASH"
                                      (my-diario--origin-hash key list-name bucket))
                       (unless (org-get-scheduled-time (point))
                         (let ((org-log-reschedule nil))
                           (org-schedule nil (my-diario--iso date my-diario--park-days))))))
                   (my-diario--later-scan))
                 (undo-boundary))
               (unless (or (equal root-name "TASKS") choices)
                 (my-diario--later-scan)))
           (when root (set-marker root nil))
           (dolist (choice choices)
             (set-marker (if (consp choice) (car choice) choice) nil))))
       (current-buffer)))
    (when (called-interactively-p 'interactive)
      (pop-to-buffer (find-buffer-visiting path)))
    (find-buffer-visiting path)))

(provide 'diario-commands)
;;; diario-commands.el ends here
