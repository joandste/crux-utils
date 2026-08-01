;;; cli.scm --- CRUX package CLI (s7)

;; ---------------------------------------------------------------------------
;; Build/install customization
;; Override these before running if your pkgmk/pkgadd differ.
;; ---------------------------------------------------------------------------

(define (pkgmk-cmd p)
  (string-append "cd " (port-dir p) " && rootlesskit pkgmk -d"))

(define (pkgadd-cmd p upgrade?)
  (string-append "pkgadd" (if upgrade? " -u" "") " /tmp/" p "#" (port-version p) "-" (port-release p) ".pkg.tar.*"))

;; ---------------------------------------------------------------------------
;; Paths - which port collections and pkg db to load.
;; Each entry in *ports-dirs* is scanned one level deep (no recursion).
;; ---------------------------------------------------------------------------

(define *ports-dirs* '("/usr/ports/muslcrux" "/usr/ports/contrib" "/usr/ports/local" "/usr/ports/core" "/usr/ports/opt" "/usr/ports/xorg"))
(define *pkg-db* "/var/lib/pkg/db")
(define *world-file* "/var/lib/pkg/world")

;; s7 doesn't have filter - provide it.
(define (filter pred lst)
  (let loop ((lst lst) (result '()))
    (if (null? lst)
        (reverse result)
        (loop (cdr lst)
              (if (pred (car lst))
                  (cons (car lst) result)
                  result)))))

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
;; Arg handling - split each command's args into (flags . operands) once, then
;; every command loops over the operands and checks flags with member.
;; ---------------------------------------------------------------------------

;; Split args into (flags . operands); flags are args starting with "-".
(define (split-args args)
  (let loop ((args args) (flags '()) (ops '()))
    (if (null? args)
        (cons (reverse flags) (reverse ops))
        (if (and (> (string-length (car args)) 0)
                 (equal? (string-ref (car args) 0) #\-))
            (loop (cdr args) (cons (car args) flags) ops)
            (loop (cdr args) flags (cons (car args) ops))))))

;; Add each port to the world list (if not already present), then write once.
(define (world-add-all ports)
  (world-read *world-file*)
  (let ((added '()))
    (for-each (lambda (p)
                (if (world-add p)
                    (set! added (cons p added))
                    (format #t "~a is already in the world file\n" p)))
              ports)
    (when (pair? added)
      (world-write *world-file*)
      (for-each (lambda (p) (format #t "added ~a to world file\n" p))
                (reverse added)))))

;; ---------------------------------------------------------------------------
;; main
;; ---------------------------------------------------------------------------

(define (usage)
  (display "usage:\n")
  (display "  install <port>...            build and install ports + missing deps\n")
  (display "  build <port>...              run pkgmk on ports (no install)\n")
  (display "  upgrade [--world] <port>...  upgrade ports, or --world for all outdated\n")
  (display "  depends <port>...            full dependency graph\n")
  (display "  depends --missing <port>...  only uninstalled deps\n")
  (display "  world [--missing|--orphan] [<file>]\n")
  (display "  world add|remove <pkg> [<file>]\n")
  (display "  diff                         installed vs ports versions\n"))

(let ((argv (cdr *command-line*)))
  (unless (pair? argv)
    (usage)
    (exit 1))

  (let ((cmd (car argv))
        (args (cdr argv)))

    (ports-clear)
    (for-each (lambda (d)
                (unless (load-ports d)
                  (error (format #f "failed to load ports from ~a" d))))
              *ports-dirs*)
    (unless (load-pkgs *pkg-db*) (error "failed to load pkgs"))

    (cond
     ((equal? cmd "install")
      (let* ((parts (split-args args))
             (ops (cdr parts)))
        (if (null? ops)
            (begin (usage) (exit 1)))
        (let* ((graph (resolve-graph ops))
               (to-build (filter (lambda (p) (not (installed? p))) graph)))
          (if (null? to-build)
              (format #t "nothing to build - requested packages and deps are already installed\n")
              (begin
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
          ;; record the requested ports in the world file (only reached on success)
          (world-add-all ops))))

     ((equal? cmd "build")
      (let* ((parts (split-args args))
             (ops (cdr parts)))
        (if (null? ops)
            (begin (usage) (exit 1)))
        (let ((failed '()))
          (for-each
           (lambda (p)
             (if (not (has-port? p))
                 (begin
                   (format (current-error-port) "~a is not in the ports tree\n" p)
                   (set! failed (cons p failed)))
                 (begin
                   (format #t "==> building ~a\n" p)
                   (unless (zero? (system (pkgmk-cmd p)))
                     (format (current-error-port) "pkgmk failed for ~a\n" p)
                     (set! failed (cons p failed))))))
           ops)
          (if (null? failed)
              (format #t "done.\n")
              (begin
                (format (current-error-port) "failed builds:\n")
                (for-each (lambda (p) (format (current-error-port) "  ~a\n" p)) failed)
                (exit 1))))))

     ((equal? cmd "upgrade")
      (let* ((parts (split-args args))
             (flags (car parts))
             (ops (cdr parts)))
        (cond
         ((member "--world" flags)
          ;; upgrade --world: upgrade every outdated port in the world file
          (let ((path *world-file*))
            (if (not (file-exists? path))
                (begin (format (current-error-port) "world file not found: ~a\n" path) (exit 1)))
            (let* ((pkgs (world-read path))
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
         ((null? ops)
          (usage) (exit 1))
         (else
          ;; upgrade <port>...
          (let ((failed '()))
            (for-each
             (lambda (port)
               (cond
                ((not (has-port? port))
                 (format (current-error-port) "~a is not in the ports tree\n" port)
                 (set! failed (cons port failed)))
                ((not (installed? port))
                 (format (current-error-port) "~a is not installed - use install instead\n" port)
                 (set! failed (cons port failed)))
                ((not (needs-upgrade? port))
                 (format #t "~a is up to date\n" port))
                (else
                 (format #t "upgrading ~a: ~a-~a -> ~a-~a\n" port
                         (installed-version port) (installed-release port)
                         (port-version port) (port-release port))
                 (if (zero? (system (pkgmk-cmd port)))
                     (unless (zero? (system (pkgadd-cmd port #t)))
                       (format (current-error-port) "pkgadd failed for ~a\n" port)
                       (set! failed (cons port failed)))
                     (begin
                       (format (current-error-port) "pkgmk failed for ~a\n" port)
                       (set! failed (cons port failed)))))))
             ops)
            (if (null? failed)
                (format #t "done.\n")
                (begin
                  (format (current-error-port) "failed upgrades:\n")
                  (for-each (lambda (p) (format (current-error-port) "  ~a\n" p)) failed)
                  (exit 1))))))))

     ((equal? cmd "depends")
      (let* ((parts (split-args args))
             (flags (car parts))
             (ops (cdr parts)))
        (if (null? ops)
            (begin (usage) (exit 1)))
        (let ((missing? (member "--missing" flags)))
          (for-each
           (lambda (p)
             (for-each (lambda (d)
                         (unless (and missing? (installed? d))
                           (display d) (newline)))
                       (resolve-graph (list p))))
           ops))))

     ((equal? cmd "world")
      (let* ((parts (split-args args))
             (flags (car parts))
             (ops (cdr parts)))
        (cond
         ;; world add <pkg> [<file>]  /  world remove <pkg> [<file>]
         ((and (pair? ops) (or (equal? (car ops) "add") (equal? (car ops) "remove")))
          (let* ((op (car ops))
                 (rest (cdr ops))
                 (pkg (and (pair? rest) (car rest)))
                 (path (if (and (pair? rest) (pair? (cdr rest)))
                           (cadr rest)
                           *world-file*)))
            (unless pkg (usage) (exit 1))
            (world-read path)
            (cond
             ((equal? op "add")
              (if (world-add pkg)
                  (begin (world-write path)
                         (format #t "added ~a to ~a\n" pkg path))
                  (begin (format #t "~a is already in ~a\n" pkg path) (exit 1))))
             (else
              (if (world-remove pkg)
                  (begin (world-write path)
                         (format #t "removed ~a from ~a\n" pkg path))
                  (begin (format #t "~a is not in ~a\n" pkg path) (exit 1)))))))
         (else
          (let ((path (if (pair? ops) (car ops) *world-file*)))
            (if (not (file-exists? path))
                (begin
                  (format (current-error-port) "world file not found: ~a\n" path)
                  (exit 1)))
            (let* ((pkgs (world-read path))
                   (graph (resolve-graph pkgs)))
              (cond
               ((member "--missing" flags)
                (for-each (lambda (p) (unless (installed? p) (display p) (newline))) graph))
               ((member "--orphan" flags)
                (let ((seen (make-hash-table 32)))
                  (for-each (lambda (p) (hash-table-set! seen p #t)) graph)
                  (for-each (lambda (p)
                              (unless (hash-table-ref seen p)
                                (display p) (newline)))
                            (all-installed))))
               (else
                (for-each (lambda (p) (display p) (newline)) graph)))))))))

     ((equal? cmd "diff")
      (for-each diff-version (all-installed)))

     (else
      (usage)
      (exit 1)))))
