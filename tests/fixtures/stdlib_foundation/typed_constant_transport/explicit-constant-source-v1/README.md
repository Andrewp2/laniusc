# Source cases (not executed)

These are intended inputs for the root integration lane, not claims of passing coverage. Every command must remain below two minutes. Reuse the existing GPU compiler executable-test harness; do not add a host compiler or evaluator.

- `runtime_typed_operands.lani`: compile, specialize, link, and execute on x86; expected exit0. Covers nonzero high limb, all-ones bits, signed minimum, booleans, char, narrow signed minimum, plus syntax, forwarded parameter, and qualified ordinary constants. A compile-only result is insufficient.
- `grammar_and_hir_boundaries.lani`: parser/HIR checks only. Assert full literal limbs, separate unary negative child, bool/char forms, float sign syntax, bound argument root, and both array payload.d values are valid operand HIR references. In particular, 4294967295 is a valid literal payload, not the missing-node sentinel. Do not allocate either maximum-size array to exercise this parser contract.
- `reject_*.lani`: each must parse then fail checking with an explicit diagnostic; no executable artifact. Full-width integer lexer overflow beyond u64 remains separately covered by numeric-v2 tests.
- `dependency_computed_const.lani`: must fail explicitly until canonical checked constexpr values are available before nominal/explicit binding; never treat VALUE as a generic parameter or use zero.
- `dependency_body_local_const.lani`: must fail explicitly at the staged boundary until canonical lexical ordinary-value lookup is available before nominal binding. It must never select module VALUE=1 under the local VALUE=2 shadow.
- `dependency_f64_literal.lani`: currently must fail explicitly. Enable an executable bit-exact check only after the float parser publishes independently rounded binary64 payload.

Additional integrated checks after imported projection changes: imported bool/char/u64 constants, imported generic own headers with interleaved domains, symbolic forwarded scalar mismatch, nested nominal arguments, arrays through symbolic count projections, and f32 +0/-0 retained identities. Shader synthetic identity probes alone do not cover these source paths.
