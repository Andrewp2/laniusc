import Lanius.Extraction.Host.Arguments.Read
import Lanius.Extraction.Entry.Path.Length

namespace Lanius.Extraction.Entry.Path.Read

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

structure Stage where
  argument : VarId
  pointer : VarId
  length : VarId
  continuation : Stmt

def Stage.call (stage : Stage) (function : FunctionId) : Expr :=
  .call function [read stage.argument, read stage.pointer, .cast (.unsigned .usize) (read stage.length)]

def Stage.statement (stage : Stage) (function : FunctionId) : Stmt :=
  .sequence (.ifThenElse (binary .notEqual (stage.call function) (read stage.length))
    (returned (number 4)) .skip) stage.continuation

def check? (function : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun (stage : Stage) => stage.statement function) statement) :=
  match shape : statement with
  | .sequence (.ifThenElse (.binary .notEqual
      (.call _ [.local argument, .local pointer, .cast _ (.local length)]) _) _ _) continuation => do
      let stage : Stage := ⟨argument, pointer, length, continuation⟩
      let same ← Equality.statement? statement (stage.statement function)
      pure ⟨stage, shape.symm.trans same.equal⟩
  | _ => none

/-- Copy the selected path and pass the real returned-count guard. The
length read on the right of the comparison survives the effectful host call.
The continuation gets exact packed bytes, not an assumed scratch encoding. -/
theorem Stage.executes (stage : Stage) (reader : Host.CheckedExternal program .argRead 3)
    (before : State) (initial : Allocation.Registry before) (index : Nat) (path : String)
    (indexRead : before.local? stage.argument = some (.signed .i32 index))
    (pointerRead : before.local? stage.pointer = some (.pointer view.address))
    (lengthRead : before.local? stage.length = some (.signed .i32 (Lanius.World.utf8Bytes path).length))
    (selected : before.world.arguments[index]? = some path)
    (member : view ∈ before.i32ArrayViews)
    (room : (Lanius.World.utf8Bytes path).length ≤ view.length * 4)
    (bounded : (Lanius.World.utf8Bytes path).length ≤ 2147483647)
    (sizeFit : (Lanius.World.utf8Bytes path).length < unsignedModulus program.target .usize)
    (post : Scope.Post)
    (continuationRun : ∀ middle, Allocation.Registry middle → Host.Frame before middle →
      middle.world = Lanius.World.record before.world .argRead →
      Host.Copied view (Lanius.World.utf8Bytes path) middle →
      Host.PreservesViews before middle (I32ViewRangesDisjoint view) →
      Prefix.Reaches program before (stage.statement reader.function.id) middle stage.continuation →
      ∃ completion after, Executes program middle stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program before (stage.statement reader.function.id) completion after ∧ post completion after := by
  have size : Evaluates program before (.cast (.unsigned .usize) (read stage.length))
      (.unsigned .usize (Lanius.World.utf8Bytes path).length) before := by
    apply evaluatesCast (local_evaluates program lengthRead)
    change (Except.ok (Value.unsigned .usize
      (((Lanius.World.utf8Bytes path).length : Int) % (unsignedModulus program.target .usize : Int)).toNat) :
        Except Lanius.Trap Value) = .ok (.unsigned .usize (Lanius.World.utf8Bytes path).length)
    rw [Int.emod_eq_of_lt (Int.natCast_nonneg (Lanius.World.utf8Bytes path).length) (Int.ofNat_lt.mpr sizeFit)]
    rfl
  obtain ⟨middle, copied, registered, frame, world, contents, preserved⟩ :=
    Host.Arguments.evaluatesRead reader initial index (Lanius.World.utf8Bytes path).length path
      selected member room bounded
      (.cons (local_evaluates program indexRead) (.cons (local_evaluates program pointerRead) (.cons size (.nil _ _))))
  simp only [List.take_length] at copied contents
  have afterLength := frame.preservesLocal initial lengthRead (by intro elements same; cases same)
  have guard : Evaluates program before (binary .notEqual (stage.call reader.function.id) (read stage.length))
      (.boolean false) middle := by
    apply evaluatesEagerBinary (by decide) (by decide) copied (local_evaluates program afterLength)
    simp [evalBinaryValue, scalarEqual]
  obtain ⟨completion, after, continued, satisfied⟩ := continuationRun middle registered frame world contents preserved
    (.sequence (executesIfFalse guard (executesSkip _ _)) .here)
  exact ⟨completion, after, executesSequence (executesIfFalse guard (executesSkip _ _)) continued, satisfied⟩

end Lanius.Extraction.Entry.Path.Read
