;;; test-diario-match.el --- Conservative diario matching fixtures -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'org)
(require 'diario-match)

(defmacro my-dmt--with-org (text &rest body)
  "Run BODY in an isolated Org buffer containing TEXT."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (let ((org-mode-hook nil)
           (org-inhibit-startup t)
           (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "SDM" "COLD"
                                         "|" "DONE" "KILL")))
           (my-diario-customer-tags nil))
       (org-mode)
       (insert ,text)
       (goto-char (point-min))
       ,@body)))

(defun my-dmt--place (incoming)
  "Place INCOMING among direct entries under the first heading at point."
  (goto-char (point-min))
  (let ((end (copy-marker (save-excursion (org-end-of-subtree t t)) t))
        starts)
    (forward-line 1)
    (while (re-search-forward "^\\*\\* " (marker-position end) t)
      (push (copy-marker (line-beginning-position)) starts)
      (forward-line 1))
    (my-dm-place incoming (nreverse starts) end)))

(defun my-dmt--count (needle text)
  "Count literal NEEDLE in TEXT."
  (let ((pos 0) (count 0))
    (while (string-match (regexp-quote needle) text pos)
      (setq pos (match-end 0)
            count (1+ count)))
    count))

(ert-deftest my-diario-match-test-id-local-sorted-and-case ()
  (my-dmt--with-org
      "* DEEP :inherited:\n** NEXT [#A] Cotizar X :clienteB:clienteA:journal:x:\n:PROPERTIES:\n:DIARIO_CONTEXT_TAGS: :clienteB:\n:END:\n** TODO [#B] Cotizar X :clienteA:\n** TODO cotizar X :clienteA:\n** TODO Cotizar X :clienteB:\n** TODO Cotizar X\n"
    (let (ids)
      (while (re-search-forward "^\\*\\* " nil t)
        (push (my-dm--id) ids))
      (setq ids (nreverse ids))
      (should (equal (nth 0 ids) (nth 1 ids)))
      (should-not (equal (nth 1 ids) (nth 2 ids)))
      (should-not (equal (nth 1 ids) (nth 3 ids)))
      (should-not (equal (nth 3 ids) (nth 4 ids)))
      (should (equal (nth 4 ids) '("Cotizar X"))))))

(ert-deftest my-diario-match-test-id-sorted-full-tags ()
  (my-dmt--with-org
      "* DEEP\n** TODO Pagar :otro_2:cliente_1:\n** WAIT [#A] Pagar :cliente_1:otro_2:\n** TODO Pagar :cliente_1:otro_3:\n"
    (let (ids)
      (while (re-search-forward "^\\*\\* " nil t)
        (push (my-dm--id) ids))
      (setq ids (nreverse ids))
      (should (equal (nth 0 ids) (nth 1 ids)))
      (should-not (equal (nth 1 ids) (nth 2 ids))))))

(ert-deftest my-diario-match-test-text-transport-and-levels ()
  (let ((a "** TODO [#A] Cotizar :cliente:\nSCHEDULED: <2026-06-05 Fri>\n:PROPERTIES:\n:DIARIO_KEY: first\n:DIARIO_ROLL_TO: next\n:DIARIO_ROLL_HASH: hash\n:DIARIO_PARK_DATE: 2026-06-19\n:DIARIO_PARKED_TO: LUEGO\n:DIARIO_LIST: DEEP\n:DIARIO_BUCKET: Empresa\n:DIARIO_ORIGIN_HASH: old\n:DIARIO_EXPORTS: old\n:DIARIO_EXPORT_PENDING: old\n:DIARIO_IMPORT_DEST: DEEP\n:DIARIO_EXPORT_HASH: old\n:DIARIO_RETURN_DATE: old\n:END:\n# DIARIO: copias con contenido distinto; revisar ambas.\nNota intacta.\n*** TODO Paso\n:PROPERTIES:\n:DIARIO_KEY: nested\n:END:\nTexto.\n")
        (b "*** TODO [#A] Cotizar :cliente:\nSCHEDULED: <2026-06-05 Fri>\nNota intacta.\n**** TODO Paso\nTexto.\n"))
    (should (equal (my-dm-text a) (my-dm-text b)))
    (should (string-search "SCHEDULED: <2026-06-05 Fri>" (my-dm-text a)))
    (should-not (string-search ":PROPERTIES:" (my-dm-text a)))))

(ert-deftest my-diario-match-test-text-preserves-meaningful-changes ()
  (let ((base "** TODO [#A] Cotizar :cliente:journal:\nSCHEDULED: <2026-06-05 Fri>\n:PROPERTIES:\n:DIARIO_CONTEXT_TAGS: :plan:\n:DIARIO_REF_KEY: referred\n:DIARIO_PLANNED_RETURN: [2026-05-31 Sun]\n:DIARIO_ACTUAL_RETURN: [2026-06-03 Wed]\n:DIARIO_FUTURE: keep\n:CUSTOM: valor\n:END:\nNotas  con espacios.\n*** TODO Paso\nTexto.\n"))
    (dolist (changed '("** WAIT [#A] Cotizar :cliente:journal:"
                       "** TODO [#B] Cotizar :cliente:journal:"
                       "** TODO [#A] Cotizar :cliente:otro:"
                       "SCHEDULED: <2026-06-06 Sat>"
                       ":DIARIO_CONTEXT_TAGS: :otro:"
                       ":DIARIO_REF_KEY: distinto"
                       ":DIARIO_PLANNED_RETURN: [2026-06-01 Mon]"
                       ":DIARIO_ACTUAL_RETURN: [2026-06-04 Thu]"
                       ":DIARIO_FUTURE: cambiado"
                       ":CUSTOM: diferente"
                       "Notas con espacios."
                       "*** NEXT Paso"
                       "Texto cambiado."))
      (let* ((original (cond
                        ((string-prefix-p "** " changed)
                         "** TODO [#A] Cotizar :cliente:journal:")
                        ((string-prefix-p "*** " changed) "*** TODO Paso")
                        ((string-prefix-p "Notas" changed) "Notas  con espacios.")
                        ((string-prefix-p "Texto" changed) "Texto.")
                        (t changed)))
             (line (cond
                    ((string-prefix-p "SCHEDULED" changed)
                     "SCHEDULED: <2026-06-05 Fri>")
                    ((string-prefix-p ":DIARIO_CONTEXT_TAGS" changed)
                     ":DIARIO_CONTEXT_TAGS: :plan:")
                    ((string-prefix-p ":DIARIO_REF_KEY" changed)
                     ":DIARIO_REF_KEY: referred")
                    ((string-prefix-p ":DIARIO_PLANNED_RETURN" changed)
                     ":DIARIO_PLANNED_RETURN: [2026-05-31 Sun]")
                    ((string-prefix-p ":DIARIO_ACTUAL_RETURN" changed)
                     ":DIARIO_ACTUAL_RETURN: [2026-06-03 Wed]")
                    ((string-prefix-p ":DIARIO_FUTURE" changed)
                     ":DIARIO_FUTURE: keep")
                    ((string-prefix-p ":CUSTOM" changed) ":CUSTOM: valor")
                    (t original))))
        (should-not (equal (my-dm-text base)
                           (my-dm-text (replace-regexp-in-string
                                        (regexp-quote line) changed base t t))))))))

(ert-deftest my-diario-match-test-text-final-newline-only ()
  (should (equal (my-dm-text "** TODO Nota\nTexto.")
                 (my-dm-text "** TODO Nota\nTexto.\n")))
  (should-not (equal (my-dm-text "** TODO Nota\nTexto.\n\n")
                     (my-dm-text "** TODO Nota\nTexto.\n")))
  (should-not (equal (my-dm-text "** TODO Nota\nTexto. \n")
                     (my-dm-text "** TODO Nota\nTexto.\n"))))

(ert-deftest my-diario-match-test-text-other-comments-are-content ()
  (let ((base "** TODO Cotizar\nNota.\n")
        (lower "** TODO Cotizar\n# diario: copias con contenido distinto; revisar ambas.\nNota.\n"))
    (should-not (equal (my-dm-text base) (my-dm-text lower)))))

(ert-deftest my-diario-match-test-text-only-real-headings ()
  (let ((a "** TODO Código\n#+begin_src text\n,* TODO literalmente en un bloque\n#+end_src\n*** TODO Hijo\n")
        (b "*** TODO Código\n#+begin_src text\n,* TODO literalmente en un bloque\n#+end_src\n**** TODO Hijo\n"))
    (should (equal (my-dm-text a) (my-dm-text b)))
    (should (string-search ",* TODO literalmente en un bloque" (my-dm-text a)))))

(ert-deftest my-diario-match-test-place-exact-first-in-scope ()
  (my-dmt--with-org
      "* DEEP\n** TODO Cotizar :cliente:\nVieja.\n** TODO Otra\nOtra.\n** NEXT Cotizar :cliente:\nIgual.\n* SHALLOW\n** NEXT Cotizar :cliente:\nIgual.\n"
    (let* ((before (buffer-string))
           (placed (my-dmt--place "** NEXT Cotizar :cliente:\nIgual.\n")))
      (should (eq (plist-get placed :result) 'exact))
      (should (markerp (plist-get placed :start)))
      (should (= (marker-position (plist-get placed :start))
                 (save-excursion
                   (goto-char (point-min))
                   (search-forward "** NEXT Cotizar :cliente:")
                   (line-beginning-position))))
      (should (equal before (buffer-string))))))

(ert-deftest my-diario-match-test-place-after-whole-first-subtree ()
  (my-dmt--with-org
      "* DEEP\n** TODO Cotizar :cliente:\nSCHEDULED: <2026-06-05 Fri>\n:PROPERTIES:\n:CUSTOM: fijo\n:END:\nNota 1.\n*** TODO Paso\nDetalle.\n** NEXT Otra\nMás.\n** WAIT Cotizar :cliente:\nNota 3.\n* SHALLOW\n** TODO Cotizar :cliente:\nFuera.\n"
    (let* ((incoming "** TODO Cotizar :cliente:\n:PROPERTIES:\n:DIARIO_KEY: transport\n:END:\nNota 2.\n")
           (placed (my-dmt--place incoming))
           (text (buffer-string))
           (warning "# DIARIO: copias con contenido distinto; revisar ambas."))
      (should (eq (plist-get placed :result) 'conflict))
      (should (markerp (plist-get placed :start)))
      (should (< (string-search "*** TODO Paso" text)
                 (marker-position (plist-get placed :start))
                 (string-search "** NEXT Otra" text)))
      (should (string-search
               "SCHEDULED: <2026-06-05 Fri>\n:PROPERTIES:\n:CUSTOM: fijo\n:END:\n# DIARIO: copias con contenido distinto; revisar ambas.\nNota 1."
               text))
      (should (string-search
               "** TODO Cotizar :cliente:\n:PROPERTIES:\n:DIARIO_KEY: transport\n:END:\n# DIARIO: copias con contenido distinto; revisar ambas.\nNota 2."
               text))
      (should (= 2 (my-dmt--count warning text)))
      (should (= 1 (my-dmt--count "*** TODO Paso" text)))
      (let ((again (my-dmt--place incoming)))
        (should (eq (plist-get again :result) 'exact))
        (should (equal text (buffer-string)))))))

(ert-deftest my-diario-match-test-place-empty-first-keeps-markers ()
  (my-dmt--with-org
      "* DEEP\n** TODO Cotizar :cliente:\n** NEXT Otra\n* SHALLOW\n"
    (let* ((first (progn (search-forward "** TODO Cotizar")
                         (copy-marker (line-beginning-position))))
           (second (progn (search-forward "** NEXT Otra")
                          (copy-marker (line-beginning-position))))
           (end (progn (search-forward "* SHALLOW")
                       (copy-marker (line-beginning-position))))
           (placed (my-dm-place "** WAIT Cotizar :cliente:\nNota.\n"
                                (list first second) end))
           (text (buffer-string)))
      (should (eq (plist-get placed :result) 'conflict))
      (should (string-search
               "** TODO Cotizar :cliente:\n# DIARIO: copias con contenido distinto; revisar ambas.\n** WAIT Cotizar :cliente:\n# DIARIO: copias con contenido distinto; revisar ambas.\nNota.\n** NEXT Otra"
               text))
      (should (save-excursion (goto-char second) (looking-at "\\*\\* NEXT Otra")))
      (should (save-excursion (goto-char end) (looking-at "\\* SHALLOW")))
      (should (save-excursion
                (goto-char (plist-get placed :start))
                (looking-at "\\*\\* WAIT Cotizar")))
      (let ((another (my-dm-place "** WAIT Cotizar :cliente:\nNota 2.\n"
                                  (list first (plist-get placed :start) second) end)))
        (should (eq (plist-get another :result) 'conflict))
        (should (= 3 (my-dmt--count
                      "# DIARIO: copias con contenido distinto; revisar ambas."
                      (buffer-string))))))))

(ert-deftest my-diario-match-test-place-no-final-newline ()
  (my-dmt--with-org "* DEEP\n** TODO Cotizar\n* SHALLOW\n"
    (let* ((incoming "** WAIT Cotizar")
           (placed (my-dmt--place incoming))
           (after (buffer-string)))
      (should (eq (plist-get placed :result) 'conflict))
      (should (string-search
               "** TODO Cotizar\n# DIARIO: copias con contenido distinto; revisar ambas.\n** WAIT Cotizar\n# DIARIO: copias con contenido distinto; revisar ambas.\n* SHALLOW"
               after))
      (should (eq (plist-get (my-dmt--place incoming) :result) 'exact))
      (should (equal after (buffer-string))))))

(ert-deftest my-diario-match-test-place-append-no-final-newline ()
  (my-dmt--with-org "* DEEP\n* SHALLOW\n"
    (let* ((incoming "** TODO Nuevo\nNota sin salto final.")
           (first (my-dmt--place incoming))
           (after (buffer-string)))
      (should (eq (plist-get first :result) 'inserted))
      (should (eq (plist-get (my-dmt--place incoming) :result) 'exact))
      (should (equal after (buffer-string))))))

(ert-deftest my-diario-match-test-place-append-without-identity ()
  (my-dmt--with-org
      "* DEEP\n** TODO Cotizar :cliente_1:\nTexto.\n** TODO Otro\nOtro.\n* SHALLOW\n** TODO Cotizar :cliente_2:\nFuera.\n"
    (let ((placed (my-dmt--place "** NEXT Cotizar :cliente_2:\nEntrante.\n")))
      (should (eq (plist-get placed :result) 'inserted))
      (should (string-search "** TODO Otro\nOtro.\n** NEXT Cotizar :cliente_2:\nEntrante.\n* SHALLOW" (buffer-string)))
      (should-not (string-search "# DIARIO:" (buffer-string))))))

(ert-deftest my-diario-match-test-clean-recursive-and-parked ()
  (let* ((text "* DEEP\n** TODO Vivo\n:PROPERTIES:\n:DIARIO_KEY: main\n:DIARIO_REF_KEY: referred\n:DIARIO_EXPORTS: receipts\n:END:\n*** Nota\n:PROPERTIES:\n:DIARIO_KEY: note\n:END:\n** COLD Aparcado\n:PROPERTIES:\n:DIARIO_KEY: parked\n:DIARIO_PARKED_TO: LUEGO.org\n:DIARIO_ROLL_HASH: consumed\n:DIARIO_PARK_DATE: 2026-06-19\n:DIARIO_PLANNED_RETURN: [2026-06-19 Fri]\n:END:\n*** TODO Hijo\n:PROPERTIES:\n:DIARIO_KEY: child\n:DIARIO_FUTURE: still-here\n:END:\n")
         (clean (my-dm-clean text)))
    (should-not (string-search ":DIARIO_KEY:" clean))
    (should-not (string-search ":DIARIO_ROLL_HASH:" clean))
    (should-not (string-search ":DIARIO_PARK_DATE:" clean))
    (should (string-search "*** Nota\n** COLD" clean))
    (dolist (value '(":DIARIO_REF_KEY: referred" ":DIARIO_EXPORTS: receipts"
                     ":DIARIO_PARKED_TO: LUEGO.org"
                     ":DIARIO_PLANNED_RETURN: [2026-06-19 Fri]"
                     ":DIARIO_FUTURE: still-here"))
      (should (string-search value clean)))
    (should (equal clean (my-dm-clean clean)))))

(ert-deftest my-diario-match-test-clean-refuses-pending-before-change ()
  (dolist (property '("DIARIO_ROLL_TO" "DIARIO_ROLL_HASH"
                      "DIARIO_EXPORT_PENDING" "DIARIO_EXPORT_HASH"
                      "DIARIO_RETURN_DATE" "DIARIO_PARK_DATE"))
    (my-dmt--with-org
        (concat "* DEEP\n** TODO Anterior\n:PROPERTIES:\n:DIARIO_KEY: old\n:END:\n** TODO Pendiente\n:PROPERTIES:\n:DIARIO_KEY: pending\n:"
                property ": receipt\n:END:\n")
      (let ((before (buffer-string))
            deleted)
        (cl-letf (((symbol-function 'org-entry-delete)
                   (lambda (&rest _args) (setq deleted t))))
          (should-error (my-dm-clean before) :type 'user-error))
        (should-not deleted)
        (should (equal before (buffer-string)))
        (should (string-search ":DIARIO_KEY: old" (buffer-string)))
        (should (string-search ":DIARIO_KEY: pending" (buffer-string)))
        (should (string-search (concat ":" property ": receipt")
                               (buffer-string)))))))

(ert-deftest my-diario-match-test-clean-refuses-pending-parked ()
  (dolist (property '("DIARIO_ROLL_TO" "DIARIO_EXPORT_PENDING"
                      "DIARIO_EXPORT_HASH" "DIARIO_RETURN_DATE"))
    (should-error
     (my-dm-clean
      (concat "* DEEP\n** COLD Aparcado\n:PROPERTIES:\n"
              ":DIARIO_KEY: parked\n:DIARIO_PARKED_TO: LUEGO.org\n:"
              property ": pending\n:END:\n"))
     :type 'user-error)))

(ert-deftest my-diario-match-test-unmatched-skips-normalization ()
  (my-dmt--with-org "* DEEP\n** TODO Existente :cliente:\nNotas.\n* SHALLOW\n"
    (cl-letf (((symbol-function 'my-dm-text)
               (lambda (&rest _) (error "Unrelated tasks need no content comparison"))))
      (should (eq 'inserted
                  (plist-get (my-dmt--place "** TODO Nueva :otro:\nTexto.\n")
                             :result))))))

(provide 'test-diario-match)
;;; test-diario-match.el ends here
