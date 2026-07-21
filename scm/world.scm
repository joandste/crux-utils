;;; world.scm --- CRUX world definition
;;;
;;; This file is evaluated as Scheme code, so you can use any
;;; Scheme expression to compute which packages belong on your
;;; system.  Define *world* as a list of package names.
;;;
;;; The default discovers every port in /usr/ports/core automatically.
;;; Uncomment the second form of *world* below to add extra packages
;;; beyond core.

(use-modules (ice-9 ftw))

(define (core-packages)
  "Return a list of every port under /usr/ports/core/ (must contain a Pkgfile)."
  (scandir "/usr/ports/core"
           (lambda (name)
             (and (not (member name '("." "..")))
                  (file-exists? (string-append "/usr/ports/core/" name "/Pkgfile"))))))

;; Default: just what's in core.  New ports added to the collection
;; are picked up automatically — no manual editing needed.
(define *world* (core-packages))

;; Uncomment and tailor this to add packages beyond core:
;;
;;   (define *world*
;;     (append (core-packages)
;;             (list "emacs" "git" "nginx" "postgresql" "redis")))
