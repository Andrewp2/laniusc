# Verification status

Status: active and incomplete. The replacement proof is one certificate-driven
spine; it is not a collection of per-program execution proofs.

## Connected proof currently available

For an accepted version-3 certificate, the Lean checker now connects:

1. exact source bytes to checked lexer, grammar, parse, Surface, declaration,
   import, and typing evidence;
2. the reconstructed Surface program to an authenticated typed Core lowering;
3. canonical Core transport, certificate-owned ELF bytes, and exact function
   spans to the currently accepted x86 backend fragment;
4. ELF startup, the selected zero-argument Core entrypoint, its uniform return
   state, and the return-to-syscall suffix.

The actual certificate encoder and decoder have a generic round-trip theorem
under explicit representability bounds. Accepted round trips recover the exact
compact payload, transport words, ELF bytes, and ordered function spans.

The native Lanius compiler's full `--certificate` mode is exercised by a
two-function source and accepted by the same checker with 34 transport words,
529 ELF bytes, and two ordered function spans.  The resulting one- and
two-function artifacts also pass the startup/entry-slice checker used by the
public x86 execution theorem.  This is connected evidence for the real output
path, while the general theorem about the Lanius generator itself remains
open.

The native Lanius extractor now emits one independently checked compact
artifact for the exact current 13-unit frontend/emitter source closure.  The
specialized Lean checker validates exact bytes, lexer traces, grammar
derivations, and reconstructed Surface for all 13 units.  Older JSON Core
payloads used by function-level proofs are not treated as current-source
evidence: the frontend and emitter boundaries each expose one explicit Core
program equality that must be discharged against a current checked lowering.

The current full facade builds 224 jobs in about one second cached. Focused
connected checks are normally below six seconds, and the current 13-unit source
closure checks in under one second including process startup.  These are
checking measurements, not substitutes for the remaining semantic proofs.

## What remains

This is not yet a proof of the entire compiler or extractor. The principal
open obligations are:

- extend the now-authoritative recursive
  expression/statement/function proof with shared local/call/control-flow
  state relations; literal/unary/binary expressions, next-completing
  statements, terminal returns, function epilogues, program checking, and ELF
  startup/exit are already connected;
- carry a real multi-unit cross-call through body lowering, transport, x86
  emission, certificate production, and the same independent checker;
- prove the Lanius certificate emitter phases produce the evidence accepted by
  the version-3 boundary;
- make the Lanius extractor emit the typed Core evidence needed to discharge
  the single current-Core equality at each legacy deep-artifact boundary;
- scale the accepted Core/x86 subset to every construct reachable from the
  compiler and extractor, rejecting unsupported forms explicitly;
- self-extract and compile the extractor through the verified x86 path.

See `../formal/PROOF_ARCHITECTURE.md` for the theorem shape, trust boundary,
performance gates, and ordered next steps.
