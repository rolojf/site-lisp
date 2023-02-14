;; (custom-set-faces
;;  '(default ((t (:family "Fira Code" :foundry "CYEL" :slant normal :weight regular :height 128 :width normal))))
;;  '(variable-pitch ((t (:family "Fira Sans Regular" :height 128 :width: normal))))
;;  '(org-date ((t (:foreground "#7590db" :underline t :height 0.8 :width normal))))
;;  '(org-drawer ((t (:foreground "gray" :height 0.8 :width condensed))))
;;  '(org-special-keyword ((t (:foreground "#bc6ec5" :height 0.8 :width condensed))))
;;  )

;; (set-cursor-color "#169100")

;; (straight-use-package 'modus-themes)

;; typeface
(set-face-attribute 'default nil :family "Iosevka Fixed" :height 140)
(set-face-attribute 'variable-pitch nil :family "Fira Sans Book" :height 0.96)
(set-face-attribute 'fixed-pitch nil :family (face-attribute 'default :family))

;; (setq modus-themes-italic-constructs t
;;       modus-themes-bold-constructs nil
;;       modus-themes-org-blocks 'tinted-background
;;       modus-themes-mixed-fonts t
;;       modus-themes-completions
;;       '((matches . (extrabold background intense))
;;         (selection . (semibold accented intense))
;;         (popup . (accented))
;;         )
;;       modus-themes-headings
;;       '((0 . (fixed-pitch light 0.75))
;;         (1 . (overline fixed-pitch bold 1.2))
;;         (2 . (rainbow fixed-pitch semibold 1.2))
;;         (3 . (rainbow fixed-pitch semibold 1.1))
;;         (t . (monochrome fixed-pitch 1.1)))
;;       modus-themes-paren-match '(bold intense)
;;       )

;; line-spacing 0.15
;; modus-themes-region '(bg-only)
;; modus-themes-syntax '(green-strings)
;; modus-themes-tabs-accented t
;; modus-themes-fringes 'subtle


;; Load the theme of your choice:
;; (load-theme 'modus-vivendi)

;; Optionally define a key to switch between Modus themes.  Also check
;; the user option `modus-themes-to-toggle'.
;; (define-key global-map (kbd "<f5>") #'modus-themes-toggle)


(provide 'setup-customFaces)
