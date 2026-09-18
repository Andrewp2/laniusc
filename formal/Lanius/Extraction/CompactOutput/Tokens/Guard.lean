import Lanius.Extraction.CompactOutput.Tokens.Source

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- Evaluate the actual signed division and guard. Up to two spare trailing input
words do not increase the number of complete three-word tokens. -/
theorem entry_guard (program : Program) (count length : Nat)
    (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean (decide (length / 3 < count))) before := by
  core_eval []

theorem entry_guard_passes (program : Program) (count length : Nat)
    (room : 3 * count ≤ length) (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean false) before := by
  have noError : ¬ length / 3 < count := by omega
  simpa only [noError, decide_false] using entry_guard program count length lengthFit countRead lengthRead

theorem entry_guard_rejects (program : Program) (count length : Nat)
    (short : length < 3 * count) (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean true) before := by
  have error : length / 3 < count := by omega
  simpa only [error, decide_true] using entry_guard program count length lengthFit countRead lengthRead

end Lanius.Extraction.CompactOutput.Tokens
