import Lanius.Extraction.Entry.File.Domain

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics
open Lanius.Extraction.CompactOutput

theorem append_position_bounds (values : List Nat) (original : List Int)
    (nonnegative : 0 ≤ position) (bounded : values.length ≤ bound)
    (room : position.toNat + bound ≤ capacity) (storage : capacity ≤ original.length) :
    0 ≤ (appendAll capacity values position original).position ∧
      (appendAll capacity values position original).position ≤ (position.toNat + bound : Nat) := by
  have appended := appendAll_success capacity position.toNat values original (by omega) storage
  rw [Int.toNat_of_nonneg nonnegative] at appended
  have cursor := congrArg AppendOutcome.position appended
  simp only [AppendOutcome.position] at cursor ⊢
  omega

/-- Successful progress under source-only syntax/storage bounds and enough
remaining output space. The original scope observes the resulting cursor,
so this guarantee survives every nested local scope in the file body. -/
def Progress {program : CoreSynthesis.Program.CheckedProgram artifacts}
    {pipeline : Load.Pipeline program} {before : State}
    (input : Load.Input pipeline before) (cursor : VarId) (position : Int)
    (completion : Completion) (after : State) : Prop :=
  ∀ bound, SourceDomain {path := input.path, bytes := input.file.bytes.map UInt8.toNat} bound →
    0 ≤ position → position.toNat + bound ≤ 16777216 →
      completion = .next ∧ ∃ finalPosition : Nat,
        (restoreLocals before after).local? cursor = some (.signed .i32 finalPosition) ∧
        finalPosition ≤ position.toNat + bound

theorem Progress.restore (progress : Progress input cursor position completion after) (caller : State) :
    Progress input cursor position completion (restoreLocals caller after) := progress

end Lanius.Extraction.Entry.File
