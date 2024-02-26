;;; setup-gptel.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package gptel
  :straight t
  :commands (gptel gptel-send)
  :hook (gptel-mode . visual-fill-column-mode)
  :bind (;("C-c C-<return>" . gptel-menu)
         ("C-c <return>" . gptel-send)
         ("C-h C-q" . gptel-quick))
  ;; :init
  ;; (setf (alist-get "^\\*ChatGPT\\*.*$"
  ;;                  display-buffer-alist
  ;;                  nil t #'equal)
  ;;       '((my/display-buffer-reuse-minor-mode-window
  ;;          display-buffer-in-direction)
  ;;         (direction . below)
  ;;         (minor-mode . (gptel-mode julia-snail-message-buffer-mode))
  ;;         (window-height . 0.4)
  ;;         (body-function . select-window)))
  :config
  (setq gptel-api-key (getenv "oaiskey")
        gptel-default-mode 'org-mode
        )

  (gptel-make-gemini "Gemini"
                     :key (getenv "gemini")
                     :stream t)

  ;; ;; pandoc -f gfm -t org|sed '/:PROPERTIES:/,/:END:/d'
  ;; (defun gjg/gptel--convert-markdown->org (str)
  ;;   "Convert string STR from markdown to org markup using Pandoc.
  ;; Remove the property drawers Pandoc insists on inserting for org output."
  ;;   ;; point will be at the last user position - assistant response will be after that to the end of the buffer (hopefully without the next user prompt)
  ;;   ;; So let's
  ;;   (interactive)
  ;;   (let* ((org-prefix (alist-get 'org-mode gptel-prompt-prefix-alist))
  ;;          (shift-indent (progn (string-match "^\\(\\*+\\)" org-prefix) (length (match-string 1 org-prefix))))
  ;;          (lua-filter (when (file-readable-p "~/.config/pandoc/gfm_code_to_org_block.lua")
  ;;                        (concat "--lua-filter=" (expand-file-name "~/.config/pandoc/gfm_code_to_org_block.lua"))))
  ;;          (temp-name (make-temp-name "gptel-convert-" ))
  ;;          (sentence-end "\\([.?!
  ;; ]\\)"))
  ;;     ;; TODO: consider placing original complete response in the kill ring
  ;;     ;; (with-temp-buffer
  ;;     (with-current-buffer (get-buffer-create (concat "*" temp-name "*"))
  ;;       (insert str)
  ;;       (write-region (point-min) (point-max) (concat "/tmp/" temp-name ".md" ))
  ;;       (shell-command-on-region (point-min) (point-max)
  ;;                                (format "pandoc -f gfm -t org --shift-heading-level-by=%d %s|sed '/:PROPERTIES:/,/:END:/d'" shift-indent lua-filter)
  ;;                                nil ;; use current buffer
  ;;                                t   ;; replace the buffer contents
  ;;                                "*gptel-convert-error*")
  ;;       (goto-char (point-min))
  ;;       (insert (format "%sAssistant: %s\n" (alist-get 'org-mode gptel-prompt-prefix-alist) (or (sentence-at-point t) "[resp]")))
  ;;       (goto-char (point-max))
  ;;       (buffer-string))))

  ;; (defun gjg/gptel-convert-org-with-pandoc (content buffer)
  ;;   "Transform CONTENT acoording to required major-mode using `pandoc'.
  ;; Currenly only `org-mode' is supported
  ;; This depends on the `pandoc' binary only, not on the  Emacs Lisp `pandoc' package."
  ;;   (pcase (buffer-local-value 'major-mode buffer)
  ;;     ('org-mode (gjg/gptel--convert-markdown->org content))
  ;;     (_ content)))

  ;; (custom-set-variables '(gptel-response-filter-functions
  ;;                         '(gjg/gptel-convert-org-with-pandoc)))
  ;; ;; (defun my/gptel-send (&optional arg)
  ;; (interactive "P")
  ;; (if (or gptel-mode (< (point) 2000) (use-region-p))
  ;; (gptel-send arg)
  ;; (if (y-or-n-p "Prompt has more than 2000 chars, send to ChatGPT?")
  ;; (gptel-send arg)
  ;; (message "ChatGPT: Request cancelled."))))
  ;;   (setf (alist-get "^\\*gptel-quick\\*" display-buffer-alist
  ;;                    nil nil #'equal)
  ;;         `((display-buffer-in-side-window)
  ;;           (side . bottom)
  ;;           (window-height . ,#'fit-window-to-buffer)))
  ;; (defvar gptel-quick--history nil)
  ;; (defun gptel-quick (prompt)
  ;;   (interactive (list (read-string "Ask ChatGPT: " nil gptel-quick--history)))
  ;;   (when (string= prompt "") (user-error "A prompt is required."))
  ;;   (gptel-request
  ;;       prompt
  ;;     :callback
  ;;     (lambda (response info)
  ;;       (if (not response)
  ;;           (message "gptel-quick failed with message: %s" (plist-get info :status))
  ;;         (with-current-buffer (get-buffer-create "*gptel-quick*")
  ;;           (let ((inhibit-read-only t))
  ;;             (erase-buffer)
  ;;             (insert response))
  ;;           (special-mode)
  ;;           (display-buffer (current-buffer)))))))
  )

(provide 'setup-gptel)
;;; setup-gptel.el ends here
