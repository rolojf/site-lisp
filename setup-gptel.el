;;; setup-gptel.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package gptel
  :straight t
  :commands (gptel gptel-send)
  :hook (gptel-mode . visual-fill-column-mode)
  :bind (("C-c C-<return>" . gptel-menu)
         ("C-c <return>" . my/gptel-send)
         ("C-h C-q" . gptel-quick))
  :init
  (setf (alist-get "^\\*ChatGPT\\*.*$"
                   display-buffer-alist
                   nil t #'equal)
        '((my/display-buffer-reuse-minor-mode-window
           display-buffer-in-direction)
          (direction . below)
          (minor-mode . (gptel-mode julia-snail-message-buffer-mode))
          (window-height . 0.4)
          (body-function . select-window)))
  :config
  (setq gptel-api-key (getenv "oaiskey")
        gptel-default-mode 'org-mode
        )
  (defun my/gptel-send (&optional arg)
    (interactive "P")
    (if (or gptel-mode (< (point) 2000) (use-region-p))
        (gptel-send arg)
      (if (y-or-n-p "Prompt has more than 2000 chars, send to ChatGPT?")
          (gptel-send arg)
        (message "ChatGPT: Request cancelled."))))
  (setf (alist-get "^\\*gptel-quick\\*" display-buffer-alist
                   nil nil #'equal)
        `((display-buffer-in-side-window)
          (side . bottom)
          (window-height . ,#'fit-window-to-buffer)))
  (defvar gptel-quick--history nil)
  (defun gptel-quick (prompt)
    (interactive (list (read-string "Ask ChatGPT: " nil gptel-quick--history)))
    (when (string= prompt "") (user-error "A prompt is required."))
    (gptel-request
     prompt
     :callback
     (lambda (response info)
       (if (not response)
           (message "gptel-quick failed with message: %s" (plist-get info :status))
         (with-current-buffer (get-buffer-create "*gptel-quick*")
           (let ((inhibit-read-only t))
             (erase-buffer)
             (insert response))
           (special-mode)
           (display-buffer (current-buffer)))))))
  )

(provide 'setup-gptel)
;;; setup-gptel.el ends here
