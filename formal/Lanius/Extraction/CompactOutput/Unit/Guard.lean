import Lanius.Extraction.CompactOutput.Unit.Source
import Lanius.Extraction.CompactOutput.Byte
import Lanius.Extraction.SemanticTokens.Collect.Record

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

theorem guard_pass (program : Program) (pathLength sourceLength nodeCount : Nat)
    (pathRead : before.local? 1 = some (.signed .i32 pathLength))
    (sourceRead : before.local? 3 = some (.signed .i32 sourceLength))
    (nodeRead : before.local? 15 = some (.signed .i32 nodeCount)) (nonempty : 0 < nodeCount) :
    Evaluates program before guard (.boolean false) before := by
  have path := Collect.lessEqual_evaluates (local_evaluates program pathRead) (negativeOne_evaluates program before)
  have source := Collect.lessEqual_evaluates (local_evaluates program sourceRead) (negativeOne_evaluates program before)
  have nodes := Collect.lessEqual_evaluates (local_evaluates program nodeRead)
    (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
  have all := evaluatesPureLogicalOr (evaluatesPureLogicalOr path source) nodes
  have pathNonnegative : ¬ ((pathLength : Int) ≤ -1) := by omega
  have sourceNonnegative : ¬ ((sourceLength : Int) ≤ -1) := by omega
  have nodesPositive : ¬ ((nodeCount : Int) ≤ 0) := by omega
  simpa only [guard, Int.ofNat_eq_natCast, pathNonnegative, sourceNonnegative, nodesPositive,
    decide_false, Bool.false_or] using all

end Lanius.Extraction.CompactOutput.Unit
