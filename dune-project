(lang dune 3.0)

(generate_opam_files true)

(package
 (name protean)
 (allow_empty)
 (synopsis "Protean: a programmable protocol emulator in Hardcaml")
 (maintainers "Caleb Norton")
 (authors "Caleb Norton")
 (homepage "https://github.com/gigamonster256/protean")
 (bug_reports "https://github.com/gigamonster256/protean/issues")
 (license Apache-2.0)
 (depends
  (ocaml (= 5.4.1))
  (dune (>= 3.20))
  (hardcaml (= v0.17.1))
  (ppx_hardcaml (= v0.17.1))
  (base (= v0.17.3))
  (stdio (= v0.17.0))
  (ppx_expect (= v0.17.3))
  (ocamlformat (= 0.29.0))))
