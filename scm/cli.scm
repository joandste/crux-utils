;;; cli.scm --- CRUX package CLI (s7)
;;;
;;; Commands: install, build, upgrade, depends, world, diff.
;;;
;;;   install <port>...            build and install ports + missing deps
;;;   build <port>...              run pkgmk on ports (no install)
;;;   upgrade [--world] <port>...  upgrade ports, or --world for all outdated
;;;   depends <port>...            full dependency graph
;;;   depends --missing <port>...  only uninstalled deps
;;;   world [--missing|--orphan]   effective world
;;;   world add|remove <pkg>       edit the user world file
;;;   diff                         installed vs ports versions
;;;
;;; Sections:
;;;   1. Configuration - paths and the settings procedures the commands call
;;;   2. World         - the effective world (hackable)
;;;   3. Helpers       - small shared functions
;;;   4. Commands      - argument handling and dispatch
;;;
;;; Everything builds on the C interface (load-ports, load-pkgs, has-port?,
;;; port-version/release/dir/deps, installed?, installed-version/release,
;;; all-ports, all-installed) plus the settings in section 1.

;; ===========================================================================
;; 1. Configuration - edit these.
;; ===========================================================================

;; Port collections to scan (one level deep, no recursion) and the pkg db.
(define *ports-dirs* '(;; "/usr/ports/local"
                       "/usr/ports/contrib" "/usr/ports/core" "/usr/ports/opt" "/usr/ports/xorg"))
(define *pkg-db* "/var/lib/pkg/db")

;; The auto-maintained file that `install` / `world add` / `world remove`
;; write to; the World section reads it back in for the effective world.
(define *user-world-file* "/var/lib/pkg/world")

;; The commands call these directly.  The defaults spawn a shell; all return
;; #t on success.
;;
;;   (pkgmk p)            build port p                      -> #t
;;   (pkgadd p upgrade?)  install / upgrade port p          -> #t
;;   (world-add p)        record p in the user world file   -> #t
;;   (world-del p)        forget p from the user world file -> #t
;;
;; Make world-add/world-del no-ops (just return #t) to stop tracking installs.
(define (pkgmk p)
  (zero? (system (string-append "cd " (port-dir p) " && rootlesskit pkgmk -d"))))

(define (pkgadd p upgrade?)
  (zero? (system (string-append "pkgadd" (if upgrade? " -u" "") " /tmp/" p "#"
                                (port-version p) "-" (port-release p) ".pkg.tar.*"))))

(define (world-add p)
  (zero? (system (string-append "echo " p " >> " *user-world-file*))))

(define (world-del p)
  (zero? (system (string-append "sed -i '/^" p "$/d' " *user-world-file*))))

;; ===========================================================================
;; 2. World - the effective world.  Hack this block however you like.
;;    *world* is set in the Commands section once the ports tree is loaded; it
;;    is what `world`, `world --missing`, `world --orphan` and
;;    `upgrade --world` operate on.
;; ===========================================================================

;; unique elements, preserving first-occurrence order
(define (dedupe lst)
  (let loop ((lst lst) (seen '()) (result '()))
    (cond ((null? lst) (reverse result))
          ((member (car lst) seen) (loop (cdr lst) seen result))
          (else (loop (cdr lst) (cons (car lst) seen) (cons (car lst) result))))))

;; The packages you installed by hand, read line by line from the auto file.
(define (read-user-packages)
  (let ((out '()))
    (when (file-exists? *user-world-file*)
      (call-with-input-file *user-world-file*
        (lambda (port)
          (let loop ()
            (let ((line (read-line port)))
              (unless (eof-object? line)
                (set! out (cons line out))
                (loop)))))))
    (reverse out)))

;; The base system: every port in the core collection.
;; Prefer a fixed list?  Swap for:
;;   (define core-packages '(base-files bash binutils coreutils ...))
(define (core-packages)
  (let ((core "/usr/ports/core")
        (out '()))
    (for-each (lambda (p)
                (let ((d (port-dir p)))
                  (when (and (>= (string-length d) (string-length core))
                             (string=? (substring d 0 (string-length core)) core))
                    (set! out (cons p out)))))
              (all-ports))
    out))

;; The effective world.  Hack this line however you like:
;;   (dedupe (read-user-packages))                    ; drop the base system
;;   (dedupe (append '("vim") (read-user-packages)))  ; fixed extras
(define (effective-world)
  (dedupe (append (core-packages) (read-user-packages))))

;; Set in the Commands section, after the ports tree is loaded.
(define *world* '())

;; ===========================================================================
;; 3. Helpers - small shared functions.
;; ===========================================================================

;; s7 doesn't have filter - provide it.
(define (filter pred lst)
  (let loop ((lst lst) (result '()))
    (if (null? lst)
        (reverse result)
        (loop (cdr lst)
              (if (pred (car lst))
                  (cons (car lst) result)
                  result)))))

;; Split args into (flags . operands); flags are args starting with "-".
(define (split-args args)
  (let loop ((args args) (flags '()) (ops '()))
    (if (null? args)
        (cons (reverse flags) (reverse ops))
        (if (and (> (string-length (car args)) 0)
                 (equal? (string-ref (car args) 0) #\-))
            (loop (cdr args) (cons (car args) flags) ops)
            (loop (cdr args) flags (cons (car args) ops))))))

;; Full dependency graph, each dependency before its dependents.
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

;; #t if p is installed and the ports tree has a newer version.
(define (needs-upgrade? p)
  (and (has-port? p) (installed? p)
       (let ((pv (port-version p)) (pr (port-release p))
             (sv (installed-version p)) (sr (installed-release p)))
         (or (not (equal? pv sv)) (not (equal? pr sr))))))

;; Print a version comparison line for an installed package.
(define (diff-version p)
  (if (has-port? p)
      (let ((pv (port-version p)) (pr (port-release p))
            (sv (installed-version p)) (sr (installed-release p)))
        (if (or (not (equal? pv sv)) (not (equal? pr sr)))
            (format #t "~a  installed ~a-~a  ports ~a-~a\n" p sv sr pv pr)))
      (format #t "~a  installed (not in ports tree)\n" p)))

;; ===========================================================================
;; 4. Commands
;; ===========================================================================

(define (usage)
  (display "usage:\n")
  (display "  install <port>...            build and install ports + missing deps\n")
  (display "  build <port>...              run pkgmk on ports (no install)\n")
  (display "  upgrade [--world] <port>...  upgrade ports, or --world for all outdated\n")
  (display "  depends <port>...            full dependency graph\n")
  (display "  depends --missing <port>...  only uninstalled deps\n")
  (display "  world [--missing|--orphan]   effective world\n")
  (display "  world add|remove <pkg>       edit the user world file\n")
  (display "  diff                         installed vs ports versions\n"))

(let ((argv (cdr *command-line*)))
  (unless (pair? argv)
    (usage)
    (exit 1))

  (let ((cmd (car argv))
        (args (cdr argv)))

    ;; Load the port collections and the pkg db, then compute the world.
    (ports-clear)
    (for-each (lambda (d)
                (unless (load-ports d)
                  (error (format #f "failed to load ports from ~a" d))))
              *ports-dirs*)
    (unless (load-pkgs *pkg-db*) (error "failed to load pkgs"))
    (set! *world* (effective-world))

    (cond
     ;; install <port>... - build and install the requested ports + missing
     ;; deps, then record the requested ports in the world file.
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
                            (unless (pkgmk p)
                              (format (current-error-port) "pkgmk failed for ~a\n" p)
                              (exit 1))
                            (unless (pkgadd p #f)
                              (format (current-error-port) "pkgadd failed for ~a\n" p)
                              (exit 1)))
                          to-build)
                (format #t "done.\n")))
          ;; record the requested ports (only reached on success)
          (for-each (lambda (p) (world-add p)) ops))))

     ;; build <port>... - run pkgmk on each port, no install.
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
                   (unless (pkgmk p)
                     (format (current-error-port) "pkgmk failed for ~a\n" p)
                     (set! failed (cons p failed))))))
           ops)
          (if (null? failed)
              (format #t "done.\n")
              (begin
                (format (current-error-port) "failed builds:\n")
                (for-each (lambda (p) (format (current-error-port) "  ~a\n" p)) failed)
                (exit 1))))))

     ;; upgrade --world - upgrade every outdated port in the world.
     ;; upgrade <port>... - upgrade the given ports.
     ((equal? cmd "upgrade")
      (let* ((parts (split-args args))
             (flags (car parts))
             (ops (cdr parts)))
        (cond
         ((member "--world" flags)
          (if (null? *world*)
              (begin (format (current-error-port) "world is empty - edit the World block in cli.scm\n") (exit 1)))
          (let* ((graph (resolve-graph *world*))
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
                        (unless (pkgmk p)
                          (format (current-error-port) "pkgmk failed for ~a\n" p) (exit 1))
                        (unless (pkgadd p #t)
                          (format (current-error-port) "pkgadd failed for ~a\n" p) (exit 1)))
                      to-upgrade)
            (format #t "done.\n")))
         ((null? ops)
          (usage) (exit 1))
         (else
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
                 (if (pkgmk port)
                     (unless (pkgadd port #t)
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

     ;; depends <port>... - full dependency graph (with --missing, only deps
     ;; that aren't installed).
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

     ;; world add <pkg> / world remove <pkg> - call the world-add / world-del
     ;; settings directly.  world [--missing|--orphan] - show the world.
     ((equal? cmd "world")
      (let* ((parts (split-args args))
             (flags (car parts))
             (ops (cdr parts)))
        (cond
         ((and (pair? ops) (or (equal? (car ops) "add") (equal? (car ops) "remove")))
          (let* ((op (car ops))
                 (rest (cdr ops))
                 (pkg (and (pair? rest) (car rest))))
            (unless pkg (usage) (exit 1))
            (if (equal? op "add")
                (if (world-add pkg)
                    (format #t "added ~a to the world\n" pkg)
                    (begin (format (current-error-port) "world-add failed for ~a\n" pkg)
                           (exit 1)))
                (if (world-del pkg)
                    (format #t "removed ~a from the world\n" pkg)
                    (begin (format (current-error-port) "world-del failed for ~a\n" pkg)
                           (exit 1))))))
         (else
          (if (pair? ops)
              (begin (format (current-error-port) "unexpected argument: ~a\n" (car ops))
                     (exit 1)))
          (let ((graph (resolve-graph *world*)))
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
              (for-each (lambda (p) (display p) (newline)) graph))))))))

     ;; diff - installed vs ports versions.
     ((equal? cmd "diff")
      (for-each diff-version (all-installed)))

     (else
      (usage)
      (exit 1)))))
