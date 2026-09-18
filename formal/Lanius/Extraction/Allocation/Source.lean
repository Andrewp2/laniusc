import Lanius.Extraction.Allocation.Execution
import Lanius.Extraction.Source.Statement

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Extraction.Source

structure Step where
  buffer : Buffer
  pointer : VarId
  distinct : pointer ≠ buffer.binding

def Step.guard (step : Step) : Stmt :=
  .ifThenElse (.binary .equal (.local step.pointer) (.value (.pointer Lanius.Memory.null)))
    (.sequence (.returnValue (some (.value (.signed .i32 3)))) .skip) .skip

def Step.initialize (allocator : FunctionId) (step : Step) : Stmt :=
  .letLocal step.pointer (.scalar .rawPtr)
    (.call allocator [.value (.unsigned .usize (step.buffer.count * 4)), .value (.unsigned .usize 4)])
    (.sequence step.guard
      (.sequence (.expression (.assign .set (.local step.buffer.binding)
        (.i32SliceFromRawParts (.local step.pointer) (.value (.signed .i32 step.buffer.count))))) .skip))

def Step.statement (allocator : FunctionId) (step : Step) (continuation : Stmt) : Stmt :=
  .letUninitialized step.buffer.binding (.slice (.scalar (.signed .i32)))
    (.sequence (step.initialize allocator) continuation)

structure Sequence where
  steps : List Step
  continuation : Stmt

def Sequence.buffers (sequence : Sequence) : List Buffer := sequence.steps.map Step.buffer

def hostStatement (allocator : FunctionId) (steps : List Step) (continuation : Stmt) : Stmt :=
  match steps with
  | [] => continuation
  | step :: rest => step.statement allocator (hostStatement allocator rest continuation)

def Sequence.statement (allocator : FunctionId) (sequence : Sequence) : Stmt :=
  hostStatement allocator sequence.steps sequence.continuation

/-- Recover binding identities from the source while checking every allocation's
byte size, alignment, element count, and nesting against the expected counts. -/
def checkSequence? (allocator : FunctionId) (counts : List Nat) (source : Stmt) :
    Option (CheckedStatement (Sequence.statement allocator) source) :=
  match counts with
  | [] => some ⟨⟨[], source⟩, rfl⟩
  | count :: rest =>
      match source with
      | .letUninitialized binding (.slice (.scalar (.signed .i32)))
          (.sequence (.letLocal pointer (.scalar .rawPtr)
            (.call called [.value (.unsigned .usize bytes), .value (.unsigned .usize alignment)])
            (.sequence (.ifThenElse
              (.binary .equal (.local tested) (.value (.pointer nullValue)))
              (.sequence (.returnValue (some (.value (.signed .i32 code)))) .skip) .skip)
              (.sequence (.expression (.assign .set (.local assigned)
                (.i32SliceFromRawParts (.local readPointer) (.value (.signed .i32 length))))) .skip))) body) => do
          if same : called = allocator ∧ bytes = count * 4 ∧ alignment = 4 ∧ length = (count : Int) ∧
              tested = pointer ∧ nullValue = Lanius.Memory.null ∧ code = 3 ∧ assigned = binding ∧
              readPointer = pointer ∧ pointer ≠ binding then
            let checked ← checkSequence? allocator rest body
            pure ⟨⟨⟨⟨binding, count⟩, pointer, same.2.2.2.2.2.2.2.2.2⟩ :: checked.locals.steps,
                checked.locals.continuation⟩, by
              rcases same with ⟨sameCall, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, distinct⟩
              subst called
              exact congrArg (Step.statement allocator ⟨⟨assigned, count⟩, readPointer, distinct⟩)
                checked.exactSource⟩
          else none
      | _ => none

def findSequence? (allocator : FunctionId) (counts : List Nat) :=
  findStatement? (Sequence.statement allocator) (checkSequence? allocator counts)

def extractorCounts : List Nat :=
  [256, 1024, 65536, 2179, 65536, 65536, 65536,
    4194304, 1048576, 65536, 131072, 16777216, 16384]

end Lanius.Extraction.Allocation
