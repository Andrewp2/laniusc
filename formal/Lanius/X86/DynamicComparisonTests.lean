import Lanius.X86.DynamicComparison

namespace Lanius.X86.DynamicComparisonTests

open Lanius.X86 Lanius.X86.Machine
open Lanius.X86.ExpressionEnvironment
open Lanius.X86.DynamicComparison

example : localNotEqualBytes (.frame 2) (.frame 3) 4 =
    frameLoadBytes 2 ++ frameStoreBytes 4 ++ frameLoadBytes 3 ++
      frameCompareBytes 4 5 := by
  simp [localNotEqualBytes, LocalExpressionCheck.Location.bodyBytes, List.append_assoc]

example (flags : BitVec 64) (left right : BitVec 32) :
    condition (subtractFlags flags left right) 5 = (left != right) :=
  compare_notEqual_condition flags left right

end Lanius.X86.DynamicComparisonTests
