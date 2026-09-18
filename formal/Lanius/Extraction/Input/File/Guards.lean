import Lanius.Extraction.Input.File.Read

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

theorem errorGuard_passes (program : Program) (count request : Nat)
    (countRead : before.local? 9 = some (.signed .i32 count))
    (requestRead : before.local? 6 = some (.signed .i32 request)) (bounded : count ≤ request) :
    Evaluates program before errorGuard (.boolean false) before := by
  have nonnegative : Evaluates program before (binary .lessEqual (read 9) negativeOne) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program countRead) (negativeOne_evaluates program before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have limited : Evaluates program before (binary .greater (read 9) (read 6)) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program countRead) (local_evaluates program requestRead)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  exact evaluatesPureLogicalOr nonnegative limited

theorem eofGuard_evaluates (program : Program) (count : Nat)
    (countRead : before.local? 9 = some (.signed .i32 count)) :
    Evaluates program before eofGuard (.boolean (decide (count = 0))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program countRead)
    (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
  simp [evalBinaryValue, scalarEqual]
  apply Bool.eq_iff_iff.mpr
  simp

theorem overflowGuard_evaluates (program : Program) (count remaining : Nat)
    (countRead : before.local? 9 = some (.signed .i32 count))
    (remainingRead : before.local? 7 = some (.signed .i32 remaining)) :
    Evaluates program before overflowGuard (.boolean (decide (remaining < count))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program countRead) (local_evaluates program remainingRead)
  simp [evalBinaryValue, evalSignedBinary]

theorem guards_eof (program : Program) (request total : Nat)
    (countRead : before.local? 9 = some (.signed .i32 0))
    (requestRead : before.local? 6 = some (.signed .i32 request))
    (totalRead : before.local? 5 = some (.signed .i32 total)) :
    Executes program before countGuards (.returned (some (.signed .i32 total))) before :=
  executesSequence (executesIfFalse (errorGuard_passes program 0 request countRead requestRead (Nat.zero_le _)) (executesSkip _ _))
    (executesSequenceReturned (executesIfTrue (eofGuard_evaluates program 0 countRead)
      (executesSequenceReturned (executesReturnValue (local_evaluates program totalRead)))))

theorem guards_continue (program : Program) (count request remaining : Nat)
    (countRead : before.local? 9 = some (.signed .i32 count))
    (requestRead : before.local? 6 = some (.signed .i32 request))
    (remainingRead : before.local? 7 = some (.signed .i32 remaining))
    (positive : 0 < count) (requested : count ≤ request) (fits : count ≤ remaining)
    (continued : Executes program before unpackAndAdvance completion after) :
    Executes program before countGuards completion after := by
  have notEof := eofGuard_evaluates program count countRead
  have noOverflow := overflowGuard_evaluates program count remaining countRead remainingRead
  simp only [Nat.ne_of_gt positive, decide_false] at notEof
  simp only [Nat.not_lt_of_ge fits, decide_false] at noOverflow
  exact executesSequence (executesIfFalse (errorGuard_passes program count request countRead requestRead requested) (executesSkip _ _))
    (executesSequence (executesIfFalse notEof (executesSkip _ _))
      (executesSequence (executesIfFalse noOverflow (executesSkip _ _)) continued))

theorem guards_overflow (program : Program) (count request remaining : Nat)
    (countRead : before.local? 9 = some (.signed .i32 count))
    (requestRead : before.local? 6 = some (.signed .i32 request))
    (remainingRead : before.local? 7 = some (.signed .i32 remaining))
    (requested : count ≤ request) (oversize : remaining < count) :
    Executes program before countGuards (.returned (some (.signed .i32 (-2)))) before := by
  have notEof := eofGuard_evaluates program count countRead
  have overflow := overflowGuard_evaluates program count remaining countRead remainingRead
  simp only [Nat.ne_of_gt (Nat.lt_of_le_of_lt (Nat.zero_le _) oversize), decide_false] at notEof
  simp only [oversize, decide_true] at overflow
  have negative : Evaluates program before negativeTwo (.signed .i32 (-2)) before := by
    apply evaluatesUnary (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  exact executesSequence (executesIfFalse (errorGuard_passes program count request countRead requestRead requested) (executesSkip _ _))
    (executesSequence (executesIfFalse notEof (executesSkip _ _))
      (executesSequenceReturned (executesIfTrue overflow (executesSequenceReturned (executesReturnValue negative)))))

end Lanius.Extraction.Input.File
