;;; test-diario-import.el --- Private PRIAD import fixtures -*- lexical-binding: t; -*-

;;; Commentary:
;; Load only diario-import, never setup-journaling or live user files.
;; Run later with an isolated Emacs session and this directory on load-path.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'org)
(require 'diario-import)

(defvar denote-directory)
(defvar denote-journal-directory)

(defconst my-di-test--source
  "#+title: Proyecto\n#+identifier: priad-id\n\n* Ideas :padre:\n** TODO Cotización :local:\n:PROPERTIES:\n:ID: source-ot-id\n:CUSTOM: valor\n:END:\nSCHEDULED: <2026-06-10 Wed>\nTexto [[denote:20260511T1358]].\n:LOGBOOK:\n- Nota de contexto.\n:END:\n*** TODO Paso anidado\n:PROPERTIES:\n:ID: source-child-id\n:END:\nMás notas.\n** TODO Diagnóstico :cliente:\n* Tareas :plan:\n** TODO Trabajo profundo :cliente:\n** TODO Llamar :cliente:\n"
  "Four selected TODO roots, a nested TODO and a tagged immediate parent.")

(defconst my-di-test--layout
  "#+title: Hoy\n#+identifier: journal-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n* DEEP\n* SHALLOW\n* Notas\nContexto intacto.\n"
  "A prepared diario without the former TASKS list.")

(defconst my-di-test--ts-format "%Y%m%dT%H%M%S"
  "The user's second-resolution Org ID timestamp format.")

(defmacro my-di-test--files (&rest body)
  "Execute BODY with temporary root PRIAD and two prepared diarios."
  (declare (indent 0) (debug t))
  `(let* ((sandbox (make-temp-file "diario-import-test-" t))
          (denote-directory (expand-file-name "priads" sandbox))
          (denote-journal-directory (expand-file-name "diario" denote-directory))
          (source (expand-file-name
                   "20260601T1200==p--cliente__cliente.org" denote-directory))
          (target (expand-file-name
                   "20260603T0800--2026w23-wed__journal.org"
                   denote-journal-directory))
          (next (expand-file-name
                 "20260604T0800--2026w23-thu__journal.org"
                 denote-journal-directory))
          (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "SDM" "COLD"
                                        "|" "DONE" "KILL")))
          (org-mode-hook nil)
          (org-inhibit-startup t)
          (my-diario-customer-tags nil)
          (org-log-done nil)
          (org-log-into-drawer nil))
     (make-directory denote-journal-directory t)
     (unwind-protect
         (progn
           (with-temp-file source (insert my-di-test--source))
           (dolist (file (list target next))
             (with-temp-file file (insert my-di-test--layout)))
           ;; `denote-directory' can be buffer-local in the owner's session;
           ;; bind the fixture roots in the visiting source buffer as well.
           (let ((fixture-root denote-directory)
                 (fixture-journal denote-journal-directory))
             (with-current-buffer (find-file-noselect source)
               (set (make-local-variable 'denote-directory) fixture-root)
               (set (make-local-variable 'denote-journal-directory)
                    fixture-journal)
               ,@body)))
       ;; Ignore the legacy global buffer-close copier if this suite runs in
       ;; a configured session instead of a standalone test process.
       (dolist (file (list source target next))
         (when-let* ((buf (find-buffer-visiting file)))
           (with-current-buffer buf
             (let ((kill-buffer-query-functions nil)
                   (kill-buffer-hook nil))
               (set-buffer-modified-p nil)
               (kill-buffer buf)))))
       (delete-directory sandbox t))))

(defun my-di-test--disk (file)
  "Read fixture FILE without visiting it."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun my-di-test--count (needle text)
  "Count literal NEEDLE in TEXT."
  (let ((offset 0) (count 0))
    (while (string-match (regexp-quote needle) text offset)
      (setq offset (match-end 0))
      (cl-incf count))
    count))

(defun my-di-test--keys (path)
  "Return the local DIARIO_KEY property values written to fixture PATH."
  (let ((text (my-di-test--disk path)) (start 0) keys)
    (while (string-match "^:DIARIO_KEY:[ \t]+\\([^ \t\n]+\\)" text start)
      (push (match-string 1 text) keys)
      (setq start (match-end 0)))
    (nreverse keys)))

(ert-deftest my-diario-import-test-four-destinations-and-content ()
  (my-di-test--files
    (let ((before (my-di-test--disk source))
          (decisions '("OT Empresa" "OT Contratista" "DEEP" "SHALLOW")))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt choices &rest _args)
                   (let ((answer (pop decisions)))
                     (should (member answer choices))
                     answer))))
        (let ((counts (my-diario-import target)))
          (should (= 4 (plist-get counts :copied)))
          (should (= 1 (plist-get counts :nested)))
          (should (= 0 (plist-get counts :already)))
          (should (null decisions))))
      (let ((text (my-di-test--disk target)))
        (should (string-match-p "\\*\\* Empresa\n\\*\\*\\* TODO Cotización" text))
        (should (string-match-p "\\*\\* Contratista\n\\*\\*\\* TODO Diagnóstico" text))
        (should (string-match-p "\\* DEEP\n\\*\\* TODO Trabajo profundo" text))
        (should (string-match-p "\\* SHALLOW\n\\*\\* TODO Llamar" text))
        (should (= 1 (my-di-test--count "TODO Paso anidado" text)))
        (should (string-match-p "\\*\\*\\*\\* TODO Paso anidado" text))
        (dolist (original '("#+identifier: priad-id" "source-ot-id"
                            "source-child-id"))
          (should-not (string-search original text)))
        (should (string-search "#+identifier: journal-id" text))
        (dolist (survives '(":CUSTOM: valor" "SCHEDULED: <2026-06-10"
                            "Texto [[denote:20260511T1358]]."
                            ":LOGBOOK:\n- Nota de contexto.\n:END:"
                            "Contexto intacto." "Más notas."))
          (should (string-search survives text)))
        (should (= 4 (my-di-test--count ":DIARIO_KEY:" text)))
        (my-di--with-org text
         (lambda ()
           (goto-char (point-min))
           (re-search-forward "^\\*\\*\\* TODO Cotización")
           (should (equal (org-get-tags nil t) '("local" "padre")))))
        (should-not (string-search "DIARIO_EXPORTS" text))
        (should-not (string-search "DIARIO_IMPORT_DEST" text))
        (should-not (string-search "* TASKS" text)))
      (should (get-file-buffer source))
      (should (string-search "source-ot-id" (my-di-test--disk source)))
      (should (string-search "source-child-id" (my-di-test--disk source)))
      (should (string-search "Texto [[denote:20260511T1358]]." before))
      (save-excursion
        (goto-char (point-min))
        (re-search-forward "^\\*\\* TODO Cotización")
        (should (equal (org-get-tags nil t) '("local" "padre")))
        (should (equal (org-entry-get nil "DIARIO_IMPORT_DEST") "OT Empresa"))
        (should-not (org-entry-get nil "DIARIO_EXPORT_PENDING"))
        (should (equal (my-di--receipts) (list (file-truename target))))))))

(ert-deftest my-diario-import-test-exported-ancestors-not-new-roots ()
  (my-di-test--files
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP")))
      (should (= 4 (plist-get (my-diario-import target) :copied))))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* TODO Cotización")
    (org-todo "DONE")
    (save-buffer)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (error "Nested historical task was offered"))))
      (let ((counts (my-diario-import next 'repeat)))
        (should (= 3 (plist-get counts :copied)))
        (should (= 1 (plist-get counts :nested)))))
    (should (= 0 (my-di-test--count "TODO Paso anidado" (my-di-test--disk next))))
    (should (= 4 (length (my-di-test--keys source))))))

(ert-deftest my-diario-import-test-extracted-child-can-import ()
  (my-di-test--files
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP")))
      (my-diario-import target))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* TODO Cotización")
    (org-todo "DONE")
    (re-search-forward "^\\*\\*\\* TODO Paso anidado")
    (beginning-of-line)
    (let* ((start (point))
           (child (buffer-substring-no-properties
                   start (save-excursion (org-end-of-subtree t t)))))
      (delete-region start (+ start (length child)))
      (goto-char (point-max))
      (insert (replace-regexp-in-string "^\\*\\*\\*" "*" child)))
    (save-buffer)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt &rest _)
                 (should (string-prefix-p "Importar a:" prompt))
                 "SHALLOW")))
      (let ((counts (my-diario-import next)))
        (should (= 1 (plist-get counts :copied)))
        (should (= 3 (plist-get counts :exported)))
        (should (= 0 (plist-get counts :nested)))))
    (should (= 1 (my-di-test--count "** TODO Paso anidado" (my-di-test--disk next))))))

(ert-deftest my-diario-import-test-pending-and-referred-ancestors ()
  (my-di-test--files
    (dolist (property '("DIARIO_EXPORT_PENDING" "DIARIO_REF_KEY"))
      (erase-buffer)
      (insert (concat "* DONE Registro\n:PROPERTIES:\n:" property ": valor\n:END:\n"
                      "** TODO Paso anidado\nContexto conservado.\n"))
      (save-buffer)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Nested record was offered"))))
        (let ((counts (my-diario-import target 'repeat)))
          (should (= 0 (plist-get counts :copied)))
          (should (= 1 (plist-get counts :nested)))))
      (should-not (my-di-test--keys target))
      (should (string-search "** TODO Paso anidado" (my-di-test--disk source))))))

(ert-deftest my-diario-import-test-local-tag-context-and-retag ()
  (my-di-test--files
    (erase-buffer)
    (insert "* Ideas :plan:clienteB:\n** TODO Cotización :clienteA_techo:\nNotas.\n")
    (save-buffer)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt &rest _)
                 (should (string-prefix-p "Importar a:" prompt))
                 "OT Empresa")))
      (should (= 1 (plist-get (my-diario-import target) :copied))))
    (dolist (text (list (my-di-test--disk source) (my-di-test--disk target)))
      (should (string-search ":clienteA_techo:plan:clienteB:" text))
      (should (string-search ":DIARIO_CONTEXT_TAGS: :plan:clienteB:" text)))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* TODO Cotización")
    (org-set-tags '("clienteC_003" "plan" "clienteB"))
    (should (equal (my-diario-association-tags) '("clienteC_003")))
    (save-buffer)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (error "Receipted entry asked again"))))
      (should (= 1 (plist-get (my-diario-import next) :exported)))
      (should (= 1 (plist-get (my-diario-import target 'repeat) :already))))))

(ert-deftest my-diario-import-test-multiple-local-tags-ask ()
  (my-di-test--files
    (erase-buffer)
    (insert "* Ideas :clienteB:\n** TODO Cotización :clienteA_techo:clienteC_003:\n")
    (save-buffer)
    (let (choices)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt options &rest _)
                   (if (string-prefix-p "Elegir asociación" prompt)
                       (progn (setq choices options) "clienteA_techo")
                     "OT Empresa"))))
        (should (= 1 (plist-get (my-diario-import target) :copied))))
      (should (member "clienteA_techo" choices))
      (should (member "clienteC_003" choices)))
    (dolist (text (list (my-di-test--disk source) (my-di-test--disk target)))
      (should (string-search ":clienteA_techo:clienteC_003:clienteB:" text))
      (should (string-search ":DIARIO_CONTEXT_TAGS: :clienteC_003:clienteB:" text)))))

(ert-deftest my-diario-import-test-inherited-choice-and-context ()
  (my-di-test--files
    (erase-buffer)
    (insert "* Ideas :clienteA_techo:clienteB:plan:\n** TODO Cotización\nNota.\n")
    (save-buffer)
    (let (offered)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt choices &rest _)
                   (if (string-prefix-p "Elegir asociación" prompt)
                       (progn (setq offered choices) "clienteA_techo")
                     (should (string-prefix-p "Importar a:" prompt))
                     "OT Empresa"))))
        (should (= 1 (plist-get (my-diario-import target) :copied))))
      (should (member "clienteA_techo" offered))
      (should (member "clienteB" offered))
      (should (member "(ninguna)" offered)))
    (dolist (text (list (my-di-test--disk source) (my-di-test--disk target)))
      (should (string-search ":clienteA_techo:clienteB:plan:" text))
      (should (string-search ":DIARIO_CONTEXT_TAGS: :clienteB:plan:" text)))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* TODO Cotización")
    (should (equal (my-diario-association-tags) '("clienteA_techo")))))

(ert-deftest my-diario-import-test-inherited-none-keeps-tags ()
  (my-di-test--files
    (erase-buffer)
    (insert "* Ideas :plan:\n** TODO Cotización\n")
    (save-buffer)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt &rest _)
                 (if (string-prefix-p "Elegir asociación" prompt)
                     "(ninguna)"
                   "DEEP"))))
      (should (= 1 (plist-get (my-diario-import target) :copied))))
    (dolist (text (list (my-di-test--disk source) (my-di-test--disk target)))
      (should (string-match-p "Cotización[ \t]+:plan:" text))
      (should (string-search ":DIARIO_CONTEXT_TAGS: :plan:" text)))))

(ert-deftest my-diario-import-test-same-second-ts-ids ()
  (my-di-test--files
    (let ((org-id-method 'ts)
          (org-id-ts-format my-di-test--ts-format)
          (original-format (symbol-function 'format-time-string)))
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (format &rest args)
                   (if (equal format org-id-ts-format)
                       "20260603T080000"
                     (apply original-format format args))))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) "DEEP")))
        (should (= 4 (plist-get (my-diario-import target) :copied))))
      (let ((source-keys (my-di-test--keys source))
            (target-keys (my-di-test--keys target))
            (target-before (my-di-test--disk target)))
        (should (eq org-id-method 'ts))
        (should (= 4 (length source-keys)))
        (should (= 4 (length (delete-dups (copy-sequence source-keys)))))
        (should (cl-every #'org-uuidgen-p source-keys))
        (should (equal (sort (copy-sequence source-keys) #'string<)
                       (sort (copy-sequence target-keys) #'string<)))
        (should (= 4 (plist-get (my-diario-import target) :already)))
        (should (equal source-keys (my-di-test--keys source)))
        (should (equal target-before (my-di-test--disk target)))
        (should (eq org-id-method 'ts))))))

(ert-deftest my-diario-import-test-batch-key-collision-retried ()
  (my-di-test--files
    (let ((org-id-method 'ts)
          (org-id-ts-format my-di-test--ts-format)
          (issued '("collision" "collision" "second" "third" "fourth")))
      (cl-letf (((symbol-function 'org-id-new)
                 (lambda (prefix)
                   (should (eq org-id-method 'uuid))
                   (should (eq prefix 'none))
                   (or (pop issued) (error "Unexpected additional ID"))))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) "SHALLOW")))
        (should (= 4 (plist-get (my-diario-import target) :copied))))
      (should (null issued))
      (should (equal (my-di-test--keys source)
                     '("collision" "second" "third" "fourth")))
      (should (= 4 (length (my-di-test--keys target)))))))

(ert-deftest my-diario-import-test-repeat-policy-and-day-receipts ()
  (my-di-test--files
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _args) "SHALLOW")))
      (should (= 4 (plist-get (my-diario-import target) :copied))))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (error "Cached classification was not reused"))))
      (let ((before (my-di-test--disk next)))
        (should (= 4 (plist-get (my-diario-import next) :exported)))
        (should (equal before (my-di-test--disk next))))
      (should (= 4 (plist-get (my-diario-import target 'repeat) :already)))
      ;; Repeat to another date is explicit; retries never duplicate.
      (should (= 4 (plist-get (my-diario-import next 'repeat) :copied)))
      (should (= 4 (plist-get (my-diario-import next 'repeat) :already))))
    (should (= 1 (my-di-test--count "** TODO Cotización" (my-di-test--disk next))))
    (save-excursion
      (goto-char (point-min))
      (re-search-forward "^\\*\\* TODO Cotización")
      (should (equal (my-di--receipts)
                     (list (file-truename target) (file-truename next)))))))

(ert-deftest my-diario-import-test-narrowed-source-covers-all-roots ()
  (my-di-test--files
    (goto-char (point-min))
    (re-search-forward "^\\* Ideas")
    (org-narrow-to-subtree)
    (unwind-protect
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "SHALLOW")))
          (should (= 4 (plist-get (my-diario-import target) :copied)))
          (should (buffer-narrowed-p)))
      (widen))))

(ert-deftest my-diario-import-test-identical-titles-not-deduplicated ()
  (my-di-test--files
    (goto-char (point-max))
    (insert "** TODO Llamar\nOtra persona y otro contexto.\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
              ((symbol-function 'completing-read)
               (lambda (prompt &rest _)
                 (if (string-prefix-p "Elegir asociación" prompt)
                     "(ninguna)" "DEEP"))))
      (should (= 5 (plist-get (my-diario-import target) :copied))))
    (let ((text (my-di-test--disk target)))
      (should (= 2 (my-di-test--count "** TODO Llamar" text)))
      (should (string-search "Otra persona y otro contexto." text))
      (should (= 5 (my-di-test--count ":DIARIO_KEY:" text))))))

(ert-deftest my-diario-import-test-no-stale-overwrite ()
  (my-di-test--files
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP")))
      (my-diario-import target))
    (let ((text (my-di-test--disk target)))
      (with-temp-file target
        (insert (replace-regexp-in-string
                 (regexp-quote "** TODO Cotización")
                 "** DONE Cotización editada"
                 (concat text "\nNota actual del diario.\n") t t))))
    (let ((before (my-di-test--disk target)))
      (should (= 4 (plist-get (my-diario-import target 'repeat) :already)))
      (should (equal before (my-di-test--disk target)))
      (should (string-search "DONE Cotización editada" before)))))

(ert-deftest my-diario-import-test-failure-after-target-save ()
  (my-di-test--files
    (let ((receipt (symbol-function 'my-di--receipt)))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP"))
                ((symbol-function 'my-di--receipt)
                 (lambda (_path) (error "Injected receipt failure"))))
        (should-error (my-diario-import target)))
      (should (= 4 (my-di-test--count ":DIARIO_KEY:" (my-di-test--disk target))))
      (should (string-search ":DIARIO_EXPORT_PENDING:"
                             (my-di-test--disk source)))
      (should-not (string-search ":DIARIO_EXPORTS:"
                                 (my-di-test--disk source)))
      (cl-letf (((symbol-function 'my-di--receipt) receipt)
                ((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Unexpected new classification"))))
        (should (= 4 (plist-get (my-diario-import target) :already))))
      (should (= 4 (my-di-test--count ":DIARIO_KEY:" (my-di-test--disk target))))
      (should-not (string-search ":DIARIO_EXPORT_PENDING:"
                                 (my-di-test--disk source))))))

(ert-deftest my-diario-import-test-repeat-save-failure-acknowledged ()
  (my-di-test--files
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP")))
      (my-diario-import target))
    (cl-letf (((symbol-function 'my-di--receipt)
               (lambda (_path) (error "Injected repeat receipt failure")))
              ((symbol-function 'completing-read)
               (lambda (&rest _) (error "Cached classification was not reused"))))
      (should-error (my-diario-import next 'repeat)))
    (should (= 4 (my-di-test--count ":DIARIO_KEY:" (my-di-test--disk next))))
    ;; Default retry may acknowledge a present key, never transfer it anew.
    (should (= 4 (plist-get (my-diario-import next) :already)))
    (should (= 4 (my-di-test--count ":DIARIO_KEY:" (my-di-test--disk next))))
    (should-not (string-search ":DIARIO_EXPORT_PENDING:"
                               (my-di-test--disk source)))))

(ert-deftest my-diario-import-test-repeat-before-write-pending ()
  (my-di-test--files
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP")))
      (should (= 4 (plist-get (my-diario-import target) :copied))))
    (should-not (my-diario-import-needed-p))
    (let ((before (my-di-test--disk next)))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Cached destination was not reused")))
                ((symbol-function 'my-di--save-target)
                 (lambda (&rest _) (user-error "Injected repeat target failure"))))
        (should-error (my-diario-import next 'repeat) :type 'user-error))
      (should (equal before (my-di-test--disk next)))
      (should (= 4 (my-di-test--count ":DIARIO_EXPORT_PENDING:"
                                      (my-di-test--disk source))))
      (should (my-diario-import-needed-p))
      (should-error (my-diario-import target) :type 'user-error)
      (should (equal before (my-di-test--disk next)))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Retry asked for classification"))))
        (should (= 4 (plist-get (my-diario-import next) :copied))))
      (should (= 4 (my-di-test--count ":DIARIO_KEY:" (my-di-test--disk next))))
      (should-not (string-search ":DIARIO_EXPORT_PENDING:"
                                 (my-di-test--disk source)))
      (should-not (my-diario-import-needed-p))
      (should (= 4 (plist-get (my-diario-import target) :already)))
      (should (= 4 (plist-get (my-diario-import next) :already)))
      (save-excursion
        (goto-char (point-min))
        (re-search-forward "^\\*\\* TODO Cotización")
        (should (equal (my-di--receipts)
                       (list (file-truename target) (file-truename next))))))))

(ert-deftest my-diario-import-test-write-failure-retry ()
  (my-di-test--files
    (let ((before (my-di-test--disk target))
          (save (symbol-function 'my-di--save-target)))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "SHALLOW"))
                ((symbol-function 'my-di--save-target)
                 (lambda (&rest _) (error "Injected target failure"))))
        (should-error (my-diario-import target)))
      (should (equal before (my-di-test--disk target)))
      (should (string-search ":DIARIO_EXPORT_PENDING:" (my-di-test--disk source)))
      (cl-letf (((symbol-function 'my-di--save-target) save)
                ((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Cached classification was not reused"))))
        (should (= 4 (plist-get (my-diario-import target) :copied)))))))

(ert-deftest my-diario-import-test-modified-target-and-unsaved-source ()
  (my-di-test--files
    (let ((before (my-di-test--disk source)))
      (goto-char (point-max))
      (insert "Nueva idea sin guardar.\n")
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (should-error (my-diario-import target) :type 'user-error))
      (should (equal before (my-di-test--disk source)))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'completing-read) (lambda (&rest _) "DEEP")))
        (with-current-buffer (find-file-noselect target)
          (goto-char (point-max))
          (insert "Conflicto sin guardar."))
        (should-error (my-diario-import target) :type 'user-error))
      (should (string-search "Nueva idea sin guardar." (my-di-test--disk source)))
      (should-not (string-search "DIARIO_KEY" (my-di-test--disk source)))
      (should-not (string-search "Conflicto" (my-di-test--disk target))))))

(ert-deftest my-diario-import-test-wrong-files-and-layout ()
  (my-di-test--files
    (let ((other (expand-file-name "otro.org" denote-journal-directory))
          (before (my-di-test--disk source)))
      (with-temp-file other (insert my-di-test--layout))
      (unwind-protect
          (progn
            (should-error (my-diario-import other) :type 'user-error)
            (should-error (my-diario-import source) :type 'user-error)
            (with-temp-file target (insert "#+title: Sin listas\n* TASKS\n"))
            (should-error (my-diario-import target) :type 'user-error)
            (should (equal before (my-di-test--disk source))))
        (delete-file other)))))

(ert-deftest my-diario-import-test-cached-choice-and-conflicting-buffer ()
  (my-di-test--files
    (goto-char (point-min))
    (re-search-forward "^\\*\\* TODO Cotización")
    (org-entry-put nil "DIARIO_IMPORT_DEST" "ruta antigua")
    (let ((choices 0))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'completing-read)
                 (lambda (&rest _)
                   (cl-incf choices)
                   "OT Contratista")))
        (my-diario-import target))
      (should (= choices 4)))
    (should (string-search "*** TODO Cotización" (my-di-test--disk target)))
    ;; An unmodified visitor that no longer matches disk is also a conflict.
    (with-current-buffer (find-file-noselect next)
      (with-temp-file next (insert my-di-test--layout "Fuera del buffer.\n")))
    (let ((source-before (my-di-test--disk source)))
      (should-error (my-diario-import next 'repeat) :type 'user-error)
      (should (equal source-before (my-di-test--disk source))))))

(ert-deftest my-diario-import-test-different-pending-target-refused ()
  (my-di-test--files
    (let ((save (symbol-function 'my-di--save-target)))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP"))
                ((symbol-function 'my-di--save-target)
                 (lambda (&rest _) (error "Injected target failure"))))
        (should-error (my-diario-import target)))
      (should-error (my-diario-import next 'repeat) :type 'user-error)
      (should-not (string-search "DIARIO_KEY" (my-di-test--disk next)))
      (cl-letf (((symbol-function 'my-di--save-target) save)
                ((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Cached classification was not reused"))))
        (should (= 4 (plist-get (my-diario-import target) :copied)))))))

(ert-deftest my-diario-import-test-non-priad-source-rejected ()
  (my-di-test--files
    (let* ((other (expand-file-name "outside.org" sandbox))
           (original (my-di-test--disk target)))
      (unwind-protect
          (progn
            (with-temp-file other (insert "* TODO No es PRIAD\n"))
            (with-current-buffer (find-file-noselect other)
              (set (make-local-variable 'denote-directory)
                   (file-name-directory source))
              (set (make-local-variable 'denote-journal-directory)
                   (file-name-directory target))
              (should-error (my-diario-import target) :type 'user-error))
            (should (equal original (my-di-test--disk target))))
        (when-let* ((buf (find-buffer-visiting other)))
          (with-current-buffer buf
            (let ((kill-buffer-query-functions nil)
                  (kill-buffer-hook nil))
              (kill-buffer buf))))))))

(ert-deftest my-diario-import-test-needed-is-read-only-and-root-scoped ()
  (my-di-test--files
    (let ((before (my-di-test--disk source)))
      (should (my-diario-import-needed-p))
      (should (equal before (my-di-test--disk source)))
      (should-not (buffer-modified-p)))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "DEEP")))
      (my-diario-import target))
    (should-not (my-diario-import-needed-p))
    (should (my-diario-import-needed-p 'repeat))
    (goto-char (point-min))
    (re-search-forward "^\\*\\* TODO Cotización")
    (org-todo "DONE")
    (save-buffer)
    (erase-buffer)
    (insert "* DONE Referida\n:PROPERTIES:\n:DIARIO_REF_KEY: ejemplo\n:END:\n** TODO Histórico\n")
    (save-buffer)
    (should-not (my-diario-import-needed-p 'repeat))
    (should-not (buffer-modified-p))
    (should-not (string-search "DIARIO_KEY" (my-di-test--disk source)))))

(provide 'test-diario-import)
;;; test-diario-import.el ends here
