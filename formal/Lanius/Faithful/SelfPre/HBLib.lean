import Lanius.Faithful.SelfPre.HB
import Lanius.Faithful.SelfPre.Tactic

/-! # Heights of the library functions the self program's Lean model calls (F14)

`HBPost.<f>.p<i>` bounds `hb (f xs)` by a potential `M` bounding the arguments'
heights; `post_auto` and `pre_auto` find these by the function's name. -/

namespace Lanius.Faithful.SelfPre

theorem HBPost.List.getD.p0 {α : Type} [HB α] :
    ∀ (l : List α) (i : Nat) (d : α) (M : Nat), hb l ≤ M → hb d ≤ M → hb (l.getD i d) ≤ M
  | [], i, d, M, h1, h2 => by simpa using h2
  | a :: l, 0, d, M, h1, h2 => by simp only [List.getD_cons_zero, hb_cons] at *; omega
  | a :: l, i + 1, d, M, h1, h2 => by
    simp only [List.getD_cons_succ, hb_cons] at *
    exact HBPost.List.getD.p0 l i d M (by omega) h2

theorem HBPost.GetElem?.getElem?.p0 {α : Type} [HB α] :
    ∀ (l : List α) (i : Nat) (M : Nat), hb l ≤ M → hb (l[i]?) ≤ M
  | [], i, M, h => by simp
  | a :: l, 0, M, h => by simp only [List.getElem?_cons_zero, hb_some, hb_cons] at *; omega
  | a :: l, i + 1, M, h => by
    simp only [List.getElem?_cons_succ, hb_cons] at *
    exact HBPost.GetElem?.getElem?.p0 l i M (by omega)

end Lanius.Faithful.SelfPre
