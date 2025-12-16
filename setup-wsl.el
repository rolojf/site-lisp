;;; setup-wsl.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(defun wsl-wayland-copy (start end)
  "Copy the selected region to the Wayland clipboard asynchronously."
  (interactive "r")
  ;; call-process-on-region arguments:
  ;; START END: The region to send to the command's stdin.
  ;; "wl-copy": The program to execute.
  ;; nil: Do not delete the region after copying.
  ;; nil: Do not redirect the command's output to a buffer.
  ;; nil: Do not display the output.
  (call-process-region start end "wl-copy" nil nil nil))

(global-set-key (kbd "M-w") 'wsl-wayland-copy)

(provide 'setup-wsl)
;;; setup-wsl.el ends here
