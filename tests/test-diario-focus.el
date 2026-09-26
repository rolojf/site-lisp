;;; test-diario-focus.el --- Isolated diario focus tests -*- lexical-binding: t; -*-

;;; Commentary:
;;; ERT fixtures use only temporary Org buffers; no diario files are opened.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'diario-focus)

(defconst my-diario-test--diario
  "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Techo de X :clienteX_003:\nNotas de la OT.\n*** NEXT Techo de XY :clienteXY_003:\n** Contratista\n*** TODO Trabajo de Y :clienteY:\n* DEEP\n** NEXT Preparar techo :clienteX_003:\nContexto profundo.\n** NEXT Otra OT de X :clienteX_otro:\n* SHALLOW\n** WAIT Recibir precio :clienteX_003:\n** TODO Pagar teléfono\n* Notas\nContexto general.\n"
  "Three-list fixture with a similar customer and a different OT suffix.")

(defmacro my-diario-test--with-org (text &rest body)
  "Run BODY in a temporary Org buffer populated with TEXT."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (let ((org-mode-hook nil)
           (org-inhibit-startup t)
           (org-highlight-sparse-tree-matches nil)
           (my-diario-customer-tags '("clienteX" "clienteY" "clienteXY")))
       (org-mode)
       (insert ,text)
       (goto-char (point-min))
       ,@body)))

(defun my-diario-test--heading (title)
  "Move to the heading whose title contains TITLE in the current fixture."
  (goto-char (point-min))
  (unless (re-search-forward (concat "^\\*+ .*" (regexp-quote title)) nil t)
    (error "Missing fixture heading: %s" title))
  (beginning-of-line))

(defun my-diario-test--visible (title)
  "Return non-nil if the fixture heading containing TITLE is visible."
  (save-excursion
    (my-diario-test--heading title)
    (not (org-invisible-p (point)))))

(ert-deftest my-diario-focus-test-tag-parts ()
  (should (equal (my-diario-tag-parts "clienteX_techo")
                 '("clienteX" . "techo")))
  (should (equal (my-diario-tag-parts "clienteX_003")
                 '("clienteX" . "003")))
  (should (equal (my-diario-tag-parts "clienteX_techo_lamina")
                 '("clienteX" . "techo_lamina")))
  (should (equal (my-diario-tag-parts "clienteX")
                 '("clienteX" . nil)))
  (dolist (tag '("" "_003" "clienteX_"))
    (should-error (my-diario-tag-parts tag) :type 'user-error)))

(ert-deftest my-diario-focus-test-customer-match ()
  (should (my-diario-customer-tag-p "clienteX" "clienteX"))
  (should (my-diario-customer-tag-p "clienteX" "clienteX_003"))
  (should (my-diario-customer-tag-p "clienteX" "clienteX_techo_lamina"))
  (should-not (my-diario-customer-tag-p "clienteX" "clienteXY_003"))
  (should-not (my-diario-customer-tag-p "clienteX" "cliente"))
  (should-error (my-diario-customer-tag-p "clienteX_techo" "clienteX_techo")
                :type 'user-error))

(ert-deftest my-diario-focus-test-focus-restores-from-anywhere ()
  (my-diario-test--with-org my-diario-test--diario
    (my-diario-focus-mode 1)
    (let ((original (buffer-substring-no-properties (point-min) (point-max))))
      (my-diario-test--heading "Techo de X :")
      (my-diario-focus)
      (should (my-diario-test--visible "Techo de X :"))
      (should (my-diario-test--visible "Preparar techo"))
      (should (my-diario-test--visible "Recibir precio"))
      (should (my-diario-test--visible "OPORTUNIDADES Y AMENAZAS"))
      (should (my-diario-test--visible "DEEP"))
      (should (my-diario-test--visible "SHALLOW"))
      (should-not (my-diario-test--visible "Techo de XY"))
      (should-not (my-diario-test--visible "Otra OT de X"))
      (should-not (my-diario-test--visible "Pagar teléfono"))
      (should (equal original (buffer-substring-no-properties
                               (point-min) (point-max))))

      ;; The second invocation must not read the tag or OT at the new point.
      (my-diario-test--heading "DEEP")
      (my-diario-focus)
      (dolist (title '("Techo de XY" "Otra OT de X" "Pagar teléfono"))
        (should (my-diario-test--visible title)))
      (should (equal original (buffer-substring-no-properties
                               (point-min) (point-max)))))))

(ert-deftest my-diario-focus-test-exact-tag-variants ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Simple :clienteX:\n*** NEXT Descriptiva :clienteX_techo_lamina:\n* DEEP :clienteX:\n** NEXT Acción simple :clienteX:\n** NEXT Acción descriptiva :clienteX_techo_lamina:\n** NEXT Otra sección :clienteX_techo:\n** NEXT No asociada\n* SHALLOW\n** NEXT Preparación :clienteX_techo_lamina:\n"
    (my-diario-test--heading "Simple :")
    (my-diario-focus)
    (should (my-diario-test--visible "Acción simple"))
    (should-not (my-diario-test--visible "Acción descriptiva"))
    (should-not (my-diario-test--visible "No asociada"))

    (my-diario-focus)
    (my-diario-test--heading "Descriptiva :")
    (my-diario-focus)
    (should (my-diario-test--visible "Acción descriptiva"))
    (should (my-diario-test--visible "Preparación"))
    (should-not (my-diario-test--visible "Acción simple"))
    (should-not (my-diario-test--visible "Otra sección"))
    (should-not (my-diario-test--visible "No asociada"))))

(ert-deftest my-diario-focus-test-no-tag-does-not-change-visibility ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Sin etiqueta\n*** TODO Con etiqueta :clienteX_003:\n* DEEP\n** TODO Otra tarea\n"
    (org-cycle-overview)
    (let ((original (buffer-substring-no-properties (point-min) (point-max)))
          (visible (my-diario-test--visible "Con etiqueta"))
          notice)
      (my-diario-test--heading "Sin etiqueta")
      ;; A headless daemon has no reliable echo-area `current-message'.
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (setq notice (apply #'format format-string args)))))
        (my-diario-focus))
      (should (equal original (buffer-substring-no-properties
                               (point-min) (point-max))))
      (should (eq visible (my-diario-test--visible "Con etiqueta")))
      (should-not my-diario--focus-tag)
      (should (stringp notice))
      (should (string-match-p "etiqueta" notice)))))

(ert-deftest my-diario-focus-test-irrelevant-and-marker-tags ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Sin asociación :journal:t:urgente:\n* DEEP\n** TODO Otra tarea\n"
    (let ((my-diario-customer-tags '("t" "clienteX")))
      (my-diario-test--heading "Sin asociación")
      (my-diario-focus)
      (should-not my-diario--focus-tag)
      (should (my-diario-test--visible "Otra tarea")))))

(ert-deftest my-diario-focus-test-new-customer-without-list ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO OT nueva :nuevoCliente_solar:t:c:journal:\n* DEEP\n** NEXT Preparar OT :nuevoCliente_solar:\n** NEXT Otro encargo :nuevoCliente_otra:\n"
    (let ((my-diario-customer-tags nil)
          (original (buffer-substring-no-properties (point-min) (point-max))))
      (my-diario-test--heading "OT nueva")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _args) (error "Bookkeeping tags prompted for completion"))))
        (should (equal (my-diario-focus) "nuevoCliente_solar")))
      (should (my-diario-test--visible "Preparar OT"))
      (should-not (my-diario-test--visible "Otro encargo"))
      (should (equal original (buffer-substring-no-properties
                               (point-min) (point-max)))))))

(ert-deftest my-diario-focus-test-context-tag-not-association ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Contexto :plan:\n:PROPERTIES:\n:DIARIO_CONTEXT_TAGS: :plan:\n:END:\n* DEEP\n** NEXT Otras notas :plan:\n"
    (let ((my-diario-customer-tags nil))
      (my-diario-test--heading "Contexto :")
      (should-not (my-diario-focus))
      (should (my-diario-test--visible "Otras notas")))))

(ert-deftest my-diario-focus-test-excludes-context-only-matches ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO OT :clienteA_techo:plan:\n:PROPERTIES:\n:DIARIO_CONTEXT_TAGS: :plan:\n:END:\n* DEEP\n** NEXT Trabajo :clienteA_techo:\n** NEXT Solo contexto :clienteA_techo:\n:PROPERTIES:\n:DIARIO_CONTEXT_TAGS: :clienteA_techo:\n:END:\n* SHALLOW\n** NEXT También trabajo :clienteA_techo:\n"
    (let ((my-diario-customer-tags nil)
          (org-highlight-sparse-tree-matches t)
          (original (buffer-string)))
      (set-buffer-modified-p nil)
      (my-diario-test--heading "OT :")
      (should (equal (my-diario-focus) "clienteA_techo"))
      (should (my-diario-test--visible "Trabajo :"))
      (should (my-diario-test--visible "También trabajo"))
      (should-not (my-diario-test--visible "Solo contexto"))
      (should (equal original (buffer-string)))
      (should-not (buffer-modified-p))
      (my-diario-focus)
      (should (my-diario-test--visible "Solo contexto")))))

(ert-deftest my-diario-focus-test-retag-needs-no-association-property ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO OT :clienteA_techo:plan:\n:PROPERTIES:\n:DIARIO_CONTEXT_TAGS: :plan:\n:END:\n* DEEP\n** NEXT Nueva :clienteB_003:\n** NEXT Vieja :clienteA_techo:\n"
    (let ((my-diario-customer-tags nil))
      (my-diario-test--heading "OT :")
      (org-set-tags '("clienteB_003" "plan"))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) (error "Retagging prompted"))))
        (should (equal (my-diario-focus) "clienteB_003")))
      (should (my-diario-test--visible "Nueva"))
      (should-not (my-diario-test--visible "Vieja")))))

(ert-deftest my-diario-focus-test-invalid-association-visible ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Sin sufijo :clienteX_:\n* DEEP\n** TODO Otra tarea\n"
    (my-diario-test--heading "Sin sufijo")
    (let ((original (buffer-string)))
      (should-error (my-diario-focus) :type 'user-error)
      (should-not my-diario--focus-tag)
      (should (my-diario-test--visible "Otra tarea"))
      (should (equal original (buffer-string))))))

(ert-deftest my-diario-focus-test-multiple-associations-ask ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Dos clientes :clienteX_003:clienteY:t:\n* DEEP\n** NEXT X :clienteX_003:\n** NEXT Y :clienteY:\n"
    (my-diario-test--heading "Dos clientes")
    (let (choices)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _args)
                   (setq choices collection)
                   "clienteY")))
        (my-diario-focus))
      (should (equal choices '("clienteX_003" "clienteY")))
      (should (my-diario-test--visible "NEXT Y"))
      (should-not (my-diario-test--visible "NEXT X")))))

(ert-deftest my-diario-focus-test-nil-list-ambiguity-asks ()
  (my-diario-test--with-org
      "* OPORTUNIDADES Y AMENAZAS\n** Empresa\n*** TODO Dos asociaciones :nuevoCliente_solar:otroCliente_003:t:\n* DEEP\n** NEXT Preparar otra :otroCliente_003:\n"
    (let ((my-diario-customer-tags nil)
          choices)
      (my-diario-test--heading "Dos asociaciones")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _args)
                   (setq choices collection)
                   "otroCliente_003")))
        (should (equal (my-diario-focus) "otroCliente_003")))
      (should (equal choices '("nuevoCliente_solar" "otroCliente_003")))
      (should (my-diario-test--visible "Preparar otra")))))

(ert-deftest my-diario-focus-test-not-an-ot-leaves-visibility ()
  (my-diario-test--with-org my-diario-test--diario
    (my-diario-test--heading "Preparar techo")
    (my-diario-focus)
    (should-not my-diario--focus-tag)
    (should (my-diario-test--visible "Pagar teléfono"))))

(ert-deftest my-diario-focus-test-mode-key-is-buffer-local ()
  (let ((global-before (lookup-key (current-global-map) (kbd "C-c n f"))))
    (my-diario-test--with-org my-diario-test--diario
      (let ((local-before (key-binding (kbd "C-c n f"))))
        (my-diario-focus-mode 1)
        (should (eq (key-binding (kbd "C-c n f")) #'my-diario-focus))
        (my-diario-focus-mode -1)
        (should (eq (key-binding (kbd "C-c n f")) local-before))))
    (should (equal (lookup-key (current-global-map) (kbd "C-c n f"))
                   global-before))))

(provide 'test-diario-focus)
;;; test-diario-focus.el ends here
