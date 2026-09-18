import Lanius.Extraction.Host.Arguments
import Lanius.Extraction.CompactOutput.Byte
import Lanius.Extraction.Source.Statement
import Lanius.Extraction.Entry.Scope
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Entry.Path.Length

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

structure Stage where
  argument : VarId
  length : VarId
  continuation : Stmt

def Stage.guard (stage : Stage) : Expr :=
  binary .logicalOr (binary .lessEqual (read stage.length) (number 0))
    (binary .greaterEqual (read stage.length) (number 1025))

def Stage.statement (stage : Stage) (function : FunctionId) : Stmt :=
  .letLocal stage.length i32 (.call function [read stage.argument])
    (.sequence (.ifThenElse stage.guard (returned (number 2)) .skip) stage.continuation)

def check? (function : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun (stage : Stage) => stage.statement function) statement) :=
  match shape : statement with
  | .letLocal length _ (.call _ [.local argument]) (.sequence _ continuation) => do
      let stage : Stage := ⟨argument, length, continuation⟩
      let same ← Equality.statement? statement (stage.statement function)
      pure ⟨stage, shape.symm.trans same.equal⟩
  | _ => none

theorem Stage.guardResult (stage : Stage) (program : Program) (state : State) (count : Nat)
    (readCount : state.local? stage.length = some (.signed .i32 count)) :
    Evaluates program state stage.guard (.boolean (decide (count = 0) || decide (1025 ≤ count))) state := by
  have lengthRead := local_evaluates program readCount
  have lower : Evaluates program state (binary .lessEqual (read stage.length) (number 0))
      (.boolean (decide (count = 0))) state := by
    apply evaluatesEagerBinary (by decide) (by decide) lengthRead
      (show Evaluates program state (number 0) (.signed .i32 0) state from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true, Except.ok.injEq,
      Value.boolean.injEq, decide_eq_decide]
    omega
  have upper : Evaluates program state (binary .greaterEqual (read stage.length) (number 1025))
      (.boolean (decide (1025 ≤ count))) state := by
    apply evaluatesEagerBinary (by decide) (by decide) lengthRead
      (show Evaluates program state (number 1025) (.signed .i32 1025) state from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true, Except.ok.injEq,
      Value.boolean.injEq, decide_eq_decide]
    omega
  exact evaluatesPureLogicalOr lower upper

/-- Execute the actual argument-length call and its valid-path guard. The
continuation receives a registered state and the selected UTF-8 byte count;
the host call's synchronizations are not extra execution assumptions. -/
theorem Stage.executes (stage : Stage) (length : Host.CheckedLength program)
    (before : State) (initial : Allocation.Registry before) (index : Nat) (path : String)
    (indexRead : before.local? stage.argument = some (.signed .i32 index))
    (selected : before.world.arguments[index]? = some path)
    (nonempty : 0 < path.toUTF8.size) (fits : path.toUTF8.size ≤ 1024)
    (post : Scope.Post)
    (continuationRun : ∀ called, Allocation.Registry called → Host.Frame before called →
      called.world = Lanius.World.record before.world .argLen →
      Host.PreservesViews before called (fun _ => True) →
      let middle := called.bindLocal stage.length (.signed .i32 path.toUTF8.size)
      Allocation.Registry middle →
      (Assertion.localPointsTo stage.length called.nextCell (some (.signed .i32 path.toUTF8.size))).holds middle →
      Prefix.Reaches program before (stage.statement length.function.id) middle stage.continuation →
      ∃ completion after, Executes program middle stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program before (stage.statement length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  obtain ⟨called, evaluated, registered, frame, world, preserved⟩ := length.evaluates initial index path selected
    (by omega) (.cons (local_evaluates program indexRead) (.nil _ _))
  let middle := called.bindLocal stage.length (.signed .i32 path.toUTF8.size)
  have owned := bindLocal_owns_fresh called stage.length (.signed .i32 path.toUTF8.size) registered.wellFormed
  have guard := stage.guardResult program middle path.toUTF8.size (Assertion.localPointsTo_local _ _ _ _ owned)
  have notEmpty : ¬ path.toUTF8.size = 0 := by omega
  have notLong : ¬ 1025 ≤ path.toUTF8.size := by omega
  simp only [notEmpty, notLong, decide_false, Bool.false_or] at guard
  obtain ⟨completion, after, continued, satisfied⟩ := continuationRun called registered frame world preserved
    (registered.bindLocal stage.length (.signed .i32 path.toUTF8.size)) owned
    (.letLocal evaluated (.sequence (executesIfFalse guard (executesSkip _ _)) .here))
  exact ⟨completion, restoreLocals called after, executesLetLocal evaluated
    (executesSequence (executesIfFalse guard (executesSkip _ _)) continued),
    post.restore completion called after satisfied, frame.locals⟩

/-- Empty and oversized paths return code two before argument bytes are
copied or a file is opened. This is a deliberate return, not a trap. -/
theorem Stage.rejects (stage : Stage) (length : Host.CheckedLength program)
    (before : State) (initial : Allocation.Registry before) (index : Nat) (path : String)
    (indexRead : before.local? stage.argument = some (.signed .i32 index))
    (selected : before.world.arguments[index]? = some path)
    (bounded : path.toUTF8.size ≤ 2147483647)
    (invalid : path.toUTF8.size = 0 ∨ 1025 ≤ path.toUTF8.size) :
    ∃ after, Executes program before (stage.statement length.function.id)
        (.returned (some (.signed .i32 2))) after ∧
      Allocation.Registry after ∧ after.locals = before.locals ∧
      after.world = Lanius.World.record before.world .argLen := by
  obtain ⟨called, evaluated, registered, frame, world, preserved⟩ := length.evaluates initial index path selected bounded
    (.cons (local_evaluates program indexRead) (.nil _ _))
  let middle := called.bindLocal stage.length (.signed .i32 path.toUTF8.size)
  have entered := registered.bindLocal stage.length (.signed .i32 path.toUTF8.size)
  have owned := bindLocal_owns_fresh called stage.length (.signed .i32 path.toUTF8.size) registered.wellFormed
  have guard := stage.guardResult program middle path.toUTF8.size (Assertion.localPointsTo_local _ _ _ _ owned)
  have bad : (decide (path.toUTF8.size = 0) || decide (1025 ≤ path.toUTF8.size)) = true := by
    rcases invalid with empty | long
    · simp only [empty, decide_true, Bool.true_or]
    · simp only [long, decide_true, Bool.or_true]
  rw [bad] at guard
  have run : Executes program before (stage.statement length.function.id)
      (.returned (some (.signed .i32 2))) (restoreLocals called middle) :=
    executesLetLocal evaluated (executesSequenceReturned
    (executesIfTrue (elseBranch := .skip) guard (executesSequenceReturned (second := .skip)
      (executesReturnValue (show Evaluates program middle (number 2) (.signed .i32 2) middle from ⟨1, rfl⟩)))))
  have restored := CellEffect.closeLocal called stage.length (.signed .i32 path.toUTF8.size)
    registered.wellFormed (CellEffect.refl (writes := CellSet.empty) entered.wellFormed)
  exact ⟨restoreLocals called middle, run, entered.restoreLocals called restored.wellFormed, frame.locals, world⟩

end Lanius.Extraction.Entry.Path.Length
