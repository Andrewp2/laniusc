# PreCompileSource

- Not generated yet. `python3 -I tools/pre_certs.py Lanius/Faithful/GenB <outdir> compile_source` emits
  the M-form post and pre lemmas (as GenP does for build_files); the ones that fail become new statements
  under this one, their reduction this statement. Overrides and value lemmas: tools/pre_certs.py
  (OVERRIDES, PRE_HAND) and SelfPre/Values.lean. Type sizes are at most 2 ^ 22 only for the front end's
  output (the front end's weight check), hence the frontEndWords premise.
