(use-package prettier-js
  :ensure t
  :chords ("zp" . prettier-js)
  :custom
  (prettier-js-args '("--bracket-spacing" "true"
		      "--tab-width" "3"
		      "--end-of-line" "lf"
		      "--print-width" "120"
		      ))
  )

(provide 'setup-prettier)
