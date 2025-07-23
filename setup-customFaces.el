;; (custom-set-faces
;;  '(default ((t (:family "Fira Code" :foundry "CYEL" :slant normal :weight regular :height 128 :width normal))))
;;  '(variable-pitch ((t (:family "Fira Sans Regular" :height 128 :width: normal))))
;;  '(org-date ((t (:foreground "#7590db" :underline t :height 0.8 :width normal))))
;;  '(org-drawer ((t (:foreground "gray" :height 0.8 :width condensed))))
;;  '(org-special-keyword ((t (:foreground "#bc6ec5" :height 0.8 :width condensed))))
;;  )

;; (set-cursor-color "#169100")
(set-face-attribute 'default nil :family "Iosevka SS05" :height 175)
(set-face-attribute 'variable-pitch nil :family "Roboto Light" :height 1.0)
(set-face-attribute 'fixed-pitch nil :family (face-attribute 'default :family))

(use-package modus-themes
  :straight t
  ;; (modus-themes :type git
  ;;               :host sourcehut
  ;;               :repo "protesilaos/modus-themes"
  ;;               ;; :branch "4.0.1"
  ;;               );;:build (:not compile))
  ;; :init
  ;; (setq modus-themes-common-palette-overrides '(,@modus-themes-preset-overrides-intense))
  :config
  (load-theme 'modus-vivendi)
  (setq modus-themes-italic-constructs t
        modus-themes-bold-constructs nil
        modus-themes-org-blocks 'tinted-background
        modus-themes-mixed-fonts t
        line-spacing 0.15
        modus-themes-paren-match '(bold intense)
        )
  (setq modus-themes-completions
        '((matches . (extrabold background intense))
          (selection . (semibold accented intense))
          (popup . (accented))
          ))
  (setq modus-themes-headings
        '((0 . (fixed-pitch light 0.75))
          (1 . (overline fixed-pitch bold 1.1))
          (2 . (rainbow fixed-pitch semibold 1.1))
          (3 . (rainbow fixed-pitch semibold 1.05))
          (t . (monochrome fixed-pitch 1.05)))
        )
  :bind
  ("<f5>" . modus-themes-toggle))

;; (straight-use-package 'modus-themes)

;; typeface

;; modus-themes-region '(bg-only)
;; modus-themes-syntax '(green-strings)
;; modus-themes-tabs-accented t
;; modus-themes-fringes 'subtle


(add-hook 'text-mode-hook
          'variable-pitch-mode)

;; (straight-use-package 'nimbus-theme)
;; (load-theme 'nimbus t)


(provide 'setup-customFaces)
