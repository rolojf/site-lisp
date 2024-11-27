(use-package prettier
  :ensure t
  :chords ("zp" . prettier-prettify)
  ;; :custom
  ;; (prettier-js-args '("--bracket-spacing" "true"
	;; 	                  "--tab-width" "3"
	;; 	                  "--end-of-line" "lf"
	;; 	                  "--print-width" "120"
  ;;                     "--plugin" "@svgr/plugin-prettier"
	;; 	                  ))
  )

(provide 'setup-prettier)
