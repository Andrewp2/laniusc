# Regex workspace compiler admission controls

These Lanius controls narrow the compiler diagnostic observed while
compiling the reusable regex increment. The six small reductions import no
`ext::regex`, parser, matcher, or extended-library source. The durable module
reproduction below intentionally imports regex. There is no replacement library.

- `workspace.lani` preserves the frozen constructor's exact dimension/product/
  byte checks, compound width guard, nine Vec initialization/resizes and partial
  cleanup. Only the required terminal destroy method and a small main remain.
  Its dummy Error retains the two constructor-used variants. Main constructs
  `(states=4, groups=1)` and destroys the same owner twice.
- `arithmetic.lani` preserves the same arithmetic and exact compound guard,
  returning requested bytes without vector storage or allocation. Its main
  checks the 44-element result using actual `size_of<i32>()`.

- `discard_try.lani` narrows an expression statement `probe(kind)?;` whose
  successful bool is discarded before returning an aggregate Span. Its paired
  `discard_explicit.lani` uses an explicit result/error branch. Both check
  success with false/true payloads and error propagation through the same main.

- `workspace_try.lani` and `workspace_explicit.lani` extend the passing
  constructor reduction with exactly one Result<Workspace,Error> propagation
  boundary. The first uses `let value = workspace(4,1)?`; the second uses
  explicit result/error checks. Their identical mains unwrap the propagated
  owner and destroy that same owner twice.

Constructor source copied from `extended/ext/regex.lani` SHA256
`cd7e82c74c9498d945e3bc5789cd624810219d7687062341e1f7f514cc64be76`.
The constructor and arithmetic controls both compiled and exited zero in root's
serialized native runs. Receipt:
`target/stdlib-work/regex-workspace-constructor-reductions-first.log`, with
individual `regex-workspace-{arithmetic,workspace}-control.log` files. Those
results rule out the isolated constructor arithmetic/nine-vector ownership as
sufficient to reproduce this diagnostic; they do not accept the regex module.
Both success-discard and workspace-propagation pairs also compile and exit
zero: `target/stdlib-work/regex-workspace-try-reductions-first.log`, with
individual control logs. All six small reductions pass. There is no established
single failing operator, constructor, aggregate shape, or discard form.

The original whole-module attempt remains in
`target/stdlib-work/regex-workspace-contracts-first-compile.log`: lowering SSA
dominance reason 17, detail kind 4, source HIR 5305, OptIR row 5250. The five
entry-point imports also failed LNC0057; that does not establish which imported
function is causal. Root confirmed eager lowering: even an unused
`import ext::regex` with a return-zero main fails with the same diagnostic
(`regex-workspace-unused-import-first.log`). Replacing only find_iter's nested
question marks with explicit locals also retained that diagnostic. Temporary
Search.next/Matches.next stubs did likewise. Stubbing the earlier VM changed
node numbering but retained dominance failure, motivating the success-discard
pair. A temporary full-module overlay replacing all new question-mark
expressions with equivalent explicit checks compiles
(`regex-workspace-all-explicit-control.log`). That result narrows the interaction
but does not establish which propagation expression or aggregate shape causes
the diagnostic. A single failing expression has not been isolated.

## Durable module reproduction

`unused_import.lani` is a five-line entry containing only an unused regex import
and return-zero main. `try-syntax.patch` restores the original question-mark
module from the accepted explicit-branch version. It changes nine source
locations containing ten question-mark operators, without storing a second
700-line module fork. It changes wrapper propagation only; parser, program,
matching engine, ownership, capacities and public APIs remain identical.

The patch has exact labels `a/ext/regex.lani` and `b/ext/regex.lani`.
Its base module SHA256 is
`4520d1fc663432af975dd774d07da0f3b747f2164c2465b8e62ff4b6b08e1659`.
The reconstructed original module SHA256 is
`cd7e82c74c9498d945e3bc5789cd624810219d7687062341e1f7f514cc64be76`;
that exact hash was checked during fixture preparation, and a CPU-only
`patch --fuzz=0` replay on a temporary copy restored it exactly. Apply the patch only
to a copy in a temporary source root. From the repository root:

```bash
regex_fixture_root="$PWD/tests/fixtures/stdlib_compiler_state/regex_workspace_admission"
regex_repro_root="$(mktemp -d /tmp/lanius-regex-workspace-repro.XXXXXX)"
mkdir -p "$regex_repro_root/ext"
cp extended/ext/regex.lani "$regex_repro_root/ext/regex.lani"
printf '%s  %s\n' 4520d1fc663432af975dd774d07da0f3b747f2164c2465b8e62ff4b6b08e1659 "$regex_repro_root/ext/regex.lani" | sha256sum --check
patch --fuzz=0 --directory="$regex_repro_root" -p1 < "$regex_fixture_root/try-syntax.patch"
printf '%s  %s\n' cd7e82c74c9498d945e3bc5789cd624810219d7687062341e1f7f514cc64be76 "$regex_repro_root/ext/regex.lani" | sha256sum --check
LANIUS_DEBUG_STAGE_ERRORS=1 timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root "$regex_repro_root" --emit x86_64 \
  "$regex_fixture_root/unused_import.lani" -o "$regex_repro_root/repro.elf"
```

Check both hashes before compiling. The patch base is version-specific; a newer
production module requires reviewing the reproduction rather than applying it
with fuzz. The original reconstructed import fails before producing a native
executable, with the dominance diagnostic above. This durable replay itself
has not yet been compiled; its source reproduces the exact already failing
module. The matching unpatched explicit-branch overlay compiles, as recorded in
`regex-workspace-all-explicit-control.log`. No production file is patched by
these steps.

This is a module-level compiler dependency. The passing small controls and
failed subset replacements do not justify claiming that ordinary question-mark
propagation or all large aggregate results fail. Existing question-mark
adoption in other accepted modules is separate evidence. No further compiler
repair is part of this library increment.

Root owns serialized compiler admission. These controls change neither compiler
nor production source; their individual native controls do not establish regex
runtime acceptance.
