import Lanius.Extraction.Source.Statement
import Lanius.Separation

namespace Lanius.Extraction.Input

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The extra byte distinguishes a full valid buffer from oversized input.
At least one byte is requested even when no capacity remains. -/
def requestSize (remaining : Nat) : Nat :=
  if remaining < 65536 then remaining + 1 else 65536

theorem requestSize_bounds (remaining : Nat) :
    0 < requestSize remaining ∧ requestSize remaining ≤ 65536 ∧
      requestSize remaining ≤ remaining + 1 := by
  unfold requestSize
  split <;> omega

theorem requestSize_covers_capacity (remaining : Nat) (bound : remaining ≤ 65536) :
    remaining ≤ requestSize remaining := by
  unfold requestSize
  split <;> omega

theorem requested_bytes_complete (bytes : List UInt8) (remaining : Nat)
    (capacity : bytes.length ≤ remaining) (bound : remaining ≤ 65536) :
    bytes.take (requestSize remaining) = bytes := by
  exact List.take_of_length_le (Nat.le_trans capacity (requestSize_covers_capacity remaining bound))

theorem requested_bytes_detect_overflow (bytes : List UInt8) (remaining : Nat)
    (room : remaining < 65536) (oversize : remaining < bytes.length) :
    (bytes.take (requestSize remaining)).length = remaining + 1 := by
  simp only [requestSize, room, if_true, List.length_take]
  omega

structure RequestLocals where
  remaining : VarId
  request : VarId

def RequestLocals.adjust (locals : RequestLocals) : Stmt :=
  .ifThenElse (.binary .less (.local locals.remaining) (.local locals.request))
    (.sequence (.expression (.assign .set (.local locals.request)
      (.binary .add (.local locals.remaining) (.value (.signed .i32 1))))) .skip) .skip

/-- The actual request-adjustment branch computes the capacity probe without
overflow. Its only write is to the owned request local. -/
theorem executes_request_adjustment (program : Program) (before : State)
    (locals : RequestLocals) (requestCell : CellId) (remaining : Nat)
    (wellFormed : StateWellFormed before)
    (remainingLocal : before.local? locals.remaining = some (.signed .i32 remaining))
    (request : (Assertion.localPointsTo locals.request requestCell
      (some (.signed .i32 65536))).holds before) :
    ∃ after, Executes program before locals.adjust .next after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo locals.request requestCell
        (some (.signed .i32 (requestSize remaining)))).holds after ∧
      ModifiesOnly (CellSet.singleton requestCell) before after := by
  have remainingResult : Evaluates program before (.local locals.remaining)
      (.signed .i32 remaining) before :=
    ⟨1, evalLocal_of_local 0 program before locals.remaining _ remainingLocal⟩
  have requestResult : Evaluates program before (.local locals.request)
      (.signed .i32 65536) before :=
    ⟨1, evalLocal_of_local 0 program before locals.request _
      (Assertion.localPointsTo_local _ _ _ _ request)⟩
  have condition : Evaluates program before
      (.binary .less (.local locals.remaining) (.local locals.request))
      (.boolean (decide (remaining < 65536))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) remainingResult requestResult
    simp [evalBinaryValue, evalSignedBinary]
    omega
  by_cases small : remaining < 65536
  · have rhs := evaluatesNatI32Add (leftValue := remaining) (rightValue := 1) remainingResult
      (show Evaluates program before (.value (.signed .i32 1)) (.signed .i32 1) before from ⟨1, rfl⟩)
      (by omega)
    obtain ⟨after, assignment, afterWF, afterRequest, effect⟩ :=
      evaluatesSetOwnedLocalFromEmpty locals.request requestCell wellFormed request rhs
        wellFormed (ModifiesOnly.refl before)
    refine ⟨after, executesIfTrue (by simpa [small] using condition)
      (executesSequence (executesExpression assignment) ⟨1, rfl⟩), afterWF, ?_, effect⟩
    simpa [requestSize, small] using afterRequest
  · exact ⟨before, executesIfFalse (by simpa [small] using condition) ⟨1, rfl⟩,
      wellFormed, by simpa [requestSize, small] using request, ModifiesOnly.reflAny _ _⟩

def checkRequestAdjustment? :
    (statement : Stmt) → Option (Source.CheckedStatement RequestLocals.adjust statement)
  | .ifThenElse (.binary .less (.local remaining) (.local request))
      (.sequence (.expression (.assign .set (.local written)
        (.binary .add (.local read) (.value (.signed .i32 1))))) .skip) .skip =>
      if same : written = request ∧ read = remaining then
        some ⟨⟨remaining, request⟩, by rcases same with ⟨rfl, rfl⟩; rfl⟩
      else none
  | _ => none

def findRequestAdjustment? := Source.findStatement? RequestLocals.adjust checkRequestAdjustment?

end Lanius.Extraction.Input
