import Lanius.X86.Source.Expression.Raw
import Lanius.X86.Lower.Expression.Literal.Entry

namespace Lanius.X86.Lower.Expression.Raw

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Facts derived at the actual raw-slice branch, after consuming tag15.
The arithmetic child depth is computed, not assumed to pass a child's entry
guard: an outer depth of511 enters here but its depth512 child must reject. -/
structure Entered (program : Program) (state : State) (bindings : List Value)
    (frontier input output work position depth start : Nat)
    (transport values workspace : List Int) : Prop where
  ready : Literal.Ready state (bindings ++ [.signed .i32 15]) frontier input output work
    transport values (workspace.set 0 (position + 1 : Nat))
  tag : state.local? 9 = some (.signed .i32 15)
  depthValue : state.local? 6 = some (.signed .i32 depth)
  childDepth : Evaluates program state (.binary .add (read 6) (number 1))
    (.signed .i32 (depth + 1 : Nat)) state
  inputPosition : (workspace.set 0 (position + 1 : Nat))[0]? = some ((position + 1 : Nat) : Int)
  codePosition : (workspace.set 0 (position + 1 : Nat))[1]? = some (start : Int)
  healthy : (workspace.set 0 (position + 1 : Nat))[4]? = some 0

/-- Dispatch the actual emitter to the checked raw-slice branch. Entry guards,
the transport read, literal-tag rejection, all earlier dispatch skips, tag
scope restoration and framing are proved here. Only the branch itself is the
continuation obligation. This entry-only theorem requires depth<512; a caller
using successful recursive operands must additionally establish depth+1<512.
The branch's exact final workspace survives tag-scope restoration. -/
theorem emits_with_branch {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (length position depth start : Nat) (kind : Int) (code : List UInt8)
    (inputCount : bindings.length = 9)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (depthLocal : before.local? 6 = some (.signed .i32 depth))
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0)
    (depthBound : depth < 512) (readable : position < length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (tagWord : transport[position]? = some 15)
    {finalWorkspace : List Int}
    (branch : ∀ tagged tagFrontier,
      Entered emitters.pack.program.core tagged bindings tagFrontier input output work position depth start
        transport values workspace →
      StoreEffect (Literal.writes output work) before tagged →
      ∃ completed emitted,
        Executes emitters.pack.program.core tagged
          (Source.Expression.Raw.branch literal checked.constants checked.helpers.calls checked.locals)
          (.returned (some (.signed .i32 kind))) completed ∧
        completed.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
        completed.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
        Emission values start code emitted ∧
        CellEffect (Literal.writes output work) tagged completed ∧ HeapFrame tagged completed) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Literal.emitBody literal.layout literal.constants literal.take.internal.source.function.id
          literal.immediate.source.function.id literal.stringBranch literal.otherBranches)
        (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      Emission values start code emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have guard := Literal.entry_guard literal.constants ready depth start depthBound depthLocal workLocal cursor healthy
  have depthEntry := ready.entry 6 (by omega) depthLocal
  have within : 0 < workspace.length := by
    by_cases inside : 0 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  obtain ⟨tagState, tagRun, afterTag, tagEffect, tagHeap⟩ := ready.take literal.take length position
    inputLocal lengthLocal workLocal current readable storage bounded tagWord
  let tagged := tagState.bindLocal 9 (.signed .i32 15)
  have taggedReady : Literal.Ready tagged (bindings ++ [.signed .i32 15]) tagged.nextCell input output work
      transport values (workspace.set 0 (position + 1 : Nat)) := by
    simpa only [inputCount] using afterTag.push (.signed .i32 15) (by intro elements same; cases same)
  have tagLocal := taggedReady.read (value := .signed .i32 15) 9 (by simp [List.getElem?_append, inputCount])
  have taggedDepth := taggedReady.read 6 ((List.getElem?_append_left (by omega)).trans depthEntry)
  have childDepth : Evaluates emitters.pack.program.core tagged (.binary .add (read 6) (number 1))
      (.signed .i32 (depth + 1 : Nat)) tagged :=
    evaluatesNatI32Add (local_evaluates _ taggedDepth)
      (show Evaluates emitters.pack.program.core tagged (number 1) (.signed .i32 1) tagged from ⟨1, rfl⟩) (by omega)
  have entered : Entered emitters.pack.program.core tagged bindings tagged.nextCell input output work position depth start
      transport values workspace :=
    ⟨taggedReady, tagLocal, taggedDepth, childDepth, List.getElem?_set_self within,
      by simpa only [List.getElem?_set_ne (by decide : 0 ≠ 1)] using cursor,
      by simpa only [List.getElem?_set_ne (by decide : 0 ≠ 4)] using healthy⟩
  have taggedFrame : StoreEffect (Literal.writes output work) before tagged :=
    (tagEffect.modifiesOnly tagHeap).toStoreEffect.trans_same
      ((bindLocal_effect tagState 9 (.signed .i32 15)).weaken CellSet.empty_subset)
  have literalConstant := literal.constants.value.evaluates (before := tagged)
  rw [literal.constants.values.2.2.2.1] at literalConstant
  have literalTest : Evaluates emitters.pack.program.core tagged
      (.binary .equal (read 9) (.constant literal.constants.value.id)) (.boolean false) tagged :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ tagLocal) literalConstant rfl
  obtain ⟨completed, emitted, branchRun, finalOutput, finalWork, emission, branchEffect, branchHeap⟩ :=
    branch tagged tagged.nextCell entered taggedFrame
  have selected := checked.select tagLocal branchRun
  have restRun := executesSequence (executesIfFalse
    (thenBranch := Source.Expression.Literal.literalBody literal.layout literal.constants
      literal.take.internal.source.function.id literal.immediate.source.function.id literal.stringBranch)
    literalTest (executesSkip _ _)) selected
  exact ⟨_, emitted,
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesLetLocal (id := 9) (type := i32) tagRun restRun), finalOutput, finalWork, emission,
    tagEffect.trans (CellEffect.closeLocal tagState 9 (.signed .i32 15) afterTag.wellFormed branchEffect),
    tagHeap.trans (HeapFrame.closeLocal tagState 9 (.signed .i32 15) branchHeap)⟩

end Lanius.X86.Lower.Expression.Raw
