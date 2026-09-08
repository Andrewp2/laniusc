import Lanius.Extraction.Parser.Derivation.Tail
import Lanius.Semantics.Relocation.Link

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics

theorem CheckedCursorTail.closed (tail : CheckedCursorTail stores)
    (allowedAccessor : allowed stores.accessor = true) :
    Dependencies.statement allowed stores.body = true := by
  simp [ChildStores.body, ChildStores.store, tail.exactTail,
    Dependencies.statement, Dependencies.expression, Dependencies.place,
    Dependencies.expressions, allowedAccessor]

/-- The entire reader loop calls only the checked field accessor, including
    its metadata guard and child-field initializers. -/
theorem CheckedCursorTail.loop_closed (tail : CheckedCursorTail stores)
    (allowedAccessor : allowed stores.accessor = true)
    (production origin offset tokenCount : Lanius.VarId) (fieldBase : Lanius.ConstantId) :
    Dependencies.statement allowed (readerLoop stores tail production origin offset tokenCount fieldBase) = true := by
  simp [readerLoop, iterationBody, Dependencies.statement, Dependencies.expression,
    Dependencies.optional, Dependencies.expressions, allowedAccessor, tail.closed allowedAccessor]

theorem CheckedCursorTail.relocation_fixed (tail : CheckedCursorTail stores)
    (symbols : Core.Relocation.Symbols) :
    Core.Relocation.statement symbols stores.rest = stores.rest := by
  rw [tail.exactTail]
  rfl

/-- Every call in the complete reader body targets the same accessor.
    Arithmetic constants and local bindings add no function dependencies. -/
theorem CheckedCursorTail.entry_closed (tail : CheckedCursorTail stores)
    (allowedAccessor : allowed stores.accessor = true)
    (production origin offset tokenCount count stateId stateCount capacity workspaceLength : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) :
    Dependencies.statement allowed
      (readerEntry stores tail production origin offset tokenCount count stateId stateCount capacity workspaceLength fieldBase) = true := by
  simp [readerEntry, readerCount, readerRoots, readerHeader, readerWalk, readerExit,
    readerExitCondition, inputCondition, workspaceCondition, rangeCondition, capacityCondition,
    Dependencies.statement, Dependencies.expression, Dependencies.place,
    Dependencies.optional, Dependencies.expressions, allowedAccessor,
    tail.loop_closed allowedAccessor]

def ChildStores.relocated (stores : ChildStores) (symbols : Core.Relocation.Symbols) : ChildStores :=
  { stores with accessor := symbols.functionId stores.accessor
                selector := symbols.constantId stores.selector
                rest := Core.Relocation.statement symbols stores.rest }

theorem ChildStores.store_relocated (stores : ChildStores)
    (symbols : Core.Relocation.Symbols) (offset : Nat) :
    Core.Relocation.statement symbols (stores.store offset) =
      (stores.relocated symbols).store offset := by
  by_cases zero : offset = 0 <;> by_cases one : offset = 1 <;>
    simp [ChildStores.store, ChildStores.relocated, zero, one,
      Core.Relocation.statement, Core.Relocation.expression, Core.Relocation.place,
      Core.Relocation.value, Core.Relocation.expressions]

theorem ChildStores.body_relocated (stores : ChildStores) (symbols : Core.Relocation.Symbols) :
    Core.Relocation.statement symbols stores.body = (stores.relocated symbols).body := by
  simp only [ChildStores.body, Core.Relocation.statement, stores.store_relocated]
  rfl

/-- For a checked cursor tail, only the accessor and selector IDs need to
    change. The continuation has no relocatable symbols. -/
theorem CheckedCursorTail.body_relocation (tail : CheckedCursorTail stores)
    (symbols : Core.Relocation.Symbols) :
    Core.Relocation.statement symbols stores.body =
      ({ stores with accessor := symbols.functionId stores.accessor
                     selector := symbols.constantId stores.selector } : ChildStores).body := by
  rw [stores.body_relocated]
  simp only [ChildStores.relocated, tail.relocation_fixed symbols]

/-- Transport a proved tail execution to the actual matched source region.
    The matching premise is about syntax; execution is supplied solely by
    the original proof and the checked program link. -/
theorem ChildStores.linked_execution (stores currentStores : ChildStores)
    (tail : CheckedCursorTail stores)
    (link : Semantics.Relocation.Link allowed symbols original linked)
    (injective : Function.Injective symbols.typeId)
    (matching : currentStores.body = (stores.relocated symbols).body)
    (execution : Executes original before stores.body .next after)
    (allowedAccessor : allowed stores.accessor = true) :
    Executes linked (Semantics.Relocation.state symbols before) currentStores.body .next
      (Semantics.Relocation.state symbols after) := by
  have transported := link.executes injective execution (tail.closed allowedAccessor)
  rw [stores.body_relocated, ← matching] at transported
  exact transported

end Lanius.Extraction.ParserDerivation
