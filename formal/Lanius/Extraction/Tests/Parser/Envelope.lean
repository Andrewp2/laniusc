import Lanius.Extraction.Parser.Envelope
import Lanius.Extraction.Entry.Domain.Parser
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.Envelope
open Lanius.Compiler.Parser
open Lanius.Compiler.Parser.Envelope

attribute [local instance] lexOrd

-- S → A, A → terminal | ε. The envelope includes nullable completion at
-- zero and ordinary completion after a token, not just the selected tree.
private def grammar : IndexedGrammar := ⟨{
  n_kinds := 1, n_nonterminals := 2, start_nonterminal := 0,
  split_token_kind := 44, split_component_kind := 13, canonical_kinds := [7],
  productions := [⟨0, [2]⟩, ⟨1, [0]⟩, ⟨1, []⟩] }, []⟩

private def items : List Item :=
  [(0,0,0,0), (0,1,0,0), (0,2,0,0), (0,0,1,0), (2,1,1,0), (2,0,1,0)]

example : check grammar [7] items = true := by decide
example : ChartClosed grammar [7] (workspace items) := check_closed (by decide)
example : (check? grammar [7] 7 items).isSome = true := by decide
example : (check? grammar [7] 6 items).isSome = false := by decide
example : (check? grammar [7] 0 items).isSome = false := by decide

-- Every item is required by some rule. Removing any one must fail, even
-- though several removals leave a complete accepting start item behind.
example : items.all (fun missing => !check grammar [7] (items.filter (· != missing))) = true := by decide
example : check grammar [7] items.reverse = true := by decide
example : check grammar [7] (items ++ items) = true := by decide
example : check grammar [7] ((0,999,0,0) :: items) = false := by decide
example : check grammar [8] items = true := by decide -- Extra states are safe upper bounds.

-- An untrusted index is checked for coverage, not taken as a list of the
-- obligations the checker should inspect.
example : checkWithIndex grammar [7] items { buildIndex grammar items with completions := ∅ } = false := by decide
example : checkWithIndex grammar [7] items { buildIndex grammar items with predictions := ∅ } = false := by decide

private def splitGrammar : IndexedGrammar := ⟨{
  n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
  split_token_kind := 44, split_component_kind := 13, canonical_kinds := [13],
  productions := [⟨0, [0,0]⟩] }, []⟩
private def splitItems : List Item := [(0,0,0,0), (1,0,1,0), (2,0,2,0)]

example : check splitGrammar [44] splitItems = true := by decide
example : check splitGrammar [44] [(0,0,0,0), (2,0,2,0)] = false := by decide
example : check splitGrammar [44] [(0,0,0,0), (1,0,1,0), (3,0,2,0)] = false := by decide

-- Sparse completion buckets exercise the indexed path at a size at which
-- comparing every candidate pair would already entail 400 million checks.
private def epsilonGrammar : IndexedGrammar := ⟨{
  n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
  split_token_kind := 44, split_component_kind := 13, canonical_kinds := [7],
  productions := [⟨0, []⟩] }, []⟩

#eval (do
  let candidates := (List.range 20000).map fun position => (position, 0, 0, position)
  let start ← IO.monoMsNow
  unless check epsilonGrammar [] candidates do throw (IO.userError "Sparse envelope rejected")
  IO.println s!"20,000-item sparse envelope accepted in {(← IO.monoMsNow) - start} ms" : IO Unit)

private def transport (words : List Nat) : ByteArray :=
  ByteArray.mk ((words.flatMap fun value =>
    [UInt8.ofNat value, UInt8.ofNat (value / 256), UInt8.ofNat (value / 65536),
      UInt8.ofNat (value / 16777216)]).toArray)

#eval (do
  let payload := [1, 1, 0, 0, 1, items.length, 0, 0] ++
    items.flatMap (fun entry => [entry.1, entry.2.1, entry.2.2.1, entry.2.2.2])
  let encoded := transport payload
  let some [candidate] := decode? encoded | throw (IO.userError "valid envelope transport rejected")
  unless candidate.tokenCount == 1 && candidate.items == items do
    throw (IO.userError "envelope coordinates did not round-trip")
  for length in [:encoded.size] do
    unless (decode? (encoded.extract 0 length)).isNone do
      throw (IO.userError s!"truncated transport accepted at {length}")
  for corrupted in [payload.set 0 2, payload.set 1 4294967295, payload.set 2 1,
      payload.set 5 4294967295, payload.set 6 1, payload ++ [0,0,0,0]] do
    unless (decode? (transport corrupted)).isNone do
      throw (IO.userError "malformed envelope length/version/reserved field accepted")
  IO.println "envelope transport rejects every truncation, oversized counts, wrong version, reserved fields, and trailing records" : IO Unit)

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``chartSound, ``contains_iff, ``checkWithIndex_closed, ``check_closed,
      ``checked_length_le, ``Checked.states_lt, ``check?,
      ``ParserRecognize.RecognizerCallExecution.success_of_envelope,
      ``Frontend.checkArtifactParserStorage?, ``Frontend.checkUnitsParserStorage?,
      ``Entry.CheckedExecution.checkParserDomain?, ``Entry.File.Resources.no_parser_capacity,
      ``Entry.File.Resources.frontend_success_or_tree_resource] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Envelope checker {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Finite envelope checking covers seed/predict/scan/nullable completion, rejects missing coverage, and proves the actual source call succeeds on recognized inputs within capacity."

end Lanius.Extraction.Tests.Parser.Envelope
