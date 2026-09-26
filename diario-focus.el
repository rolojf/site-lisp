;;; diario-focus.el --- Tag association and diario OT focus -*- lexical-binding: t; -*-

;;; Commentary:
;;; A diario-local Org sparse-tree toggle.  Integration enables the minor mode
;;; only in diario buffers; an optional base-tag whitelist narrows candidates.
;;; DIARIO_CONTEXT_TAGS is automatic bookkeeping, not a user-maintained tag.

;;; Code:

(require 'cl-lib)
(require 'org)

(defgroup my-diario-focus nil
  "Focus an OT and its associated diario work."
  :group 'org)

(defcustom my-diario-customer-tags nil
  "Customer/project BASE tags eligible for OT association.
Nil accepts valid local OT tags except workflow markers and tags listed in
a heading's DIARIO_CONTEXT_TAGS, without requiring a customer list.  A non-nil list explicitly restricts candidates
to these customer/project bases, each without an underscore (e.g.,
`clienteX').  An OT can use BASE or BASE_suffix as its association tag."
  :type '(repeat string)
  :group 'my-diario-focus)

(defcustom my-diario-ignored-tags '("x" "c" "n" "t" "u" "g" "journal")
  "Tags that must not be treated as associations, even if configured.
The one-letter tags are the existing referir bookkeeping markers.
Add any other workflow markers used in this diario to this list."
  :type '(repeat string)
  :group 'my-diario-focus)

(defconst my-diario--ot-section "OPORTUNIDADES Y AMENAZAS"
  "Top-level diario heading that contains the job buckets and OTs.")

(defvar-local my-diario--focus-tag nil
  "Full association tag currently focused in this buffer, or nil.")

(defun my-diario-tag-parts (tag)
  "Split association TAG into (BASE . SUFFIX) at its first underscore.
SUFFIX is nil for an unsuffixed tag (one OT per customer/project).
Keep any further underscores in SUFFIX, e.g., `cliente_techo_sur' becomes
(`cliente' . `techo_sur').  Signal `user-error' for an empty TAG, BASE,
or SUFFIX; such tags cannot identify an OT unambiguously."
  (unless (and (stringp tag) (not (equal tag "")))
    (user-error "Etiqueta de asociación vacía"))

  (let* ((separator (string-match "_" tag))
         (base (if separator (substring tag 0 separator) tag))
         (suffix (when separator (substring tag (1+ separator)))))
    (when (or (equal base "") (equal suffix ""))
      (user-error "Etiqueta de asociación incompleta: %s" tag))
    (cons base suffix)))

(defun my-diario-customer-tag-p (base tag)
  "Return non-nil if TAG belongs to customer/project BASE exactly.
BASE must be a nonempty, underscore-free customer tag; TAG may be BASE
or BASE_suffix.  This does not match textual prefixes (`clienteX' does
not match `clienteXY_003').  Invalid BASE or TAG signals `user-error'.
Use this matcher for full-customer reviews; exact-OT focus matches the
entire TAG instead."
  (unless (and (stringp base)
               (not (equal base ""))
               (not (string-match-p "_" base)))
    (user-error "La base del cliente debe estar completa y no tener '_': %S"
                base))
  (equal base (car (my-diario-tag-parts tag))))

(defun my-diario-association-tags (&optional tags)
  "Return eligible association TAGS at point, defaulting to local Org tags.
DIARIO_CONTEXT_TAGS stores colon-delimited tags (e.g. `:plan:clienteB:')
that were preserved as context, not chosen as customer/OT associations.
Only these excluded tags and workflow markers are ignored by default; an
optional customer-base whitelist may further restrict candidates.  A new
local customer tag needs no update to this property or to a whitelist."
  (let ((context (split-string
                  (or (org-entry-get nil "DIARIO_CONTEXT_TAGS" nil) "") ":" t)))
    (cl-remove-if-not
     (lambda (tag)
       (and (not (member tag my-diario-ignored-tags))
            (not (member tag context))
            (let ((base (car (my-diario-tag-parts tag))))
              (or (null my-diario-customer-tags)
                  (member base my-diario-customer-tags)))))
     (or tags (org-get-tags nil t)))))

(defun my-diario--ot-p ()
  "Return non-nil when point is at a level-three OT under the OT section."
  (and (= (org-outline-level) 3)
       (save-excursion
         (and (org-up-heading-safe)
              (org-up-heading-safe)
              (equal (org-get-heading t t t t) my-diario--ot-section)))))

(defun my-diario--ot-tag ()
  "Return the full eligible association tag on the OT at point, or nil.
Without a whitelist, ignore only workflow and automatic context tags.
Ask for an explicit choice when more than one eligible tag is local."
  (save-excursion
    (if (or (org-before-first-heading-p)
            (progn (org-back-to-heading t) (not (my-diario--ot-p))))
        (progn
          (message "El cursor no está en una OT de OPORTUNIDADES Y AMENAZAS")
          nil)
      (let ((tags (my-diario-association-tags)))
        (cond
         ((null tags)
          (message "La OT no tiene etiqueta de asociación elegible")
          nil)
         ((null (cdr tags)) (car tags))
         (t (completing-read "Elegir asociación de la OT: " tags nil t)))))))

(defun my-diario-focus ()
  "Toggle an exact-OT sparse tree in the current diario Org buffer.
On first invocation, read the full local association tag of the OT at
point and reveal its exact tag matches with Org's list/heading context.
On second invocation, from anywhere in the buffer, show the full Org
buffer again; the previous fold arrangement is not saved.  Return the
selected full tag when focusing and nil on restore or no association.
Without a relevant tag, report why and leave visibility unchanged."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "El enfoque del diario requiere un buffer Org"))

  (if my-diario--focus-tag
      (progn
        (org-remove-occur-highlights)
        (org-fold-show-all)
        (setq my-diario--focus-tag nil)
        (message "Vista completa del diario restaurada")
        nil)
    (let ((tag (my-diario--ot-tag)))
      (when tag
        ;; Use Org's native sparse-tree scanner, but do not select a heading
        ;; whose matching local tag was preserved only as context.
        (let* ((org-use-tag-inheritance nil)
               (org-group-tags nil)
               (matcher (cdr (org-make-tags-matcher (concat "+" tag) t))))
          (org-agenda-prepare-buffers (list (current-buffer)))
          (org-scan-tags 'sparse-tree
                         (lambda (todo tags level)
                           (and (funcall matcher todo tags level)
                                (member tag (my-diario-association-tags))))
                         nil))
        (setq my-diario--focus-tag tag)
        (message "Enfoque de OT: %s" tag)
        tag))))

(defvar my-diario-focus-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c n f") #'my-diario-focus)
    map)
  "Keymap used only in buffers with `my-diario-focus-mode' enabled.")

(define-minor-mode my-diario-focus-mode
  "Bind `C-c n f' locally for an OT sparse-tree toggle in diario buffers.
Enable only from diario integration, not as a global Org hook.  Disabling
while focused restores the full Org buffer."
  :lighter " DFocus"
  :keymap my-diario-focus-mode-map
  (when (and (not my-diario-focus-mode) my-diario--focus-tag)
    (org-remove-occur-highlights)
    (org-fold-show-all)
    (setq my-diario--focus-tag nil)))

(provide 'diario-focus)
;;; diario-focus.el ends here
