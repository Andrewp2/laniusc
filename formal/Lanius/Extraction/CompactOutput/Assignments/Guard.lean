import Lanius.Extraction.CompactOutput.Assignments.Source

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- Evaluate the actual signed division and guard. A spare trailing input
word does not increase the number of complete two-word assignments. -/
theorem entry_guard (program : Program) (count length : Nat)
    (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean (decide (length / 2 < count))) before := by
  core_eval []

theorem entry_guard_passes (program : Program) (count length : Nat)
    (room : 2 * count ≤ length) (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean false) before := by
  have noError : ¬ length / 2 < count := by omega
  simpa only [noError, decide_false] using entry_guard program count length lengthFit countRead lengthRead

theorem entry_guard_rejects (program : Program) (count length : Nat)
    (short : length < 2 * count) (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean true) before := by
  have error : length / 2 < count := by omega
  simpa only [error, decide_true] using entry_guard program count length lengthFit countRead lengthRead

end Lanius.Extraction.CompactOutput.Assignments
