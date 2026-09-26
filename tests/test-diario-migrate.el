;;; test-diario-migrate.el --- Isolated diario migration tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'org)
(require 'diario-migrate nil t)

(defconst my-dmig-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the modules for load-order tests.")

(defmacro my-dmig-test--with-org (text &rest body)
  "Run BODY in a disposable Org buffer containing TEXT."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (let ((org-mode-hook nil)
           (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "PROG"
                                         "SDM" "COLD" "|" "DONE" "KILL")))
           (org-inhibit-startup t))
       (org-mode))
     (insert ,text)
     (goto-char (point-min))
     (set-buffer-modified-p nil)
     (setq buffer-undo-list nil)
     (unwind-protect
         (progn ,@body)
       (set-buffer-modified-p nil))))

(ert-deftest my-diario-migrate-prepare-and-repeat ()
  (let ((original "#+title: Diario\n* TASKS\n** PROG Legado\n:PROPERTIES:\n:ID: abc\n:END:\nTexto.\n* Notas\nFuera de listas.\n"))
    (my-dmig-test--with-org original
      (my-diario-prepare)
      (let ((prepared (buffer-string)))
        (should (string-prefix-p original prepared))
        (should (string-match-p "^\\* OPORTUNIDADES Y AMENAZAS\n\\*\\* Empresa\n\\*\\* Contratista\n" prepared))
        (should (string-match-p "^\\* DEEP\n\\* SHALLOW\n" prepared))
        (should (= 1 (my-diario-legacy-count)))
        (my-diario-prepare)
        (should (equal prepared (buffer-string)))))))

(ert-deftest my-diario-migrate-prepare-existing-layout ()
  (my-dmig-test--with-org "* DEEP\n** TODO Trabajo\n* OPORTUNIDADES Y AMENAZAS\nContexto.\n** Contratista\n*** NEXT Encargo\n* SHALLOW\n* Notas\nTexto.\n"
    (my-diario-prepare)
    (should (= 1 (how-many "^\\* DEEP$" (point-min) (point-max))))
    (should (= 1 (how-many "^\\* SHALLOW$" (point-min) (point-max))))
    (should (= 1 (how-many "^\\*\\* Contratista$" (point-min) (point-max))))
    (should (= 1 (how-many "^\\*\\* Empresa$" (point-min) (point-max))))
    (should (string-match-p "Contexto\\.\n\\*\\* Contratista\n\\*\\*\\* NEXT Encargo\n\\*\\* Empresa\n\\* SHALLOW" (buffer-string)))
    (should (string-suffix-p "* Notas\nTexto.\n" (buffer-string)))))

(ert-deftest my-diario-migrate-bulk-same-title-and-order ()
  (my-dmig-test--with-org "* TASKS\n** TODO Igual :uno:\nPrimer cuerpo.\n** NEXT Igual :dos:\n:PROPERTIES:\n:ID: dos\n:END:\nSegundo cuerpo.\n** WAIT Sin clasificar\n* DEEP\n** TODO Ya presente\n* SHALLOW\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n* Notas\nNota exterior.\n"
    (goto-char (point-min))
    (search-forward "** TODO Igual")
    (beginning-of-line)
    (let ((beg (point)))
      (search-forward "** WAIT Sin clasificar")
      (beginning-of-line)
      (my-diario-classify "DEEP" beg (point)))
    (should (equal (buffer-string)
                   "* TASKS\n** WAIT Sin clasificar\n* DEEP\n** TODO Ya presente\n** TODO Igual :uno:\nPrimer cuerpo.\n** NEXT Igual :dos:\n:PROPERTIES:\n:ID: dos\n:END:\nSegundo cuerpo.\n* SHALLOW\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n* Notas\nNota exterior.\n"))
    (should (= 1 (my-diario-legacy-count)))))

(ert-deftest my-diario-migrate-ot-level-and-nested-notes ()
  (my-dmig-test--with-org "* TASKS\n** TODO Encargo :cliente:\nTexto [[denote:20260511T1358]].\n:LOGBOOK:\n- Nota.\n:END:\n*** Apunte anidado\nMás texto.\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n*** NEXT Otro\n* DEEP\n* SHALLOW\n"
    (goto-char (point-min))
    (search-forward "** TODO Encargo")
    (my-diario-classify "OT Contratista")
    (should (equal (buffer-string)
                   "* TASKS\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n*** NEXT Otro\n*** TODO Encargo :cliente:\nTexto [[denote:20260511T1358]].\n:LOGBOOK:\n- Nota.\n:END:\n**** Apunte anidado\nMás texto.\n* DEEP\n* SHALLOW\n"))
    (goto-char (point-min))
    (search-forward "*** TODO Encargo")
    (my-diario-classify "DEEP")
    (should (equal (buffer-string)
                   "* TASKS\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n*** NEXT Otro\n* DEEP\n** TODO Encargo :cliente:\nTexto [[denote:20260511T1358]].\n:LOGBOOK:\n- Nota.\n:END:\n*** Apunte anidado\nMás texto.\n* SHALLOW\n"))))

(ert-deftest my-diario-migrate-region-must-cover-whole-entries ()
  (my-dmig-test--with-org "* TASKS\n** TODO Uno\nCuerpo.\n** NEXT Dos\n* DEEP\n* SHALLOW\n"
    (let ((original (buffer-string)))
      (goto-char (point-min))
      (search-forward "TODO Uno")
      (let ((beg (point)))
        (search-forward "NEXT Dos")
        (should-error (my-diario-classify "DEEP" beg (point)) :type 'user-error))
      (should (equal original (buffer-string))))))

(ert-deftest my-diario-migrate-invalid-source-and-destination ()
  (my-dmig-test--with-org "* TASKS\n** KILL Perdida\n** TODO Tarea\n*** Nota interior\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** KILL Otra perdida\n** Contratista\n* DEEP\n* SHALLOW\n* Notas\n** TODO Apunte\n"
    (let ((original (buffer-string)))
      (dolist (heading '("* TASKS" "** Empresa" "*** Nota interior" "** TODO Apunte"))
        (goto-char (point-min))
        (search-forward heading)
        (should-error (my-diario-classify "DEEP") :type 'user-error))
      (goto-char (point-min))
      (search-forward "*** KILL Otra perdida")
      (should-error (my-diario-classify "SHALLOW") :type 'user-error)
      (goto-char (point-min))
      (search-forward "** KILL Perdida")
      (should-error (my-diario-classify "DEEP") :type 'user-error)
      (goto-char (point-min))
      (search-forward "** TODO Tarea")
      (should-error (my-diario-classify "DESCONOCIDO") :type 'user-error)
      (should (equal original (buffer-string))))))

(ert-deftest my-diario-migrate-overlap-and-cross-list ()
  (my-dmig-test--with-org "* TASKS\n** TODO Uno\n** NEXT Dos\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Ya\n** Contratista\n*** WAIT Otra\n* DEEP\n* SHALLOW\n"
    (goto-char (point-min))
    (search-forward "*** TODO Ya")
    (let ((original (buffer-string)))
      (my-diario-classify "OT Empresa")
      (should (equal original (buffer-string))))
    (goto-char (point-min))
    (search-forward "*** TODO Ya")
    (beginning-of-line)
    (let ((beg (point)))
      (search-forward "*** WAIT Otra")
      (end-of-line)
      (should-error (my-diario-classify "DEEP" beg (point)) :type 'user-error))
    (goto-char (point-min))
    (search-forward "** TODO Uno")
    (beginning-of-line)
    (let ((beg (point)))
      (search-forward "*** TODO Ya")
      (beginning-of-line)
      (should-error (my-diario-classify "SHALLOW" beg (point)) :type 'user-error))
    (should (= 2 (my-diario-legacy-count)))))

(ert-deftest my-diario-migrate-legacy-count-read-only ()
  (my-dmig-test--with-org "* TASKS\n** DONE Terminada\n*** Nota\n** PROG Antigua\n* Notas\n** TODO Fuera\n"
    (let ((before (buffer-string)))
      (should (= 2 (my-diario-legacy-count)))
      (should (equal before (buffer-string)))
      (should-not (buffer-modified-p)))))

(ert-deftest my-diario-migrate-adjacent-buckets-and-final-newline ()
  (my-dmig-test--with-org "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Primero\n** Contratista\n*** NEXT Segundo\n* DEEP\n* SHALLOW\n** WAIT Final"
    (goto-char (point-min))
    (search-forward "*** TODO Primero")
    (my-diario-classify "OT Contratista")
    (should (equal (buffer-string)
                   "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n*** NEXT Segundo\n*** TODO Primero\n* DEEP\n* SHALLOW\n** WAIT Final"))
    (goto-char (point-min))
    (search-forward "*** NEXT Segundo")
    (my-diario-classify "OT Empresa")
    (should (equal (buffer-string)
                   "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** NEXT Segundo\n** Contratista\n*** TODO Primero\n* DEEP\n* SHALLOW\n** WAIT Final"))
    (goto-char (point-min))
    (search-forward "** WAIT Final")
    (my-diario-classify "DEEP")
    (should (equal (buffer-string)
                   "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** NEXT Segundo\n** Contratista\n*** TODO Primero\n* DEEP\n** WAIT Final\n* SHALLOW\n"))))

(ert-deftest my-diario-migrate-active-region-one-choice ()
  (my-dmig-test--with-org "* TASKS\n** TODO Uno\n** NEXT Dos\n* DEEP\n* SHALLOW\n"
    (let ((transient-mark-mode t)
          (calls 0))
      (goto-char (point-min))
      (search-forward "** TODO Uno")
      (beginning-of-line)
      (push-mark (point) t t)
      (search-forward "* DEEP")
      (beginning-of-line)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _choices &rest _args)
                   (setq calls (1+ calls))
                   "SHALLOW")))
        (call-interactively #'my-diario-classify))
      (should (= 1 calls))
      (should (equal (buffer-string)
                     "* TASKS\n* DEEP\n* SHALLOW\n** TODO Uno\n** NEXT Dos\n")))))

(ert-deftest my-diario-migrate-missing-destination-no-change ()
  (my-dmig-test--with-org "* TASKS\n** TODO Uno\n* Notas\nNada.\n"
    (let ((before (buffer-string)))
      (goto-char (point-min))
      (search-forward "** TODO Uno")
      (should-error (my-diario-classify "DEEP") :type 'user-error)
      (should (equal before (buffer-string))))))

(ert-deftest my-diario-migrate-duplicate-container-no-change ()
  (my-dmig-test--with-org "* DEEP\n* DEEP\n* TASKS\n** TODO Uno\n"
    (let ((before (buffer-string)))
      (should-error (my-diario-prepare) :type 'user-error)
      (should (equal before (buffer-string))))))

(ert-deftest my-diario-migrate-legacy-count-narrowed ()
  (my-dmig-test--with-org "* TASKS\n** DONE Uno\n** WAIT Dos\n* Notas\nContexto.\n"
    (let ((before (buffer-string)))
      (search-forward "* Notas")
      (save-restriction
        (narrow-to-region (line-beginning-position) (point-max))
        (should (= 2 (my-diario-legacy-count)))
        (should-not (buffer-modified-p)))
      (should (equal before (buffer-string))))))

(ert-deftest my-diario-migrate-undo-partial-layout ()
  (let ((original "* DEEP\n** NEXT Trabajo\n* OPORTUNIDADES Y AMENAZAS\n** Contratista\n* TASKS\n** TODO Legado\n"))
    (my-dmig-test--with-org original
      (my-diario-prepare)
      (should (string-match-p "^\\*\\* Empresa$" (buffer-string)))
      (should (string-match-p "^\\* SHALLOW$" (buffer-string)))
      (undo 1)
      (should (equal original (buffer-string))))))

(ert-deftest my-diario-migrate-undo-and-no-auto-save ()
  (let* ((initial "* TASKS\n** TODO Uno\n")
         (file (make-temp-file "test-diario-migrate-" nil ".org" initial)))
    (unwind-protect
        (my-dmig-test--with-org initial
          (setq buffer-file-name file)
          (set-visited-file-modtime)
          (my-diario-prepare)
          (should (buffer-modified-p))
          (should (equal initial (with-temp-buffer
                                   (insert-file-contents-literally file)
                                   (buffer-string))))
          (undo 1)
          (should (equal initial (buffer-string)))
          (my-diario-prepare)
          (setq buffer-undo-list nil)
          (goto-char (point-min))
          (search-forward "** TODO Uno")
          (my-diario-classify "SHALLOW")
          (should (= 0 (my-diario-legacy-count)))
          (undo 1)
          (should (= 1 (my-diario-legacy-count)))
          (should (equal initial (with-temp-buffer
                                   (insert-file-contents-literally file)
                                   (buffer-string)))))
      (delete-file file))))

(ert-deftest my-diario-migrate-module-load-orders ()
  (dolist (order '((diario-migrate diario-rollover diario-focus)
                   (diario-rollover diario-focus diario-migrate)))
    (dolist (module order)
      (load (expand-file-name (format "%s.el" module) my-dmig-test--root)
            nil t t))
    (should (equal my-diario--lists
                   '("OPORTUNIDADES Y AMENAZAS" "DEEP" "SHALLOW")))
    (should (equal my-dmig--lists '("DEEP" "SHALLOW")))
    (should (equal my-dmig--choices
                   '("OT Empresa" "OT Contratista" "DEEP" "SHALLOW")))
    (my-dmig-test--with-org "* LUEGO\n"
      (my-diario--append "** COLD Pendiente\n" "LUEGO")
      (should (equal (buffer-string) "* LUEGO\n** COLD Pendiente\n")))
    (my-dmig-test--with-org
        "* TASKS\n** TODO Preparar :cliente:\n:PROPERTIES:\n:ID: uno\n:END:\n*** Nota\nCuerpo.\n** TODO Encargo\n* Notas\nFuera.\n"
      (let ((before (buffer-string)))
        (my-diario-prepare)
        (should (string-prefix-p before (buffer-string)))
        (should (string-suffix-p
                 "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n* DEEP\n* SHALLOW\n"
                 (buffer-string)))
        (my-diario-prepare)
        (goto-char (point-min))
        (search-forward "** TODO Preparar")
        (my-diario-classify "DEEP")
        (goto-char (point-min))
        (search-forward "** TODO Encargo")
        (my-diario-classify "OT Contratista")
        (should (equal (buffer-string)
                       "* TASKS\n* Notas\nFuera.\n* OPORTUNIDADES Y AMENAZAS\n** Empresa\n** Contratista\n*** TODO Encargo\n* DEEP\n** TODO Preparar :cliente:\n:PROPERTIES:\n:ID: uno\n:END:\n*** Nota\nCuerpo.\n* SHALLOW\n"))
        (should (= 0 (my-diario-legacy-count)))
        (should-not (buffer-file-name))))))

(provide 'test-diario-migrate)
;;; test-diario-migrate.el ends here
