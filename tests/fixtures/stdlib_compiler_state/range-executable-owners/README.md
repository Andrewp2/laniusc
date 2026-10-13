# Reachable instruction ownership

The GPU compiler now uses its validated CFG reachability consistently for executable access rows, SSA definitions, aliases, operands, uses, and native instruction publication. Unreachable source rows remain available as provenance; their canonical executable fields are invalid and cannot satisfy a reachable use.

Thirteen distinct Linux x86-64 execution tests pass on the recorded build. They cover four formerly failing direct/named early-return range cases, unreachable call arguments and aggregate elements, nested/open-loop continue controls, the original named range program, wide ranges, endpoint snapshot semantics, repeated empty/inclusive ranges, and the imported numeric/stack-argument program. Every positive test compiles and executes an ELF.

The two runs have identical source and shader manifests. The recorded build predates float integration. Full-range break dominance and the combined postfix endpoint fixture remain separate unresolved failures; this evidence does not establish complete range or generics support.

Wasm source emission was preserved, but no Wasm runtime acceptance was run for this checkpoint.
