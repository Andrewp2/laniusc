import Lanius.Extraction.OutputPacking
import Lanius.Extraction.OutputPacking.Prefix
import Lanius.Separation

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem pack_as_i32_values (bytes : List UInt8) :
    ∃ values, signedI32Values values = pack bytes := by
  match bytes with
  | [] => exact ⟨[], rfl⟩
  | [a] => exact ⟨[decodeI32 [a, 0, 0, 0]], rfl⟩
  | [a, b] => exact ⟨[decodeI32 [a, b, 0, 0]], rfl⟩
  | [a, b, c] => exact ⟨[decodeI32 [a, b, c, 0]], rfl⟩
  | a :: b :: c :: d :: rest =>
      obtain ⟨values, encoded⟩ := pack_as_i32_values rest
      refine ⟨decodeI32 [a, b, c, d] :: values, ?_⟩
      simpa only [signedI32Values, List.map_cons, pack] using
        congrArg (Value.signed .i32 (decodeI32 [a, b, c, d]) :: ·) encoded
termination_by bytes.length

theorem workspace_as_i32_values (words : Nat) (processed : List UInt8) (tail : List Int) :
    ∃ values, signedI32Values values = workspace words processed (signedI32Values tail) := by
  obtain ⟨packed, encoded⟩ := pack_as_i32_values processed
  refine ⟨packed ++ List.replicate (words - (pack processed).length) 0 ++ tail, ?_⟩
  simp only [signedI32Values, List.map_append, List.map_replicate, workspace]
  rw [show List.map (fun value => Value.signed .i32 value) packed = pack processed from encoded]

/-- Compose the actual Core operations used on the right-hand side of the
packing assignment. The operand evaluations preserve their real evaluation
order; the arithmetic result follows from the zero-high-lanes invariant. -/
theorem evaluates_insert_byte
    {program : Program} {before afterLower afterByte afterShift : State}
    {lowerExpr byteExpr shiftExpr : Expr} {lower lane : Nat} (byte : UInt8)
    (laneBound : lane < 4) (lowerBound : lower < 2 ^ (lane * 8))
    (lowerResult : Evaluates program before lowerExpr
      (.signed .i32 (wrapSigned program.target .i32 lower)) afterLower)
    (byteResult : Evaluates program afterLower byteExpr
      (.signed .i32 byte.toNat) afterByte)
    (shiftResult : Evaluates program afterByte shiftExpr
      (.signed .i32 (lane * 8 : Nat)) afterShift) :
    Evaluates program before
      (.binary .bitOr lowerExpr (.binary .shiftLeft byteExpr shiftExpr))
      (.signed .i32 (wrapSigned program.target .i32
        (lower + byte.toNat * 2 ^ (lane * 8) : Nat))) afterShift := by
  apply evaluatesEagerBinary (by decide) (by decide) lowerResult
  · apply evaluatesEagerBinary (by decide) (by decide) byteResult shiftResult
    simpa only [evalBinaryValue, BEq.rfl, if_true] using
      packing_shift program.target byte lane laneBound
  · simpa only [evalBinaryValue, BEq.rfl, if_true] using
      packing_or program.target byte lane lower laneBound lowerBound

/-- One real source-level workspace update, not a second list-only model.
The postcondition gives the changed i32 cell and a one-cell write footprint,
so the source byte buffer and unrelated locals can be framed across the loop. -/
theorem writes_packed_byte
    (program : Program) (before : State) (values : List Int)
    (workspaceId : VarId) (workspaceCell : CellId)
    (indexExpr byteExpr shiftExpr : Expr) (position lane lower : Nat) (byte : UInt8)
    (wellFormed : StateWellFormed before)
    (inBounds : position < values.length)
    (laneBound : lane < 4) (lowerBound : lower < 2 ^ (lane * 8))
    (workspaceLocal : before.local? workspaceId = some
      (.slice (.scalar (.signed .i32)) workspaceCell [] 0 values.length))
    (backing : before.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values values)) })
    (wordValue : values.get ⟨position, inBounds⟩ = wrapSigned program.target .i32 lower)
    (indexResult : Evaluates program before indexExpr (.signed .i32 position) before)
    (byteResult : Evaluates program before byteExpr (.signed .i32 byte.toNat) before)
    (shiftResult : Evaluates program before shiftExpr (.signed .i32 (lane * 8 : Nat)) before) :
    ∃ after,
      Evaluates program before
        (.assign .set (.index (.local workspaceId) indexExpr)
          (.binary .bitOr (.index (.local workspaceId) indexExpr)
            (.binary .shiftLeft byteExpr shiftExpr))) .unit after ∧
      StateWellFormed after ∧
      after.cellEntry? workspaceCell = some {
        id := workspaceCell
        value := some (.array (signedI32Values (setI32Value values position
          (wrapSigned program.target .i32
            (lower + byte.toNat * 2 ^ (lane * 8) : Nat)))))
      } ∧ ModifiesOnly (CellSet.singleton workspaceCell) before after := by
  have baseResult : Evaluates program before (.local workspaceId)
      (.slice (.scalar (.signed .i32)) workspaceCell [] 0 values.length) before :=
    ⟨1, evalLocal_of_local 0 program before workspaceId _ workspaceLocal⟩
  have readWord := evaluatesSignedI32SliceIndex program before before before values
    (.local workspaceId) indexExpr workspaceCell position inBounds baseResult
    indexResult backing
  rw [wordValue] at readWord
  have rhs := evaluates_insert_byte byte laneBound lowerBound readWord byteResult shiftResult
  exact evaluatesSetSignedI32SliceIndexFromEmpty program before before before values
    workspaceId indexExpr _ workspaceCell position _ inBounds workspaceLocal
    indexResult wellFormed (ModifiesOnly.refl before) rhs wellFormed
    (ModifiesOnly.refl before) backing

/-- Advance the byte-prefix invariant through the actual Core assignment.
The caller supplies only the current packed prefix, not the value of the word
being overwritten or an assumed encoding of the next prefix. -/
theorem writes_next_workspace_byte
    (program : Program) (before : State) (values : List Int)
    (workspaceId : VarId) (workspaceCell : CellId)
    (indexExpr byteExpr shiftExpr : Expr)
    (words : Nat) (processed : List UInt8) (byte : UInt8) (tail : List Value)
    (room : (processed.length + 4) / 4 ≤ words)
    (wellFormed : StateWellFormed before)
    (contents : signedI32Values values = workspace words processed tail)
    (workspaceLocal : before.local? workspaceId = some
      (.slice (.scalar (.signed .i32)) workspaceCell [] 0 values.length))
    (backing : before.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values values)) })
    (indexResult : Evaluates program before indexExpr
      (.signed .i32 (processed.length / 4)) before)
    (byteResult : Evaluates program before byteExpr (.signed .i32 byte.toNat) before)
    (shiftResult : Evaluates program before shiftExpr
      (.signed .i32 (processed.length % 4 * 8 : Nat)) before) :
    ∃ after,
      Evaluates program before
        (.assign .set (.index (.local workspaceId) indexExpr)
          (.binary .bitOr (.index (.local workspaceId) indexExpr)
            (.binary .shiftLeft byteExpr shiftExpr))) .unit after ∧
      StateWellFormed after ∧
      after.cellEntry? workspaceCell = some {
        id := workspaceCell
        value := some (.array (workspace words (processed ++ [byte]) tail))
      } ∧ ModifiesOnly (CellSet.singleton workspaceCell) before after := by
  have selected := workspace_current_word program.target words processed tail room
  rw [← contents] at selected
  have inBounds : processed.length / 4 < values.length := by
    have bound := (List.getElem?_eq_some_iff.mp selected).1
    simpa [signedI32Values] using bound
  have wordValue : values.get ⟨processed.length / 4, inBounds⟩ =
      wrapSigned program.target .i32 (pendingBits processed) := by
    simpa [signedI32Values, inBounds] using selected
  obtain ⟨after, evaluated, afterWF, afterBacking, footprint⟩ :=
    writes_packed_byte program before values workspaceId workspaceCell
      indexExpr byteExpr shiftExpr (processed.length / 4) (processed.length % 4)
      (pendingBits processed) byte wellFormed inBounds (Nat.mod_lt _ (by decide))
      (pendingBits_bound processed) workspaceLocal backing wordValue
      indexResult byteResult shiftResult
  refine ⟨after, evaluated, afterWF, ?_, footprint⟩
  rw [← setValue_signedI32Values, contents,
    workspace_insert_byte program.target words processed byte tail room] at afterBacking
  exact afterBacking

end Lanius.Extraction.OutputPacking
