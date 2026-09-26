;;; test-diario-priads.el --- Isolated PRIAD referring fixtures -*- lexical-binding: t; -*-

;;; Commentary:
;; Run later in an isolated ERT session; only temporary .org files are used.
;; No production journaling setup, keybindings, or live KB files are loaded.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'diario-priads)

(defmacro my-dpt--with-files (text &rest body)
  "Run BODY on TEXT in private SOURCE, PRIAD and DIR fixtures."
  (declare (indent 1) (debug t))
  `(let* ((dir (make-temp-file "diario-priads-test-" t))
          (source (expand-file-name "20260601--journal__journal.org" dir))
          (priad (expand-file-name "20260601T1200==p--cliente__cliente.org" dir))
          (other (expand-file-name "20260601T1201==r--otro__cliente.org" dir))
          (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "SDM" "COLD"
                                        "PROG" "|" "DONE" "KILL")))
          (org-log-done nil)
          (org-log-into-drawer nil)
          (org-mode-hook nil)
          (find-file-hook nil)
          (kill-buffer-query-functions nil)
          (my-diario-customer-tags nil))
     (unwind-protect
         (progn
           (with-temp-file source (insert ,text))
           (with-temp-file priad (insert "#+title: Cliente\n\n* Bitácora\nProsa anterior.\n"))
           (with-current-buffer (find-file-noselect source)
             (org-mode)
             (goto-char (point-min))
             ,@body))
       (dolist (file (directory-files dir t "\\.org\\'"))
         (when-let* ((live (find-buffer-visiting file)))
           (with-current-buffer live (set-buffer-modified-p nil))
           (kill-buffer live)))
       (delete-directory dir t))))

(defun my-dpt--read (file)
  "Read fixture FILE from disk."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun my-dpt--at (heading)
  "Place point on the fixture headline containing HEADING."
  (goto-char (point-min))
  (unless (re-search-forward (concat "^\\*+ .*" (regexp-quote heading)) nil t)
    (error "Missing fixture heading: %s" heading))
  (beginning-of-line))

(defun my-dpt--count (text fragment)
  "Count literal FRAGMENT occurrences in TEXT."
  (let ((count 0) (start 0))
    (while (string-match (regexp-quote fragment) text start)
      (cl-incf count)
      (setq start (match-end 0)))
    count))

(ert-deftest my-dpt-states-and-managed-roots ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE A :cliente_003:\n*** SDM B :cliente_003:\n*** KILL C :cliente_003:\n*** TODO D :cliente_003:\n*** NEXT E :cliente_003:\n*** WAIT F :cliente_003:\n*** COLD G :cliente_003:\n** Contratista\n*** DONE H :cliente_003:\n* DEEP\n** DONE I :cliente_003:\n*** DONE Nota anidada :cliente_003:\n** SDM J :cliente_003:\n** KILL K :cliente_003:\n** TODO L :cliente_003:\n** NEXT M :cliente_003:\n** WAIT N :cliente_003:\n** COLD O :cliente_003:\n* SHALLOW\n** DONE P :cliente_003:\n** SDM Q :cliente_003:\n** KILL R :cliente_003:\n** TODO S :cliente_003:\n** NEXT T :cliente_003:\n** WAIT U :cliente_003:\n** COLD V :cliente_003:\n* Notas\n** DONE Fuera :cliente_003:\n"
    (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
    ;; Point at the section selects only its managed descendants.
    (let* ((ot (my-diario-refer (list priad)))
           (file (my-dpt--read priad)))
      (should (equal (plist-get ot :copied) 4))
      (should (equal (plist-get ot :ineligible) 4))
      (should-not (string-search "Nota anidada" file))
      (should-not (string-search "Fuera" file)))
    (my-dpt--at "DEEP")
    (let* ((deep (my-diario-refer (list priad)))
           (file (my-dpt--read priad)))
      (should (equal (plist-get deep :copied) 2))
      (should (equal (plist-get deep :ineligible) 5))
      (should (string-search "*** DONE Nota anidada" file))
      (should (= (my-dpt--count file ":DIARIO_REF_DATE:") 6))
      (should (string-match-p ":DIARIO_REF_DATE: [0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" file))
      (should (string-search ":DIARIO_REF_STATE: KILL" file))
      (should (string-search "** KILL C" file))
      (should-not (string-search "** KILL K" file)))
    (my-dpt--at "SHALLOW")
    (let ((shallow (my-diario-refer (list priad))))
      (should (equal (plist-get shallow :ineligible) 7))
      (should (equal (plist-get shallow :copied) 0))
      (should-not (string-search "COLD V" (my-dpt--read priad))))
    (should (string-search "COLD V" (my-dpt--read source)))))

(ert-deftest my-dpt-suffixes-exact-base-and-separate-groups ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE A :cliente_techo_sur:\n*** DONE B :cliente_003:\n*** DONE C :cliente:\n*** DONE D :clienteXY_003:\n* DEEP\n** SDM E :cliente_003:\n* SHALLOW\n"
    (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
    (let ((counts (my-diario-refer (list priad))))
      (should (equal (plist-get counts :copied) 3))
      (should (equal (plist-get counts :unresolved) 1)))
    (let ((text (my-dpt--read priad)))
      (dolist (tag '("cliente_techo_sur" "cliente_003" "cliente"))
        (should (string-search (concat ":DIARIO_OT_TAG: " tag "\n") text)))
      (should-not (string-search "clienteXY_003" text)))
    ;; An unsuffixed record cannot be silently merged once another OT exists.
    (my-dpt--at "E :")
    (let ((counts (my-diario-refer (list priad))))
      (should (equal (plist-get counts :copied) 1)))
    (let ((text (my-dpt--read priad)))
      (should (string-match-p "\\* OT cliente_003\\(?:.\\|\n\\)*?\\*\\* SDM E" text)))
    (my-dpt--at "C :")
    (should (= 1 (plist-get (my-diario-refer (list priad)) :already)))))

(ert-deftest my-dpt-deep-first-later-ot-without-active-copy ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Abrir obra :cliente_techo:\nNotas de OT activa.\n** Contratista\n* DEEP\n** DONE Medición :cliente_techo:\nMedidas y [[https://example.org][enlace]].\n*** TODO Nota interna\n* SHALLOW\n"
    (my-dpt--at "Medición")
    (should (= 1 (plist-get (my-diario-refer (list priad)) :copied)))
    (let ((text (my-dpt--read priad)))
      (should (string-search "* OT cliente_techo" text))
      (should-not (string-search "Abrir obra" text))
      (should (string-search "*** TODO Nota interna" text)))
    ;; Simulate later closure using Org TODO machinery, not text replacement.
    (my-dpt--at "Abrir obra")
    (org-todo "DONE")
    (save-buffer)
    (my-dpt--at "Abrir obra")
    (should (= 1 (plist-get (my-diario-refer (list priad)) :copied)))
    (let ((text (my-dpt--read priad)))
      (should (= 1 (my-dpt--count text ":DIARIO_OT_TAG: cliente_techo")))
      (should (string-search "** DONE Abrir obra" text))
      (should (string-search "Notas de OT activa." text))
      (should (string-search "Medidas y [[https://example.org][enlace]]." text)))))

(ert-deftest my-dpt-identical-titles-ids-and-repeat ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Igual :cliente_003:\n:PROPERTIES:\n:ID: original-ot\n:END:\n**** Nota privada\n:PROPERTIES:\n:ID: original-nested\n:END:\nProsa de la OT.\n** Contratista\n* DEEP\n** DONE Igual :cliente_003:\n:PROPERTIES:\n:ID: original-deep\n:END:\nOtra prosa.\n* SHALLOW\n"
    (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
    (my-diario-refer (list priad))
    (my-dpt--at "DEEP")
    (my-diario-refer (list priad))
    (let ((text (my-dpt--read priad)))
      (should (= 2 (my-dpt--count text "** DONE Igual")))
      (should (= 2 (my-dpt--count text ":DIARIO_REF_DATE:")))
      (should (string-search "**** Nota privada" (my-dpt--read source)))
      (should (string-search "*** Nota privada" text))
      (should-not (string-search "**** Nota privada" text))
      (should (string-search "original-ot" (my-dpt--read source)))
      (should (string-search "original-nested" (my-dpt--read source)))
      (should (string-search "original-deep" (my-dpt--read source)))
      (dolist (id '("original-ot" "original-nested" "original-deep"))
        (should-not (string-search id text)))
      (should (string-search "Prosa de la OT." text))
      (should (string-search "Otra prosa." text))
      (my-dpt--at "DEEP")
      (should (= 1 (plist-get (my-diario-refer (list priad)) :already)))
      (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
      (should (= 1 (plist-get (my-diario-refer (list priad)) :already)))
      (should (equal text (my-dpt--read priad))))))

(ert-deftest my-dpt-ambiguous-tag-file-and-omit ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Dos etiquetas :cliente_003:otro_ot:t:journal:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (with-temp-file other (insert "#+title: Otro\n"))
    (let ((third (expand-file-name "20260601T1202==p--otro__otro.org" dir))
          (answers (list "otro_ot")))
      (with-temp-file third (insert "#+title: Tercero\n"))
      (my-dpt--at "Dos etiquetas")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt choices &rest _args)
                   (should (member "cliente_003" choices))
                   (should (member "otro_ot" choices))
                   (pop answers))))
        (should (= 1 (plist-get (my-diario-refer (list priad third)) :copied))))
      (should (string-search "* OT otro_ot" (my-dpt--read third)))
      (should-not (string-search "* OT otro_ot" (my-dpt--read priad)))))
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Igual :cliente_003:t:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (with-temp-file other (insert "#+title: También cliente\n"))
    (my-dpt--at "Igual")
    (let (choices)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt options &rest _args)
                   (setq choices options)
                   my-dp--omit)))
        (should (= 1 (plist-get (my-diario-refer (list priad other)) :omitted))))
      (should (member priad choices))
      (should (member other choices))
      (should-not (string-search "Igual" (my-dpt--read priad)))
      (should-not (string-search "Igual" (my-dpt--read other))))))

(ert-deftest my-dpt-choose-tag-before-destination ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Dos :clienteA_techo:clienteB:\n* DEEP\n* SHALLOW\n"
    (let (choices)
      (my-dpt--at "Dos :")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt options &rest _)
                   (should (string-prefix-p "Elegir asociación" prompt))
                   (setq choices options)
                   "clienteA_techo")))
        (let ((counts (my-diario-refer (list priad))))
          (should (= 1 (plist-get counts :unresolved)))
          (should (= 0 (plist-get counts :omitted)))))
      (should (member "clienteA_techo" choices))
      (should (member "clienteB" choices))
      (should-not (string-search "DIARIO_REF_KEY" (my-dpt--read source)))
      (should-not (string-search "* OT " (my-dpt--read priad))))))

(ert-deftest my-dpt-unmatched-chosen-tag-offers-creation ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Dos :clienteA_techo:clienteB:\n* DEEP\n* SHALLOW\n"
    (let ((new (expand-file-name "20260601T1300==p--nuevo__clienteA.org" dir))
          (prompts nil))
      (my-dpt--at "Dos :")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt choices &rest _)
                   (push prompt prompts)
                   (cond ((string-prefix-p "Elegir asociación" prompt)
                          (should (member "clienteA_techo" choices))
                          "clienteA_techo")
                         ((string-prefix-p "Sin PRIAD:" prompt)
                          (should (member my-dp--create choices))
                          my-dp--create)
                         (t (error "Unexpected destination choice: %s" prompt))))))
        (should (= 1
                   (plist-get
                    (my-diario-refer
                     (list priad)
                     (lambda (base tag)
                       (should (equal base "clienteA"))
                       (should (equal tag "clienteA_techo"))
                       (with-temp-file new (insert "#+title: Cliente A\n"))
                       new))
                    :copied))))
      (should (= 2 (length prompts)))
      (should (string-search "* OT clienteA_techo" (my-dpt--read new)))
      (should-not (string-search "* OT clienteA_techo" (my-dpt--read priad))))))

(ert-deftest my-dpt-context-tags-cannot-route ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Sin asociación :cliente:\n:PROPERTIES:\n:DIARIO_CONTEXT_TAGS: :cliente:\n:END:\n* DEEP\n* SHALLOW\n"
    (my-dpt--at "Sin asociación")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (error "Context-only tag was offered"))))
      (should (= 1 (plist-get (my-diario-refer (list priad)) :unresolved))))
    (should-not (string-search "Sin asociación" (my-dpt--read priad)))))

(ert-deftest my-dpt-unmatched-with-callback-omission-distinct ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Sin PRIAD :clienteA_techo:\n* DEEP\n* SHALLOW\n"
    (my-dpt--at "Sin PRIAD")
    (let (options)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt choices &rest _)
                   (should (string-prefix-p "Sin PRIAD:" prompt))
                   (setq options choices)
                   my-dp--omit)))
        (should (= 1 (plist-get
                      (my-diario-refer (list priad) (lambda (&rest _) (error "Created")))
                      :omitted))))
      (should (member my-dp--create options))
      (should (member my-dp--omit options)))
    (should-not (string-search "DIARIO_REF_KEY" (my-dpt--read source)))))

(ert-deftest my-dpt-ambiguous-legacy-group-and-unsuffixed ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE A :cliente_003:\n*** DONE B :cliente:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (with-temp-file priad (insert "* Bitácora\nConservar.\n* OT cliente_003\nProsa legacy.\n"))
    (my-dpt--at "A :")
    (should (= 1 (plist-get (my-diario-refer (list priad)) :unresolved)))
    (should-not (string-search "DIARIO_REF_KEY" (my-dpt--read source)))
    (should (string-search "Prosa legacy." (my-dpt--read priad)))
    (with-temp-file priad
      (insert "* Bitácora\nConservar.\n* OT cliente_003\n:PROPERTIES:\n:DIARIO_OT_TAG: cliente_003\n:END:\n"))
    (my-dpt--at "B :")
    (should (= 1 (plist-get (my-diario-refer (list priad)) :unresolved)))
    (should-not (string-search "** DONE B" (my-dpt--read priad)))
    (with-temp-file priad
      (insert "* completadas\n** DONE A :cliente_003:\nRegistro sin marcador.\n"))
    (let ((before (my-dpt--read priad)))
      (my-dpt--at "A :")
      (should (= 1 (plist-get (my-diario-refer (list priad)) :copied)))
      (should (string-prefix-p before (my-dpt--read priad))))))

(ert-deftest my-dpt-tagged-log-and-planning-survive ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cierre A :cliente_003:\n*** SDM Cierre B :cliente_003:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (with-temp-file priad
      (insert "#+title: Cliente\n\n* Apuntes :cliente_003:\nNarrativa sin tarea.\n* Plan\n** TODO Verificar datos :cliente_003:\n:PROPERTIES:\n:ID: plan-antiguo\n:END:\nCálculo [[https://example.org][anterior]].\n* completadas\n** DONE Cierre histórico :cliente_003:\n:PROPERTIES:\n:ID: cierre-antiguo\n:END:\nBitácora sin marcador.\n"))
    (let ((before (my-dpt--read priad)))
      (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
      (should (= 2 (plist-get (my-diario-refer (list priad)) :copied)))
      (let ((after (my-dpt--read priad)))
        (should (string-prefix-p before after))
        (should (string-search "* Apuntes :cliente_003:\nNarrativa sin tarea.\n" after))
        (should (string-search "** TODO Verificar datos :cliente_003:\n:PROPERTIES:\n:ID: plan-antiguo\n:END:\nCálculo [[https://example.org][anterior]].\n" after))
        (should (string-search "** DONE Cierre histórico :cliente_003:\n:PROPERTIES:\n:ID: cierre-antiguo\n:END:\nBitácora sin marcador.\n" after))
        (should (string-search "* OT cliente_003\n" after))
        (should (= 1 (my-dpt--count after ":DIARIO_OT_TAG: cliente_003")))
        (should (string-search "** DONE Cierre A" after))
        (should (string-search "** SDM Cierre B" after))
        (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
        (should (= 2 (plist-get (my-diario-refer (list priad)) :already)))
        (should (equal after (my-dpt--read priad)))))))

(ert-deftest my-dpt-source-scope-body-and-unrelated-notes ()
  (my-dpt--with-files
      "#+title: Fixture\n\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Uno :cliente:\nTexto del cuerpo.\n**** DONE Nota :cliente:\n*** DONE Dos :cliente:\n** Contratista\n* DEEP\n* SHALLOW\n* Notas\n** DONE Fuera :cliente:\n"
    (my-dpt--at "Uno :")
    (forward-line 1)
    (should (= 1 (plist-get (my-diario-refer (list priad)) :copied)))
    (should (string-search "*** DONE Nota" (my-dpt--read priad)))
    (should-not (string-search "**** DONE Nota" (my-dpt--read priad)))
    (should-not (string-search "Dos :" (my-dpt--read priad)))
    (my-dpt--at "Notas")
    (should (= 0 (plist-get (my-diario-refer (list priad)) :copied)))
    (goto-char (point-min))
    (should (org-before-first-heading-p))
    (should (= 0 (plist-get (my-diario-refer (list priad)) :copied)))))

(ert-deftest my-dpt-callback-and-failed-save-retry ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cerrada :nuevo_techo:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (let ((new (expand-file-name "20260601T1300==p--nuevo__nuevo.org" dir))
          (created 0)
          (save (symbol-function 'my-dp--save)))
      (my-dpt--at "Cerrada")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _choices &rest _args) my-dp--create))
                ((symbol-function 'my-dp--save)
                 (lambda (file before after)
                   (if (equal file new)
                       (error "Injected destination write failure")
                     (funcall save file before after)))))
        (should-error
         (my-diario-refer
          nil (lambda (base full-tag)
                (should (equal base "nuevo"))
                (should (equal full-tag "nuevo_techo"))
                (cl-incf created)
                (with-temp-file new (insert "#+title: Nuevo\n"))
                new))))
      (should (= created 1))
      (should (string-search "Cerrada" (my-dpt--read source)))
      (should (string-search ":DIARIO_REF_KEY:" (my-dpt--read source)))
      (should-not (string-search "Cerrada" (my-dpt--read new)))
      (my-dpt--at "Cerrada")
      (should (= 1 (plist-get (my-diario-refer (list new)) :copied)))
      (my-dpt--at "Cerrada")
      (should (= 1 (plist-get (my-diario-refer (list new)) :already)))
      (should (= 1 (my-dpt--count (my-dpt--read new) "** DONE Cerrada"))))))

(ert-deftest my-dpt-earlier-notes-and-records-survive ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Igual :cliente_003:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (with-temp-file priad
      (insert "* Bitácora\nNarrativa anterior.\n* OT cliente_003\n:PROPERTIES:\n:DIARIO_OT_TAG: cliente_003\n:END:\nCálculos viejos.\n** DONE Igual\n:PROPERTIES:\n:DIARIO_REF_KEY: otra-fuente\n:END:\nUn registro anterior con título igual.\n* completadas\n** DONE Legacy\nOtro registro.\n"))
    (let ((before (my-dpt--read priad)))
      (my-dpt--at "Igual")
      (should (= 1 (plist-get (my-diario-refer (list priad)) :copied)))
      (let ((after (my-dpt--read priad)))
        (dolist (part '("Narrativa anterior." "Cálculos viejos."
                        "Un registro anterior con título igual."
                        "* completadas\n** DONE Legacy\nOtro registro."))
          (should (string-search part before))
          (should (string-search part after)))
        (should (= 1 (my-dpt--count after ":DIARIO_OT_TAG: cliente_003")))
        (should (= 2 (my-dpt--count after "** DONE Igual")))))))

(ert-deftest my-dpt-source-save-fails-without-target-write ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cerrada :cliente:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (let ((original (my-dpt--read source))
          (original-target (my-dpt--read priad))
          (save (symbol-function 'my-dp--save)))
      (my-dpt--at "Cerrada")
      (cl-letf (((symbol-function 'my-dp--save)
                 (lambda (file before after)
                   (if (equal file source)
                       (error "Injected source write failure")
                     (funcall save file before after)))))
        (should-error (my-diario-refer (list priad))))
      (should (equal original (my-dpt--read source)))
      (should (equal original-target (my-dpt--read priad)))
      (my-dpt--at "Cerrada")
      (should (= 1 (plist-get (my-diario-refer (list priad)) :copied))))))

(ert-deftest my-dpt-unrelated-duplicate-ids-and-ambiguous-retry ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cliente :cliente_003:\n*** DONE Otro :otro_003:\n* DEEP\n* SHALLOW\n"
    (let ((first (expand-file-name
                  "20260511T1358==i--workflow__otro.org" dir))
          (second (expand-file-name
                   "20260511T1358==p--workflow__apuntes.org" dir))
          ambiguous-before)
      (my-dpt--at "Otro :")
      (setq ambiguous-before
            (buffer-substring-no-properties
             (point) (save-excursion (org-end-of-subtree t t))))
      (with-temp-file first (insert "* Notas de otro\n"))
      (with-temp-file second (insert "* Notas no relacionadas\n"))
      (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
      (let ((counts (my-diario-refer (list priad first second))))
        (should (= 1 (plist-get counts :copied)))
        (should (= 1 (plist-get counts :unresolved))))
      (should (string-search "** DONE Cliente" (my-dpt--read priad)))
      (my-dpt--at "Otro :")
      (should-not (org-entry-get nil "DIARIO_REF_KEY"))
      (should (equal ambiguous-before
                     (buffer-substring-no-properties
                      (point) (save-excursion (org-end-of-subtree t t)))))
      (should (equal (my-dpt--read first) "* Notas de otro\n"))
      (should (equal (my-dpt--read second) "* Notas no relacionadas\n"))

      ;; A retry by Denote ID cannot pick the first of two distinct files.
      (should (= 1 (plist-get (my-diario-refer (list first)) :copied)))
      (let ((saved-source (my-dpt--read source))
            (saved-first (my-dpt--read first)))
        (my-dpt--at "Otro :")
        (should (equal (org-entry-get nil "DIARIO_REF_DEST") "20260511T1358"))
        (should (= 1 (plist-get (my-diario-refer (list priad first second))
                                 :unresolved)))
        (should (equal saved-source (my-dpt--read source)))
        (should (equal saved-first (my-dpt--read first)))
        (should (equal (my-dpt--read second)
                       "* Notas no relacionadas\n"))))))

(ert-deftest my-dpt-reject-duplicate-denote-id-and-source-edits ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cerrada :cliente:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (let ((duplicate (expand-file-name
                      "20260601T1200==r--segundo__cliente.org" dir))
          (before (my-dpt--read priad)))
      (with-temp-file duplicate (insert "* Otro archivo\n"))
      (my-dpt--at "Cerrada")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt choices &rest _)
                   (should (member priad choices))
                   priad)))
        (should (= 1 (plist-get (my-diario-refer (list priad duplicate))
                                 :unresolved))))
      (should (equal before (my-dpt--read priad)))
      (should-not (string-search "DIARIO_REF_KEY" (my-dpt--read source)))
      (insert "Nota nueva sin grabar")
      (should-error (my-diario-refer (list priad)) :type 'user-error)
      (should-not (string-search "DIARIO_REF_KEY" (my-dpt--read source))))))

(ert-deftest my-dpt-open-source-marker-syncs-without-prompt ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cerrada :cliente:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (let ((visitor (current-buffer))
          (supersessions 0))
      (my-dpt--at "Cerrada")
      (cl-letf (((symbol-function 'ask-user-about-supersession-threat)
                 (lambda (&rest _args)
                   (cl-incf supersessions)
                   (error "Unexpected supersession prompt"))))
        (should (= 1 (plist-get (my-diario-refer (list priad)) :copied)))
        (my-dpt--at "Cerrada")
        (should (= 1 (plist-get (my-diario-refer (list priad)) :already))))
      (should (= 0 supersessions))
      (should (eq visitor (find-buffer-visiting source)))
      (should-not (buffer-modified-p visitor))
      (should (verify-visited-file-modtime visitor))
      (should (equal (my-dpt--read source) (buffer-string)))
      (should (string-search ":DIARIO_REF_KEY:" (buffer-string))))))

(ert-deftest my-dpt-stale-destination-buffer-is-refused ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cerrada :cliente:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (let ((visitor (find-file-noselect priad))
          (original-source (my-dpt--read source)))
      (with-temp-file priad (insert "#+title: Editado fuera de Emacs\n"))
      (my-dpt--at "Cerrada")
      (should-error (my-diario-refer (list priad)) :type 'user-error)
      (should (equal original-source (my-dpt--read source)))
      (should-not (buffer-modified-p visitor))
      (should-not (equal (my-dpt--read priad)
                         (with-current-buffer visitor (buffer-string)))))))

(ert-deftest my-dpt-preexisting-modified-buffer-is-not-saved ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Cerrada :cliente:\n** Contratista\n* DEEP\n* SHALLOW\n"
    (let ((before (my-dpt--read priad)))
      (with-current-buffer (find-file-noselect priad)
        (goto-char (point-max))
        (insert "Nota no guardada.\n"))
      (my-dpt--at "Cerrada")
      (should-error (my-diario-refer (list priad)) :type 'user-error)
      (should (equal before (my-dpt--read priad)))
      (should-not (string-search "DIARIO_REF_KEY" (my-dpt--read source)))
      (should (buffer-modified-p (find-buffer-visiting priad))))))

(defun my-dpt--keys (text)
  "Return all automatic reference keys in fixture TEXT."
  (let ((start 0) keys)
    (while (string-match "^:DIARIO_REF_KEY: \\([^[:space:]]+\\)$" text start)
      (push (match-string 1 text) keys)
      (setq start (match-end 0)))
    (nreverse keys)))

(ert-deftest my-dpt-unique-keys-with-second-resolution-org-ids ()
  (my-dpt--with-files
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** DONE Igual :cliente_003:\n*** DONE Igual :cliente_003:\n*** SDM Quizás :cliente_003:\n*** KILL Perdida :cliente_003:\n** Contratista\n* DEEP\n** DONE Medición :cliente_003:\n* SHALLOW\n"
    (let* ((org-id-method 'ts)
           (org-id-ts-format "%Y%m%dT%H%M%S")
           (org-id-prefix "usuario")
           (format-time-string-original (symbol-function 'format-time-string)))
      ;; Freeze only timestamp-based Org ID generation; the old code then
      ;; reused one key for every root even if the fixture crossed a second.
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (format &rest args)
                   (if (equal format org-id-ts-format)
                       "20260601T120000"
                     (apply format-time-string-original format args)))))
        (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
        (should (= 4 (plist-get (my-diario-refer (list priad)) :copied)))
        (my-dpt--at "DEEP")
        (should (= 1 (plist-get (my-diario-refer (list priad)) :copied)))
        (let* ((source-keys (my-dpt--keys (my-dpt--read source)))
               (target (my-dpt--read priad))
               (target-keys (my-dpt--keys target)))
          (should (= 5 (length source-keys)))
          (should (= 5 (length (delete-dups (copy-sequence source-keys)))))
          (should (equal (sort (copy-sequence source-keys) #'string<)
                         (sort (copy-sequence target-keys) #'string<)))
          (should (= 2 (my-dpt--count target "** DONE Igual")))
          (my-dpt--at "OPORTUNIDADES Y AMENAZAS")
          (should (= 4 (plist-get (my-diario-refer (list priad)) :already)))
          (my-dpt--at "DEEP")
          (should (= 1 (plist-get (my-diario-refer (list priad)) :already)))
          (should (equal target (my-dpt--read priad))))))))

(provide 'test-diario-priads)
;;; test-diario-priads.el ends here
