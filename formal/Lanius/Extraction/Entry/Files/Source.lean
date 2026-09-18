import Lanius.Extraction.Entry.Files.Loop

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics

/-- The exact enclosing cursor initialization and loop. The body is the
already checked file pipeline, not a replacement loop body. -/
def initialized (argument countId : VarId) (body continuation : Stmt) : Stmt :=
  .letLocal argument (.scalar (.signed .i32)) (.value (.signed .i32 1))
    (.sequence (.whileLoop (condition argument countId) body) continuation)

structure CheckedSource (argument countId : VarId) (body source : Stmt) where
  continuation : Stmt
  exactSource : source = initialized argument countId body continuation
  distinct : argument ≠ countId

def check? (argument countId : VarId) (body source : Stmt) : Option (CheckedSource argument countId body source) :=
  match shape : source with
  | .letLocal _ _ _ (.sequence (.whileLoop _ _) continuation) => do
    let same ← Equality.statement? source (initialized argument countId body continuation)
    if distinct : argument ≠ countId then
      pure ⟨continuation, shape.symm.trans same.equal, distinct⟩
    else none
  | _ => none

/-- Enter the source cursor scope without executing a file iteration. -/
theorem CheckedSource.reaches (checked : CheckedSource argument countId body source) :
    Prefix.Reaches program ready source (ready.bindLocal argument (.signed .i32 1))
      (.whileLoop (condition argument countId) body) := by
  rw [checked.exactSource]
  exact .letLocal (show Evaluates program ready (.value (.signed .i32 1)) (.signed .i32 1) ready from ⟨1, rfl⟩)
    (.sequenceHead .here)

/-- A normally completed loop reaches its actual source tail while the
argument binding remains in scope. This is the suffix entry, not a second
execution of the loop or an assumed intermediate state. -/
theorem CheckedSource.afterLoop {argument countId : VarId} {body source : Stmt}
    (checked : CheckedSource argument countId body source)
    (startup : Prefix.Reaches program before main ready source)
    (run : Executes program (ready.bindLocal argument (.signed .i32 1))
      (.whileLoop (condition argument countId) body) .next after) :
    Prefix.Reaches program before main after checked.continuation := by
  apply startup.trans
  apply (congrArg (fun statement => Prefix.Reaches program ready statement after checked.continuation)
    checked.exactSource).mpr
  exact .letLocal (show Evaluates program ready (.value (.signed .i32 1)) (.signed .i32 1) ready from ⟨1, rfl⟩)
    (.sequence run .here)

end Lanius.Extraction.Entry.Files
