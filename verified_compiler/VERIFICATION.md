# Verification status

Status: active and incomplete. The direct Lean path and the older
certificate-based backend path share semantic checks but have different trust
boundaries.

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

The native Lanius extractor now emits Lean Core directly by default from the
semantic IR shared with x86 compilation. `--lean-checked` also emits a typed
frontend artifact that the independent Lean checker validates against source
bytes, lexer traces, grammar derivations, and reconstructed Surface. This
checked path is practical for small connected programs; the full extractor
closure's parser derivation is too large for routine per-program checking.
The compiler's explicit `--certificate` mode still supports the separate
legacy backend proof while its migration remains open.

With shared Lean infrastructure built, the direct two-source source-to-Core
check takes about 1.2 seconds. The 86-source extractor emits Core-only Lean in
about 25 seconds, and that generated module checks in about 20 seconds; this
is only a Core-typing check, not a full source-to-Core proof. Its full checked
frontend is about 68 MB and did not finish checking under a 105-second
diagnostic cap. These timings are measurements, not correctness claims.

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
- prove the Lanius extractor's general source-to-Core and Lean-emission
  correctness so ordinary Core-only output need not carry a full parser
  derivation for every program;
- scale the accepted Core/x86 subset to every construct reachable from the
  compiler and extractor, rejecting unsupported forms explicitly;
- self-extract and compile the extractor through the verified x86 path.

See `../formal/PROOF_ARCHITECTURE.md` for the theorem shape, trust boundary,
performance gates, and ordered next steps.
