;;; setup-wsl.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require-package 'xclip)
(xclip-mode 1)
(global-set-key (kbd "M-ñ") 'set-mark-command)

(provide 'setup-wsl)
;;; setup-wsl.el ends here
