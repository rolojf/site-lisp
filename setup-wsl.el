;;; setup-wsl.el --- Insert description here -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

;; (require-package 'xclip)
;; (xclip-mode 1)
;; (global-set-key (kbd "M-ñ") 'set-mark-command)

(setq select-active-regions nil
      select-enable-primary nil
      select-enable-clipboard t)

(defun a1rolo-wslg-clipboard-paste ()
  "Obtener primero el texto UTF-8 ofrecido por WSLg."
  (or (gui-get-selection
       'CLIPBOARD
       (intern "text/plain;charset=utf-8"))
      (gui-selection-value)))

(when (eq window-system 'pgtk)
  (setq interprogram-paste-function
        #'a1rolo-wslg-clipboard-paste))

(provide 'setup-wsl)
;;; setup-wsl.el ends here
