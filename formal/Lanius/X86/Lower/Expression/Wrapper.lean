import Lanius.X86.Lower.Expression.Contract
import Lanius.X86.Lower.Expression.Wrapper.Tail

namespace Lanius.X86.Lower.Expression.Wrapper

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer
open Literal

/-- Compose the actual emitter's total contract with TOP capture, aggregate
classification and scope restoration. Output facts survive unchanged. -/
theorem body (checked : Source.Expression.Literal.Checked emitters) (c : Context)
    (kind : Int) (post : List Int → Prop) (nextWorkspace : List Int)
    (ready : c.Ready before frontier) (topFound : c.workspace[6]? = some c.top)
    (sameLength : nextWorkspace.length = c.workspace.length)
    (emits : c.Call emitters.pack.program.core checked.emitter.source.function.id kind nextWorkspace post) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.body checked.layout checked.constants checked.emitter.source.function.id)
        (.returned (some (.signed .i32 kind))) after ∧
      c.Result (finish kind c.top nextWorkspace) post after ∧
      CellEffect (writes c.output c.work) before after ∧ HeapFrame before after := by
  have within : 6 < c.workspace.length := (List.getElem?_eq_some_iff.mp topFound).1
  have initial := ready.field checked.constants.top 6 checked.constants.values.2.2.2.2.2.2
    (ready.read 2 (by simp [Context.arguments, inputValues])) topFound
  let entered := before.bindLocal 9 (.signed .i32 c.top)
  have enteredReady := ready.bind 9 (by simp [Context.arguments, inputValues]) (.signed .i32 c.top)
  have saved := bindLocal_finds_local before 9 (.signed .i32 c.top) ready.wellFormed
  have reads := enteredReady.locals.found
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core entered Source.Expression.Indexed.recurseArguments
      c.arguments entered := by
    repeat' apply ArgumentsEvaluateTo.cons
    all_goals first
      | exact ArgumentsEvaluateTo.nil _ _
      | (apply local_evaluates; exact reads ⟨_, by simp [Context.arguments, inputValues]⟩)
  obtain ⟨emittedState, emittedRun, ⟨emitted, emittedOutput, emittedWork, fact⟩, emittedEffect, emittedHeap⟩ :=
    emits.call enteredReady.wellFormed arguments (Context.Ready.memory enteredReady)
  have emittedReady := enteredReady.frame emittedEffect emittedOutput emittedWork
  have keptSaved := emittedEffect.preserves_local enteredReady.wellFormed saved (by
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value saved enteredReady.outputBacking (by intro same; cases same) binding out
    · exact local_cell_ne_of_distinct_value saved enteredReady.workBacking (by intro same; cases same) binding work)
  let kinded := emittedState.bindLocal 10 (.signed .i32 kind)
  have kindedReady := emittedReady.bind 10 (by simp [Context.arguments, inputValues]) (.signed .i32 kind)
  have kindLocal := bindLocal_finds_local emittedState 10 (.signed .i32 kind) emittedReady.wellFormed
  have topLocal := (bindLocal_preserves_other_local (boundId := 10) (queriedId := 9) (value := .signed .i32 kind)
    emittedReady.wellFormed (by decide)).trans keptSaved
  have workLocal := kindedReady.read 2 (value := .slice i32 c.work [] 0 c.workspace.length)
    (by simp [Context.arguments, inputValues])
  obtain ⟨completed, restRun, finalOutput, finalWork, restEffect, restHeap⟩ :=
    tail checked kindedReady kind c.top (by omega : 6 < nextWorkspace.length)
      (by simpa only [sameLength] using workLocal) topLocal kindLocal
  have closedEffect := emittedEffect.trans (CellEffect.closeLocal emittedState 10 (.signed .i32 kind)
    emittedReady.wellFormed restEffect)
  have closedHeap := emittedHeap.trans (HeapFrame.closeLocal emittedState 10 (.signed .i32 kind) restHeap)
  exact ⟨_, executesLetLocal initial (executesLetLocal emittedRun restRun),
    ⟨emitted, finalOutput, finalWork, fact⟩,
    CellEffect.closeLocal before 9 (.signed .i32 c.top) ready.wellFormed closedEffect,
    HeapFrame.closeLocal before 9 (.signed .i32 c.top) closedHeap⟩

/-- The same contract at the public expression call: parameter entry and
caller restoration are proved once, independent of the expression case. -/
theorem call (checked : Source.Expression.Literal.Checked emitters) (c : Context)
    (kind : Int) (post : List Int → Prop) (nextWorkspace : List Int)
    (topFound : c.workspace[6]? = some c.top) (sameLength : nextWorkspace.length = c.workspace.length)
    (emits : c.Call emitters.pack.program.core checked.emitter.source.function.id kind nextWorkspace post) :
    c.Call emitters.pack.program.core checked.wrapper.source.function.id kind (finish kind c.top nextWorkspace) post := by
  constructor
  intro caller arguments before wellFormed evaluated memory
  let params := parameterBindings (fun index : Fin 9 => c.arguments.get index)
  have ready := Literal.Ready.enterCall (bindings := c.arguments) wellFormed memory.plain
    memory.inputBacking memory.outputBacking memory.workBacking memory.inputOutput memory.inputWork memory.outputWork
  obtain ⟨completed, run, result, effect, heap⟩ := body checked c kind post nextWorkspace ready topFound sameLength emits
  have called := checked.wrapper.call wellFormed evaluated (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, result, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Expression.Wrapper
