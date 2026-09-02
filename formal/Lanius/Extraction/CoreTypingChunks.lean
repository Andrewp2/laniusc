import Lanius.Extraction.CoreTypingChecker

namespace Lanius.Extraction.CoreTyping

theorem checkConstants_append_isSome (program : Lanius.Core.Program)
    (left right : List Lanius.Core.Constant) :
    (checkConstants program (left ++ right)).isSome =
      ((checkConstants program left).isSome &&
        (checkConstants program right).isSome) := by
  induction left with
  | nil => simp [checkConstants]
  | cons head tail ih =>
      simp only [List.cons_append, checkConstants]
      cases checkConstant program head
      · simp
      · cases htr : checkConstants program (tail ++ right) <;>
          cases ht : checkConstants program tail <;>
            cases hr : checkConstants program right <;> simp_all

theorem checkFunctions_append_isSome (program : Lanius.Core.Program)
    (left right : List Lanius.Core.Function) :
    (checkFunctions program (left ++ right)).isSome =
      ((checkFunctions program left).isSome &&
        (checkFunctions program right).isSome) := by
  induction left with
  | nil => simp [checkFunctions]
  | cons head tail ih =>
      simp only [List.cons_append, checkFunctions]
      cases checkFunction program head
      · simp
      · cases htr : checkFunctions program (tail ++ right) <;>
          cases ht : checkFunctions program tail <;>
            cases hr : checkFunctions program right <;> simp_all

end Lanius.Extraction.CoreTyping
