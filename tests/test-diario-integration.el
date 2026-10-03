;;; test-diario-integration.el --- Keyless cross-command fixtures -*- lexical-binding: t; -*-

;;; Commentary:
;; Load after test-diario-commands and test-diario-priad-commands.  Reuse
;; their bounded temporary files; never load setup-journaling or live notes.

;;; Code:

(require 'ert)
(require 'test-diario-commands)
(require 'test-diario-priad-commands)

(defvar denote-directory)
(defvar denote-journal-directory)

(defun my-dit-fresh (path)
  "Write fresh next-day Denote metadata to fixture PATH."
  (with-temp-file path
    (insert "#+title: Mañana\n#+date: [2026-06-04 Thu]\n#+identifier: 20260604T0900\n\n")))

(defun my-dit-deep (path)
  "Read the ordered direct DEEP entry titles from fixture PATH."
  (my-diario--with-text (my-dpc-test--disk path)
    (mapcar (lambda (entry)
              (goto-char (my-diario--entry-start entry))
              (org-get-heading t t t t))
            (cl-remove-if-not
             (lambda (entry) (equal (my-diario--entry-list entry) "DEEP"))
             (my-diario--scan)))))

(ert-deftest my-diario-integration-import-roll-close ()
  (my-dpc-test--files
    (let ((later (expand-file-name "LUEGO.org" denote-journal-directory)))
      (my-dit-fresh next)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "DEEP")))
        (should (= 1 (plist-get (my-diario-import target) :copied))))
      (should (= 1 (plist-get (my-diario-roll target next later "20260604")
                              :moved)))
      ;; The ordinary close hook must not resurrect an exported task merely
      ;; because the destination no longer stores its original transfer key.
      (cl-letf (((symbol-function 'my-diario-current) (lambda () next)))
        (let ((this-command 'kill-buffer))
          (should (my-dpc-maybe-on-kill))))
      (should (equal (my-dit-deep next) '("Cotización")))
      (should-not (my-dit-deep target))
      (should-not (my-diario-import-needed-p))
      (should (string-search ":DIARIO_EXPORTS:" (my-dpc-test--disk source)))
      (dolist (file (list target next))
        (should-not (string-search ":DIARIO_KEY:" (my-dpc-test--disk file))))
      (should (string-search "Contexto [[denote:20260511T1358]]."
                             (my-dpc-test--disk next)))
      (should (string-search "*** TODO Paso interno" (my-dpc-test--disk next))))))

(ert-deftest my-diario-integration-conflict-roll-repeat ()
  (my-dpc-test--files
    (let ((later (expand-file-name "LUEGO.org" denote-journal-directory)))
      (with-temp-file target
        (insert
         (replace-regexp-in-string
          "^\\* DEEP$"
          "* DEEP\n** TODO Cotización :cliente_techo:\nNotas existentes.\n*** Detalle previo\nConservar.\n** TODO Otra tarea :otro:"
          my-dpc-test--diario t t)))
      (my-dit-fresh next)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "DEEP")))
        (should (= 1 (plist-get (my-diario-import target) :copied))))
      (should (equal (my-dit-deep target)
                     '("Cotización" "Cotización" "Otra tarea")))
      (let ((text (my-dpc-test--disk target)))
        (should (string-search "# DIARIO: copias con contenido distinto; revisar ambas."
                               text))
        (should (string-search "*** Detalle previo\nConservar." text))
        (should (string-search "*** TODO Paso interno" text)))
      (my-diario-roll target next later "20260604")
      (should (equal (my-dit-deep next)
                     '("Cotización" "Cotización" "Otra tarea")))
      ;; Exact-content precedence finds the already imported variant, not
      ;; merely the first same-title sibling, and does not add a third copy.
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "DEEP")))
        (let ((result (my-diario-import next 'repeat)))
          (should (= 0 (plist-get result :copied)))
          (should (= 1 (plist-get result :already)))))
      (should (equal (my-dit-deep next)
                     '("Cotización" "Cotización" "Otra tarea")))
      (dolist (file (list target next))
        (should-not (string-search ":DIARIO_KEY:" (my-dpc-test--disk file)))))))

(ert-deftest my-diario-integration-clean-existing-day ()
  (my-dct-test--with-files
    (let ((older (expand-file-name "20260530T0900--older__journal.org" dir))
          (key "\n:PROPERTIES:\n:DIARIO_KEY: legacy-key\n:END:"))
      (with-temp-file older (insert "* Nota" key "\nHistoria.\n"))
      (with-temp-file source
        (insert (replace-regexp-in-string
                 "^\\* Notas$" (concat "* Notas" key)
                 my-dct-test--source t t)))
      (with-temp-file target
        (insert (replace-regexp-in-string
                 "^\\* Notas$" (concat "* Notas" key)
                 my-dct-test--ready t t)))
      (let ((old-text (my-dct-test--text older)))
        (should (equal (plist-get (my-diario-today) :target) target))
        (dolist (file (list source target))
          (should-not (string-search ":DIARIO_KEY:" (my-dct-test--text file))))
        (should (equal old-text (my-dct-test--text older)))
        (should (string-search "Texto fuera de listas." (my-dct-test--text source)))
        (should (string-search "Editado hoy." (my-dct-test--text target)))
        (let ((before (my-dct-test--text target)))
          (my-diario-today)
          (should (equal before (my-dct-test--text target))))))))

(provide 'test-diario-integration)
;;; test-diario-integration.el ends here
