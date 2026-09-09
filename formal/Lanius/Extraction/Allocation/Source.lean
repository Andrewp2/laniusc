import Lanius.Extraction.Allocation.Execution
import Lanius.Extraction.Source.Statement

namespace Lanius.Extraction.Allocation

open Lanius.Core Lanius.Extraction.Source

structure Sequence where
  buffers : List Buffer
  continuation : Stmt

def hostInitializer (allocator : FunctionId) (buffer : Buffer) : Expr :=
  .i32SliceFromRawParts
    (.call allocator [.value (.unsigned .usize (buffer.count * 4)), .value (.unsigned .usize 4)])
    (.value (.signed .i32 buffer.count))

def hostStatement (allocator : FunctionId) (buffers : List Buffer) (continuation : Stmt) : Stmt :=
  match buffers with
  | [] => continuation
  | buffer :: rest => .letLocal buffer.binding (.slice (.scalar (.signed .i32)))
      (hostInitializer allocator buffer) (hostStatement allocator rest continuation)

def Sequence.statement (allocator : FunctionId) (sequence : Sequence) : Stmt :=
  hostStatement allocator sequence.buffers sequence.continuation

/-- Recover binding identities from the source while checking every allocation's
byte size, alignment, element count, and nesting against the expected counts. -/
def checkSequence? (allocator : FunctionId) (counts : List Nat) (source : Stmt) :
    Option (CheckedStatement (Sequence.statement allocator) source) :=
  match counts with
  | [] => some ⟨⟨[], source⟩, rfl⟩
  | count :: rest =>
      match source with
      | .letLocal binding (.slice (.scalar (.signed .i32)))
          (.i32SliceFromRawParts
            (.call called [.value (.unsigned .usize bytes), .value (.unsigned .usize alignment)])
            (.value (.signed .i32 length))) body => do
          if same : called = allocator ∧ bytes = count * 4 ∧ alignment = 4 ∧ length = (count : Int) then
            let checked ← checkSequence? allocator rest body
            pure ⟨⟨⟨binding, count⟩ :: checked.locals.buffers, checked.locals.continuation⟩, by
              rcases same with ⟨sameCall, rfl, rfl, rfl⟩
              subst called
              change _ = Stmt.letLocal _ _ _ (Sequence.statement allocator checked.locals)
              exact congrArg (Stmt.letLocal binding (.slice (.scalar (.signed .i32)))
                (hostInitializer allocator ⟨binding, count⟩)) checked.exactSource⟩
          else none
      | _ => none

def findSequence? (allocator : FunctionId) (counts : List Nat) :=
  findStatement? (Sequence.statement allocator) (checkSequence? allocator counts)

def extractorCounts : List Nat :=
  [256, 1024, 65536, 2179, 65536, 65536, 65536,
    4194304, 1048576, 65536, 131072, 8388608, 16384]

end Lanius.Extraction.Allocation
