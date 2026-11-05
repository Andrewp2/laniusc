# cert spike RESUME
Worktree /home/andrew-peterson/code/laniusc-wt/cert, branch cert-spike (from origin/lang 0fec9e7dc).
Status 11-04: DONE (spike). FORMAT.md written here; REPORT content was returned to the coordinator
as text (the harness blocks subagents from writing report files).
Code formal/cert/: Export.lean+ExportGenP.lean (kernel-term exporter, run by assembling
data/RunExport.lean = ExportGenP imports + Export body, then lcheck), certlib.py (build/write/reference
check/digest), gen.py (generator, 27-axiom theory), check.lani (checker, lcc -> cert/check),
mutate.py + attacks.py (tests), leanbench.py (Omega.lean) + KernelBench.lean (Lean baselines),
theory_lean.py (axioms proved in Lean: lean/TheorySound.lean).
Key numbers: 3172 distinct obligations (15090 uses), 578,452 steps, 23.6 MB; Lanius check 118-183 ms;
Lean kernel on LinCert terms 15.7-16.9 s; omega 500: 34 s wall + 7 timeouts; gen 4.0 s python;
SelfP02 profile: tactics 405 s vs kernel 31.5 s.

## 11-04 stage 2 (branch `cert`, worktree laniusc-wt/cert)
- cert = local lang + cert-spike (formal/cert only) + FORMAT.md + check_mini.lani + mini_build.py; ed593555b, fast-forward of lang, gate 26/26.
- check_mini.elf (verified compiler) = check.lani's output on all.cert and 600 mutants; 0.45 s vs 0.23 s.
- Build: `python3 -I formal/cert/mini_build.py target/claude-work/cert/mini --run-all <main>/formal/.lake/build/bin/runAll` (from the worktree root).
- Next needs formal/Lanius (check in with the coordinator first): a Lean statement of the checker (its SrcProgram + compileSource_correct instance), then soundness of `check`.

## 11-04 stage 3 (Lean): branch cert at 690884b1d (ff of lang ed593555b), gate passes
- checkMini_process (Lanius/Cert/Process.lean): process_exits for check_mini's program.
- Proved: CertShallowSound (via CertCheckFacts, CertMatchSound), CertReferenceAxiomsHold, CertNatSound.red1.
- Open: CertMainFaithful only (Core run of main = Shallow.check); see its NOTES.md.

## 11-04 reflection experiment (no commits; files in target/claude-work/cert/reflect)
- `check (n+1) w = 0 := by decide +kernel` on ONE gen.py obligation certificate (3,054 words): not done at lv's 228 s stop.
- One kernel `rd` near index 3,000 of a List Int literal: ~70 ms (Parts.lean: 101 reads ~7 s). certlib.check needs median 22K reads (40 sampled obligations, 7K-107K).
- LinCert terms (what pre_auto emits now): ~5 ms kernel per obligation. SelfP02: 3,532 obligation uses; 405 s tactic = ~115 ms per use even if all were arithmetic; 11-03 phase profile (f14c/bp.log): arith ~21% of pre_auto time, ar.cert 5.2 s of 38 s.
- Verdict: not faster; pre_certs.py unchanged.
