;;; cli.scm --- prttil-like CLI on top of the C++ package DB
;;;
;;; Usage:
;;;   ./repl -s cli.scm install <port>
;;;   ./repl -s cli.scm depends [--missing] <port>
;;;   ./repl -s cli.scm world [--missing|--orphan]

(define *world-file* (or (getenv "WORLD_FILE") "/var/lib/pkg/world.scm"))

;; ---------------------------------------------------------------------------
;; graph resolver
;; ---------------------------------------------------------------------------

(define (resolve-graph roots)
  (let ((seen (make-hash-table))
        (order '()))
    (letrec ((dfs (lambda (pkg)
                    (unless (hash-ref seen pkg)
                      (hash-set! seen pkg #t)
                      (if (has-port? pkg)
                          (begin
                            (for-each dfs (port-deps pkg))
                            (set! order (cons pkg order)))
                          (begin
                            (display "warning: " (current-error-port))
                            (display pkg (current-error-port))
                            (display " is not in the ports tree\n" (current-error-port))))))))
      (for-each dfs roots)
      (reverse order))))

;; ---------------------------------------------------------------------------
;; world file reader — evaluates world.scm as Scheme, returns *world*
;; ---------------------------------------------------------------------------

(define (read-world-file path)
  (if (file-exists? path)
      (begin
        (load path)
        (if (defined? '*world*) *world* '()))
      (begin
        (display "warning: " (current-error-port))
        (display path (current-error-port))
        (display " not found\n" (current-error-port))
        '())))

;; ---------------------------------------------------------------------------
;; output helpers
;; ---------------------------------------------------------------------------

(define (print-lines items)
  (for-each (lambda (item) (display item) (newline)) items))

;; ---------------------------------------------------------------------------
;; commands
;; ---------------------------------------------------------------------------

(define (build-package p)
  (format #t "==> building ~a\n" p)
  (let* ((dir (port-dir p))
         (mk (system (string-append "cd " dir " && setpriv --reuid=pkgmk --regid=pkgmk --clear-groups rootlesskit pkgmk -d"))))
    (unless (zero? mk)
      (display "pkgmk failed, aborting\n" (current-error-port))
      (exit 1))
    (let ((add (system (string-append "cd /tmp && pkgadd -u " p "#" (port-version p) "-" (port-release p) ".pkg.tar.*"))))
      (unless (zero? add)
        (display "pkgadd failed, aborting\n" (current-error-port))
        (exit 1)))))

(define (command-install port)
  (let* ((graph (resolve-graph (list port)))
         (to-build (filter (lambda (p) (not (installed? p))) graph)))
    (if (null? to-build)
        (begin (format #t "nothing to build — ~a and its deps are already installed\n" port)
               (exit 0)))
    (format #t "building ~a packages:\n" (length to-build))
    (for-each (lambda (p) (format #t "  ~a\n" p)) to-build)
    (newline)
    (for-each build-package to-build)
    (format #t "done.\n")))

(define (needs-upgrade? p)
  (and (has-port? p)
       (installed? p)
       (let ((pv (port-version p))
             (pr (port-release p))
             (sv (installed-version p))
             (sr (installed-release p)))
         (or (not (equal? pv sv)) (not (equal? pr sr))))))

(define (command-upgrade port)
  (unless (has-port? port)
    (format #t "~a is not in the ports tree\n" port)
    (exit 1))
  (unless (installed? port)
    (format #t "~a is not installed — use install instead\n" port)
    (exit 1))
  (unless (needs-upgrade? port)
    (format #t "~a is up to date\n" port)
    (exit 0))
  (format #t "upgrading ~a: ~a-~a → ~a-~a\n"
          port (installed-version port) (installed-release port)
          (port-version port) (port-release port))
  (build-package port))

(define (command-upgrade-world)
  (let* ((world (read-world-file *world-file*))
         (graph (resolve-graph world))
         (to-upgrade (filter needs-upgrade? graph)))
    (if (null? to-upgrade)
        (begin (display "all world packages are up to date\n")
               (exit 0)))
    (format #t "upgrading ~a packages:\n" (length to-upgrade))
    (for-each (lambda (p) (format #t "  ~a ~a-~a → ~a-~a\n" p
                                  (installed-version p) (installed-release p)
                                  (port-version p) (port-release p)))
              to-upgrade)
    (newline)
    (for-each build-package to-upgrade)
    (format #t "done.\n")))

(define (command-remove port)
  (unless (installed? port)
    (format #t "~a is not installed\n" port)
    (exit 1))
  (format #t "removing ~a ...\n" port)
  (let ((ret (system (string-append "pkgrm " port))))
    (unless (zero? ret)
      (display "pkgrm failed\n" (current-error-port))
      (exit 1))))

(define (command-depends port missing?)
  (let ((graph (resolve-graph (list port))))
    (if missing?
        (for-each (lambda (p) (unless (installed? p) (display p) (newline))) graph)
        (print-lines graph))))

(define (command-sync)
  (display "updating ports ...\n")
  (let* ((dir (dirname (car (command-line))))
         (script (if (file-exists? (string-append dir "/ports"))
                     (string-append dir "/ports")
                     (string-append dir "/../ports")))
         (ret (system script)))
    (if (zero? ret)
        (display "done.\n")
        (begin (display "port sync failed\n" (current-error-port))
               (exit 1)))))

(define (command-diff)
  (for-each (lambda (p)
              (if (has-port? p)
                  (let ((pv (port-version p))
                        (pr (port-release p))
                        (sv (installed-version p))
                        (sr (installed-release p)))
                    (if (or (not (equal? pv sv)) (not (equal? pr sr)))
                        (format #t "~a  installed ~a-~a  ports ~a-~a\n"
                                p sv sr pv pr)))
                  (format #t "~a  installed (not in ports tree)\n" p)))
            (all-installed)))

(define (command-world missing? orphan?)
  (let* ((world (read-world-file *world-file*))
         (graph (resolve-graph world)))
    (cond
     (missing?
      (for-each (lambda (p) (unless (installed? p) (display p) (newline))) graph))
     (orphan?
      (let ((in-graph (make-hash-table)))
        (for-each (lambda (p) (hash-set! in-graph p #t)) graph)
        (for-each (lambda (p)
                    (unless (hash-ref in-graph p)
                      (display p) (newline)))
                  (all-installed))))
     (else
      (print-lines graph)))))

;; ---------------------------------------------------------------------------
;; usage
;; ---------------------------------------------------------------------------

(define (print-usage)
  (display "Usage:\n")
  (display "  install <port>\n")
  (display "  remove <port>\n")
  (display "  upgrade [--world] [<port>]\n")
  (display "  depends [--missing] <port>\n")
  (display "  world [--missing|--orphan]\n")
  (display "  diff\n")
  (display "  sync\n"))

(define (print-usage-and-exit)
  (print-usage)
  (exit 1))

;; ---------------------------------------------------------------------------
;; main
;; ---------------------------------------------------------------------------

(define (main argv)
  (let ((cmd (and (pair? argv) (car argv))))

    (unless cmd
      (print-usage-and-exit))

    ;; load data
    (unless (load-ports)
      (error "failed to load ports"))
    (unless (load-installed)
      (error "failed to load installed packages"))

    (cond
     ;; install <port>
     ((equal? cmd "install")
      (if (not (= (length argv) 2))
          (print-usage-and-exit))
      (command-install (cadr argv)))

     ;; remove <port>
     ((equal? cmd "remove")
      (if (not (= (length argv) 2))
          (print-usage-and-exit))
      (command-remove (cadr argv)))

     ;; depends [--missing] <port>
     ((equal? cmd "depends")
      (cond
       ((= (length argv) 2)
        (command-depends (cadr argv) #f))
       ((and (= (length argv) 3) (equal? (cadr argv) "--missing"))
        (command-depends (caddr argv) #t))
       (else
        (print-usage-and-exit))))

     ;; world [--missing|--orphan]
     ((equal? cmd "world")
      (cond
       ((= (length argv) 1)
        (command-world #f #f))
       ((and (= (length argv) 2) (equal? (cadr argv) "--missing"))
        (command-world #t #f))
       ((and (= (length argv) 2) (equal? (cadr argv) "--orphan"))
        (command-world #f #t))
       (else
        (print-usage-and-exit))))

     ((equal? cmd "upgrade")
      (cond
       ((and (= (length argv) 2) (equal? (cadr argv) "--world"))
        (command-upgrade-world))
       ((= (length argv) 2)
        (command-upgrade (cadr argv)))
       (else
        (print-usage-and-exit))))

     ((equal? cmd "sync")
      (command-sync))

     ((equal? cmd "diff")
      (command-diff))

     (else
      (print-usage-and-exit)))))

;; run when invoked via -s, not when loaded into a REPL
(if (string-suffix? "cli.scm" (car (command-line)))
    (main (cdr (command-line))))
