;; better work troguht ssh
(vertico-flat-mode)

;; Buscando una pantalla más ancha
;; (when (not (display-graphic-p))
;;  (set-frame-size (selected-frame) 80 40))

;; Faster cursor movement feedback
(setq inhibit-compacting-font-caches t)

;; Avoid unnecessary redraws
(setq redisplay-skip-fontification-on-input t)

;; Don't blink the cursor (saves render cycles)
(blink-cursor-mode -1)

;; Disable menu bar (useless in terminal)
(menu-bar-mode -1)

;; Avoid mouse-related overhead
(xterm-mouse-mode 1)

;; Terminal clipboard integration (if your SSH setup supports OSC 52)
;; (setq select-enable-clipboard t)

(provide 'setup-remote)

