;;; setup-wsl.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(defun wsl-wayland-copy (start end)
  "Copy the selected region to the Wayland clipboard asynchronously."
  (interactive "r")
  (call-process-region start end "wl-copy" nil nil nil)
  (deactivate-mark) ;; Deactivates the region
  (goto-char start)) ;; Moves point back to the start of the selection

(global-set-key (kbd "M-w") 'wsl-wayland-copy)

(defun wsl-wayland-paste ()
  "Paste from Wayland clipboard enforcing UTF-8 encoding."
  (interactive)
  ;; Force Emacs to read the shell output as UTF-8
  (let ((coding-system-for-read 'utf-8))
    ;; Insert the output of wl-paste
    (insert (shell-command-to-string "wl-paste --no-newline"))))

(global-set-key (kbd "C-M-y") 'wsl-wayland-paste)

(provide 'setup-wsl)
;;; setup-wsl.el ends here
