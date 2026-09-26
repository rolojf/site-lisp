;;; diario-rollover.el --- Isolated three-list diario engine -*- lexical-binding: t; -*-

;;; Commentary:
;; Explicit-file engine only.  No keys, hooks, Denote creation, or PRIAD routing.
;; Source markers are saved before destination copies; transferred work is
;; pruned only after its destination is verified.  A retry uses the markers.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'calendar)

(defconst my-diario--lists '("OPORTUNIDADES Y AMENAZAS" "DEEP" "SHALLOW"))
(defconst my-diario--active '("TODO" "NEXT" "WAIT"))
(defconst my-diario--park-days 14)

(cl-defstruct my-diario--entry start end list bucket state key)

(defmacro my-diario--with-text (text &rest body)
  "Run BODY in a private Org buffer containing TEXT."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (let ((org-mode-hook nil)) (org-mode))
     (insert ,text)
     (org-with-wide-buffer ,@body)))

(defun my-diario--read (path)
  "Read PATH without opening it; refuse an unsaved or stale visiting buffer."
  (let ((text (when (file-exists-p path)
                (unless (file-regular-p path)
                  (user-error "Diario path is not a regular file: %s" path))
                (with-temp-buffer
                  (insert-file-contents path)
                  (buffer-string)))))
    (when-let* ((live (find-buffer-visiting path)))
      (with-current-buffer live
        (when (or (buffer-modified-p)
                  (not (equal (save-restriction
                                (widen)
                                (buffer-substring-no-properties (point-min) (point-max)))
                              text)))
          (user-error "Unsaved or conflicting live diario buffer: %s" path))))
    text))

(defun my-diario--save (path expected text)
  "Write TEXT to PATH only if its current content equals EXPECTED; verify it.
An on-disk temporary file avoids a truncated destination on write failure."
  (unless (equal (my-diario--read path) expected)
    (user-error "Diario file changed during operation: %s" path))
  (unless (equal expected text)
    (let ((tmp (make-temp-file (expand-file-name ".diario-roll-"
                                                 (file-name-directory path)))))
      (unwind-protect
          (progn
            (write-region text nil tmp nil 'silent)
            (when expected (set-file-modes tmp (file-modes path)))
            (unless (equal (my-diario--read path) expected)
              (user-error "Diario file changed before replacement: %s" path))
            (rename-file tmp path t)
            (unless (equal (my-diario--read-disk path) text)
              (error "Diario destination verification failed: %s" path))
            ;; Only an unchanged, unmodified visiting buffer may be refreshed.
            (when-let* ((live (find-buffer-visiting path)))
              (with-current-buffer live
                (unless (and (not (buffer-modified-p))
                             (equal (save-restriction
                                      (widen)
                                      (buffer-substring-no-properties (point-min) (point-max)))
                                    expected))
                  (user-error "Live diario buffer changed after save: %s" path))
                (save-restriction
                  (let ((before-revert-hook nil)
                        (after-revert-hook nil)
                        (revert-buffer-function nil))
                    (revert-buffer t t t))))))
        (when (file-exists-p tmp) (delete-file tmp)))))
  text)

(defun my-diario--read-disk (path)
  "Read PATH without inspecting a visiting buffer (for post-write verification)."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun my-diario--date (date)
  "Validate YYYYMMDD DATE and return its Gregorian calendar triple."
  (unless (and (stringp date) (string-match-p "\\`[0-9]\\{8\\}\\'" date))
    (user-error "Expected a YYYYMMDD date: %S" date))
  (let ((triple (list (string-to-number (substring date 4 6))
                      (string-to-number (substring date 6 8))
                      (string-to-number (substring date 0 4)))))
    (unless (calendar-date-is-valid-p triple)
      (user-error "Invalid diario date: %s" date))
    triple))

(defun my-diario--iso (date &optional days)
  "Return DATE plus DAYS as an ISO date."
  (pcase-let ((`(,month ,day ,year)
               (calendar-gregorian-from-absolute
                (+ (calendar-absolute-from-gregorian (my-diario--date date))
                   (or days 0)))))
    (format "%04d-%02d-%02d" year month day)))

(defun my-diario--scan ()
  "Validate the three root lists and return their direct managed entries.
Nested headlines are content of their direct ancestor, not separate entries."
  (let ((roots nil) (buckets nil) (entries nil) (list-name nil)
        (bucket nil) (keys (make-hash-table :test 'equal)))
    (goto-char (point-min))
    (while (re-search-forward org-heading-regexp nil t)
      (goto-char (line-beginning-position))
      (let* ((level (org-outline-level))
             (title (org-get-heading t t t t))
             (state (org-get-todo-state))
             (start (point)))
        (cond
         ((= level 1)
          (when (equal title "TASKS")
            (user-error "Unclassified legacy * TASKS; classify before rollover"))
          (setq list-name (and (member title my-diario--lists) title)
                bucket nil)
          (when list-name
            (when (or state (member list-name roots))
              (user-error "Duplicate or TODO diario list: %s" list-name))
            (push list-name roots)))
         ((and list-name (= level 2)
               (equal list-name (car my-diario--lists)))
          (when (or state (member title buckets) (string-empty-p title))
            (user-error "Ambiguous OT bucket: %s" title))
          (setq bucket title)
          (push title buckets))
         ((and list-name
               (= level (if (equal list-name (car my-diario--lists)) 3 2)))
          (unless (or (not (equal list-name (car my-diario--lists))) bucket)
            (user-error "OT outside either bucket: %s" title))
          (unless (or (member state my-diario--active)
                      (member state (if (equal list-name (car my-diario--lists))
                                        '("DONE" "SDM" "KILL" "COLD")
                                      '("DONE" "SDM" "COLD"))))
            (user-error "Unsupported diario state %S in %s: %s"
                        state list-name title))
          (let ((key (org-entry-get nil "DIARIO_KEY")))
            (when (and key (gethash key keys))
              (user-error "Duplicate diario key within file: %s" key))
            (when key (puthash key t keys))
            (push (make-my-diario--entry
                   :start start
                   :end (save-excursion (org-end-of-subtree t t))
                   :list list-name :bucket bucket :state state :key key)
                  entries))))
        (forward-line 1)))
    (unless (and (= (length roots) 3) (= (length buckets) 2))
      (user-error "Diario needs exactly three lists and two OT buckets"))
    (nreverse entries)))

(defun my-diario--origin-hash (key list-name bucket)
  "Fingerprint KEY's original LIST-NAME and BUCKET, not its editable contents."
  (secure-hash 'sha256
               (prin1-to-string
                (mapcar (lambda (value)
                          (when value (substring-no-properties value)))
                        (list key list-name bucket)))))

(defun my-diario--later-scan ()
  "Return LUEGO entries, refusing old records without origin/date metadata."
  (let ((roots 0) (seen-entry nil) (entries nil)
        (keys (make-hash-table :test 'equal)))
    (goto-char (point-min))
    (while (re-search-forward org-heading-regexp nil t)
      (goto-char (line-beginning-position))
      (let ((level (org-outline-level))
            (title (org-get-heading t t t t)))
        (cond
         ((= level 1)
          (unless (and (equal title "LUEGO") (= roots 0))
            (user-error "Legacy or ambiguous LUEGO root: %s" title))
          (setq roots 1))
         ((= level 2)
          (let* ((key (org-entry-get nil "DIARIO_KEY"))
                 (origin (org-entry-get nil "DIARIO_LIST"))
                 (bucket (org-entry-get nil "DIARIO_BUCKET"))
                 (origin-hash (org-entry-get nil "DIARIO_ORIGIN_HASH"))
                 (raw (org-entry-get nil "SCHEDULED"))
                 (valid (when (and raw
                                   (string-match
                                    "\\`<\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\(?:[ \t][^<>]*\\)?>\\'"
                                    raw))
                          (my-diario--date (concat (match-string 1 raw)
                                                   (match-string 2 raw)
                                                   (match-string 3 raw)))
                          t))
                 (schedule (when valid (org-get-scheduled-time (point)))))
            (unless (and (= roots 1) key
                         (member origin my-diario--lists)
                         (equal origin-hash
                                (my-diario--origin-hash key origin bucket))
                         (if (equal origin (car my-diario--lists))
                             (and bucket (not (string-empty-p bucket)))
                           (not bucket))
                         (equal (org-get-todo-state) "COLD") schedule
                         (not (gethash key keys)))
              (user-error "Unreconciled LUEGO entry: %s" title))
            (puthash key t keys)
            (setq seen-entry t)
            (push (make-my-diario--entry
                   :start (point) :end (save-excursion (org-end-of-subtree t t))
                   :list origin :bucket bucket :state "COLD" :key key)
                  entries)))
         ((and (> level 2) (not seen-entry))
          (user-error "Orphan heading in LUEGO: %s" title)))
        (forward-line 1)))
    (unless (= roots 1) (user-error "Missing * LUEGO root"))
    (nreverse entries)))

(defun my-diario--delete (entries)
  "Delete whole ENTRIES from the current working buffer, last first."
  (dolist (entry (sort (copy-sequence entries)
                       (lambda (a b) (> (my-diario--entry-start a)
                                        (my-diario--entry-start b)))))
    (delete-region (my-diario--entry-start entry) (my-diario--entry-end entry))))

(defun my-diario--key (path entry)
  "Derive an initial stable key from PATH and ENTRY's original position."
  (secure-hash 'sha256
               (format "%s:%s:%s" path (my-diario--entry-start entry)
                       (my-diario--entry-list entry))))

(defun my-diario--fingerprint (subtree)
  "Hash SUBTREE's user content, excluding only the engine's source receipts."
  (my-diario--with-text subtree
    (goto-char (point-min))
    (dolist (property '("DIARIO_ROLL_TO" "DIARIO_ROLL_HASH" "DIARIO_PARK_DATE"
                         "DIARIO_PARKED_TO"))
      (org-entry-delete nil property))
    (secure-hash 'sha256 (string-trim-right (buffer-string)))))

(defun my-diario--mark (source path date &optional target)
  "Mark SOURCE for TARGET's first roll, or just its unparked COLD entries.
PATH supplies new keys; DATE fixes default parking dates across retries.
Receipts are stored before any destination write, so edits after a failed
copy cannot be mistaken for the original source snapshot."
  (my-diario--with-text source
    (dolist (entry (reverse (my-diario--scan)))
      (let* ((state (my-diario--entry-state entry))
             (transfer (and target (member state my-diario--active)
                            (not (equal (my-diario--entry-list entry)
                                        (car my-diario--lists)))))
             (cold (equal state "COLD")))
        (when (or (and target (member state my-diario--active))
                  (and cold (not (save-excursion
                                   (goto-char (my-diario--entry-start entry))
                                   (org-entry-get nil "DIARIO_PARKED_TO")))))
          (goto-char (my-diario--entry-start entry))
          (unless (org-entry-get nil "DIARIO_KEY")
            (org-entry-put nil "DIARIO_KEY" (my-diario--key path entry)))
          (when (or transfer cold)
            (let ((previous (org-entry-get nil "DIARIO_ROLL_TO"))
                  (receipt (org-entry-get nil "DIARIO_ROLL_HASH")))
              (when (and previous target (not (equal previous target)))
                (user-error "Entry pending a different diario: %s" previous))
              (when (and previous (not receipt))
                (user-error "Pending entry has no source receipt; reconcile manually: %s"
                            (org-get-heading t t t t)))
              (unless receipt
                (when (and cold (not (org-get-scheduled-time (point))))
                  (org-entry-put nil "DIARIO_PARK_DATE"
                                 (my-diario--iso date my-diario--park-days)))
                (when target
                  (org-entry-put nil "DIARIO_ROLL_TO" target))
                (org-entry-put nil "DIARIO_ROLL_HASH"
                               (my-diario--fingerprint
                                (buffer-substring-no-properties
                                 (point) (save-excursion (org-end-of-subtree t t)))))))))))
    (buffer-string)))

(defun my-diario--receipt (text entry)
  "Refuse if ENTRY in TEXT no longer matches its saved source receipt."
  (let ((receipt (my-diario--with-text text
                   (goto-char (my-diario--entry-start entry))
                   (org-entry-get nil "DIARIO_ROLL_HASH"))))
    (unless (and receipt
                 (equal receipt (my-diario--fingerprint
                                 (my-diario--subtree text entry))))
      (user-error "Diario source changed since copy/parking: %s"
                  (my-diario--entry-key entry)))))

(defun my-diario--source-payload ()
  "Return current source text without its Denote metadata preamble."
  (goto-char (point-min))
  (unless (re-search-forward org-heading-regexp nil t)
    (user-error "No diario headings"))
  (let ((body (buffer-substring-no-properties (line-beginning-position) (point-max)))
        (preamble (buffer-substring-no-properties (point-min) (line-beginning-position)))
        (case-fold-search t))
    (concat (replace-regexp-in-string
             "^\\(?:#\\+\\(?:PROPERTY:[ \t]+ID\\(?:[ \t].*\\)?\\|ID:[^\n]*\\)\\|:ID:[^\n]*\\)\n"
             ""
             (replace-regexp-in-string
              "^#\\+\\(title\\|date\\|filetags\\|identifier\\|signature\\):[^\n]*\n"
              "" preamble t) t)
            body)))

(defun my-diario--file-ids (text)
  "Return explicit Denote and file-level Org identities in TEXT's preamble."
  (let ((preamble (my-diario--with-text text
                    (goto-char (point-min))
                    (let ((end (if (re-search-forward org-heading-regexp nil t)
                                   (line-beginning-position)
                                 (point-max))))
                      (buffer-substring-no-properties (point-min) end))))
        (case-fold-search t)
        ids)
    (dolist (pattern '("^#\\+identifier:[ \t]*\\([^ \t\n]+\\)"
                       "^#\\+PROPERTY:[ \t]+ID[ \t]+\\([^ \t\n]+\\)"
                       "^#\\+ID:[ \t]*\\([^ \t\n]+\\)"
                       "^:ID:[ \t]*\\([^ \t\n]+\\)"))
      (let ((start 0))
        (while (string-match pattern preamble start)
          (push (match-string 1 preamble) ids)
          (setq start (match-end 0)))))
    ids))

(defun my-diario--new-target (source target)
  "Copy SOURCE's body to fresh TARGET metadata, pruning non-carried entries."
  (let ((payload (my-diario--with-text source (my-diario--source-payload))))
    (my-diario--with-text (concat target (unless (string-suffix-p "\n" target) "\n")
                                  payload)
      (let ((entries (my-diario--scan)))
        (my-diario--delete
         (cl-remove-if
          (lambda (entry) (member (my-diario--entry-state entry) my-diario--active))
          entries))
        (setq entries (my-diario--scan))
        ;; Notes and copied OT snapshots keep their text, not duplicate Org IDs.
        (goto-char (point-max))
        (while (re-search-backward org-heading-regexp nil t)
          (let ((pos (line-beginning-position)))
            (unless (cl-some
                     (lambda (entry)
                       (and (<= (my-diario--entry-start entry) pos)
                            (< pos (my-diario--entry-end entry))
                            (not (equal (my-diario--entry-list entry)
                                        (car my-diario--lists)))
                            (member (my-diario--entry-state entry) my-diario--active)))
                     entries)
              (save-excursion (org-entry-delete nil "ID")))))
        (dolist (entry (reverse (my-diario--scan)))
          (goto-char (my-diario--entry-start entry))
          (dolist (property '("DIARIO_ROLL_TO" "DIARIO_ROLL_HASH"
                               "DIARIO_PARK_DATE" "DIARIO_PARKED_TO"))
            (org-entry-delete nil property)))
        (buffer-string)))))

(defun my-diario--subtree (text entry)
  "Return ENTRY's complete subtree from TEXT."
  (substring text (1- (my-diario--entry-start entry))
             (1- (my-diario--entry-end entry))))

(defun my-diario--parked (subtree entry)
  "Prepare ENTRY's COLD SUBTREE with its fixed return date in LUEGO."
  (my-diario--with-text subtree
    (goto-char (point-min))
    (when (equal (my-diario--entry-list entry) (car my-diario--lists))
      (org-promote-subtree))
    (unless (org-get-scheduled-time (point))
      (let ((chosen (org-entry-get nil "DIARIO_PARK_DATE"))
            (org-log-reschedule nil))
        (unless chosen (user-error "Missing fixed COLD parking date"))
        (org-schedule nil chosen)))
    (org-entry-put nil "DIARIO_LIST" (my-diario--entry-list entry))
    (when-let* ((bucket (my-diario--entry-bucket entry)))
      (org-entry-put nil "DIARIO_BUCKET" bucket))
    (org-entry-put nil "DIARIO_ORIGIN_HASH"
                   (my-diario--origin-hash
                    (org-entry-get nil "DIARIO_KEY")
                    (my-diario--entry-list entry) (my-diario--entry-bucket entry)))
    (org-entry-delete nil "DIARIO_ROLL_TO")
    (dolist (property '("DIARIO_PARKED_TO" "DIARIO_PARK_DATE"
                         "DIARIO_ROLL_HASH"))
      (org-entry-delete nil property))
    (goto-char (point-max))
    (while (re-search-backward org-heading-regexp nil t)
      (save-excursion (org-entry-delete nil "ID")))
    (buffer-string)))

(defun my-diario--returned (subtree entry date)
  "Convert parked SUBTREE to NEXT in ENTRY's original hierarchy and DATE."
  (my-diario--with-text subtree
    (goto-char (point-min))
    (let ((scheduled (org-get-scheduled-time (point))))
      (unless scheduled (user-error "LUEGO return date missing"))
      (let ((org-log-done nil)
            (org-log-reschedule nil)
            (org-after-todo-state-change-hook nil)
            (org-trigger-hook nil)
            (org-todo-state-tags-triggers nil))
        (org-schedule '(4))
        (org-todo "NEXT"))
      (org-entry-put nil "DIARIO_PLANNED_RETURN"
                     (format-time-string "[%Y-%m-%d %a]" scheduled))
      (org-entry-put nil "DIARIO_ACTUAL_RETURN"
                     (format "[%s]" (my-diario--iso date))))
    (dolist (property '("DIARIO_LIST" "DIARIO_BUCKET" "DIARIO_ORIGIN_HASH"
                         "DIARIO_PARKED_TO" "DIARIO_ROLL_TO"))
      (org-entry-delete nil property))
    (when (equal (my-diario--entry-list entry) (car my-diario--lists))
      (goto-char (point-min))
      (org-demote-subtree))
    (buffer-string)))

(defun my-diario--dest-heading (title &optional parent)
  "Find the unique TITLE root or direct child of PARENT by Org heading title."
  (save-excursion
    (let ((limit (if parent
                     (progn (goto-char parent) (org-end-of-subtree t t))
                   (point-max)))
          (level (if parent 2 1))
          found)
      (goto-char (if parent (1+ parent) (point-min)))
      (while (re-search-forward org-heading-regexp limit t)
        (when (and (= (org-outline-level) level)
                   (equal (org-get-heading t t t t) title))
          (when found (user-error "Duplicate diario destination: %s" title))
          (setq found (line-beginning-position))))
      found)))

(defun my-diario--append (text root &optional bucket)
  "Append TEXT at the end of ROOT/BUCKET in the current working buffer."
  (let ((destination (or (my-diario--dest-heading root)
                         (user-error "Missing destination list: %s" root))))
    (when bucket
      (setq destination (or (my-diario--dest-heading bucket destination)
                            (user-error "Missing destination OT bucket: %s" bucket))))
    (goto-char destination))
  (org-end-of-subtree t t)
  (unless (bolp) (insert "\n"))
  (insert text)
  (unless (bolp) (insert "\n")))

(defun my-diario--fresh-p (text)
  "Return non-nil if TEXT contains only new-file Denote metadata/whitespace."
  (let ((case-fold-search t))
    (and (string-match-p "^#\\+title:[ \t]*[^\n \t]+" text)
         (string-match-p "^#\\+identifier:[ \t]*[^\n \t]+" text)
         (string-empty-p
          (string-trim
           (replace-regexp-in-string
            "^:PROPERTIES:\n\\(?:[ \t]*:[^:\n]+:[^\n]*\n\\)*:END:\n"
            ""
            (replace-regexp-in-string
             "^#\\+\\(?:PROPERTY:[ \t]+ID\\(?:[ \t].*\\)?\\|ID:[^\n]*\\|\\(title\\|date\\|filetags\\|identifier\\|signature\\):[^\n]*\\)\n"
             "" text t) t))))))

(defun my-diario--index (entries)
  "Return hash of ENTRIES indexed by the internal key."
  (let ((index (make-hash-table :test 'equal)))
    (dolist (entry entries)
      (when-let* ((key (my-diario--entry-key entry)))
        (puthash key entry index)))
    index))

(defun my-diario--check-paths (paths date)
  "Check DATE and distinct absolute PATHS; the last path may not exist yet."
  (my-diario--date date)
  (unless (and (cl-every (lambda (path)
                           (and (stringp path) (file-name-absolute-p path)))
                         paths)
               (= (length paths) (length (delete-dups (mapcar #'file-truename paths))))
               (cl-every (lambda (path) (not (file-symlink-p path))) paths)
               (cl-loop for (path . others) on paths
                        always (cl-every
                                (lambda (other)
                                  (not (and (file-exists-p path)
                                            (file-exists-p other)
                                            (file-equal-p path other))))
                                others))
               (cl-every #'file-regular-p (butlast paths)))
    (user-error "Need distinct absolute paths and existing regular diario files")))

(defun my-diario--transfers (source-text target-text target)
  "Find pending transfers and verify both copies against SOURCE-TEXT's receipts.
TARGET-TEXT may be the in-memory new diario or a saved resumed one."
  (let ((index (my-diario--index
                (my-diario--with-text target-text (my-diario--scan))))
        (entries (my-diario--with-text source-text (my-diario--scan)))
        transfers)
    (dolist (entry entries)
      (when (and (member (my-diario--entry-state entry) my-diario--active)
                 (not (equal (my-diario--entry-list entry) (car my-diario--lists)))
                 (equal (my-diario--with-text source-text
                          (goto-char (my-diario--entry-start entry))
                          (org-entry-get nil "DIARIO_ROLL_TO")) target))
        (my-diario--receipt source-text entry)
        (let ((copy (gethash (my-diario--entry-key entry) index)))
          (unless (and copy
                       (equal (my-diario--entry-list copy) (my-diario--entry-list entry))
                       (equal (my-diario--entry-bucket copy)
                              (my-diario--entry-bucket entry))
                       (equal (my-diario--with-text source-text
                                (goto-char (my-diario--entry-start entry))
                                (org-entry-get nil "DIARIO_ROLL_HASH"))
                              (my-diario--fingerprint
                               (my-diario--subtree target-text copy))))
            (user-error "Diario target copy changed or missing; keep source: %s"
                        (my-diario--entry-key entry))))
        (push entry transfers)))
    (nreverse transfers)))

(defun my-diario--park-pending (source source-text later-text later &optional target)
  "Save pending COLD entries to LATER, then acknowledge them in SOURCE.
With TARGET, park only COLD entries marked for that roll.  Return a list
(UPDATED-SOURCE UPDATED-LATER NEW-COUNT).  Never remove source snapshots."
  (let* ((entries (my-diario--with-text source-text (my-diario--scan)))
         (index (my-diario--index
                 (when later-text
                   (my-diario--with-text later-text (my-diario--later-scan)))))
         (count 0)
         acknowledge)
    (dolist (entry entries)
      (when (and (equal (my-diario--entry-state entry) "COLD")
                 (my-diario--with-text source-text
                   (goto-char (my-diario--entry-start entry))
                   (and (not (org-entry-get nil "DIARIO_PARKED_TO"))
                        (or (not target)
                            (equal (org-entry-get nil "DIARIO_ROLL_TO") target)))))
        (my-diario--receipt source-text entry)
        (let* ((key (my-diario--entry-key entry))
               (parked (my-diario--parked (my-diario--subtree source-text entry)
                                         entry))
               (copy (gethash key index)))
          (if copy
              (unless (equal (string-trim-right parked)
                             (string-trim-right (my-diario--subtree later-text copy)))
                (user-error "LUEGO copy changed or conflicts with source: %s" key))
            (let ((updated (my-diario--with-text (or later-text "* LUEGO\n")
                             (my-diario--append parked "LUEGO")
                             (buffer-string))))
              (my-diario--save later later-text updated)
              (setq later-text updated
                    index (my-diario--index
                           (my-diario--with-text updated (my-diario--later-scan)))
                    count (1+ count))))
          (push entry acknowledge))))

    (when acknowledge
      (let ((updated (my-diario--with-text source-text
                       (dolist (entry acknowledge)
                         (goto-char (my-diario--entry-start entry))
                         (org-entry-put nil "DIARIO_PARKED_TO" later)
                         (when target (org-entry-delete nil "DIARIO_ROLL_TO")))
                       (buffer-string))))
        (my-diario--save source source-text updated)
        (setq source-text updated)))
    (list source-text later-text count)))

(defun my-diario--return-date (target-text entry)
  "Recover the previously recorded actual date for ENTRY's saved return."
  (let ((actual (my-diario--with-text target-text
                  (goto-char (my-diario--entry-start entry))
                  (org-entry-get nil "DIARIO_ACTUAL_RETURN"))))
    (unless (and actual (string-match "\\`\\[\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\]\\'" actual))
      (user-error "Due item target has no valid return receipt: %s"
                  (my-diario--entry-key entry)))
    (let ((date (concat (match-string 1 actual) (match-string 2 actual)
                        (match-string 3 actual))))
      (my-diario--date date)
      date)))

(defun my-diario--return-due (target later date)
  "Safely return due/overdue LATER entries into existing TARGET; count new copies.
An existing keyed copy is trusted only if its full transformed subtree still
matches LATER, including location, state and return history.  LATER is pruned
only after the destination was saved and verified."
  (let* ((target-before (my-diario--read target))
         (target-text target-before)
         (later-text (my-diario--read later))
         (entries (when later-text
                    (my-diario--with-text later-text (my-diario--later-scan))))
         (index (my-diario--index
                 (my-diario--with-text target-text (my-diario--scan))))
         (count 0)
         due)
    (dolist (entry entries)
      (let ((scheduled (my-diario--with-text later-text
                         (goto-char (my-diario--entry-start entry))
                         (org-get-scheduled-time (point)))))
        (unless (string< date (format-time-string "%Y%m%d" scheduled))
          (let* ((key (my-diario--entry-key entry))
                 (copy (gethash key index))
                 (actual (if copy (my-diario--return-date target-text copy) date))
                 (returned (my-diario--returned
                            (my-diario--subtree later-text entry) entry actual)))
            (if copy
                (unless (and (equal (my-diario--entry-list copy)
                                    (my-diario--entry-list entry))
                             (equal (my-diario--entry-bucket copy)
                                    (my-diario--entry-bucket entry))
                             (equal (string-trim-right returned)
                                    (string-trim-right
                                     (my-diario--subtree target-text copy))))
                  (user-error "Due item target changed; keep LUEGO: %s" key))
              (setq target-text
                    (my-diario--with-text target-text
                      (my-diario--append returned (my-diario--entry-list entry)
                                         (my-diario--entry-bucket entry))
                      (buffer-string))
                    index (my-diario--index
                           (my-diario--with-text target-text (my-diario--scan)))
                    count (1+ count)))
            (push entry due)))))

    (my-diario--save target target-before target-text)
    (when due
      (let ((updated (my-diario--with-text later-text
                       (my-diario--delete due)
                       (buffer-string))))
        (my-diario--save later later-text updated)))
    count))

;;;###autoload
(defun my-diario-park (source later date)
  "Park newly COLD managed entries from absolute SOURCE into absolute LATER.
DATE is YYYYMMDD; missing schedules are fixed at DATE + 14 days on the
source before any copy.  Keep all source COLD subtrees as snapshots.  Repeat
calls neither duplicate parked entries nor reset their dates.  A plist with
:parked gives the number of new LATER copies.  No diario target is needed.
A legacy LUEGO layout, absent receipts, or changed copies require manual
reconciliation; no guessing or destructive recovery is attempted."
  (my-diario--check-paths (list source later) date)
  (let* ((original (my-diario--read source))
         (later-text (my-diario--read later)))
    (my-diario--with-text original (my-diario--scan))
    (when later-text (my-diario--with-text later-text (my-diario--later-scan)))
    (let ((marked (my-diario--mark original source date)))
      (my-diario--save source original marked)
      (list :parked (nth 2 (my-diario--park-pending source marked later-text later))))))

;;;###autoload
(defun my-diario-return (target later date)
  "Return due/overdue COLD entries from absolute LATER to absolute TARGET.
DATE is YYYYMMDD; TARGET must already have all three lists/two OT buckets.
Append each due item to its original list/bucket in LUEGO order as NEXT,
consume its SCHEDULED date into inactive planned/actual return properties,
and retain the entire subtree.  This needs no previous source diario and no
PRIAD action.  Remove from LATER only after verifying a saved target copy;
refuse edited or ambiguous copies.  Return a plist with :returned (new copies)."
  (my-diario--check-paths (list target later) date)
  (list :returned (my-diario--return-due target later date)))

;;;###autoload
(defun my-diario-roll (source target later date)
  "Roll SOURCE to TARGET, park COLD in LATER, and return due items on DATE.
All paths are distinct absolute files; DATE is YYYYMMDD.  TARGET must exist
with fresh Denote metadata (not an empty unprepared file) or an initialized
three-list diario.  A fresh roll copies the whole body, then omits closed and
COLD entries while preserving live OT order/snapshots, notes and live DEEP/
SHALLOW subtrees.  Source COLD snapshots always stay; transferred active
DEEP/SHALLOW entries are deleted only after verifying both source receipt
and saved target content.  An initialized target is never recopied or
clobbered: only pending transfers and due returns resume.  Legacy pending
entries without receipts need manual reconciliation.  Return a plist with
:copied-ot, :moved, :parked, :returned and :mode (new or resume)."
  (my-diario--check-paths (list source target later) date)
  (let* ((source-text (my-diario--read source))
         (target-before (my-diario--read target))
         (target-text target-before)
         (later-text (my-diario--read later))
         (fresh (my-diario--fresh-p target-text))
         (source-entries (my-diario--with-text source-text (my-diario--scan)))
         (summary (list :copied-ot 0 :moved 0 :parked 0 :returned 0
                        :mode (if fresh 'new 'resume))))
    (when later-text (my-diario--with-text later-text (my-diario--later-scan)))
    (unless fresh (my-diario--with-text target-text (my-diario--scan)))
    (when (cl-intersection (my-diario--file-ids source-text)
                           (my-diario--file-ids target-text) :test #'equal)
      (user-error "Source and target share a file-level identity; do not copy"))

    ;; Persist receipts before copying.  The saved target is never initialized
    ;; from an already edited, initialized diario on a same-day retry.
    (when fresh
      (let ((marked (my-diario--mark source-text source date target)))
        (my-diario--save source source-text marked)
        (setq source-text marked
              source-entries (my-diario--with-text marked (my-diario--scan))))
      (setq target-text (my-diario--new-target source-text target-text))
      (setf (plist-get summary :copied-ot)
            (cl-count-if (lambda (entry)
                           (and (equal (my-diario--entry-list entry)
                                       (car my-diario--lists))
                                (member (my-diario--entry-state entry)
                                        my-diario--active)))
                         source-entries)))

    (my-diario--transfers source-text target-text target)
    (pcase-let ((`(,marked ,parked ,count)
                 (my-diario--park-pending source source-text later-text later target)))
      (setq source-text marked later-text parked)
      (setf (plist-get summary :parked) count))

    (my-diario--save target target-before target-text)
    (setf (plist-get summary :returned) (my-diario--return-due target later date))

    ;; Recheck both complete copies after all target writes, immediately before
    ;; removing transferred work from SOURCE.  A key alone is not a receipt.
    (let ((transfers (my-diario--transfers source-text (my-diario--read target)
                                           target)))
      (when transfers
        (let ((updated (my-diario--with-text source-text
                         (my-diario--delete transfers)
                         (buffer-string))))
          (my-diario--save source source-text updated)
          (setf (plist-get summary :moved) (length transfers)))))
    summary))

(provide 'diario-rollover)
;;; diario-rollover.el ends here
