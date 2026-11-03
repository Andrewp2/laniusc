# PreStepLetFirst

- 11-03 (f14c): `pre_auto` on the generated step (GenP/SelfP07, scratch:
  `f14c/tools/scratch.py 07 pre_step_let_first --debug`) works steadily for ~68 s (about 2,000 premise
  instantiations over Pre_let_first's if-chain of let forms) and hits maxHeartbeats 1000000; no single
  slow step. Options: a PRE_HAND entry in tools/pre_certs.py that splits the top-level `if`s and runs
  `pre_auto n, M` per branch (each under its own heartbeats), or caching hbFacts across sibling goals.
  Raising heartbeats alone would put P07 near 3-4 minutes.
