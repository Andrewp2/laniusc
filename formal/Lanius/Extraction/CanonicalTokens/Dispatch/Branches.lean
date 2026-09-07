import Lanius.Extraction.CanonicalTokens.Dispatch.Choices

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def dispatched (program : Program) (source : List Int) (start width : Nat)
    (fallback : ConstantId) : List Group → Int
  | [] => tag program fallback
  | group :: rest =>
      if width = group.width then
        (selected program source start group.width group.rules).getD
          (dispatched program source start width fallback rest)
      else dispatched program source start width fallback rest

theorem executes_branches (program : Program) (matcher fallback : Nat)
    (before : State) (sourceCell : CellId) (source : List Int) (start width : Nat) (groups : List Group)
    (found : program.function? matcher = some (Ascii.sourceFunction matcher))
    (valid : ∀ group ∈ groups, ∀ rule ∈ group.rules, ValidRule program group.width rule)
    (fallbackFound : program.constant? fallback = some {
      id := fallback, type := .scalar (.signed .i32), value := .signed .i32 (tag program fallback) })
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (startLocal : before.local? 1 = some (.signed .i32 start))
    (lengthLocal : before.local? 3 = some (.signed .i32 width))
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Executes program before (branches matcher fallback groups)
      (.returned (some (.signed .i32 (dispatched program source start width fallback groups)))) after ∧
      CellEffect CellSet.empty before after := by
  induction groups generalizing before with
  | nil =>
      refine ⟨before, executesSequenceReturned (executesReturnValue ?_), CellEffect.refl wellFormed⟩
      refine ⟨1, ?_⟩
      rw [evalExpr.eq_def]
      simp only [fallbackFound]
      rfl
  | cons group rest ih =>
      have tailValid : ∀ group ∈ rest, ∀ rule ∈ group.rules, ValidRule program group.width rule :=
        fun group member => valid group (List.mem_cons_of_mem _ member)
      have lengthResult : Evaluates program before (.local 3) (.signed .i32 width) before :=
        ⟨1, evalLocal_of_local 0 program before _ _ lengthLocal⟩
      have literal : Evaluates program before (.value (.signed .i32 group.width)) (.signed .i32 group.width) before := ⟨1, rfl⟩
      have tested : Evaluates program before (.binary .equal (.local 3) (.value (.signed .i32 group.width)))
          (.boolean ((width : Int) == (group.width : Int))) before :=
        evaluatesEagerBinary (by decide) (by decide) lengthResult literal (by rfl)
      by_cases same : width = group.width
      · have conditionTrue : Evaluates program before
            (.binary .equal (.local 3) (.value (.signed .i32 group.width))) (.boolean true) before := by
          simpa only [same, BEq.rfl] using tested
        obtain ⟨middle, chosen, frame⟩ := executes_choices program matcher before sourceCell source start
          group.width group.rules found (valid group (by simp)) wellFormed sourceLocal sourceContents
          startLocal (by simpa only [same] using capacity) bounded
        cases choice : selected program source start group.width group.rules with
        | none =>
            simp only [choice, selectedCompletion] at chosen
            obtain ⟨after, run, tailFrame⟩ := ih middle tailValid frame.wellFormed
              (frame.empty_preserves_local wellFormed sourceLocal) (frame.empty_preserves_entry wellFormed sourceContents)
              (frame.empty_preserves_local wellFormed startLocal) (frame.empty_preserves_local wellFormed lengthLocal)
            refine ⟨after, ?_, frame.trans tailFrame⟩
            simpa only [branches, dispatched, if_pos same, choice, Option.getD_none] using
              executesSequence (executesIfTrue conditionTrue chosen) run
        | some kind =>
            simp only [choice, selectedCompletion] at chosen
            refine ⟨middle, ?_, frame⟩
            simpa only [branches, dispatched, if_pos same, choice, Option.getD_some] using
              (executesSequenceReturned (second := branches matcher fallback rest)
                (executesIfTrue conditionTrue chosen))
      · have different : (width : Int) ≠ (group.width : Int) := fun equality => same (Int.ofNat.inj equality)
        have conditionFalse : Evaluates program before
            (.binary .equal (.local 3) (.value (.signed .i32 group.width))) (.boolean false) before := by
          simpa only [beq_eq_false_iff_ne.mpr different] using tested
        obtain ⟨after, run, frame⟩ := ih before tailValid wellFormed sourceLocal sourceContents startLocal lengthLocal
        refine ⟨after, ?_, frame⟩
        simpa only [branches, dispatched, if_neg same] using
          executesSequence (executesIfFalse conditionFalse (executesSkip program before)) run

end Lanius.Extraction.CanonicalTokens.Dispatch
