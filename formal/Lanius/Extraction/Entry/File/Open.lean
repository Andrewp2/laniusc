import Lanius.Extraction.Host.File.Open
import Lanius.Semantics.Prefix
import Lanius.Extraction.CompactOutput.Byte
import Lanius.Extraction.Source.Statement
import Lanius.Extraction.Entry.Scope

namespace Lanius.Extraction.Entry.File.Open

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

structure Stage where
  pointer : VarId
  length : VarId
  handle : VarId
  continuation : Stmt

def Stage.call (stage : Stage) (function : FunctionId) : Expr :=
  .call function [read stage.pointer, .cast (.unsigned .usize) (read stage.length)]

def Stage.statement (stage : Stage) (function : FunctionId) : Stmt :=
  .letLocal stage.handle i32 (stage.call function)
    (.sequence (.ifThenElse (binary .lessEqual (read stage.handle) negativeOne)
      (returned (number 5)) .skip) stage.continuation)

def check? (function : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun (stage : Stage) => stage.statement function) statement) := do
  let .letLocal handle _ (.call _ [.local pointer, .cast _ (.local length)])
      (.sequence _ continuation) := statement | none
  let stage : Stage := ⟨pointer, length, handle, continuation⟩
  let same ← Equality.statement? statement (stage.statement function)
  pure ⟨stage, same.equal⟩

theorem Stage.arguments (stage : Stage) (program : Program) (before : State) {count : Nat}
    (pointerRead : before.local? stage.pointer = some (.pointer address))
    (lengthRead : before.local? stage.length = some (.signed .i32 count))
    (sizeFit : count < unsignedModulus program.target .usize) :
    ArgumentsEvaluateTo program before [read stage.pointer, .cast (.unsigned .usize) (read stage.length)]
      [.pointer address, .unsigned .usize count] before := by
  have size : Evaluates program before (.cast (.unsigned .usize) (read stage.length))
      (.unsigned .usize count) before := by
    apply evaluatesCast (local_evaluates program lengthRead)
    change (Except.ok (Value.unsigned .usize
      (((count : Int) % (unsignedModulus program.target .usize : Int)).toNat)) :
        Except Lanius.Trap Value) = .ok (.unsigned .usize count)
    rw [Int.emod_eq_of_lt (Int.natCast_nonneg count) (Int.ofNat_lt.mpr sizeFit)]
    rfl
  exact .cons (local_evaluates program pointerRead) (.cons size (.nil _ _))

/-- Open the copied path and pass the actual negative-handle guard.
The modeled filesystem supplies the existing file; the byte read and all
language-level execution follow from the retained path resources. -/
theorem Stage.executes (stage : Stage) (opener : Host.CheckedExternal program .openRead 2)
    (before : State) (initial : Allocation.Registry before) (path : List UInt8)
    (copied : Host.Copied view path before)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : view ∈ before.i32ArrayViews)
    (pointerRead : before.local? stage.pointer = some (.pointer view.address))
    (lengthRead : before.local? stage.length = some (.signed .i32 path.length))
    (sizeFit : path.length < unsignedModulus program.target .usize)
    (fileFound : before.world.file? path = some file)
    (bounded : before.world.nextFileHandle ≤ 2147483647)
    (post : Scope.Post)
    (continuationRun : ∀ called, Allocation.Registry called → Host.Frame before called →
      called.world = Host.File.openedWorld before.world path →
      Host.PreservesViews before called (fun _ => True) →
      let middle := called.bindLocal stage.handle (.signed .i32 before.world.nextFileHandle)
      Allocation.Registry middle →
      (Assertion.localPointsTo stage.handle called.nextCell
        (some (.signed .i32 before.world.nextFileHandle))).holds middle →
      Prefix.Reaches program before (stage.statement opener.function.id) middle stage.continuation →
      ∃ completion after, Executes program middle stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program before (stage.statement opener.function.id) completion after ∧ post completion after := by
  obtain ⟨called, opened, registered, frame, world, preserved⟩ := Host.File.evaluatesOpen opener initial
    copied disjoint member fileFound bounded (stage.arguments program before pointerRead lengthRead sizeFit)
  let middle := called.bindLocal stage.handle (.signed .i32 before.world.nextFileHandle)
  have owned := bindLocal_owns_fresh called stage.handle (.signed .i32 before.world.nextFileHandle) registered.wellFormed
  have guard : Evaluates program middle (binary .lessEqual (read stage.handle) negativeOne)
      (.boolean false) middle := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned))
      (negativeOne_evaluates program middle)
    simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true, Except.ok.injEq,
      Value.boolean.injEq, decide_eq_false_iff_not]
    omega
  obtain ⟨completion, after, continued, satisfied⟩ := continuationRun called registered frame world preserved
    (registered.bindLocal stage.handle (.signed .i32 before.world.nextFileHandle)) owned
    (.letLocal opened (.sequence (executesIfFalse guard (executesSkip _ _)) .here))
  exact ⟨completion, restoreLocals called after, executesLetLocal opened
    (executesSequence (executesIfFalse guard (executesSkip _ _)) continued), post.restore completion called after satisfied⟩

/-- A missing file takes the actual negative-handle branch and returns five.
The reader continuation is not executed; files, handles, and output remain
unchanged even when the unused handle counter is outside the i32 range. -/
theorem Stage.rejectsMissing (stage : Stage) (opener : Host.CheckedExternal program .openRead 2)
    (before : State) (initial : Allocation.Registry before) (path : List UInt8)
    (copied : Host.Copied view path before) (member : view ∈ before.i32ArrayViews)
    (pointerRead : before.local? stage.pointer = some (.pointer view.address))
    (lengthRead : before.local? stage.length = some (.signed .i32 path.length))
    (sizeFit : path.length < unsignedModulus program.target .usize)
    (missing : before.world.file? path = none) :
    ∃ after, Executes program before (stage.statement opener.function.id)
        (.returned (some (.signed .i32 5))) after ∧
      Allocation.Registry after ∧ after.locals = before.locals ∧
      after.world = Lanius.World.record before.world .openRead := by
  obtain ⟨called, evaluated, registered, frame, world⟩ := Host.File.evaluatesMissing opener initial
    copied member missing (stage.arguments program before pointerRead lengthRead sizeFit)
  let middle := called.bindLocal stage.handle (.signed .i32 (-1))
  have entered := registered.bindLocal stage.handle (.signed .i32 (-1))
  have owned := bindLocal_owns_fresh called stage.handle (.signed .i32 (-1)) registered.wellFormed
  have guard : Evaluates program middle (binary .lessEqual (read stage.handle) negativeOne)
      (.boolean true) middle := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned))
      (negativeOne_evaluates program middle)
    rfl
  have run : Executes program before (stage.statement opener.function.id)
      (.returned (some (.signed .i32 5))) (restoreLocals called middle) :=
    executesLetLocal evaluated (executesSequenceReturned
      (executesIfTrue (elseBranch := .skip) guard (executesSequenceReturned (second := .skip)
        (executesReturnValue (show Evaluates program middle (number 5) (.signed .i32 5) middle from ⟨1, rfl⟩)))))
  have restored := CellEffect.closeLocal called stage.handle (.signed .i32 (-1))
    registered.wellFormed (CellEffect.refl (writes := CellSet.empty) entered.wellFormed)
  exact ⟨restoreLocals called middle, run, entered.restoreLocals called restored.wellFormed, frame.locals, world⟩

end Lanius.Extraction.Entry.File.Open
