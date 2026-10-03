;;; diario-match.el --- Conservative diario subtree matching -*- lexical-binding: t; -*-

;;; Commentary:
;; In-memory Org helpers.  Callers select the destination and own all saves
;; and recovery receipts; this module neither classifies nor opens task files.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'diario-focus)

(defconst my-dm--warning
  "# DIARIO: copias con contenido distinto; revisar ambas."
  "Fixed root comment for two copies of a task with different content.")

(defconst my-dm--transport
  '("DIARIO_KEY" "DIARIO_ROLL_TO" "DIARIO_ROLL_HASH"
    "DIARIO_PARK_DATE" "DIARIO_PARKED_TO" "DIARIO_LIST"
    "DIARIO_BUCKET" "DIARIO_ORIGIN_HASH" "DIARIO_EXPORTS"
    "DIARIO_EXPORT_PENDING" "DIARIO_IMPORT_DEST"
    "DIARIO_EXPORT_HASH" "DIARIO_RETURN_DATE")
  "Transport-only properties ignored during content comparison.")

(defun my-dm--id ()
  "Return current heading's text and sorted eligible local association tags.
States and priority cookies do not identify a task; inherited and context
association tags do not participate.  No eligible tag matches only no tag."
  (cons (org-get-heading t t t nil)
        (sort (copy-sequence (my-diario-association-tags)) #'string<)))

(defun my-dm-text (subtree)
  "Return comparison text for Org SUBTREE without transport differences.
Only heading levels relative to the root, whitelisted transport properties,
the fixed conflict comment, and one structural final newline are normalized.
Empty property drawers removed by Org property deletion disappear as well."
  (with-temp-buffer
    (let ((org-mode-hook nil) (org-inhibit-startup t)) (org-mode))
    (insert subtree)
    (goto-char (point-max))
    (while (re-search-backward org-heading-regexp nil t)
      (dolist (property my-dm--transport)
        (org-entry-delete nil property)))

    (goto-char (point-min))
    (let ((case-fold-search nil))
      (while (re-search-forward
              (concat "^" (regexp-quote my-dm--warning) "$") nil t)
        (replace-match "" t t)
        (when (eq (char-after) ?\n) (delete-char 1))))

    (goto-char (point-min))
    (when (re-search-forward "^\\(\\*+\\) +" nil t)
      (let ((root-level (length (match-string 1))))
        (goto-char (point-min))
        (while (re-search-forward "^\\(\\*+\\) +" nil t)
          (replace-match
           (make-string (1+ (- (length (match-string 1)) root-level)) ?*)
           t t nil 1))))
    ;; Org insertion supplies one separator to a subtree lacking its final LF.
    ;; Preserve any additional blank lines and trailing body whitespace.
    (when (eq (char-before (point-max)) ?\n)
      (delete-region (1- (point-max)) (point-max)))
    (buffer-string)))

(defun my-dm--warn (start &optional markers)
  "Add the fixed warning to root heading START, after its metadata, once.
Keep MARKERS anchored at headings when the warning precedes an empty body."
  (save-excursion
    (goto-char start)
    (let ((body (save-excursion (org-end-of-meta-data) (point)))
          (limit (save-excursion
                   (let ((end (org-end-of-subtree t t)))
                     (goto-char start)
                     (forward-line 1)
                     (if (re-search-forward org-heading-regexp end t)
                         (line-beginning-position)
                       end)))))
      (goto-char body)
      (unless (let ((case-fold-search nil))
                (re-search-forward
                 (concat "^" (regexp-quote my-dm--warning) "$") limit t))
        (goto-char body)
        (let ((moved (cl-remove-if-not
                      (lambda (marker) (= (marker-position marker) body))
                      markers)))
          (unless (bolp) (insert "\n"))
          (insert my-dm--warning "\n")
          (dolist (marker moved) (set-marker marker (point))))))))

(defun my-dm-place (subtree starts end)
  "Place SUBTREE in the current private Org buffer within STARTS and END.
STARTS are ordered markers for scoped direct-entry siblings; END marks the
container end.  Reuse any exact full-content match before considering a
conflict.  Otherwise insert after the first same-identity sibling's whole
subtree (and flag both roots), or append at END if no identity matches.
Return (:result exact|inserted|conflict :start MARKER)."
  (let ((incoming-id (with-temp-buffer
                       (let ((org-mode-hook nil) (org-inhibit-startup t))
                         (org-mode))
                       (insert subtree)
                       (goto-char (point-min))
                       (my-dm--id)))
        incoming-text first exact)
    ;; Inspect every scoped sibling: a later exact copy wins over an earlier
    ;; same-title conflict, without disturbing their manual order.
    (dolist (start starts)
      (save-excursion
        (goto-char start)
        (when (equal incoming-id (my-dm--id))
          ;; Distinct titles/tags need no expensive full-subtree normalization.
          (unless incoming-text (setq incoming-text (my-dm-text subtree)))
          (unless first (setq first start))
          (when (and (not exact)
                     (equal incoming-text
                            (my-dm-text
                             (buffer-substring-no-properties
                              (point) (org-end-of-subtree t t)))))
            (setq exact start)))))
    (if exact
        (list :result 'exact :start exact)
      (let* ((inserted (if first
                           (with-temp-buffer
                             (let ((org-mode-hook nil) (org-inhibit-startup t))
                               (org-mode))
                             (insert subtree)
                             (my-dm--warn (point-min))
                             (buffer-string))
                         subtree))
             (result (if first 'conflict 'inserted))
             moved pos placed)
        (when first (my-dm--warn first (cons end starts)))
        (goto-char (if first
                       (save-excursion
                         (goto-char first)
                         (org-end-of-subtree t t))
                     end))
        (unless (bolp) (insert "\n"))
        (setq pos (point)
              moved (cl-remove-if-not (lambda (marker)
                                        (= (marker-position marker) pos))
                                      (cons end starts))
              placed (copy-marker pos))
        (insert inserted)
        (unless (bolp) (insert "\n"))
        ;; Keep the caller's next-sibling and container markers on their
        ;; original headings when insertion happened at their position.
        (dolist (marker moved) (set-marker marker (point)))
        (list :result result :start placed)))))

(defun my-dm-clean (text)
  "Return settled diario TEXT without DIARIO_KEY, preserving other records.
Refuse pending roll/export/return or unacknowledged parking anywhere in the journal
before removing any keys.  An acknowledged parked snapshot retains its
DIARIO_PARKED_TO but loses the consumed roll hash and default date."
  (with-temp-buffer
    (let ((org-mode-hook nil) (org-inhibit-startup t)) (org-mode))
    (insert text)
    (goto-char (point-min))
    (while (re-search-forward org-heading-regexp nil t)
      (let ((parked (org-entry-get nil "DIARIO_PARKED_TO" nil)))
        (when (or (org-entry-get nil "DIARIO_ROLL_TO" nil)
                  (org-entry-get nil "DIARIO_EXPORT_PENDING" nil)
                  (org-entry-get nil "DIARIO_EXPORT_HASH" nil)
                  (org-entry-get nil "DIARIO_RETURN_DATE" nil)
                  (and (not parked)
                       (or (org-entry-get nil "DIARIO_ROLL_HASH" nil)
                           (org-entry-get nil "DIARIO_PARK_DATE" nil))))
          (user-error "Recibo pendiente en el diario: %s"
                      (org-get-heading t t t t)))))

    (goto-char (point-max))
    (while (re-search-backward org-heading-regexp nil t)
      (when (org-entry-get nil "DIARIO_PARKED_TO" nil)
        (org-entry-delete nil "DIARIO_ROLL_HASH")
        (org-entry-delete nil "DIARIO_PARK_DATE"))
      (org-entry-delete nil "DIARIO_KEY"))
    (buffer-string)))

(provide 'diario-match)
;;; diario-match.el ends here
