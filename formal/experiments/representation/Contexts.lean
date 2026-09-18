import SelfSurface
import Lanius.Extraction.Reconstruction.Contexts
import Lean.Util.CollectAxioms

/-! Profile real byte-I/O precedence contexts using saved source data and caches.
Native proposal is untrusted: the kernel rechecks each source range and applies
the general context theorem. This is a fragment benchmark, not a fresh unit or
whole-compiler certificate. Build Lanius.Extraction.Tests.Contexts first, then
run this recipe with `lake -d formal run certify` from the repository root. -/

open Lean Elab Lanius.Extraction Lanius.Extraction.Reconstruction
open Lanius.Extraction.Self.Surface.ByteIO
namespace ContextProbe
set_option maxRecDepth 4096
set_option maxHeartbeats 2000000
set_option compiler.extract_closed false

private def phase (message : String) : IO Unit :=
  IO.FS.withFile "target/verified-compiler/context-probe-phases.log" .append fun handle => do
    handle.putStrLn s!"[{← IO.monoMsNow} ms] {message}"
    handle.flush

private def base (entry : Nat × ParseNode) : ParseTree := .node entry.1 entry.2 []

elab "contexts%" : term => do
  let emitted ← IO.FS.readFile "target/verified-compiler/SelfCompactRequirements.lean"
  let some first := (emitted.splitOn "def encodedPack : String := \"")[1]?
    | throwError "missing compact literal"
  let some encoded := (first.splitOn "\"").head? | throwError "missing literal end"
  let some pack := decodeCompactArtifactPack? encoded | throwError "invalid compact input"
  let some unit := pack.units[2]? | throwError "missing byte-I/O unit"
  let table := unit.parse_nodes.toArray
  let candidates := unit.parse_nodes.zipIdx.filterMap fun (node, id) =>
    if node.nonterminal != 131 then none else
    let entry := (id, node)
    if (Contexts.nodes Contexts.levels (base entry)).zipIdx.all
        (fun (expected, offset) => table[id + 1 + offset]? == some expected) then
      some entry
    else none
  phase s!"proposed {candidates.length} complete precedence contexts ({candidates.length * 20} nodes)"
  quoteBounded candidates (compile := false)

run_elab do
  IO.FS.writeFile "target/verified-compiler/context-probe-phases.log" ""
  phase "start quotation"
private noncomputable def candidates : List (Nat × ParseNode) := contexts%

private noncomputable def requirements (entry : Nat × ParseNode) : Bool :=
  indexed.cache.parseNodes.rangeEq entry.1 (entry.2 :: Contexts.nodes Contexts.levels (base entry)) &&
    decide (entry.2.nonterminal = 131 ∧ entry.2.position_start ≤ entry.2.position_end ∧
      entry.2.position_end ≤ parseView.semanticKinds.size * 2)

run_elab phase "quoted; authenticate all source nodes and bounds"
set_option Elab.async false in
private theorem authenticated : candidates.all requirements = true := by decide +kernel
run_elab phase "authenticated; apply shared context proof"

private noncomputable def check (entry : Nat × ParseNode) : Bool :=
  checkNodesFromParseView laniusGrammar artifact parseView (entry.1 + 1)
    (Contexts.nodes Contexts.levels (base entry))

set_option Elab.async false in
theorem retained : candidates.all check = true := by
  apply List.all_eq_true.mpr
  intro entry member
  have accepted := List.all_eq_true.mp authenticated entry member
  unfold requirements at accepted
  simp only [Bool.and_eq_true, decide_eq_true_eq] at accepted
  obtain ⟨range, properties⟩ := accepted
  have matched := Contexts.matchesSource_of_range indexed (base entry) range
  exact Contexts.source_checked parseView (base entry) matched
    properties.1 properties.2.1 properties.2.2

run_elab phase "shared proof checked; run original node validator"
set_option Elab.async false in
theorem recomputed : candidates.all check = true := by decide +kernel
run_elab phase "indexed validator checked; run current fused linker"
set_option Elab.async false in
theorem fused : candidates.all (fun entry =>
    (Validated.linkFrom laniusGrammar parseView Parse.productions.lookup (entry.1 + 1)
      (Contexts.nodes Contexts.levels (base entry)) [base entry]).isSome) = true := by decide +kernel
run_elab phase "fused linker checked; audit"

run_elab do
  for name in #[``retained, ``recomputed, ``fused, ``Contexts.precedence_eq, ``Contexts.precedence_link] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "unexpected axiom {assumption} in {name}"
  phase "audit passed"
end ContextProbe
