;;; cli.scm --- CRUX package CLI (s7)

;; ---------------------------------------------------------------------------
;; Build/install customization
;; Override these before running if your pkgmk/pkgadd differ.
;; ---------------------------------------------------------------------------

(define *pkgmk-command*
  "cd ~a && setpriv --reuid=pkgmk --regid=pkgmk --clear-groups rootlesskit pkgmk -d")

(define *pkgadd-command*
  "pkgadd~a ~a")

(define (pkgmk-cmd p)
  (format #f *pkgmk-command* (port-dir p)))

(define (pkgadd-cmd p upgrade?)
  (format #f *pkgadd-command*
          (if upgrade? " -u" "")
          (string-append "/tmp/" p "#" (port-version p) "-" (port-release p) ".pkg.tar.*")))

;; s7 doesn't have filter - provide it.
(define (filter pred lst)
  (let loop ((lst lst) (result '()))
    (if (null? lst)
        (reverse result)
        (loop (cdr lst)
              (if (pred (car lst))
                  (cons (car lst) result)
                  result)))))

(define (read-world-file path)
  (define (trim s)
    (let loop ((i 0) (j (- (string-length s) 1)))
      (cond
       ((and (<= i j) (char-whitespace? (string-ref s i))) (loop (+ i 1) j))
       ((and (<= i j) (char-whitespace? (string-ref s j))) (loop i (- j 1)))
       ((> i j) "")
       (else (substring s i (+ j 1))))))
  (call-with-input-file path
    (lambda (port)
      (let loop ((lines '()))
        (let ((line (read-line port)))
          (if (eof-object? line)
              (reverse lines)
              (let ((s (trim line)))
                (if (or (= (string-length s) 0) (char=? (string-ref s 0) #\#))
                    (loop lines)
                    (loop (cons s lines))))))))))

(define (resolve-graph roots)
  (let ((seen (make-hash-table 32))
        (order '()))
    (letrec ((dfs (lambda (pkg)
                    (unless (hash-table-ref seen pkg)
                      (hash-table-set! seen pkg #t)
                      (if (has-port? pkg)
                          (begin
                            (for-each dfs (port-deps pkg))
                            (set! order (cons pkg order)))
                          (format (current-error-port)
                                  "warning: ~a is not in the ports tree\n" pkg))))))
      (for-each dfs roots)
      (reverse order))))

(define (diff-version p)
  (if (has-port? p)
      (let ((pv (port-version p)) (pr (port-release p))
            (sv (installed-version p)) (sr (installed-release p)))
        (if (or (not (equal? pv sv)) (not (equal? pr sr)))
            (format #t "~a  installed ~a-~a  ports ~a-~a\n" p sv sr pv pr)))
      (format #t "~a  installed (not in ports tree)\n" p)))

(define (needs-upgrade? p)
  (and (has-port? p) (installed? p)
       (let ((pv (port-version p)) (pr (port-release p))
             (sv (installed-version p)) (sr (installed-release p)))
         (or (not (equal? pv sv)) (not (equal? pr sr))))))

;; ---------------------------------------------------------------------------
;; main
;; ---------------------------------------------------------------------------

(define (usage)
  (display "usage:\n")
  (display "  install <port>              build and install port + missing deps\n")
  (display "  upgrade [--world] [<port>]  upgrade a port, or --world for all outdated\n")
  (display "  depends <port>              full dependency graph\n")
  (display "  depends --missing <port>    only uninstalled deps\n")
  (display "  world [--missing|--orphan] [<file>]\n")
  (display "  diff                        installed vs ports versions\n"))

(let ((argv (cdr *command-line*)))
  (unless (pair? argv)
    (usage)
    (exit 1))

  (let ((cmd (car argv))
        (args (cdr argv)))

    (unless (load-ports) (error "failed to load ports"))
    (unless (load-pkgs) (error "failed to load pkgs"))

    (cond
     ((equal? cmd "install")
      (if (not (pair? args))
          (begin (usage) (exit 1)))
      (let* ((graph (resolve-graph (list (car args))))
             (to-build (filter (lambda (p) (not (installed? p))) graph)))
        (if (null? to-build)
            (begin (format #t "nothing to build - ~a and its deps are already installed\n" (car args))
                   (exit 0)))
        (format #t "building ~a packages:\n" (length to-build))
        (for-each (lambda (p) (format #t "  ~a\n" p)) to-build)
        (newline)
        (for-each (lambda (p)
                    (format #t "==> building ~a\n" p)
                    (unless (zero? (system (pkgmk-cmd p)))
                      (format (current-error-port) "pkgmk failed for ~a\n" p)
                      (exit 1))
                    (unless (zero? (system (pkgadd-cmd p #f)))
                      (format (current-error-port) "pkgadd failed for ~a\n" p)
                      (exit 1)))
                  to-build)
        (format #t "done.\n")))

     ((equal? cmd "upgrade")
      (cond
       ((and (= (length args) 1) (equal? (car args) "--world"))
        ;; upgrade --world: upgrade every outdated port in the world file
        (let ((path "/var/lib/pkg/world"))
          (if (not (file-exists? path))
              (begin (format (current-error-port) "world file not found: ~a\n" path) (exit 1)))
          (let* ((pkgs (read-world-file path))
                 (graph (resolve-graph pkgs))
                 (to-upgrade (filter needs-upgrade? graph)))
            (if (null? to-upgrade)
                (begin (display "all world packages are up to date\n") (exit 0)))
            (format #t "upgrading ~a packages:\n" (length to-upgrade))
            (for-each (lambda (p) (format #t "  ~a ~a-~a -> ~a-~a\n" p
                                         (installed-version p) (installed-release p)
                                         (port-version p) (port-release p)))
                      to-upgrade)
            (newline)
            (for-each (lambda (p)
                        (format #t "==> upgrading ~a\n" p)
                        (unless (zero? (system (pkgmk-cmd p)))
                          (format (current-error-port) "pkgmk failed for ~a\n" p) (exit 1))
                        (unless (zero? (system (pkgadd-cmd p #t)))
                          (format (current-error-port) "pkgadd failed for ~a\n" p) (exit 1)))
                      to-upgrade)
            (format #t "done.\n"))))
       ((= (length args) 1)
        ;; upgrade <port>
        (let ((port (car args)))
          (unless (has-port? port)
            (format #t "~a is not in the ports tree\n" port) (exit 1))
          (unless (installed? port)
            (format #t "~a is not installed - use install instead\n" port) (exit 1))
          (unless (needs-upgrade? port)
            (format #t "~a is up to date\n" port) (exit 0))
          (format #t "upgrading ~a: ~a-~a -> ~a-~a\n" port
                  (installed-version port) (installed-release port)
                  (port-version port) (port-release port))
          (unless (zero? (system (pkgmk-cmd port)))
            (format (current-error-port) "pkgmk failed\n") (exit 1))
          (unless (zero? (system (pkgadd-cmd port #t)))
            (format (current-error-port) "pkgadd failed\n") (exit 1))
          (format #t "done.\n")))
       (else
        (usage) (exit 1))))

     ((equal? cmd "depends")
      (if (and (pair? args) (equal? (car args) "--missing"))
          (let ((graph (resolve-graph (list (cadr args)))))
            (for-each (lambda (p) (unless (installed? p) (display p) (newline))) graph))
          (let ((graph (resolve-graph (list (car args)))))
            (for-each (lambda (p) (display p) (newline)) graph))))

     ((equal? cmd "world")
      (let ((flag (and (pair? args) (car args)))
            (path (if (and (pair? args) (not (equal? (car args) "--missing"))
                           (not (equal? (car args) "--orphan")))
                      (car args)
                      "/var/lib/pkg/world")))
        (if (not (file-exists? path))
            (begin
              (format (current-error-port) "world file not found: ~a\n" path)
              (exit 1)))
        (let* ((pkgs (read-world-file path))
               (graph (resolve-graph pkgs)))
          (cond
           ((equal? flag "--missing")
            (for-each (lambda (p) (unless (installed? p) (display p) (newline))) graph))
           ((equal? flag "--orphan")
            (let ((seen (make-hash-table 32)))
              (for-each (lambda (p) (hash-table-set! seen p #t)) graph)
              (for-each (lambda (p)
                          (unless (hash-table-ref seen p)
                            (display p) (newline)))
                        (all-installed))))
           (else
            (for-each (lambda (p) (display p) (newline)) graph))))))

     ((equal? cmd "diff")
      (for-each diff-version (all-installed)))

     (else
      (usage)
      (exit 1)))))
