import Lanius.Extraction.Parser.Tree.Failure

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout Lanius.Extraction.ParserTreeDerivation

/-- Successful output is exact. On failure the output buffers may contain
    partial work, but the status and returned cursors remain bounded. A separate
    `CellEffect` confines those partial writes to the two output buffers. -/
def TreeRuntime.Result (runtime : TreeRuntime) (tree : Lanius.Compiler.Parser.ParseTree)
    (code : Int) (nodes words : Nat) (cells : List Cell) : Prop :=
  let serialized := treeFrom runtime.nodeBase runtime.wordBase tree
  (code = 0 ∨ code = 2 ∨ code = 3) ∧
    runtime.nodeBase ≤ nodes ∧ nodes ≤ runtime.offsets.length ∧
    runtime.wordBase ≤ words ∧ words ≤ runtime.records.length ∧
    (code = 0 → nodes = runtime.nodeBase + serialized.offsets.length ∧
      words = runtime.wordBase + serialized.words.length ∧
      ({ cells := cells } : State).cellEntry? runtime.recordsCell = some {
        id := runtime.recordsCell, value := some (.array (signedI32Values
          (runtime.records.take runtime.wordBase ++ serialized.words ++ runtime.records.drop words))) } ∧
      ({ cells := cells } : State).cellEntry? runtime.offsetsCell = some {
        id := runtime.offsetsCell, value := some (.array (signedI32Values
          (runtime.offsets.take runtime.nodeBase ++ serialized.offsets.map Int.ofNat ++ runtime.offsets.drop nodes))) })

theorem TreeRuntime.Result.failure (runtime : TreeRuntime) (tree : Lanius.Compiler.Parser.ParseTree)
    (code : Int) (nodes words : Nat) (cells : List Cell)
    (failed : code = 2 ∨ code = 3)
    (nodesStart : runtime.nodeBase ≤ nodes) (nodesBound : nodes ≤ runtime.offsets.length)
    (wordsStart : runtime.wordBase ≤ words) (wordsBound : words ≤ runtime.records.length) :
    runtime.Result tree code nodes words cells :=
  ⟨Or.inr failed, nodesStart, nodesBound, wordsStart, wordsBound, by intro success; omega⟩

/-- Later result construction may allocate locals without changing the tree
certificate or bounded partial-output contract. -/
theorem TreeRuntime.Result.preserved {runtime : TreeRuntime} {writes : CellSet}
    (result : runtime.Result tree code nodes words before.cells)
    (wellFormed : StateWellFormed before) (effect : CellEffect writes before after)
    (recordsUntouched : ¬ writes runtime.recordsCell) (offsetsUntouched : ¬ writes runtime.offsetsCell) :
    runtime.Result tree code nodes words after.cells := by
  rcases result with ⟨status, nodesStart, nodesBound, wordsStart, wordsBound, success⟩
  refine ⟨status, nodesStart, nodesBound, wordsStart, wordsBound, ?_⟩
  intro accepted
  obtain ⟨nodesExact, wordsExact, records, offsets⟩ := success accepted
  exact ⟨nodesExact, wordsExact, effect.preserves_entry wellFormed records recordsUntouched,
    effect.preserves_entry wellFormed offsets offsetsUntouched⟩

/-- The failure branch carries the actual returned value through arbitrary
    successful prefixes. It is not an accepted partial tree. -/
def TreeRuntime.Failed (runtime : TreeRuntime) (symbols : Symbols) (completion : Completion) : Prop :=
  ∃ code nodes words, (code = 2 ∨ code = 3) ∧
    runtime.nodeBase ≤ nodes ∧ nodes ≤ runtime.offsets.length ∧
    runtime.wordBase ≤ words ∧ words ≤ runtime.records.length ∧
    completion = .returned (some (resultValue symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)))

/-- One smaller-state obligation, including both success and failure. Unlike
    `EarlierCalls`, it does not require the selected child to fit. -/
def TreeRuntime.EarlierSteps (runtime : TreeRuntime) (checked : CheckedVisit program)
    (rootId : Nat) (allTrees : List Lanius.Compiler.Parser.ParseTree) (frame : State → Prop)
    (grammar : IndexedGrammar) (workspace : LogicalWorkspace) : Prop :=
  ∀ (processed : List Lanius.Compiler.Parser.ParseTree) (pending : List Child)
    (childId : Nat) (child : Lanius.Compiler.Parser.ParseTree) (state : State),
    runtime.At processed (.state childId :: pending) state → frame state → childId < rootId →
    ChildExpansion grammar workspace (.state childId) child → child ∈ allTrees →
    ∃ completion after, Executes program.core state (childIteration checked.symbols) completion after ∧
      ((completion = .next ∧ runtime.At (processed ++ [child]) pending after) ∨ runtime.Failed checked.symbols completion) ∧
      CellEffect runtime.writes state after

/-- Execute every successful sibling until either the list ends or the first
    failed recursive child returns. No total-tree capacity or depth assumption
    is made. Whole-call induction must construct `EarlierSteps`. -/
theorem TreeRuntime.At.loop_outcome {runtime : TreeRuntime} (checked : CheckedVisit program)
    (allTrees : List Lanius.Compiler.Parser.ParseTree) (frame : State → Prop)
    (retain : ∀ {processed pending state after}, runtime.At processed pending state →
      frame state → CellEffect runtime.writes state after → frame after)
    (rootId : Nat) (recursive : runtime.EarlierSteps checked rootId allTrees frame grammar workspace)
    (held : runtime.At processed pending before) (framed : frame before)
    (matched : ChildrenExpansion grammar workspace pending remaining)
    (selected : processed ++ remaining = allTrees)
    (earlier : ∀ childId, .state childId ∈ pending → childId < rootId) :
    ∃ completion after, Executes program.core before
        (.whileLoop (.binary .notEqual (.local 15) (.local 12)) (childIteration checked.symbols)) completion after ∧
      ((completion = .next ∧ runtime.At allTrees [] after ∧ frame after) ∨ runtime.Failed checked.symbols completion) ∧
      CellEffect runtime.writes before after := by
  have localRead {id : Lanius.VarId} {value : Value} (found : before.local? id = some value) :
      Evaluates program.core before (.local id) value before :=
    ⟨1, evalLocal_of_local 0 program.core before id value found⟩
  cases matched with
  | nil =>
    have equal : processed.length = runtime.parent.dot := by simpa using held.count
    have finished : processed = allTrees := by simpa using selected
    refine ⟨.next, before, ?_, Or.inl ⟨rfl, finished ▸ held, framed⟩, CellEffect.refl held.wellFormed⟩
    exact executesWhileFalse (evaluatesEagerBinary (by decide) (by decide)
      (localRead (Assertion.localPointsTo_local _ _ _ _ held.cursorOwned)) (localRead held.countLocal)
      (by simp [evalBinaryValue, scalarEqual, equal]))
  | @cons reference child references remaining head tail =>
    have different : processed.length ≠ runtime.parent.dot := by
      have count := held.count
      simp only [List.length_cons] at count
      omega
    have condition : Evaluates program.core before (.binary .notEqual (.local 15) (.local 12)) (.boolean true) before :=
      evaluatesEagerBinary (by decide) (by decide)
        (localRead (Assertion.localPointsTo_local _ _ _ _ held.cursorOwned)) (localRead held.countLocal)
        (by simp [evalBinaryValue, scalarEqual]; exact fun equal => different (Int.ofNat.inj equal))
    have step : ∃ completion middle, Executes program.core before (childIteration checked.symbols) completion middle ∧
        ((completion = .next ∧ runtime.At (processed ++ [child]) references middle) ∨ runtime.Failed checked.symbols completion) ∧
        CellEffect runtime.writes before middle := by
      cases head with
      | token =>
        obtain ⟨middle, executed, next, effect⟩ := held.token_step checked
        refine ⟨.next, middle, executed, Or.inl ⟨rfl, next⟩, effect.weaken ?_⟩
        intro cell member
        simp_all [TreeRuntime.writes, CellSet.singleton]
      | state found productionBound complete enough computed =>
        exact recursive processed references _ _ before held framed (earlier _ (List.mem_cons_self ..))
          (.state found productionBound complete enough computed)
          (selected ▸ (List.mem_append.mpr (Or.inr (List.mem_cons_self ..))))
    obtain ⟨completion, middle, executed, outcome, stepEffect⟩ := step
    rcases outcome with ⟨rfl, next⟩ | failed
    · have selectedNext : (processed ++ [child]) ++ remaining = allTrees := by
        simpa only [List.append_assoc, List.singleton_append] using selected
      obtain ⟨completion, after, loop, outcome, loopEffect⟩ := TreeRuntime.At.loop_outcome checked allTrees frame retain
        rootId recursive next (retain held framed stepEffect) tail selectedNext
        (fun childId member => earlier childId (List.mem_cons_of_mem reference member))
      exact ⟨completion, after, executesWhileTrueThen condition executed loop, outcome, stepEffect.trans loopEffect⟩
    · obtain ⟨code, nodes, words, failedCode, nodesStart, nodesBound, wordsStart, wordsBound, rfl⟩ := failed
      exact ⟨_, middle, executesWhileReturned condition executed,
        Or.inr ⟨code, nodes, words, failedCode, nodesStart, nodesBound, wordsStart, wordsBound, rfl⟩, stepEffect⟩
termination_by pending.length

end Lanius.Extraction.ParserTreeSource
