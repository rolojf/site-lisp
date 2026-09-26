;;; diario-migrate.el --- Manual, buffer-local diario migration -*- lexical-binding: t; -*-

;;; Commentary:
;; Prepare the three-list layout and move only entries the user classifies.
;; This module does not open files, save buffers, or enable itself.

;;; Code:

(require 'org)

(defconst my-dmig--ot "OPORTUNIDADES Y AMENAZAS"
  "Heading for the opportunity/threat queues.")
(defconst my-dmig--legacy "TASKS"
  "Heading for entries still awaiting classification.")
(defconst my-dmig--jobs '("Empresa" "Contratista")
  "OT bucket headings.")
(defconst my-dmig--lists '("DEEP" "SHALLOW")
  "Task-only list headings.")
(defconst my-dmig--choices '("OT Empresa" "OT Contratista" "DEEP" "SHALLOW")
  "Explicit destinations offered during classification.")

(defun my-dmig--heading (title &optional parent)
  "Find the unique heading TITLE directly below PARENT, or at level one.
Return its buffer position, nil if absent; reject duplicate matches."
  (save-excursion
    (let ((limit (if parent
                     (progn
                       (goto-char parent)
                       (org-end-of-subtree t t))
                   (point-max)))
          (level (if parent 2 1))
          found)
      (goto-char (if parent (1+ parent) (point-min)))
      (while (re-search-forward org-heading-regexp limit t)
        (when (and (= (org-outline-level) level)
                   (equal (org-get-heading t t t t) title))
          (if found
              (user-error "Encabezado diario duplicado: %s" title)
            (setq found (line-beginning-position)))))
      found)))

(defun my-dmig--append (text &optional parent)
  "Append TEXT at the end of PARENT's subtree, or the whole buffer."
  (goto-char (if parent
                 (progn (goto-char parent) (org-end-of-subtree t t))
               (point-max)))
  (unless (or (bobp) (eq (char-before) ?\n))
    (insert "\n"))
  (insert text))

;;;###autoload
(defun my-diario-prepare ()
  "Add missing OT (Empresa/Contratista), DEEP and SHALLOW headings here.
Keep TASKS, other headings and all existing text unchanged.  Safe to repeat;
changes remain in this buffer's undo history and are not saved."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Preparar requiere un buffer Org"))
  (org-with-wide-buffer
   ;; Validate existing containers before any edit, to avoid choosing a
   ;; duplicate heading as the parent of new entries.
   (let* ((ot (my-dmig--heading my-dmig--ot))
          (lists (mapcar #'my-dmig--heading my-dmig--lists))
          (jobs (when ot
                  (mapcar (lambda (job) (my-dmig--heading job ot))
                          my-dmig--jobs))))
     (unless (and ot (not (memq nil lists)) (not (memq nil jobs)))
       (undo-boundary)
       (atomic-change-group
         (unless ot
           (my-dmig--append (concat "* " my-dmig--ot "\n")))
         (let ((ot (my-dmig--heading my-dmig--ot)))
           (dolist (bucket my-dmig--jobs)
             (unless (my-dmig--heading bucket ot)
               (my-dmig--append (format "** %s\n" bucket) ot))))
         (dolist (title my-dmig--lists)
           (unless (my-dmig--heading title)
             (my-dmig--append (format "* %s\n" title)))))
       (undo-boundary)))))

(defun my-dmig--destination (choice)
  "Return the heading position for CHOICE, requiring an existing container."
  (unless (member choice my-dmig--choices)
    (user-error "Destino no válido: %s" choice))
  (let ((pos (if (string-prefix-p "OT " choice)
                 (let ((ot (my-dmig--heading my-dmig--ot)))
                   (when ot (my-dmig--heading (substring choice (length "OT ")) ot)))
               (my-dmig--heading choice))))
    (unless pos
      (user-error "Falta el destino %s; ejecute my-diario-prepare" choice))
    pos))

(defun my-dmig--source ()
  "Return the direct list parent at point, or reject this heading."
  (unless (org-at-heading-p)
    (user-error "Seleccione encabezados de entradas completos"))
  (let* ((level (org-outline-level))
         (parent (save-excursion
                   (when (org-up-heading-safe) (point))))
         (ot (my-dmig--heading my-dmig--ot)))
    (unless (and parent
                 (or (and (= level 2)
                          (member parent (delq nil
                                               (mapcar #'my-dmig--heading
                                                       (cons my-dmig--legacy my-dmig--lists)))))
                     (and (= level 3) ot
                          (member parent
                                  (delq nil (mapcar (lambda (bucket)
                                                      (my-dmig--heading bucket ot))
                                                    my-dmig--jobs))))))
      (user-error "Solo se pueden mover entradas directas de TASKS/OT/DEEP/SHALLOW"))
    parent))

(defun my-dmig--selection (beg end)
  "Check that BEG..END consists of complete adjacent list entries.
Return (PARENT LEVEL), where LEVEL is the entries' current level."
  (unless (and (< beg end) (<= (point-min) beg) (<= end (point-max)))
    (user-error "Región vacía o fuera del buffer"))
  (let ((cursor beg) parent level)
    (while (< cursor end)
      (goto-char cursor)
      (let ((next-parent (my-dmig--source))
            (next-level (org-outline-level))
            (next-end (save-excursion (org-end-of-subtree t t))))
        (when (or (> next-end end)
                  (and parent (not (= parent next-parent))))
          (user-error "Seleccione solo subárboles completos de la misma lista"))
        (setq parent next-parent
              level next-level
              cursor next-end)))
    (unless (= cursor end)
      (user-error "La región debe terminar después de un subárbol completo"))
    (list parent level)))

(defun my-dmig--shift-levels (text delta)
  "Shift the Org headline levels in TEXT by DELTA."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (while (re-search-forward "^\\(\\*+\\) " nil t)
      (replace-match (make-string (+ delta (length (match-string 1))) ?*)
                     t t nil 1))
    (buffer-string)))

;;;###autoload
(defun my-diario-classify (destination &optional beg end)
  "Move whole entry subtrees to DESTINATION in the current Org buffer.
DESTINATION is exactly one of: OT Empresa, OT Contratista, DEEP, SHALLOW.
With an active region (or explicit BEG and END), select complete adjacent
sibling subtrees, starting at the first headline and ending at the next
headline or end of buffer.  Otherwise move the entry at point.  Nested
notes follow their parent.  TASKS items remain there until explicitly moved.
Reject KILL entries in DEEP/SHALLOW: correct their state manually first.
The move is one undoable buffer edit; this function never saves the file."
  (interactive
   (let ((bounds (when (use-region-p)
                   (cons (region-beginning) (region-end)))))
     (list (completing-read "Clasificar en: " my-dmig--choices nil t)
           (car bounds) (cdr bounds))))
  (unless (derived-mode-p 'org-mode)
    (user-error "Clasificar requiere un buffer Org"))
  (unless (eq (null beg) (null end))
    (user-error "Indique ambos extremos de la región"))
  (org-with-wide-buffer
   (let* ((region (or beg (and (use-region-p) (region-beginning))))
          (finish (or end (and (use-region-p) (region-end))))
          (start (if region
                     region
                   (save-excursion
                     (org-back-to-heading t)
                     (point))))
          (stop (if finish
                    finish
                  (save-excursion (goto-char start) (org-end-of-subtree t t))))
          (source (save-excursion (my-dmig--selection start stop)))
          (target (my-dmig--destination destination)))
     ;; A same-list classification does not reorder entries or eat its own
     ;; destination subtree.  Validate the choice and source first.
     (unless (= (car source) target)
       (when (and (member destination my-dmig--lists)
                  (save-excursion
                    (goto-char start)
                    (catch 'kill
                      (while (< (point) stop)
                        (when (equal (org-get-todo-state) "KILL")
                          (throw 'kill t))
                        (goto-char (org-end-of-subtree t t))))))
         (user-error "KILL es solo para OT; corrija el estado antes de mover"))
       (let* ((content (buffer-substring-no-properties start stop))
              (shift (1+ (- (save-excursion (goto-char target) (org-outline-level))
                            (cadr source))))
              (moved (my-dmig--shift-levels content shift))
              (at (copy-marker (save-excursion
                                 (goto-char target)
                                 (org-end-of-subtree t t)))))
         (unwind-protect
             (progn
               (undo-boundary)
               (atomic-change-group
                 (delete-region start stop)
                 (goto-char at)
                 (unless (or (bobp) (eq (char-before) ?\n))
                   (insert "\n"))
                 (insert moved)
                 (unless (or (eobp) (eq (char-before) ?\n))
                   (insert "\n")))
               (undo-boundary))
           (set-marker at nil)))))))

;;;###autoload
(defun my-diario-legacy-count ()
  "Count unclassified direct child entries under legacy * TASKS here.
All states (including DONE, PROG and KILL) count; nested notes are part of
their parent entry.  Return zero if TASKS is absent.  This is read-only,
including on narrowed/folded buffers, for rollover integration."
  (unless (derived-mode-p 'org-mode)
    (user-error "Contar requiere un buffer Org"))
  (save-excursion
    (org-with-wide-buffer
     (let ((tasks (my-dmig--heading my-dmig--legacy))
           (count 0))
       (when tasks
         (goto-char (1+ tasks))
         (let ((limit (save-excursion
                        (goto-char tasks)
                        (org-end-of-subtree t t))))
           (while (re-search-forward org-heading-regexp limit t)
             (when (= (org-outline-level) 2)
               (setq count (1+ count))))))
       count))))

(provide 'diario-migrate)
;;; diario-migrate.el ends here
