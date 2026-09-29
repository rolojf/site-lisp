;;; test-diario-rollover.el --- Isolated diario rollover fixtures -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'cl-lib)

(defconst my-diario-test--source
  "#+title: Ayer\n#+identifier: ayer-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n*** WAIT Primero :cliente_1:\n:PROPERTIES:\n:ID: ot-original\n:END:\nNota [[https://example.org][link]].\n**** TODO Detalle anidado\n*** DONE Cerrado\n** Empresa\n*** TODO Igual :cliente_2:\n*** NEXT Igual :cliente_3:\n*** COLD Frío OT\nSCHEDULED: <2026-06-10 Wed>\n*** KILL Perdido\n* DEEP\n** TODO Trabajo :cliente_2:\n:PROPERTIES:\n:ID: deep-original\n:END:\nContenido profundo.\n*** TODO Subtarea\n** WAIT Espera\n** DONE Hecho\n** SDM Quizá\n** COLD Frío profundo\n* SHALLOW\n** NEXT Ligero\n** TODO Igual\n** DONE Otro hecho\n** COLD Frío superficial\n* Notas\nTexto del día.\n** Apunte\n:PROPERTIES:\n:ID: note-original\n:END:\nMás notas.\n"
  "Source fixture with distinct same-title entries and both OT queues.")

(defmacro my-diario-test--with-files (&rest body)
  "Evaluate BODY with private fixture files and no production hooks."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "diario-roll-test-" t))
          (source (expand-file-name "20260601-journal.org" dir))
          (target (expand-file-name "20260603-journal.org" dir))
          (later (expand-file-name "LUEGO.org" dir))
          (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "SDM" "COLD" "PROG"
                                        "|" "DONE" "KILL")))
          (org-log-done nil)
          (org-log-into-drawer nil)
          (org-log-reschedule nil))
     (unwind-protect
         (progn
           (with-temp-file source (insert my-diario-test--source))
           (with-temp-file target
             (insert "#+title: Hoy\n#+date: [2026-06-03 Wed]\n#+identifier: hoy-id\n\n"))
           ,@body)
       (dolist (path (list source target later))
         (when-let* ((buf (get-file-buffer path)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (delete-directory dir t))))

(defun my-diario-test--text (path)
  "Read PATH as a string without opening a visiting buffer."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun my-diario-test--replace (path from to)
  "Replace the unique FROM string in PATH with TO for fixture setup."
  (let ((text (my-diario-test--text path)))
    (unless (string-match-p (regexp-quote from) text)
      (error "Fixture text not found: %s" from))
    (with-temp-file path
      (insert (replace-regexp-in-string (regexp-quote from) to text t t)))))

(defun my-diario-test--count (pattern text)
  "Count occurrences of PATTERN in TEXT."
  (let ((start 0) (count 0))
    (while (string-match (regexp-quote pattern) text start)
      (setq start (match-end 0))
      (cl-incf count))
    count))

(ert-deftest my-diario-test-roll-order-and-content ()
  (my-diario-test--with-files
    (let* ((summary (my-diario-roll source target later "20260603"))
           (old (my-diario-test--text source))
           (new (my-diario-test--text target))
           (parked (my-diario-test--text later)))
      (should (equal (plist-get summary :copied-ot) 3))
      (should (equal (plist-get summary :moved) 4))
      (should (equal (plist-get summary :parked) 3))
      (should (string-prefix-p "#+title: Hoy\n#+date: [2026-06-03 Wed]\n#+identifier: hoy-id" new))
      (should-not (string-match-p "ayer-id\|#+title: Ayer" new))
      (should (< (string-search "** Contratista" new) (string-search "** Empresa" new)))
      (should (< (string-search "*** TODO Igual :cliente_2:" new)
                 (string-search "*** NEXT Igual :cliente_3:" new)))
      (should (< (string-search "** TODO Trabajo" new) (string-search "** WAIT Espera" new)))
      (should (string-search "Contenido profundo.\n*** TODO Subtarea" new))
      (should (string-search "Nota [[https://example.org][link]]." new))
      (should (string-search "Texto del día." old))
      (should (string-search "Texto del día." new))
      (should (string-search "** Apunte" old))
      (should (string-search "** Apunte" new))
      (should (string-search "ot-original" old))
      (should-not (string-search "ot-original" new))
      (should-not (string-search "note-original" new))
      (should (string-search "deep-original" new))
      (dolist (missing '("deep-original" "** TODO Trabajo" "** WAIT Espera" "** NEXT Ligero"))
        (should-not (string-search missing old)))
      (should (string-search "** DONE Hecho" old))
      (should (string-search "** SDM Quizá" old))
      (dolist (missing '("** DONE Hecho" "** SDM Quizá" "*** KILL Perdido"))
        (should-not (string-search missing new)))
      (should (string-search "*** KILL Perdido" old))
      (should (string-search "** COLD Frío superficial" parked))
      (should-not (string-search "** COLD Frío superficial" new)))))

(ert-deftest my-diario-test-repeat-does-not-clobber-edits ()
  (my-diario-test--with-files
    (my-diario-roll source target later "20260603")
    (my-diario-test--replace target "* Notas\n" "* Notas\nEdición de hoy.\n")
    (let ((before (my-diario-test--text target)))
      (my-diario-roll source target later "20260603")
      (should (equal before (my-diario-test--text target)))
      (should (= 1 (my-diario-test--count "*** TODO Igual :cliente_2:" before)))
      (should (= 1 (my-diario-test--count "*** NEXT Igual :cliente_3:" before)))
      (should (= 3 (my-diario-test--count ":DIARIO_LIST:" (my-diario-test--text later)))))))

(ert-deftest my-diario-test-due-skipped-date-and-history ()
  (my-diario-test--with-files
    (my-diario-test--replace source "SCHEDULED: <2026-06-10 Wed>" "SCHEDULED: <2026-05-31 Sun>")
    (my-diario-roll source target later "20260603")
    (let ((new (my-diario-test--text target))
          (later-text (my-diario-test--text later)))
      (should (string-search "*** NEXT Frío OT" new))
      (should (< (string-search "*** TODO Igual :cliente_2:" new)
                 (string-search "*** NEXT Igual :cliente_3:" new)
                 (string-search "*** NEXT Frío OT" new)))
      (should (string-search ":DIARIO_PLANNED_RETURN: [2026-05-31" new))
      (should (string-search ":DIARIO_ACTUAL_RETURN: [2026-06-03" new))
      (should-not (string-search "SCHEDULED: <2026-05-31" new))
      (should-not (string-search "Frío OT" later-text))
      (should (string-search "Frío OT" (my-diario-test--text source))))))

(ert-deftest my-diario-test-default-date-and-return-shallow ()
  (my-diario-test--with-files
    (my-diario-roll source target later "20260603")
    (let ((text (my-diario-test--text later)))
      (should (string-match-p "SCHEDULED: <2026-06-17" text))
      (should (string-match-p "SCHEDULED: <2026-06-10" text)))
    (let ((next (expand-file-name "20260620-journal.org" dir)))
      (with-temp-file next (insert "#+title: Next\n#+identifier: next-id\n\n"))
      (my-diario-roll target next later "20260620")
      (let ((text (my-diario-test--text next)))
        (should (string-search "** NEXT Frío superficial" text))
        (should (string-search "** NEXT Frío profundo" text))
        (should (string-search "*** NEXT Frío OT" text))
        (should-not (string-search "SCHEDULED: <2026-06-17" text)))
      (dolist (missing '("Frío superficial" "Frío profundo" "Frío OT"))
        (should-not (string-search missing (my-diario-test--text later)))))))

(ert-deftest my-diario-test-repark-cycle ()
  (my-diario-test--with-files
    (my-diario-roll source target later "20260603")
    (let ((next (expand-file-name "20260620-journal.org" dir))
          (third (expand-file-name "20260710-journal.org" dir)))
      (with-temp-file next (insert "#+title: Next\n#+identifier: next-id\n\n"))
      (my-diario-roll target next later "20260620")
      (my-diario-test--replace next "** NEXT Frío superficial" "** COLD Frío superficial")
      (with-temp-file third (insert "#+title: Third\n#+identifier: third-id\n\n"))
      (my-diario-roll next third later "20260710")
      (should (= 1 (my-diario-test--count "** COLD Frío superficial"
                                           (my-diario-test--text later))))
      (should (string-match-p "SCHEDULED: <2026-07-24" (my-diario-test--text later)))
      (my-diario-roll next third later "20260710")
      (should (= 1 (my-diario-test--count "** COLD Frío superficial"
                                           (my-diario-test--text later)))))))

(ert-deftest my-diario-test-failure-and-recovery ()
  (my-diario-test--with-files
    (let ((original-source (my-diario-test--text source))
          (original-target (my-diario-test--text target))
          (original-save (symbol-function 'my-diario--save)))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (if (equal path target)
                       (error "Injected target write failure")
                     (funcall original-save path expected text)))))
        (should-error (my-diario-roll source target later "20260603")))
      (should (equal original-target (my-diario-test--text target)))
      (should (string-search "** TODO Trabajo" (my-diario-test--text source)))
      (should (string-search "** COLD Frío superficial" (my-diario-test--text later)))
      (should-not (equal original-source (my-diario-test--text source)))
      (my-diario-roll source target later "20260603")
      (should-not (string-search "** TODO Trabajo" (my-diario-test--text source)))
      (should (= 1 (my-diario-test--count "** TODO Trabajo" (my-diario-test--text target)))))))

(ert-deftest my-diario-test-target-saved-source-prune-fails ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save))
          (source-writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path source)
                     (cl-incf source-writes)
                     (when (= source-writes 3)
                       (error "Injected source prune failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-roll source target later "20260603")))
      (should (string-match-p "** TODO Trabajo" (my-diario-test--text source)))
      (should (string-match-p "** TODO Trabajo" (my-diario-test--text target)))
      (my-diario-roll source target later "20260603")
      (should-not (string-match-p "** TODO Trabajo" (my-diario-test--text source)))
      (should (= 1 (my-diario-test--count "** TODO Trabajo" (my-diario-test--text target)))))))

(ert-deftest my-diario-test-retry-refuses-edited-source ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save))
          (source-writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path source)
                     (cl-incf source-writes)
                     (when (= source-writes 3)
                       (error "Injected source prune failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-roll source target later "20260603")))
      (my-diario-test--replace source "Contenido profundo."
                               "Contenido profundo editado tras el fallo.")
      (let ((old (my-diario-test--text source))
            (new (my-diario-test--text target)))
        (should-error (my-diario-roll source target later "20260603")
                      :type 'user-error)
        (should (equal old (my-diario-test--text source)))
        (should (equal new (my-diario-test--text target)))))))

(ert-deftest my-diario-test-retry-preserves-edited-target ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save))
          (source-writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path source)
                     (cl-incf source-writes)
                     (when (= source-writes 3)
                       (error "Injected source prune failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-roll source target later "20260603")))
      (my-diario-test--replace target "Contenido profundo."
                               "Contenido profundo editado en destino.")
      (should (= 4 (plist-get (my-diario-roll source target later "20260603") :moved)))
      (should-not (string-search "** TODO Trabajo" (my-diario-test--text source)))
      (let ((new (my-diario-test--text target)))
        (should (string-search "Contenido profundo editado en destino." new))
        (should (string-search "Contenido profundo." new))
        (should (= 2 (my-diario-test--count "** TODO Trabajo" new)))
        (should (= 1 (my-diario-test--count ":ID: deep-original\n" new)))
        (should-not (string-search ":DIARIO_KEY:" new))
        (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text source)))
        (should (= 2 (my-diario-test--count "# DIARIO: copias con contenido distinto; revisar ambas." new)))
        (should (= 0 (plist-get (my-diario-roll source target later "20260603") :moved)))
        (should (equal new (my-diario-test--text target)))))))

(ert-deftest my-diario-test-retry-remaps-retained-id-links ()
  (my-diario-test--with-files
    (my-diario-test--replace source "Contenido profundo.\n"
                             "Contenido profundo. [[id:deep-child-original][Paso]] [[id:externo][Fuera]].\n")
    (my-diario-test--replace source "*** TODO Subtarea\n"
                             "*** TODO Subtarea\n:PROPERTIES:\n:ID: deep-child-original\n:END:\n[[id:deep-original][Padre]]\n")
    (my-diario-test--replace source "Más notas.\n"
                             "Más notas. [[id:externo][Referencia]].\n")
    (let ((save (symbol-function 'my-diario--save)) (writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path source)
                     (cl-incf writes)
                     (when (= writes 3) (error "Injected prune failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-roll source target later "20260603"))))
    (my-diario-test--replace target "Contenido profundo."
                             "Contenido editado en destino.")
    (should (= 4 (plist-get (my-diario-roll source target later "20260603") :moved)))
    (let ((new (my-diario-test--text target))
          original retained retained-root retained-child)
      (should (= 1 (my-diario-test--count ":ID: deep-original\n" new)))
      (should (= 1 (my-diario-test--count ":ID: deep-child-original\n" new)))
      (should (= 2 (my-diario-test--count "** TODO Trabajo" new)))
      (should (string-search "[[id:externo][Referencia]]" new))
      (my-diario--with-text new
        (dolist (entry (my-diario--scan))
          (when (and (equal (my-diario--entry-list entry) "DEEP")
                     (string-search "** TODO Trabajo"
                                    (my-diario--subtree new entry)))
            (let ((tree (my-diario--subtree new entry)))
              (goto-char (my-diario--entry-start entry))
              (let ((root-id (org-entry-get nil "ID" nil))
                    (child-id (save-excursion
                                (re-search-forward "^\\*\\*\\* TODO Subtarea"
                                                   (my-diario--entry-end entry) t)
                                (org-entry-get nil "ID" nil))))
                (if (string-search "Contenido editado en destino." tree)
                    (setq retained tree retained-root root-id retained-child child-id)
                  (setq original tree)))))))
      (should original)
      (should retained)
      (should (string-search ":ID: deep-original\n" original))
      (should (string-search ":ID: deep-child-original\n" original))
      (should (string-search "[[id:deep-child-original][Paso]]" original))
      (should (string-search "[[id:deep-original][Padre]]" original))
      (should (and retained-root retained-child
                   (not (equal retained-root "deep-original"))
                   (not (equal retained-child "deep-child-original"))
                   (not (equal retained-root retained-child))))
      (should (string-search (format "[[id:%s][Paso]]" retained-child) retained))
      (should (string-search (format "[[id:%s][Padre]]" retained-root) retained))
      (should (string-search "[[id:externo][Fuera]]" retained))
      (should-not (string-search ":DIARIO_KEY:" new))
      (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text source)))
      (should (= 0 (plist-get (my-diario-roll source target later "20260603") :moved)))
      (should (equal new (my-diario-test--text target))))))

(ert-deftest my-diario-test-retry-remap-save-failure ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save)) (writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path source)
                     (cl-incf writes)
                     (when (= writes 3) (error "Injected prune failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-roll source target later "20260603"))))
    (my-diario-test--replace target "Contenido profundo."
                             "Contenido editado en destino.")
    (let ((before (my-diario-test--text target))
          (save (symbol-function 'my-diario--save)))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (if (equal path target) (error "Injected remap save failure")
                     (funcall save path expected text)))))
        (should-error (my-diario-roll source target later "20260603")))
      (should (equal before (my-diario-test--text target)))
      (should (string-search "** TODO Trabajo" (my-diario-test--text source))))
    (should (= 4 (plist-get (my-diario-roll source target later "20260603") :moved)))
    (let ((new (my-diario-test--text target)))
      (should (= 1 (my-diario-test--count ":ID: deep-original\n" new)))
      (should (= 2 (my-diario-test--count "** TODO Trabajo" new)))
      (should-not (string-search ":DIARIO_KEY:" new))
      (should (= 0 (plist-get (my-diario-roll source target later "20260603") :moved)))
      (should (equal new (my-diario-test--text target))))))

(ert-deftest my-diario-test-retry-blocks-foreign-id ()
  (dolist (list-name '("DEEP" "SHALLOW"))
    (my-diario-test--with-files
      (let ((save (symbol-function 'my-diario--save)))
        (cl-letf (((symbol-function 'my-diario--save)
                   (lambda (path expected text)
                     (if (equal path target) (error "Injected destination failure")
                       (funcall save path expected text)))))
          (should-error (my-diario-roll source target later "20260603"))))
      (with-temp-file target
        (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
                "* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n"
                "* DEEP\n" (if (equal list-name "DEEP")
                               "** TODO Otro\n:PROPERTIES:\n:ID: deep-original\n:END:\n" "")
                "* SHALLOW\n" (if (equal list-name "SHALLOW")
                                  "** TODO Otro\n:PROPERTIES:\n:ID: deep-original\n:END:\n" "")))
      (let ((old (my-diario-test--text source))
            (new (my-diario-test--text target)))
        (should-error (my-diario-roll source target later "20260603") :type 'user-error)
        (should (equal old (my-diario-test--text source)))
        (should (equal new (my-diario-test--text target)))))))

(ert-deftest my-diario-test-independent-park-and-return ()
  (my-diario-test--with-files
    (let ((old (my-diario-test--text source)))
      (should (= 3 (plist-get (my-diario-park source later "20260603") :parked)))
      (should (string-search "** COLD Frío superficial" (my-diario-test--text source)))
      (should (string-search "Texto del día." (my-diario-test--text source)))
      (should-not (string-search "SCHEDULED: <2026-06-17" (my-diario-test--text source)))
      (should (string-search "SCHEDULED: <2026-06-17" (my-diario-test--text later)))
      (should (= 0 (plist-get (my-diario-park source later "20260604") :parked)))
      (should (= 1 (my-diario-test--count "** COLD Frío superficial"
                                         (my-diario-test--text later))))
      (should (string-search "*** COLD Frío OT" old)))
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n* SHALLOW\n")
    (let ((before (my-diario-test--text target)))
      (should (= 0 (plist-get (my-diario-return target later "20260603") :returned)))
      (should (equal before (my-diario-test--text target))))
    (should (= 3 (plist-get (my-diario-return target later "20260620") :returned)))
    (should (= 0 (plist-get (my-diario-return target later "20260620") :returned)))
    (let ((text (my-diario-test--text target)))
      (should (string-search "*** NEXT Frío OT" text))
      (should (string-search "** NEXT Frío profundo" text))
      (should (string-search "** NEXT Frío superficial" text))
      (should-not (string-search "SCHEDULED: <2026-06-17" text)))
    (should-not (string-search "Frío superficial" (my-diario-test--text later)))))

(ert-deftest my-diario-test-tagged-return ()
  (my-diario-test--with-files
    (my-diario-test--replace source "* OPORTUNIDADES Y AMENAZAS\n"
                             "* OPORTUNIDADES Y AMENAZAS :operaciones:\n")
    (my-diario-test--replace source "** Empresa\n" "** Empresa :trabajo:\n")
    (my-diario-test--replace source "* DEEP\n" "* DEEP :clienteX:\n")
    (my-diario-test--replace source "* SHALLOW\n" "* SHALLOW :clienteX:\n")
    (my-diario-test--replace source "** COLD Frío profundo\n"
                             "** COLD Frío profundo\n** COLD Segundo profundo :cliente_4:\n")
    (should (= 4 (plist-get (my-diario-park source later "20260603") :parked)))
    (with-temp-file target
      (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
              "* Notas\n** DEEP\n*** Apunte profundo\n** SHALLOW\n"
              "*** Apunte ligero\n** Empresa\n*** Apunte empresa\n"
              "* OPORTUNIDADES Y AMENAZAS :operaciones:\n"
              "** Contratista :otro:\n*** WAIT OT contratista\n"
              "** Empresa :trabajo:\nCola sin cambiar.\n*** TODO OT existente\n"
              "* DEEP :clienteX:\nLista DEEP sin cambiar.\n** TODO Deep existente\n"
              "* SHALLOW :clienteX:\nLista SHALLOW sin cambiar.\n"
              "** WAIT Shallow existente\n* Cierre\nOtro contexto.\n"))
    (should (= 4 (plist-get (my-diario-return target later "20260620") :returned)))
    (let ((text (my-diario-test--text target))
          second)
      (should (string-search "* Notas\n** DEEP\n*** Apunte profundo\n** SHALLOW\n*** Apunte ligero\n** Empresa\n*** Apunte empresa\n" text))
      (dolist (container '("* OPORTUNIDADES Y AMENAZAS :operaciones:\n"
                           "** Empresa :trabajo:\nCola sin cambiar.\n"
                           "* DEEP :clienteX:\nLista DEEP sin cambiar.\n"
                           "* SHALLOW :clienteX:\nLista SHALLOW sin cambiar.\n"))
        (should (= 1 (my-diario-test--count container text))))
      (my-diario--with-text text
        (goto-char (point-min))
        (while (re-search-forward org-heading-regexp nil t)
          (when (and (= (org-outline-level) 2)
                     (equal (org-get-heading t t t t) "Segundo profundo"))
            (should (equal (org-get-todo-state) "NEXT"))
            (should (equal (org-get-tags nil t) '("cliente_4")))
            (should-not second)
            (setq second (1- (line-beginning-position))))))
      (should second)
      (should (< (string-search "** Contratista :otro:" text)
                 (string-search "** Empresa :trabajo:" text)
                 (string-search "*** TODO OT existente" text)
                 (string-search "*** NEXT Frío OT" text)
                 (string-search "* DEEP :clienteX:" text)
                 (string-search "** TODO Deep existente" text)
                 (string-search "** NEXT Frío profundo" text)
                 second
                 (string-search "* SHALLOW :clienteX:" text)
                 (string-search "** WAIT Shallow existente" text)
                 (string-search "** NEXT Frío superficial" text)
                 (string-search "* Cierre" text)))
      (dolist (returned '("*** NEXT Frío OT" "** NEXT Frío profundo"
                           "** NEXT Frío superficial"))
        (should (= 1 (my-diario-test--count returned text))))
      (should (= 0 (plist-get (my-diario-return target later "20260620") :returned)))
      (should (equal text (my-diario-test--text target)))
      (should-not (string-search "Frío OT" (my-diario-test--text later)))
      (should-not (string-search "Segundo profundo" (my-diario-test--text later))))))

(ert-deftest my-diario-test-bucket-scope ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (with-temp-file target
      (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
              "* Notas\n** Empresa :decoy:\n"
              "* OPORTUNIDADES Y AMENAZAS :trabajo:\n"
              "** Contratista\n** Otra cola\n"
              "* DEEP :trabajo:\n* SHALLOW :trabajo:\n"))
    (let ((before (my-diario-test--text target))
          (parked (my-diario-test--text later)))
      (let ((reason (should-error (my-diario-return target later "20260620")
                                  :type 'user-error)))
        (should (string-match-p "Missing destination OT bucket"
                                (error-message-string reason))))
      (should (equal before (my-diario-test--text target)))
      (should (equal parked (my-diario-test--text later))))))

(ert-deftest my-diario-test-duplicate-dest ()
  (dolist (case '(("* DEEP :a:\n* DEEP :b:\n" "DEEP" nil)
                  ("* OPORTUNIDADES Y AMENAZAS :ops:\n** Empresa :a:\n** Empresa :b:\n"
                   "OPORTUNIDADES Y AMENAZAS" "Empresa")))
    (pcase-let ((`(,text ,root ,bucket) case))
      (my-diario--with-text text
        (let ((reason (should-error (my-diario--append "** NEXT Nueva\n" root bucket)
                                    :type 'user-error)))
          (should (string-match-p "Duplicate\\|Ambiguous"
                                  (error-message-string reason))))
        (should (equal text (buffer-string)))))))

(ert-deftest my-diario-test-park-retry-preserves-source-snapshot ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save))
          (writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path source)
                     (cl-incf writes)
                     (when (= writes 2) (error "Injected park acknowledgement failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-park source later "20260603")))
      (my-diario-park source later "20260604")
      (should (= 1 (my-diario-test--count "** COLD Frío superficial"
                                         (my-diario-test--text later))))
      (should (string-search "SCHEDULED: <2026-06-17" (my-diario-test--text later)))
      (should-not (string-search "SCHEDULED: <2026-06-17" (my-diario-test--text source)))
      (should (string-search "*** COLD Frío OT" (my-diario-test--text source))))))

(ert-deftest my-diario-test-park-retry-preserves-edited-later ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save))
          (writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path source)
                     (cl-incf writes)
                     (when (= writes 2) (error "Injected park acknowledgement failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-park source later "20260603")))
      (with-temp-file later
        (insert (my-diario-test--text later) "Nota editada en LUEGO.\n"))
      (should (= 1 (plist-get (my-diario-park source later "20260604") :parked)))
      (let ((parked (my-diario-test--text later)))
        (should (string-search "Nota editada en LUEGO." parked))
        (should (= 2 (my-diario-test--count "** COLD Frío superficial\n" parked)))
        (should (= 2 (my-diario-test--count
                      "# DIARIO: copias con contenido distinto; revisar ambas." parked)))
        (should (= 0 (plist-get (my-diario-park source later "20260604") :parked)))
        (should (equal parked (my-diario-test--text later)))))))

(ert-deftest my-diario-test-return-retry-preserves-edited-target ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n* SHALLOW\n")
    (let ((save (symbol-function 'my-diario--save)) (later-writes 0))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (equal path later)
                     (cl-incf later-writes)
                     (when (= later-writes 2)
                       (error "Injected LUEGO removal failure")))
                   (funcall save path expected text))))
        (should-error (my-diario-return target later "20260620"))))
    (with-temp-file target
      (insert (my-diario-test--text target) "Nota editada en destino.\n"))
    (should (= 1 (plist-get (my-diario-return target later "20260621") :returned)))
    (let ((new (my-diario-test--text target)))
      (should (= 2 (my-diario-test--count "** NEXT Frío superficial" new)))
      (should (= 2 (my-diario-test--count
                    "# DIARIO: copias con contenido distinto; revisar ambas." new)))
      (should (string-search ":DIARIO_ACTUAL_RETURN: [2026-06-20" new))
      (should (string-search "Nota editada en destino." new))
      (should-not (string-search "Frío superficial" (my-diario-test--text later)))
      (should (= 0 (plist-get (my-diario-return target later "20260621") :returned))))))

(ert-deftest my-diario-test-frontmatter-and-nested-ids ()
  (my-diario-test--with-files
    (my-diario-test--replace source "#+identifier: ayer-id\n"
                             "#+identifier: ayer-id\n#+PROPERTY: ID file-original\n:PROPERTIES:\n:ID: root-original\n:LANGUAGE: es\n:END:\n")
    (my-diario-test--replace source "**** TODO Detalle anidado\n"
                             "**** TODO Detalle anidado\n:PROPERTIES:\n:ID: ot-child-original\n:END:\n")
    (my-diario-test--replace source "*** TODO Subtarea\n"
                             "*** TODO Subtarea\n:PROPERTIES:\n:ID: deep-child-original\n:END:\n")
    (my-diario-roll source target later "20260603")
    (let ((new (my-diario-test--text target))
          (old (my-diario-test--text source)))
      (dolist (id '("file-original" "root-original" "ot-child-original"
                    "note-original"))
        (should (string-search id old))
        (should-not (string-search id new)))
      (should (string-search ":LANGUAGE: es" new))
      (should (= 1 (my-diario-test--count "deep-child-original" new)))
      (should-not (string-search "deep-child-original" old)))))

(ert-deftest my-diario-test-reject-unidentified-new-target ()
  (my-diario-test--with-files
    (with-temp-file target (insert ""))
    (let ((old (my-diario-test--text source)))
      (should-error (my-diario-roll source target later "20260603")
                    :type 'user-error)
      (should (equal old (my-diario-test--text source)))
      (should (equal "" (my-diario-test--text target)))
      (should-not (file-exists-p later)))))

(ert-deftest my-diario-test-reject-shared-file-identifier ()
  (my-diario-test--with-files
    (my-diario-test--replace target "#+identifier: hoy-id"
                             "#+identifier: ayer-id")
    (let ((old (my-diario-test--text source))
          (new (my-diario-test--text target)))
      (should-error (my-diario-roll source target later "20260603")
                    :type 'user-error)
      (should (equal old (my-diario-test--text source)))
      (should (equal new (my-diario-test--text target)))
      (should-not (file-exists-p later)))))

(ert-deftest my-diario-test-target-file-id-is-preserved ()
  (my-diario-test--with-files
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n#+PROPERTY: ID target-property-id\n:PROPERTIES:\n:ID: target-root-id\n:END:\n\n")
    (my-diario-test--replace source "#+identifier: ayer-id\n"
                             "#+identifier: ayer-id\n#+PROPERTY: ID source-property-id\n:PROPERTIES:\n:ID: source-root-id\n:END:\n")
    (my-diario-roll source target later "20260603")
    (let ((new (my-diario-test--text target))
          (old (my-diario-test--text source)))
      (dolist (id '("target-property-id" "target-root-id"))
        (should (string-search id new)))
      (dolist (id '("source-property-id" "source-root-id"))
        (should (string-search id old))
        (should-not (string-search id new))))))

(ert-deftest my-diario-test-narrowed-visiting-buffers ()
  (my-diario-test--with-files
    (let ((source-buf (find-file-noselect source))
          (target-buf (find-file-noselect target)))
      (with-current-buffer source-buf
        (goto-char (point-min))
        (forward-line 3)
        (narrow-to-region (line-beginning-position) (line-end-position)))
      (with-current-buffer target-buf
        (goto-char (point-min))
        (narrow-to-region (point) (line-end-position)))
      (my-diario-roll source target later "20260603")
      (should (with-current-buffer source-buf (buffer-narrowed-p)))
      (should (with-current-buffer target-buf (buffer-narrowed-p)))
      (should (string-search "** TODO Trabajo" (my-diario-test--text target))))))

(ert-deftest my-diario-test-no-cascade-or-duplicated-cold-id ()
  (my-diario-test--with-files
    (my-diario-test--replace source "*** COLD Frío OT\nSCHEDULED: <2026-06-10 Wed>\n"
                             "*** COLD Frío OT\nSCHEDULED: <2026-06-10 Wed>\n**** TODO Paso propio\n:PROPERTIES:\n:ID: cold-child-id\n:END:\n")
    (my-diario-roll source target later "20260610")
    (let ((new (my-diario-test--text target))
          (old (my-diario-test--text source))
          (parked (my-diario-test--text later)))
      (should (string-search "*** NEXT Frío OT" new))
      (should (string-search "**** TODO Paso propio" new))
      (should (string-search "**** TODO Paso propio" old))
      (should (string-search ":ID: cold-child-id" old))
      (should-not (string-search ":ID: cold-child-id" new))
      (should-not (string-search "Frío OT" parked)))))

(ert-deftest my-diario-test-stale-later-bucket-refuses-return ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (my-diario-test--replace later ":DIARIO_BUCKET: Empresa"
                             ":DIARIO_BUCKET: NoExiste")
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n* SHALLOW\n")
    (let ((before (my-diario-test--text target))
          (parked (my-diario-test--text later)))
      (should-error (my-diario-return target later "20260620")
                    :type 'user-error)
      (should (equal before (my-diario-test--text target)))
      (should (equal parked (my-diario-test--text later))))))

(ert-deftest my-diario-test-reject-orphan-later-heading ()
  (my-diario-test--with-files
    (with-temp-file later
      (insert "* LUEGO\n*** COLD Nivel huérfano\nSCHEDULED: <2026-06-03 Wed>\n"))
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n* SHALLOW\n")
    (let ((before (my-diario-test--text target)))
      (should-error (my-diario-return target later "20260603")
                    :type 'user-error)
      (should (equal before (my-diario-test--text target))))))

(ert-deftest my-diario-test-reject-tampered-later-origin ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (my-diario-test--replace later ":DIARIO_LIST: SHALLOW"
                             ":DIARIO_LIST: DEEP")
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n* SHALLOW\n")
    (let ((before (my-diario-test--text target))
          (parked (my-diario-test--text later)))
      (should-error (my-diario-return target later "20260620")
                    :type 'user-error)
      (should (equal before (my-diario-test--text target)))
      (should (equal parked (my-diario-test--text later))))))

(ert-deftest my-diario-test-reject-invalid-later-date ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (my-diario-test--replace later "SCHEDULED: <2026-06-10 Wed>"
                             "SCHEDULED: <2026-02-31 Sun>")
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n* SHALLOW\n")
    (let ((before (my-diario-test--text target))
          (parked (my-diario-test--text later)))
      (should-error (my-diario-return target later "20260620")
                    :type 'user-error)
      (should (equal before (my-diario-test--text target)))
      (should (equal parked (my-diario-test--text later))))))

(ert-deftest my-diario-test-conflicting-disk-change ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save))
          (changed nil))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (when (and (equal path target) (not changed))
                     (setq changed t)
                     (my-diario-test--replace target "#+title: Hoy"
                                              "#+title: Editado externamente"))
                   (funcall save path expected text))))
        (should-error (my-diario-roll source target later "20260603")
                      :type 'user-error))
      (should (string-search "#+title: Editado externamente"
                             (my-diario-test--text target)))
      (should (string-search "** TODO Trabajo" (my-diario-test--text source))))))

(ert-deftest my-diario-test-reject-hardlink-paths ()
  (my-diario-test--with-files
    (delete-file target)
    (add-name-to-file source target)
    (let ((old (my-diario-test--text source)))
      (let ((reason (should-error (my-diario-roll source target later "20260603")
                                  :type 'user-error)))
        (should (string-match-p "distinct" (error-message-string reason))))
      (should (file-equal-p source target))
      (should (equal old (my-diario-test--text source)))
      (should-not (file-exists-p later)))))

(ert-deftest my-diario-test-reject-symlink-later ()
  (my-diario-test--with-files
    (let ((backing (expand-file-name "backing.org" dir)))
      (with-temp-file backing (insert "* LUEGO\n"))
      (make-symbolic-link backing later)
      (let ((old (my-diario-test--text source)))
        (should-error (my-diario-park source later "20260603")
                      :type 'user-error)
        (should (file-symlink-p later))
        (should (equal "* LUEGO\n" (my-diario-test--text backing)))
        (should (equal old (my-diario-test--text source)))))))

(ert-deftest my-diario-test-reject-unclassified-tasks ()
  (my-diario-test--with-files
    (my-diario-test--replace source "* Notas\n"
                             "* TASKS\n** PROG Pendiente sin clasificar\n* Notas\n")
    (let ((old (my-diario-test--text source))
          (new (my-diario-test--text target)))
      (should-error (my-diario-roll source target later "20260603")
                    :type 'user-error)
      (should (equal old (my-diario-test--text source)))
      (should (equal new (my-diario-test--text target)))
      (should-not (file-exists-p later)))))

(ert-deftest my-diario-test-reject-conflicts-and-legacy ()
  (my-diario-test--with-files
    (let ((old (my-diario-test--text source)))
      (with-current-buffer (find-file-noselect target)
        (goto-char (point-max))
        (insert "unsaved"))
      (should-error (my-diario-roll source target later "20260603"))
      (should (equal old (my-diario-test--text source))))
    (with-current-buffer (get-file-buffer target) (set-buffer-modified-p nil))
    (kill-buffer (get-file-buffer target))
    (my-diario-test--replace source "** NEXT Ligero" "** PROG Ligero")
    (should-error (my-diario-roll source target later "20260603"))
    (should-not (file-exists-p later))
    (my-diario-test--replace source "** PROG Ligero" "** NEXT Ligero")
    (with-temp-file later (insert "* TASKS\n** PROG Legacy\nSCHEDULED: <2026-06-03 Wed>\n"))
    (should-error (my-diario-roll source target later "20260603"))
    (should (string-match-p "Legacy" (my-diario-test--text later)))))

(ert-deftest my-diario-test-no-duplicate-org-id-and-existing-target ()
  (my-diario-test--with-files
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n** TODO Usuario\n* SHALLOW\n")
    (let ((before (my-diario-test--text target)))
      (my-diario-roll source target later "20260603")
      (should (equal before (my-diario-test--text target)))
      (should (string-search "** TODO Trabajo" (my-diario-test--text source))))))

(ert-deftest my-diario-test-keyless-recursive-cleanup ()
  (my-diario-test--with-files
    (my-diario-test--replace source "**** TODO Detalle anidado\n"
                             "**** TODO Detalle anidado\n:PROPERTIES:\n:DIARIO_KEY: nested-old\n:END:\n")
    (my-diario-test--replace source ":ID: note-original\n"
                             ":ID: note-original\n:DIARIO_KEY: note-old\n")
    (my-diario-test--replace source ":ID: ot-original\n"
                             ":ID: ot-original\n:DIARIO_KEY: ot-old\n")
    (my-diario-test--replace source ":ID: deep-original\n"
                             ":ID: deep-original\n:DIARIO_KEY: deep-old\n")
    (my-diario-roll source target later "20260603")
    (dolist (path (list source target))
      (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text path)))
      (should-not (string-search ":DIARIO_ROLL_HASH:" (my-diario-test--text path))))
    (should (string-search ":DIARIO_PARKED_TO:" (my-diario-test--text source)))
    (should (string-search ":DIARIO_KEY:" (my-diario-test--text later)))
    (should (= 0 (plist-get (my-diario-roll source target later "20260604") :moved)))))

(ert-deftest my-diario-test-duplicate-legacy-keys-in-diario ()
  (my-diario-test--with-files
    (my-diario-test--replace source "*** WAIT Primero :cliente_1:\n"
                             "*** WAIT Primero :cliente_1:\n:PROPERTIES:\n:DIARIO_KEY: legacy-duplicate\n:END:\n")
    (my-diario-test--replace source "** TODO Trabajo :cliente_2:\n"
                             "** TODO Trabajo :cliente_2:\n:PROPERTIES:\n:DIARIO_KEY: legacy-duplicate\n:END:\n")
    (should (= 4 (plist-get (my-diario-roll source target later "20260603") :moved)))
    (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text source)))
    (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text target)))))

(ert-deftest my-diario-test-pending-legacy-hash-before-key-cleanup ()
  (my-diario-test--with-files
    (my-diario-test--replace source "** TODO Trabajo :cliente_2:\n"
                             "** TODO Trabajo :cliente_2:\n:PROPERTIES:\n:DIARIO_KEY: old-fingerprint\n:END:\n")
    (let ((save (symbol-function 'my-diario--save)) (failed nil))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path before text)
                   (when (and (equal path target) (not failed))
                     (setq failed t) (error "Injected target save failure"))
                   (funcall save path before text))))
        (should-error (my-diario-roll source target later "20260603"))))
    (should (string-search ":DIARIO_KEY: old-fingerprint" (my-diario-test--text source)))
    (should (string-search ":DIARIO_ROLL_HASH:" (my-diario-test--text source)))
    (should (= 4 (plist-get (my-diario-roll source target later "20260604") :moved)))
    (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text source)))
    (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text target)))))

(ert-deftest my-diario-test-return-freezes-date-on-next-day-retry ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (my-diario-test--replace target "#+identifier: hoy-id\n\n"
                             "#+identifier: hoy-id\n\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n* DEEP\n* SHALLOW\n")
    (let ((save (symbol-function 'my-diario--save)))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path before text)
                   (if (equal path target) (error "Injected destination save failure")
                     (funcall save path before text)))))
        (should-error (my-diario-return target later "20260620"))))
    (should (string-search ":DIARIO_ROLL_TO:" (my-diario-test--text later)))
    (should (string-search ":DIARIO_RETURN_DATE: 20260620" (my-diario-test--text later)))
    (should (= 3 (plist-get (my-diario-return target later "20260621") :returned)))
    (should (= 3 (my-diario-test--count ":DIARIO_ACTUAL_RETURN: [2026-06-20"
                                       (my-diario-test--text target))))
    (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text target)))))

(ert-deftest my-diario-test-cleanup-interruption-retries ()
  (my-diario-test--with-files
    (my-diario-test--replace source ":ID: ot-original\n"
                             ":ID: ot-original\n:DIARIO_KEY: cleanup-ot\n")
    (let ((clean (symbol-function 'my-diario-clean)) (failed nil))
      (cl-letf (((symbol-function 'my-diario-clean)
                 (lambda (path)
                   (when (and (equal path target) (not failed))
                     (setq failed t) (error "Injected cleanup failure"))
                   (funcall clean path))))
        (should-error (my-diario-roll source target later "20260603"))))
    (should-not (string-search "** TODO Trabajo" (my-diario-test--text source)))
    (should (string-search ":DIARIO_KEY:" (my-diario-test--text target)))
    (my-diario-roll source target later "20260604")
    (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text target)))
    (should (= 1 (my-diario-test--count "** TODO Trabajo" (my-diario-test--text target))))))

(ert-deftest my-diario-test-keyless-active-receipt-on-failure ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save)))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (if (equal path target)
                       (error "Injected destination failure")
                     (funcall save path expected text)))))
        (should-error (my-diario-roll source target later "20260603"))))
    (let ((old (my-diario-test--text source)))
      (should (string-search "DIARIO_ROLL_HASH:" old))
      (my-diario--with-text old
        (dolist (entry (my-diario--scan))
          (when (member (my-diario--entry-state entry) my-diario--active)
            (should-not (my-diario--entry-key entry)))))
      (should-error (my-diario-clean source) :type 'user-error)
      (should (equal old (my-diario-test--text source))))
    (should (= 4 (plist-get (my-diario-roll source target later "20260603") :moved)))))

(ert-deftest my-diario-test-pending-transfer-scope-and-adjacency ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save)))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (if (equal path target) (error "Injected destination failure")
                     (funcall save path expected text)))))
        (should-error (my-diario-roll source target later "20260603"))))
    (with-temp-file target
      (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
              "* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n"
              "* DEEP\n** TODO Manual :cliente_2:\nManual.\n"
              "** TODO Trabajo :cliente_2:\nContenido editado.\n"
              "** TODO Archivo :cliente_3:\nArchivo.\n"
              "* SHALLOW\n** TODO Igual\n:PROPERTIES:\n:CUSTOM: diferente\n:END:\n"))
    (should (= 4 (plist-get (my-diario-roll source target later "20260604") :moved)))
    (let ((new (my-diario-test--text target)))
      (should (< (string-search "** TODO Manual" new)
                 (string-search "Contenido editado." new)
                 (string-search "Contenido profundo." new)
                 (string-search "** TODO Archivo" new)
                 (string-search "* SHALLOW" new)))
      (should (= 2 (my-diario-test--count "** TODO Trabajo" new)))
      (should (= 2 (my-diario-test--count "** TODO Igual\n" new)))
      (should (= 4 (my-diario-test--count
                    "# DIARIO: copias con contenido distinto; revisar ambas." new)))
      (should-not (string-search "*** WAIT Primero" new))
      (should-not (string-search ":DIARIO_KEY:" new)))
    (should-not (string-search "** TODO Trabajo" (my-diario-test--text source)))))

(ert-deftest my-diario-test-park-conflicting-key-allocates-new ()
  (my-diario-test--with-files
    (my-diario-test--replace source "** COLD Frío superficial\n"
                             "** COLD Frío superficial\n:PROPERTIES:\n:DIARIO_KEY: parked-collision\n:END:\n")
    (with-temp-file later
      (insert "* LUEGO\n** COLD Frío superficial\n"
              "SCHEDULED: <2026-06-17 Wed>\n:PROPERTIES:\n"
              ":DIARIO_KEY: parked-collision\n:DIARIO_LIST: SHALLOW\n"
              (format ":DIARIO_ORIGIN_HASH: %s\n"
                      (my-diario--origin-hash "parked-collision" "SHALLOW" nil))
              ":END:\nNota previa.\n"))
    (should (= 3 (plist-get (my-diario-park source later "20260603") :parked)))
    (let ((text (my-diario-test--text later)) copies)
      (my-diario--with-text text
        (dolist (entry (my-diario--later-scan))
          (when (and (equal (my-diario--entry-list entry) "SHALLOW")
                     (save-excursion
                       (goto-char (my-diario--entry-start entry))
                       (equal (org-get-heading t t t t) "Frío superficial")))
            (push (my-diario--entry-key entry) copies)
            (goto-char (my-diario--entry-start entry))
            (should (equal (org-entry-get nil "DIARIO_ORIGIN_HASH")
                           (my-diario--origin-hash (my-diario--entry-key entry)
                                                   "SHALLOW" nil))))))
      (should (= 2 (length copies)))
      (should (member "parked-collision" copies))
      (should (= 2 (my-diario-test--count "** COLD Frío superficial" text)))
      (should (= 2 (my-diario-test--count
                    "# DIARIO: copias con contenido distinto; revisar ambas." text)))
      (should (string-search "Nota previa." text))
      (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text source)))
      (should (string-search ":DIARIO_PARKED_TO:" (my-diario-test--text source)))
      (should (= 0 (plist-get (my-diario-park source later "20260604") :parked)))
      (should (equal text (my-diario-test--text later))))))

(ert-deftest my-diario-test-park-origin-scope-and-exact-reuse ()
  (my-diario-test--with-files
    (my-diario-test--replace source "*** DONE Cerrado\n"
                             "*** COLD Frío OT :cliente_a:\nSCHEDULED: <2026-06-10 Wed>\nContratista.\n*** DONE Cerrado\n")
    (my-diario-test--replace source "*** COLD Frío OT\nSCHEDULED: <2026-06-10 Wed>\n"
                             "*** COLD Frío OT :cliente_a:\nSCHEDULED: <2026-06-10 Wed>\nEmpresa.\n")
    (my-diario-test--replace source "** COLD Frío profundo\n"
                             "** COLD Frío profundo\n** COLD Frío superficial\nLista profunda.\n")
    (should (= 5 (plist-get (my-diario-park source later "20260603") :parked)))
    (let ((parked (my-diario-test--text later)))
      (should (= 2 (my-diario--with-text parked
                     (cl-count-if (lambda (entry)
                                    (equal (my-diario--entry-list entry)
                                           "OPORTUNIDADES Y AMENAZAS"))
                                  (my-diario--later-scan)))))
      (should-not (string-search "# DIARIO:" parked)))
    (with-temp-file target
      (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
              "* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n"
              "* DEEP\n* SHALLOW\n"))
    (should (= 5 (plist-get (my-diario-return target later "20260620") :returned)))
    (let ((new (my-diario-test--text target)))
      (my-diario--with-text new
        (let ((entries (my-diario--scan)))
          (dolist (case '(("Contratista" . "Contratista.")
                          ("Empresa" . "Empresa.")))
            (should (cl-some (lambda (entry)
                               (and (equal (my-diario--entry-bucket entry) (car case))
                                    (string-search (cdr case)
                                                   (my-diario--subtree new entry))))
                             entries)))
          (should (cl-some (lambda (entry)
                             (and (equal (my-diario--entry-list entry) "DEEP")
                                  (string-search "Lista profunda."
                                                 (my-diario--subtree new entry))))
                           entries))))
      (should (= 2 (my-diario-test--count "** NEXT Frío superficial" new)))
      (should-not (string-search "# DIARIO:" new)))))

(ert-deftest my-diario-test-legacy-return-unique-date-and-ambiguous ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (let* ((parked (my-diario-test--text later))
           (entry (my-diario--with-text parked
                    (cl-find-if (lambda (item)
                                  (equal (my-diario--entry-list item) "SHALLOW"))
                                (my-diario--later-scan))))
           (returned (my-diario--returned (my-diario--subtree parked entry)
                                          entry "20260620")))
      (with-temp-file target
        (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
                "* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n"
                "* DEEP\n* SHALLOW\n" returned))
      (let ((before (my-diario-test--text target)))
        (with-temp-file target (insert before returned))
        (let ((ambiguous (my-diario-test--text target)))
          (should-error (my-diario-return target later "20260621")
                        :type 'user-error)
          (should (equal ambiguous (my-diario-test--text target)))
          (should (equal parked (my-diario-test--text later)))))
      (with-temp-file target (insert (substring (my-diario-test--text target)
                                             0 (- (length (my-diario-test--text target))
                                                  (length returned)))))
      (should (= 2 (plist-get (my-diario-return target later "20260621") :returned)))
      (let ((new (my-diario-test--text target)))
        (should (= 1 (my-diario-test--count "** NEXT Frío superficial" new)))
        (should (= 1 (my-diario-test--count ":DIARIO_ACTUAL_RETURN: [2026-06-20" new)))
        (should-not (string-search ":DIARIO_KEY:" new)))
      (should-not (string-search "Frío superficial" (my-diario-test--text later))))))

(ert-deftest my-diario-test-pending-return-rejects-other-target ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (with-temp-file target
      (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
              "* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n"
              "* DEEP\n* SHALLOW\n"))
    (let ((save (symbol-function 'my-diario--save)))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (if (equal path target) (error "Injected destination failure")
                     (funcall save path expected text)))))
        (should-error (my-diario-return target later "20260620"))))
    (let* ((next (expand-file-name "20260621-journal.org" dir))
           (original (my-diario-test--text target))
           (pending (my-diario-test--text later)))
      (with-temp-file next (insert original))
      (should-error (my-diario-return next later "20260621") :type 'user-error)
      (should (equal original (my-diario-test--text next)))
      (should (equal pending (my-diario-test--text later)))
      (should (= 3 (plist-get (my-diario-return target later "20260621") :returned)))
      (should (= 3 (my-diario-test--count ":DIARIO_ACTUAL_RETURN: [2026-06-20"
                                         (my-diario-test--text target)))))))

(ert-deftest my-diario-test-return-cleanup-failure-retry ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (with-temp-file target
      (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
              "* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n"
              "* DEEP\n* SHALLOW\n"))
    (let ((clean (symbol-function 'my-diario-clean)))
      (cl-letf (((symbol-function 'my-diario-clean)
                 (lambda (path)
                   (if (equal path target) (error "Injected cleanup failure")
                     (funcall clean path)))))
        (should-error (my-diario-return target later "20260620"))))
    (should-not (string-search "Frío superficial" (my-diario-test--text later)))
    (should (string-search ":DIARIO_KEY:" (my-diario-test--text target)))
    (should (= 0 (plist-get (my-diario-return target later "20260621") :returned)))
    (should-not (string-search ":DIARIO_KEY:" (my-diario-test--text target)))))

(ert-deftest my-diario-test-verify-saved-target-before-prune ()
  (my-diario-test--with-files
    (let ((save (symbol-function 'my-diario--save)) (changed nil))
      (cl-letf (((symbol-function 'my-diario--save)
                 (lambda (path expected text)
                   (prog1 (funcall save path expected text)
                     (when (and (equal path target) (not changed))
                       (setq changed t)
                       (my-diario-test--replace target "Contenido profundo."
                                                "Contenido intervenido."))))))
        (should-error (my-diario-roll source target later "20260603")
                      :type 'user-error)))
    (should (string-search "** TODO Trabajo" (my-diario-test--text source)))
    (should (string-search "Contenido intervenido." (my-diario-test--text target)))
    (should (= 4 (plist-get (my-diario-roll source target later "20260603") :moved)))
    (should (= 2 (my-diario-test--count "** TODO Trabajo"
                                       (my-diario-test--text target))))))

(ert-deftest my-diario-test-clean-refuses-unsaved-or-stale-visitor ()
  (my-diario-test--with-files
    (my-diario-test--replace source ":ID: ot-original\n"
                             ":ID: ot-original\n:DIARIO_KEY: old-note\n")
    (let ((visitor (find-file-noselect source))
          (before (my-diario-test--text source)))
      (with-current-buffer visitor
        (goto-char (point-max)) (insert "Cambio sin guardar"))
      (should-error (my-diario-clean source) :type 'user-error)
      (should (equal before (my-diario-test--text source)))
      (with-current-buffer visitor
        (set-buffer-modified-p nil))
      (my-diario-test--replace source "Texto del día." "Texto alterado afuera.")
      (should-error (my-diario-clean source) :type 'user-error)
      (should (string-search ":DIARIO_KEY: old-note" (my-diario-test--text source))))))

(ert-deftest my-diario-test-park-reuses-equal-without-sweeping ()
  (my-diario-test--with-files
    (my-diario-test--replace source "** COLD Frío superficial\n"
                             "** COLD Frío superficial\n** COLD Frío superficial\n")
    (should (= 3 (plist-get (my-diario-park source later "20260603") :parked)))
    (let ((old (my-diario-test--text source))
          (parked (my-diario-test--text later)))
      (should (= 2 (my-diario-test--count "** COLD Frío superficial" old)))
      (should (= 1 (my-diario-test--count "** COLD Frío superficial" parked)))
      (should-not (string-search "# DIARIO:" parked))
      (should-not (string-search ":DIARIO_KEY:" old))
      (should (= 0 (plist-get (my-diario-park source later "20260604") :parked)))
      (should (equal parked (my-diario-test--text later))))))

(ert-deftest my-diario-test-luego-duplicate-key-stays-blocked ()
  (my-diario-test--with-files
    (my-diario-park source later "20260603")
    (let* ((text (my-diario-test--text later))
           (entry (my-diario--with-text text (car (my-diario--later-scan)))))
      (with-temp-file later (insert text (my-diario--subtree text entry))))
    (with-temp-file target
      (insert "#+title: Hoy\n#+identifier: hoy-id\n\n"
              "* OPORTUNIDADES Y AMENAZAS\n** Contratista\n** Empresa\n"
              "* DEEP\n* SHALLOW\n"))
    (let ((before (my-diario-test--text target))
          (parked (my-diario-test--text later)))
      (should-error (my-diario-return target later "20260620")
                    :type 'user-error)
      (should (equal before (my-diario-test--text target)))
      (should (equal parked (my-diario-test--text later))))))

(ert-deftest my-diario-test-one-placement-pass ()
  (my-diario-test--with-files
    (let ((place (symbol-function 'my-diario--transfers))
          (calls 0))
      (cl-letf (((symbol-function 'my-diario--transfers)
                 (lambda (&rest arguments)
                   (cl-incf calls)
                   (apply place arguments))))
        (my-diario-roll source target later "20260603"))
      (should (= 1 calls)))))

(provide 'test-diario-rollover)
;;; test-diario-rollover.el ends here
