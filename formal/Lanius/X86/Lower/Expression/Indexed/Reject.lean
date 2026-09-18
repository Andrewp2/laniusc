import Lanius.X86.Source.Expression.Indexed
import Lanius.X86.Frame.Allocate
import Lanius.X86.Lower.Expression.Indexed.Prepare
import Lanius.X86.Lower.Index.Reject

namespace Lanius.X86.Lower.Expression.Indexed.Reject

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Exhausted slot capacity rejects the actual indexed-expression body
before any output access, operand save, or recursive expression call. Only
FAILED changes in the existing workspace; the temporary's scope is closed. -/
theorem body (checked : Source.Expression.Indexed.Checked emitters)
    (wellFormed : StateWellFormed before)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (within : 6 < workspace.length)
    (full : workspace[6]? = some (Frame.Allocate.limit : Int)) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Indexed.preparation checked.allocate.internal.source.function.id
          checked.save.internal.source.function.id checked.index.constants.rax.id
          (Source.Expression.Indexed.continuation checked.expression.function.id checked.index.internal.source.function.id))
        (.returned (some (.boolean false))) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 4 1))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo emitters.pack.program.core before [Source.read 2, Source.number 1]
      (Frame.Allocate.inputValues work workspace.length 1) before :=
    .cons (local_evaluates _ workLocal) (.cons ⟨1, rfl⟩ (.nil _ _))
  obtain ⟨allocated, allocateRun, allocatedWork, allocateEffect, allocateHeap⟩ :=
    Frame.Allocate.rejects checked.allocate Frame.Allocate.limit 1 wellFormed workBacking within full
      (by omega) (by simp) args
  let scope := allocated.bindLocal 9 (.signed .i32 (-1))
  have scopeWF := bindLocal_preserves_well_formed allocated 9 (.signed .i32 (-1)) allocateEffect.wellFormed
  have saved := bindLocal_finds_local allocated 9 (.signed .i32 (-1)) allocateEffect.wellFormed
  have guard : Evaluates emitters.pack.program.core scope Source.Expression.Indexed.rejected (.boolean true) scope := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ saved)
      (show Evaluates emitters.pack.program.core scope (Source.number 0) (.signed .i32 0) scope from ⟨1, rfl⟩)
    rfl
  have returnedFalse : Executes emitters.pack.program.core scope (returned (.value (.boolean false)))
      (.returned (some (.boolean false))) scope :=
    executesSequenceReturned (executesReturnValue ⟨1, rfl⟩)
  have scopeWork := ((bindLocal_effect allocated 9 (.signed .i32 (-1))).oldCells work
    (StateWellFormed.cell_lt_next_of_entry allocateEffect.wellFormed allocatedWork)
    (by simp [CellSet.empty])).trans allocatedWork
  exact ⟨restoreLocals allocated scope,
    executesLetLocal allocateRun (executesSequenceReturned (executesIfTrue guard returnedFalse)),
    scopeWork,
    allocateEffect.trans (CellEffect.closeLocal allocated 9 (.signed .i32 (-1)) allocateEffect.wellFormed
      (CellEffect.refl scopeWF)),
    allocateHeap.trans (HeapFrame.closeLocal allocated 9 (.signed .i32 (-1)) (HeapFrame.refl scope))⟩

/-- Parameters other than the workspace are never read on this path. In
particular, no input/output/context slice-validity premise is necessary. -/
def inputValues (input length : Value) (work : CellId) (size : Nat)
    (output capacity active depth context contextLength : Value) : List Value :=
  [input, length, .slice i32 work [] 0 size, output, capacity, active, depth, context, contextLength]

/-- Source-linked whole-call rejection, with both the local `saved` scope
and the function-parameter scope closed. The caller bindings, host world,
raw heap, views, and every existing cell except the workspace are preserved.
The workspace itself changes at FAILED (index 4) only. -/
theorem rejects (checked : Source.Expression.Indexed.Checked emitters)
    (wellFormed : StateWellFormed before)
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (within : 6 < workspace.length)
    (full : workspace[6]? = some (Frame.Allocate.limit : Int))
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input length work workspace.length output capacity active depth context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.boolean false) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 4 1))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  let values := inputValues input length work workspace.length output capacity active depth context contextLength
  let params := parameterBindings (fun index : Fin 9 => values.get index)
  have initialBacking := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  have initialWork : (enterCall before params).local? 2 = some (.slice i32 work [] 0 workspace.length) :=
    enterCall_parameterBindings_matches wellFormed ⟨2, by decide⟩
  obtain ⟨completed, run, finalWork, effect, heap⟩ := body checked
    (enterCall_preserves_wellFormed wellFormed) initialWork initialBacking within full
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalWork, called.2, HeapFrame.closeCall before params heap⟩

/-- Propagate a recursively compiled invalid index kind through the actual
indexed continuation. The induction hypothesis concerns only the recursive
expression call. Address rejection, argument reads, the false result, and
closing `kind`'s local scope are proved here. The final empty footprint from
`recursed` proves that rejection emits no additional bytes or workspace writes. -/
theorem continues (checked : Source.Expression.Indexed.Checked emitters) (kind capacity : Int)
    (ready : Prepared before inputs frontier output work top peak start values workspace preparedValues)
    (recursiveRun : Evaluates emitters.pack.program.core before
      (.call checked.expression.function.id Source.Expression.Indexed.recurseArguments)
      (.signed .i32 kind) recursed)
    (recursiveEffect : CellEffect (writes output work) before recursed)
    (recursiveHeap : HeapFrame before recursed)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (notSigned : kind ≠ 1) (notUnsigned : kind ≠ 3) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Indexed.continuation checked.expression.function.id checked.index.internal.source.function.id)
        (.returned (some (.boolean false))) after ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after ∧
      CellEffect CellSet.empty recursed after ∧ HeapFrame recursed after := by
  have kept (id : Nat) (value : Value) (found : before.local? id = some value)
      (notOutput : value ≠ .array (signedI32Values preparedValues))
      (notWork : value ≠ .array (signedI32Values
        (workspaceAfter workspace top peak (start + (saveBytes top).length)))) :
      recursed.local? id = some value := by
    apply recursiveEffect.preserves_local ready.wellFormed found
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value found ready.outputBacking notOutput binding out
    · exact local_cell_ne_of_distinct_value found ready.workBacking notWork binding work
  have recursedWork := kept 2 _ workLocal (by intro same; cases same) (by intro same; cases same)
  have recursedOutput := kept 3 _ outputLocal (by intro same; cases same) (by intro same; cases same)
  have recursedCapacity := kept 4 _ capacityLocal (by intro same; cases same) (by intro same; cases same)
  have recursedSaved := kept 9 _ ready.saved (by intro same; cases same) (by intro same; cases same)
  let entered := recursed.bindLocal 10 (.signed .i32 kind)
  have enteredWF := bindLocal_preserves_well_formed recursed 10 (.signed .i32 kind) recursiveEffect.wellFormed
  have enteredWork := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 2)
    (value := .signed .i32 kind) recursiveEffect.wellFormed (by decide)).trans recursedWork
  have enteredOutput := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 3)
    (value := .signed .i32 kind) recursiveEffect.wellFormed (by decide)).trans recursedOutput
  have enteredCapacity := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 4)
    (value := .signed .i32 kind) recursiveEffect.wellFormed (by decide)).trans recursedCapacity
  have enteredSaved := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 9)
    (value := .signed .i32 kind) recursiveEffect.wellFormed (by decide)).trans recursedSaved
  have enteredKind := bindLocal_finds_local recursed 10 (.signed .i32 kind) recursiveEffect.wellFormed
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core entered
      [Source.read 3, Source.read 4, Source.read 2, Source.read 9, Source.read 10]
      (Index.Reject.inputValues (.slice i32 output [] 0 values.length) (.signed .i32 capacity)
        (.slice i32 work [] 0 workspace.length) (.signed .i32 top) kind) entered :=
    .cons (local_evaluates _ enteredOutput) (.cons (local_evaluates _ enteredCapacity)
      (.cons (local_evaluates _ enteredWork) (.cons (local_evaluates _ enteredSaved)
        (.cons (local_evaluates _ enteredKind) (.nil _ _)))))
  obtain ⟨completed, addressRun, effect, heap⟩ :=
    Index.Reject.rejects checked.index kind enteredWF notSigned notUnsigned arguments
  have result : Evaluates emitters.pack.program.core entered
      (.binary .greaterEqual (.call checked.index.internal.source.function.id
        [Source.read 3, Source.read 4, Source.read 2, Source.read 9, Source.read 10]) (Source.number 0))
      (.boolean false) completed := by
    apply evaluatesEagerBinary (by decide) (by decide) addressRun
      (show Evaluates emitters.pack.program.core completed (Source.number 0) (.signed .i32 0) completed from ⟨1, rfl⟩)
    rfl
  have closedEffect := CellEffect.closeLocal recursed 10 (.signed .i32 kind) recursiveEffect.wellFormed effect
  have closedHeap := HeapFrame.closeLocal recursed 10 (.signed .i32 kind) heap
  exact ⟨restoreLocals recursed completed,
    executesLetLocal recursiveRun (executesSequenceReturned (executesReturnValue result)),
    recursiveEffect.trans (closedEffect.weaken CellSet.empty_subset), recursiveHeap.trans closedHeap,
    closedEffect, closedHeap⟩

end Lanius.X86.Lower.Expression.Indexed.Reject
