(use-package web-mode
  :straight t
  :mode (("\\.html$" . web-mode) ("\\.php$" . web-mode)
         ("\\.njk$" . web-mode) ("\\.htm$" . web-mode)
         )
  ;;:init  (require 'company-web-html)
  :bind
  (:map web-mode-map
        ("C-c o b" . browse-url-of-file)
        ;; ("C-c {" . emmet-prev-edit-point)
        ("M-n" . web-mode-tag-match)
        ;;("C-'" . company-web-html)
        ;; ("C-c }" . emmet-next-edit-point)
        ))
;;
;; (require 'ocultar-clases)
;; (setq web-mode-ac-sources-alist
;;       '(("css" . (ac-source-css-property))
;;         ("html" . (ac-source-words-in-buffer ac-source-abbrev))))
(add-hook 'local-write-file-hooks (lambda () (delete-trailing-whitespace) nil))
(setq web-mode-enable-current-element-highlight t)
(setq web-mode-enable-current-column-highlight t)
(setq web-mode-enable-auto-pairing t)
(setq web-mode-engines-alist '(("go"    . "\\.html\\'")))
(setq web-mode-markup-indent-offset 3)
(setq web-mode-css-indent-offset 3)
(setq web-mode-code-indent-offset 3)
(setq web-mode-enable-css-colorization t)
(setq web-mode-enable-auto-indentation t)
;;(eldoc-mode)
(electric-indent-mode -1)
(flycheck-mode)
(add-hook 'web-mode-hook 'flycheck-mode)
(add-hook 'web-mode-hook (lambda ()
                          (set (make-local-variable 'company-backends) '(company-web-html))
                          (company-mode t)))
(defhydra hydra-web ()
      "Web mode" 
      ("r" web-mode-element-rename "rename")
      ("c" web-mode-element-clone "clone")
      ("f" web-mode-element-children-fold-or-unfold "fold")
      ("s" web-mode-element-select "select")
      ("k" web-mode-element-kill "kill")
      ("v" web-mode-element-vanish "vanish")
      ("w" web-mode-element-wrap "wrap")
      ("a" web-mode-element-content-select "content-select")
      ("b" web-mode-element-beginning "beginning")
      ("e" web-mode-element-end "end")
      ("n" web-mode-element-next "next")
      ("p" web-mode-element-previous "previous")
      ("u" web-mode-element-parent "parent")
      ("d" web-mode-element-child "child")
      ("m" web-mode-element-mute-blanks "mute-blanks")
      ("t" web-mode-element-transpose "transpose")
      ("i" web-mode-element-insert "insert")
      ("/" web-mode-element-close "close")
      ("q" nil "quit")
      ("z" nil "quit")
      ("<" nil "quit")
)

(key-chord-define-global "h0"  'hydra-web/body)
;;
;; company-backends setup
;;  (set (make-local-variable 'company-backends)
;;         '((company-tide company-files company-yasnippet))))
;;
;;  (defun my-web-mode-hook ()
;;    "Hook for `web-mode'."
;;    (set (make-local-variable 'company-backends)
;;         '((company-tern company-css company-web-html company-files))))
;;
;;  (unless (string-equal "tsx" (file-name-extension buffer-file-name))
;;    (add-hook 'web-mode-hook 'my-web-mode-hook))
;;
;; emmet-mode: dynamic snippets for HTML
;; https://github.com/smihica/emmet-mode

(use-package emmet-mode
  :straight t
  :bind
  ((:map emmet-mode-keymap
         ("C-}" . emmet-prev-edit-point)
         ("C-{" . emmet-next-edit-point)))
  :config
  (setq emmet-move-cursor-between-quotes t)
  (setq emmet-indentation 3)
  (unbind-key "C-M-<left>" emmet-mode-keymap)
  (unbind-key "C-M-<right>" emmet-mode-keymap)
  (add-hook 'web-mode-hook 'emmet-mode))
;;
;;(require 'counsel-css)
;;
(provide 'setup-webmode)
