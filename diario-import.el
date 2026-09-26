;;; diario-import.el --- Explicit PRIAD to three-list diario import -*- lexical-binding: t; -*-

;;; Commentary:
;; No hooks or key bindings.  DIARIO_KEY identifies the source entry in
;; diarios and in rollover; source receipts record each verified export.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'subr-x)
(require 'diario-focus)

(defvar denote-directory)
(defvar denote-journal-directory)

(defconst my-di--choices '("OT Empresa" "OT Contratista" "DEEP" "SHALLOW")
  "User-chosen destinations for imported TODO subtrees.")
(defconst my-di--ot "OPORTUNIDADES Y AMENAZAS")
(defconst my-di--no-tag "(ninguna)"
  "Explicit choice to keep all inherited tags as context, not an OT.")
(defconst my-di--journal-name
  "\\`[0-9]\\{8\\}T[0-9]\\{4\\}\\([0-9]\\{2\\}\\)?--.+__\\([[:alnum:]_]*_\\)?journal\\(_[[:alnum:]_]+\\)?\\.org\\'"
  "Denote journal filename pattern accepted as a diario target.")

(defun my-di--path (path directory)
  "Return canonical PATH if it is a regular file directly in DIRECTORY."
  (unless (and (stringp path) (file-name-absolute-p path)
               (file-regular-p path) (stringp directory)
               (file-directory-p directory))
    (user-error "Se requiere un archivo regular y un directorio configurado: %S" path))
  (let ((file (file-truename path))
        (root (file-name-as-directory (file-truename directory))))
    (unless (equal (file-name-directory file) root)
      (user-error "Archivo fuera del directorio esperado: %s" path))
    file))

(defun my-di--files (target)
  "Validate current PRIAD and TARGET and return their canonical paths."
  (unless (and (derived-mode-p 'org-mode) buffer-file-name)
    (user-error "La fuente debe ser un buffer Org de un PRIAD"))
  (let* ((source (my-di--path buffer-file-name denote-directory))
         (journal (my-di--path target denote-journal-directory)))
    (unless (and (equal (file-name-extension source) "org")
                 (string-match-p my-di--journal-name (file-name-nondirectory journal))
                 (not (equal source journal)))
      (user-error "Se requiere un PRIAD .org y un diario Denote distintos"))
    (cons source journal)))

(defun my-di--disk (path)
  "Return decoded disk contents of PATH without opening a visiting buffer."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun my-di--source-saved (path)
  "Explicitly confirm/save unsaved source PATH, then verify disk and buffer."
  (save-restriction
    (widen)
    (unless (verify-visited-file-modtime (current-buffer))
      (user-error "El PRIAD cambió en disco: %s" path))
    (when (buffer-modified-p)
      (unless (y-or-n-p "El PRIAD no está guardado. ¿Guardarlo antes de importar? ")
        (user-error "Importación cancelada"))
      (save-buffer))
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (unless (and (not (buffer-modified-p))
                   (equal (my-di--disk path) text))
        (user-error "No se pudo verificar el PRIAD guardado: %s" path))
      text)))

(defun my-di--save-source (path expected)
  "Save current source after verifying EXPECTED on disk; return saved text."
  (unless (and (equal expected (my-di--disk path))
               (verify-visited-file-modtime (current-buffer)))
    (user-error "El PRIAD cambió antes de guardar: %s" path))
  (when (buffer-modified-p) (save-buffer))
  (let ((text (buffer-substring-no-properties (point-min) (point-max))))
    (unless (and (not (buffer-modified-p)) (equal text (my-di--disk path)))
      (user-error "No se pudo verificar el PRIAD guardado: %s" path))
    text))

(defun my-di--target-text (path)
  "Read PATH, refusing modified or conflicting pre-existing visiting buffers."
  (let ((text (my-di--disk path)))
    (when-let* ((live (find-buffer-visiting path)))
      (with-current-buffer live
        (save-restriction
          (widen)
          (unless (and (not (buffer-modified-p))
                       (equal text (buffer-substring-no-properties
                                    (point-min) (point-max))))
            (user-error "Buffer diario modificado o desactualizado: %s" path)))))
    text))

(defun my-di--save-target (path expected text)
  "Write TEXT to PATH if still EXPECTED, and verify before any receipt.
Use a same-directory temporary file so a failed write cannot truncate PATH."
  (unless (equal (my-di--target-text path) expected)
    (user-error "El diario cambió antes de guardar: %s" path))
  (unless (equal text expected)
    (let ((tmp (make-temp-file (expand-file-name ".diario-import-"
                                                 (file-name-directory path)))))
      (unwind-protect
          (progn
            (let ((coding-system-for-write
                   (with-temp-buffer
                     (insert-file-contents path)
                     buffer-file-coding-system)))
              (write-region text nil tmp nil 'silent))
            (set-file-modes tmp (file-modes path))
            (unless (equal (my-di--target-text path) expected)
              (user-error "El diario cambió durante la importación: %s" path))
            (rename-file tmp path t)
            (unless (equal (my-di--disk path) text)
              (error "No se verificó el diario guardado: %s" path))
            ;; Refresh only a visitor proven unchanged before the replacement.
            (when-let* ((live (find-buffer-visiting path)))
              (with-current-buffer live
                (save-restriction
                  (widen)
                  (unless (and (not (buffer-modified-p))
                               (equal (buffer-substring-no-properties
                                       (point-min) (point-max)) expected))
                    (user-error "El buffer diario cambió durante el guardado: %s" path))
                  (let ((before-revert-hook nil)
                        (after-revert-hook nil)
                        (revert-buffer-function nil))
                    (revert-buffer t t t))))))
        (when (file-exists-p tmp) (delete-file tmp)))))
  (unless (equal (my-di--target-text path) text)
    (user-error "No se verificó el diario guardado: %s" path))
  text)

(defun my-di--with-org (text function)
  "Call FUNCTION inside a private, wide Org buffer containing TEXT."
  (with-temp-buffer
    (let ((org-mode-hook nil) (org-inhibit-startup t)) (org-mode))
    (insert text)
    (org-with-wide-buffer (funcall function))))

(defun my-di--heading (title &optional parent)
  "Find unique TITLE root or direct child of PARENT in current Org buffer."
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
          (if found
              (user-error "Encabezado diario duplicado: %s" title)
            (setq found (line-beginning-position)))))
      found)))

(defun my-di--container (choice)
  "Return the exact prepared diario parent position for CHOICE."
  (let ((parent (if (string-prefix-p "OT " choice)
                    (let ((root (my-di--heading my-di--ot)))
                      (when root
                        (my-di--heading (substring choice 3) root)))
                  (my-di--heading choice))))
    (unless parent (user-error "Falta el destino diario: %s" choice))
    parent))

(defun my-di--target-keys ()
  "Validate the diario lists and return DIARIO_KEY to direct-entry index.
A key in a nested or outside-list heading is not an importable direct entry."
  (let* ((ot (my-di--heading my-di--ot))
         (deep (my-di--heading "DEEP"))
         (shallow (my-di--heading "SHALLOW"))
         (empresa (when ot (my-di--heading "Empresa" ot)))
         (contratista (when ot (my-di--heading "Contratista" ot)))
         (index (make-hash-table :test 'equal))
         list-name bucket)
    (unless (and ot deep shallow empresa contratista)
      (user-error "Diario sin las tres listas y las dos colas OT"))
    (goto-char (point-min))
    (while (re-search-forward org-heading-regexp nil t)
      (goto-char (line-beginning-position))
      (let* ((level (org-outline-level))
             (title (org-get-heading t t t t))
             (key (org-entry-get nil "DIARIO_KEY"))
             (choice nil))
        (cond
         ((= level 1)
          (setq list-name (and (member title (list my-di--ot "DEEP" "SHALLOW")) title)
                bucket nil)
          (when (and list-name (org-get-todo-state))
            (user-error "La lista diario no debe ser una tarea: %s" title)))
         ((and (= level 2) (equal list-name my-di--ot))
          (unless (and (member title '("Empresa" "Contratista"))
                       (not (org-get-todo-state)))
            (user-error "Cola OT ambigua: %s" title))
          (setq bucket title))
         ((and (equal list-name my-di--ot) (= level 3) bucket)
          (setq choice (concat "OT " bucket)))
         ((and (member list-name '("DEEP" "SHALLOW")) (= level 2))
          (setq choice list-name)))
        (when key
          (when (string-empty-p key)
            (user-error "DIARIO_KEY vacía en el diario"))
          (when (gethash key index)
            (user-error "DIARIO_KEY repetida en el diario: %s" key))
          (puthash key (or choice 'nested) index)))
      (forward-line 1))
    index))

(defun my-di--receipts ()
  "Return decoded paths in DIARIO_EXPORTS at point, or signal invalid data."
  (let ((raw (org-entry-get nil "DIARIO_EXPORTS")))
    (when raw
      (condition-case nil
          (mapcar (lambda (token)
                    (let ((path (decode-coding-string
                                 (base64-decode-string token) 'utf-8)))
                      (unless (and (not (string-empty-p token))
                                   (equal (base64-encode-string
                                           (encode-coding-string path 'utf-8) t)
                                          token))
                        (error "Invalid receipt"))
                      path))
                  (split-string raw "," nil))
        (error (user-error "Recibos DIARIO_EXPORTS inválidos"))))))

(defun my-di--receipt (path)
  "Append verified PATH to DIARIO_EXPORTS at point, without repetitions."
  (let ((paths (my-di--receipts)))
    (unless (member path paths)
      (org-entry-put nil "DIARIO_EXPORTS"
                     (mapconcat (lambda (item)
                                  (base64-encode-string
                                   (encode-coding-string item 'utf-8) t))
                                (append paths (list path)) ",")))))

(defun my-di--roots ()
  "Return (MARKERS . NESTED) for literal TODO roots in current source.
A TODO under another TODO, exported/pending root, or referred record is
historical subtree content even after the ancestor changes TODO state."
  (let (markers (nested 0))
    (org-map-entries
     (lambda ()
       (if (save-excursion
             (catch 'ancestor
               (while (org-up-heading-safe)
                 (when (or (equal (org-get-todo-state) "TODO")
                           (org-entry-get nil "DIARIO_EXPORTS")
                           (org-entry-get nil "DIARIO_EXPORT_PENDING")
                           (org-entry-get nil "DIARIO_REF_KEY"))
                   (throw 'ancestor t)))))
           (cl-incf nested)
         (push (copy-marker (point)) markers)))
     "/TODO" 'file)
    (cons (nreverse markers) nested)))

(defun my-di--choice ()
  "Return valid cached classification at point, or ask for an explicit one."
  (let ((cached (org-entry-get nil "DIARIO_IMPORT_DEST")))
    (if (member cached my-di--choices)
        cached
      (completing-read "Importar a: " my-di--choices nil t))))

(defun my-di--parent-tags ()
  "Return inherited Org tags at point, nearest parent first.
Read ancestors directly so propagation does not depend on the user's
Org tag-inheritance setting."
  (save-excursion
    (let (tags)
      (while (org-up-heading-safe)
        (setq tags (append tags (org-get-tags nil t))))
      (delete-dups tags))))

(defun my-di--select-tag (tags)
  "Ask which of TAGS is the association, or keep them all as context."
  (let ((answer (completing-read "Elegir asociación (o ninguna): "
                                 (append tags (list my-di--no-tag)) nil t)))
    (unless (equal answer my-di--no-tag)
      (unless (member answer tags)
        (user-error "Asociación no válida: %s" answer))
      answer)))

(defun my-di--association (local inherited)
  "Choose an association from LOCAL first, otherwise ask about INHERITED.
A unique explicit local association needs no prompt; inherited tags never
confirm an association without an explicit choice, even if only one exists."
  (let ((local (my-diario-association-tags local))
        (inherited (when inherited
                     (my-diario-association-tags inherited))))
    (cond ((cdr local) (my-di--select-tag local))
          (local (car local))
          (inherited (my-di--select-tag inherited)))))

(defun my-di--context (tags association)
  "Record preserved TAGS other than ASSOCIATION as automatic context."
  (let ((context (remove association (copy-sequence tags))))
    (if context
        (org-entry-put nil "DIARIO_CONTEXT_TAGS"
                       (concat ":" (mapconcat #'identity context ":") ":"))
      (org-entry-delete nil "DIARIO_CONTEXT_TAGS"))))

(defun my-di--copy (choice)
  "Return the full subtree at point adjusted to the diario level for CHOICE.
Keep all user content; copied Org IDs and source export metadata are removed."
  (let ((text (buffer-substring-no-properties
               (point) (save-excursion (org-end-of-subtree t t))))
        (level (if (string-prefix-p "OT " choice) 3 2)))
    (my-di--with-org
     text
     (lambda ()
       (let ((org-odd-levels-only nil)
             (org-adapt-indentation nil))
         (goto-char (point-min))
         (while (< (org-outline-level) level)
           (org-demote-subtree)
           (goto-char (point-min)))
         (while (> (org-outline-level) level)
           (org-promote-subtree)
           (goto-char (point-min))))
       (goto-char (point-max))
       (while (re-search-backward org-heading-regexp nil t)
         (goto-char (line-beginning-position))
         (dolist (property '("ID" "DIARIO_EXPORTS" "DIARIO_EXPORT_PENDING"
                              "DIARIO_IMPORT_DEST"))
           (org-entry-delete nil property)))
       (buffer-string)))))

(defun my-di--append (choice text)
  "Append subtree TEXT under CHOICE in the current working diario buffer."
  (goto-char (my-di--container choice))
  (org-end-of-subtree t t)
  (unless (bolp) (insert "\n"))
  (insert text)
  (unless (bolp) (insert "\n")))

;;;###autoload
(defun my-diario-import-needed-p (&optional policy)
  "Return non-nil if the current PRIAD has a TODO root to import.
POLICY is `new-only' (default) or `repeat'.  Pending transfers require
resolution even with older receipts.  Inspect roots without opening a diario,
prompting, or changing the source."
  (unless (memq policy '(nil new-only repeat))
    (user-error "Política inválida: %S" policy))
  (unless (and (derived-mode-p 'org-mode) buffer-file-name)
    (user-error "La fuente debe ser un buffer Org de un PRIAD"))
  (my-di--path buffer-file-name denote-directory)
  (org-with-wide-buffer
   (save-excursion
     (pcase-let ((`(,markers . ,_nested) (my-di--roots)))
       (unwind-protect
           (cl-some (lambda (marker)
                      (goto-char marker)
                      (or (org-entry-get nil "DIARIO_EXPORT_PENDING")
                          (eq policy 'repeat)
                          (null (my-di--receipts))))
                    markers)
         (dolist (marker markers) (set-marker marker nil)))))))

;;;###autoload
(defun my-diario-import (target &optional policy)
  "Copy TODO roots from the current PRIAD into existing diario TARGET.
POLICY is `new-only' (default) or `repeat'.  A repeat can offer entries
previously exported to a different day; it never replaces a diario entry
already bearing the same DIARIO_KEY.  Return a plist with :copied, :already,
:exported, and :nested counts.  Leave the source open and unchanged except
for parent tag preservation, automatic context exclusions, and internal
identity/export metadata."
  (interactive (list (read-file-name "Diario destino: " denote-journal-directory
                                     nil t)
                     (if current-prefix-arg 'repeat 'new-only)))
  (unless (memq policy '(nil new-only repeat))
    (user-error "Política inválida: %S" policy))
  (pcase-let* ((`(,source . ,journal) (my-di--files target))
               (source-text (my-di--source-saved source))
               (target-text (my-di--target-text journal))
               (target-before target-text)
               (index (my-di--with-org target-text #'my-di--target-keys))
               (roots (org-with-wide-buffer (my-di--roots)))
               (markers (car roots))
               (summary (list :copied 0 :already 0 :exported 0
                              :nested (cdr roots)))
               (representations nil)
               (copies nil)
               (source-keys (make-hash-table :test 'equal)))
    (unwind-protect
        (org-with-wide-buffer
         ;; Check outstanding exports before preparing any target transfer.
         (dolist (marker markers)
           (goto-char marker)
           (let ((key (org-entry-get nil "DIARIO_KEY"))
                 (pending (org-entry-get nil "DIARIO_EXPORT_PENDING")))
             (when (and pending (not (equal pending journal)))
               (user-error "Exportación pendiente a otro diario: %s" pending))
             (when (and key (string-empty-p key))
               (user-error "DIARIO_KEY vacía en PRIAD"))
             (when (and key (gethash key source-keys))
               (user-error "DIARIO_KEY repetida en PRIAD: %s" key))
             (when key (puthash key t source-keys))))
         (dolist (marker markers)
           (goto-char marker)
           (let* ((key (org-entry-get nil "DIARIO_KEY"))
                  (receipts (my-di--receipts))
                  (pending (org-entry-get nil "DIARIO_EXPORT_PENDING"))
                  (existing (and key (gethash key index))))
             (when (and receipts (not key))
               (user-error "Recibo sin DIARIO_KEY en el PRIAD"))
             (when (eq existing 'nested)
               (user-error "DIARIO_KEY solo está en una nota anidada: %s" key))
             (cond
              (existing
               (push marker representations)
               (cl-incf (plist-get summary :already)))
              ((and receipts (not pending) (not (eq policy 'repeat)))
               (cl-incf (plist-get summary :exported)))
              (t
               (let* ((local-tags (org-get-tags nil t))
                      (parent-tags (my-di--parent-tags))
                      (inherited (cl-remove-if (lambda (tag)
                                                 (member tag local-tags))
                                               parent-tags))
                      (association (my-di--association local-tags inherited))
                      (choice (my-di--choice))
                      (preserved (delete-dups (append local-tags parent-tags))))
                 (unless (member choice my-di--choices)
                   (user-error "Destino no válido: %s" choice))
                 (when parent-tags (org-set-tags preserved))
                 (my-di--context preserved association)
                 (unless key
                   ;; User Org IDs may use second-resolution timestamps; import
                   ;; identity instead uses UUIDs without changing that setting.
                   (let ((org-id-method 'uuid))
                     (setq key (org-id-new 'none))
                     (while (or (gethash key source-keys) (gethash key index))
                       (setq key (org-id-new 'none))))
                   (puthash key t source-keys)
                   (org-entry-put nil "DIARIO_KEY" key))
                 (org-entry-put nil "DIARIO_IMPORT_DEST" choice)
                 (unless (equal pending journal)
                   (org-entry-put nil "DIARIO_EXPORT_PENDING" journal))
                 (push (cons marker choice) copies)
                 (push marker representations))))))
         ;; Persist the identity and pending destination before any target write.
         (setq source-text (my-di--save-source source source-text))
         (setq copies (nreverse copies))
         (when copies
           (let ((payloads (mapcar (lambda (item)
                                     (goto-char (car item))
                                     (cons (my-di--copy (cdr item)) (cdr item)))
                                   copies)))
             (setq target-text
                   (my-di--with-org target-text
                    (lambda ()
                      (dolist (item payloads)
                        (my-di--append (cdr item) (car item)))
                      (my-di--target-keys)
                      (buffer-string))))))
         (my-di--save-target journal target-before target-text)
         ;; Only now does a source receipt acknowledge an actual saved entry.
         (dolist (marker representations)
           (goto-char marker)
           (my-di--receipt journal)
           (org-entry-delete nil "DIARIO_EXPORT_PENDING"))
         (my-di--save-source source source-text)
         (setf (plist-get summary :copied) (length copies))
         summary)
      (dolist (marker markers) (set-marker marker nil)))))

(provide 'diario-import)
;;; diario-import.el ends here
