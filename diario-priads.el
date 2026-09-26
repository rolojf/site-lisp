;;; diario-priads.el --- Deliberate three-list PRIAD records -*- lexical-binding: t; -*-

;;; Commentary:
;; Refer only managed, finished OT/DEEP roots.  The source remains the log of
;; what happened; PRIADS receive independent records, never a live task list.
;; A source marker is saved first so a failed destination write can be retried.
;; No keys, hooks, Denote creation, or discovery of real KB files live here.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'subr-x)
(require 'diario-focus)

(defconst my-dp--deep "DEEP")
(defconst my-dp--shallow "SHALLOW")
(defconst my-dp--omit "(omitir)")
(defconst my-dp--create "(crear PRIAD con callback)")
(defconst my-dp--active-file
  "\\`[0-9]\\{8\\}T[0-9]\\{4\\}\\([0-9]\\{2\\}\\)?==[pri]--[^/]+__\\([^/]+\\)\\.org\\'"
  "Active, keyword-bearing PRIAD filename (not an archive or journal).")

(defun my-dp--identity (file)
  "Return (DENOTE-ID . KEYWORDS) for active candidate FILE, or nil."
  (let ((name (file-name-nondirectory file))
        (case-fold-search nil))
    (when (string-match my-dp--active-file name)
      (let ((keywords (match-string 2 name)))
        (cons (substring name 0 (string-match "==" name))
              (split-string keywords "_" t))))))

(defun my-dp--disk (file)
  "Read FILE without opening a visiting buffer."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun my-dp--snapshot (file)
  "Read FILE, refusing an unsaved or stale visiting buffer."
  (unless (and (file-regular-p file) (not (file-symlink-p file)))
    (user-error "PRIAD/diario file is not a regular file: %s" file))
  (let ((text (my-dp--disk file)))
    (when-let* ((live (find-buffer-visiting file)))
      (with-current-buffer live
        (save-restriction
          (widen)
          (when (or buffer-read-only (buffer-modified-p)
                    (not (equal text (buffer-string))))
            (user-error "Read-only, unsaved or stale involved buffer: %s" file)))))
    text))

(defun my-dp--save (file expected text)
  "Replace only FILE if it still equals EXPECTED; sync its clean visiting buffer.
The temporary file and rename prevent a failed write from truncating FILE.
A saved source marker or destination record survives a later failed write."
  (unless (equal (my-dp--snapshot file) expected)
    (user-error "PRIAD/diario file changed: %s" file))
  (unless (equal expected text)
    (let ((tmp (make-temp-file (expand-file-name ".diario-priad-"
                                                 (file-name-directory file)))))
      (unwind-protect
          (progn
            (write-region text nil tmp nil 'silent)
            (set-file-modes tmp (file-modes file))
            (unless (equal (my-dp--snapshot file) expected)
              (user-error "PRIAD/diario file changed before save: %s" file))
            (rename-file tmp file t)
            (unless (equal (my-dp--disk file) text)
              (error "PRIAD/diario save verification failed: %s" file))
            (when-let* ((live (find-buffer-visiting file)))
              (with-current-buffer live
                (save-restriction
                  (widen)
                  (unless (and (not (buffer-modified-p))
                               (equal (buffer-string) expected))
                    (user-error "Visiting buffer changed during save: %s" file))
                  (unless (equal (my-dp--disk file) text)
                    (user-error "PRIAD/diario file changed before buffer sync: %s" file))
                  ;; The verified rename changed the file's modtime; acknowledge
                  ;; it before editing the unchanged visitor to avoid a false
                  ;; supersession prompt.  Never acknowledge unverified bytes.
                  (set-visited-file-modtime)
                  (with-temp-buffer
                    (insert text)
                    (let ((new (current-buffer)))
                      (with-current-buffer live
                        (replace-buffer-contents new))))
                  (set-buffer-modified-p nil)))))
        (when (file-exists-p tmp) (delete-file tmp)))))
  text)

(defun my-dp--kind ()
  "Return `ot', `deep', `shallow' or nil for a managed root at point."
  (let ((level (org-outline-level)))
    (save-excursion
      (cond
       ((and (= level 3) (org-up-heading-safe)
             (org-up-heading-safe)
             (equal (org-get-heading t t t t) my-diario--ot-section))
        'ot)
       ((and (= level 2) (org-up-heading-safe))
        (let ((parent (org-get-heading t t t t)))
          (cond ((equal parent my-dp--deep) 'deep)
                ((equal parent my-dp--shallow) 'shallow))))))))

(defun my-dp--entries ()
  "Collect managed roots in the current point/headline scope, last first.
A headline with children selects its subtree only when point is on its
headline; a leaf or point in the body selects only its containing heading."
  (unless (org-before-first-heading-p)
    (let* ((on-heading (org-at-heading-p))
           (start (save-excursion (org-back-to-heading t) (point)))
           (end (save-excursion
                  (goto-char start)
                  (if (and on-heading (org-goto-first-child))
                      (progn (goto-char start) (org-end-of-subtree t t))
                    (save-excursion (forward-line 1) (point)))))
           (entries nil))
      (goto-char start)
      (while (re-search-forward org-heading-regexp end t)
        (beginning-of-line)
        (when-let* ((kind (my-dp--kind)))
          (push (cons (point) kind) entries))
        (forward-line 1))
      entries)))

(defun my-dp--choose (prompt choices)
  "Choose from CHOICES or omit; a unique choice needs no prompt."
  (pcase choices
    (`() nil)
    (`(,only) only)
    (_ (let ((answer (completing-read prompt (append choices (list my-dp--omit))
                                      nil t nil nil my-dp--omit)))
         (unless (equal answer my-dp--omit) answer)))))

(defun my-dp--destination (tag files create-priad)
  "Resolve TAG to a keyword-bearing active PRIAD in FILES.
Return nil when unresolved, or `my-dp--omit' for an explicit omission.
For no match, offer the optional CREATE-PRIAD callback or omission.  The
callback receives BASE and full TAG and must return a saved active Denote
PRIAD file with a BASE filename keyword, or nil if cancelled."
  (let* ((base (car (my-diario-tag-parts tag)))
         (matches (cl-remove-if-not
                   (lambda (file) (member base (cdr (my-dp--identity file))))
                   files)))
    (cond
     (matches (or (my-dp--choose "Elegir PRIAD: " matches) my-dp--omit))
     (create-priad
      (if (equal (completing-read "Sin PRIAD: "
                                  (list my-dp--create my-dp--omit)
                                  nil t nil nil my-dp--omit)
                 my-dp--omit)
          my-dp--omit
        (let ((file (funcall create-priad base tag)))
          (when file
            (setq file (expand-file-name file))
            (unless (and (my-dp--identity file)
                         (member base (cdr (my-dp--identity file)))
                         (file-regular-p file))
              (user-error "Callback did not provide a saved active PRIAD for %s" base))
            file)))))))

(defun my-dp--inspect (text tag key state)
  "Inspect destination TEXT for TAG/KEY/STATE; return a status plist.
A matching marked group is reusable.  Only explicitly OT-named unmarked
groups, duplicate markers, misplaced records, or unsuffixed associations
with other OT groups are conflicts; ordinary tagged log entries are not."
  (with-temp-buffer
    (let ((org-mode-hook nil)) (org-mode))
    (insert text)
    (goto-char (point-min))
    (let* ((group nil) (found nil) (conflict nil) (other-ot nil)
           (parts (my-diario-tag-parts tag))
           (base (car parts)) (suffix (cdr parts))
           (name (concat "OT " tag)))
      (while (re-search-forward org-heading-regexp nil t)
        (beginning-of-line)
        (let* ((level (org-outline-level))
               (title (org-get-heading t t t t))
               (ot-tag (org-entry-get nil "DIARIO_OT_TAG"))
               (record-key (org-entry-get nil "DIARIO_REF_KEY")))
          (when ot-tag
            (cond
             ((not (= level 1)) (setq conflict "Grupo OT fuera del nivel raíz"))
             ((equal ot-tag tag)
              (if group (setq conflict "Grupos OT duplicados")
                (setq group (point))))
             ((and (null (cdr (my-diario-tag-parts tag)))
                   (my-diario-customer-tag-p base ot-tag))
              (setq other-ot t))))
          (when (and (not ot-tag) (not record-key)
                     (not (org-get-todo-state))
                     (or (equal title name)
                         (and suffix (equal title (concat "OT " suffix)))
                         (and (not suffix)
                              (string-prefix-p (concat "OT " base "_") title))))
            (setq conflict "Grupo OT previo sin metadatos; requiere revisión"))
          (when (equal record-key key)
            (if found (setq conflict "Registro de referencia duplicado")
              (setq found
                    (list (org-entry-get nil "DIARIO_REF_TAG")
                          (org-entry-get nil "DIARIO_REF_STATE")
                          (save-excursion
                            (when (org-up-heading-safe)
                              (org-entry-get nil "DIARIO_OT_TAG"))))))))
        (forward-line 1))
      (when (and found (not (equal found (list tag state tag))))
        (setq conflict "Registro existente cambió de OT, ubicación o estado"))
      (when (and other-ot (not found))
        (setq conflict "OT sin sufijo ambigua con otro grupo"))
      (list :group group :already (and found (not conflict)) :conflict conflict))))

(defun my-dp--marked (text pos key tag dest-id)
  "Add automatic source KEY, TAG and DEST-ID to root at POS in TEXT."
  (with-temp-buffer
    (let ((org-mode-hook nil)) (org-mode))
    (insert text)
    (goto-char pos)
    (org-entry-put nil "DIARIO_REF_KEY" key)
    (org-entry-put nil "DIARIO_REF_TAG" tag)
    (org-entry-put nil "DIARIO_REF_DEST" dest-id)
    (buffer-string)))

(defun my-dp--record (subtree kind tag key state)
  "Copy SUBTREE into a level-two record, without duplicate Org IDs."
  (with-temp-buffer
    (let ((org-mode-hook nil)) (org-mode))
    (insert subtree)
    (goto-char (point-min))
    (when (eq kind 'ot) (org-promote-subtree))
    (org-entry-delete nil "DIARIO_REF_DEST")
    (org-entry-put nil "DIARIO_REF_KEY" key)
    (org-entry-put nil "DIARIO_REF_TAG" tag)
    (org-entry-put nil "DIARIO_REF_STATE" state)
    (org-entry-put nil "DIARIO_REF_DATE" (format-time-string "%Y-%m-%d"))
    (goto-char (point-min))
    (while (re-search-forward org-heading-regexp nil t)
      (beginning-of-line)
      (org-entry-delete nil "ID")
      (forward-line 1))
    (buffer-string)))

(defun my-dp--append (text group tag record)
  "Append RECORD to GROUP in TEXT, creating a plain OT TAG group if absent."
  (with-temp-buffer
    (let ((org-mode-hook nil)) (org-mode))
    (insert text)
    (if group
        (goto-char group)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (let ((start (point)))
        (insert "* OT " tag "\n")
        (goto-char start)
        (org-entry-put nil "DIARIO_OT_TAG" tag)))
    (org-end-of-subtree t t)
    (unless (bolp) (insert "\n"))
    (insert record)
    (unless (bolp) (insert "\n"))
    (buffer-string)))

(defun my-dp--refer-one (pos kind candidates create-priad source)
  "Refer managed root at POS of KIND from SOURCE, returning a count key.
CANDIDATES is a one-cell list, updated when the callback creates a PRIAD."
  (goto-char pos)
  (let* ((state (org-get-todo-state))
         (files (car candidates))
         (eligible (if (eq kind 'ot) '("DONE" "SDM" "KILL")
                     '("DONE" "SDM"))))
    (if (or (eq kind 'shallow) (not (member state eligible)))
        :ineligible
      (let* ((tags (my-diario-association-tags))
             (tag (my-dp--choose "Elegir asociación: " tags)))
        (if (not tag)
            (if tags :omitted :unresolved)
          (let* ((key (org-entry-get nil "DIARIO_REF_KEY"))
                 (prior-tag (org-entry-get nil "DIARIO_REF_TAG"))
                 (prior-dest (org-entry-get nil "DIARIO_REF_DEST"))
                 (prior-matches (when key
                                  (cl-remove-if-not
                                   (lambda (file)
                                     (equal prior-dest (car (my-dp--identity file))))
                                   files)))
                 (dest (if key
                           (and (= (length prior-matches) 1)
                                (car prior-matches))
                         (my-dp--destination tag files create-priad)))
                 (dest-id (when (and dest (not (equal dest my-dp--omit)))
                            (car (my-dp--identity dest)))))
            (cond
             ((and key (cdr prior-matches))
              (message "Identificador Denote duplicado para referencia: %s" prior-dest)
              :unresolved)
             ((and key (or (not (equal tag prior-tag)) (not dest)))
              (message "Referencia previa sin destino/asociación consistente: %s" tag)
              :unresolved)
             ((equal dest my-dp--omit) :omitted)
             ((not dest) :unresolved)
             ((cl-some (lambda (file)
                         (and (not (equal file dest))
                              (equal dest-id (car (my-dp--identity file)))))
                       files)
              (message "Identificador Denote duplicado para destino: %s" dest)
              :unresolved)
             ((equal (expand-file-name dest) source)
              (user-error "Source cannot be its own PRIAD destination"))
             (t
              (unless (member dest files)
                (setcar candidates (cons dest files)))
              (let* ((dest-text (my-dp--snapshot dest))
                     (target-id dest-id)
                     ;; User Org IDs may be second-resolution timestamps;
                     ;; reference keys need an independent UUID per record.
                     (new-key (or key (let ((org-id-method 'uuid))
                                        (org-id-new 'none))))
                     (status (my-dp--inspect dest-text tag new-key state)))
                (cond
                 ((plist-get status :conflict)
                  (message "%s: %s" (plist-get status :conflict) dest)
                  :unresolved)
                 ((plist-get status :already) :already)
                 (t
                  ;; Commit the source key before the record.  A failed second
                  ;; save leaves the entire source entry intact and retryable.
                  (unless key
                    (let ((before (my-dp--snapshot source)))
                      (my-dp--save source before
                                   (my-dp--marked before pos new-key tag target-id))))
                  (goto-char pos)
                  (let* ((subtree (buffer-substring-no-properties
                                   (point) (save-excursion (org-end-of-subtree t t))))
                         (record (my-dp--record subtree kind tag new-key state))
                         (updated (my-dp--append dest-text
                                                 (plist-get status :group)
                                                 tag record)))
                    (my-dp--save dest dest-text updated)
                    :copied))))))))))))

(defun my-diario-refer (candidate-files &optional create-priad)
  "Refer eligible roots at point from the current Org file to CANDIDATE-FILES.
CANDIDATE-FILES is an explicit list of existing active keyword-bearing Denote
PRIAD filenames (p/r/i); no KB-wide search, live work import, or hook occurs.
On a headline with children, visit managed roots in that subtree; on a leaf
or in a heading body, only that heading; before the first heading, none.
Only eligible local association tags are considered, excluding automatic
context and workflow tags.  An ambiguous association or destination offers
omission.  With no matching PRIAD, an
optional CREATE-PRIAD function (BASE FULL-TAG) can be offered; it must use
integration's Denote creation flow and return its saved file or nil.  Without
it an unmatched entry remains unresolved.  Duplicate Denote IDs refuse only
entries whose chosen destination or retry ID is ambiguous; unrelated entries
continue.  Existing modified/stale involved buffers are refused rather than
silently saved or closed.

Return a plist with :copied, :already, :omitted, :unresolved and :ineligible
counts.  An error during a save propagates; previously saved source markers
and records permit a later retry, never deleting source data.  No binding is
installed here; command integration supplies candidates and any callback."
  (unless (and (derived-mode-p 'org-mode) (buffer-file-name))
    (user-error "Referir requiere un diario Org que visite un archivo"))
  (let ((source (expand-file-name (buffer-file-name)))
        (files (delete-dups (mapcar #'expand-file-name candidate-files)))
        (counts (list :copied 0 :already 0 :omitted 0 :unresolved 0
                      :ineligible 0)))
    (unless (cl-every (lambda (file)
                        (and (my-dp--identity file) (file-regular-p file)))
                      files)
      (user-error "Se requieren archivos PRIADS activos con keywords"))
    (unless (or (null create-priad) (functionp create-priad))
      (user-error "CREATE-PRIAD debe ser una función"))
    (my-dp--snapshot source)
    (let ((candidates (list files)))
      (org-with-wide-buffer
       (save-excursion
         (dolist (entry (my-dp--entries))
           (let ((result (my-dp--refer-one (car entry) (cdr entry)
                                           candidates create-priad source)))
             (setf (plist-get counts result) (1+ (plist-get counts result))))))))
    counts))

(provide 'diario-priads)
;;; diario-priads.el ends here
