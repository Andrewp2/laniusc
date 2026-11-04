module

public import Lanius.Open.F5.HomeLendArgs.Stmt
public import Lanius.Open.F5.HomesLend.Proof
public import Lanius.Mini.Refs.Lemmas

@[expose] public section

open Lanius.Mini

theorem Lanius.Open.HomeLendArgs.evalAll_map (env : Env) :
    ∀ (es : List Expr), Expr.evalAll env es = es.map (·.eval env)
  | [] => rfl
  | e :: rest => by simp only [Expr.evalAll, List.map_cons, evalAll_map env rest]

/-- `HomesLend`, at the entry slots of the two words: the address is the
home's pointer (a packed array's lowest byte), below `2 ^ 62`. -/
theorem Lanius.Open.HomeLendArgs.proof : Lanius.Open.HomeLendArgs := by
  intro sx bud places st hp x element length env r offset before after homes mem hty helem haddr hlen
  have small := homes.small x mem
  have pointer : x.pointer = x.address := by
    unfold Addressed.pointer
    rcases helem with rfl | rfl <;> rw [hty]
  refine Lanius.Open.HomesLend.proof sx bud places st hp x element length _ before.length homes mem hty helem
    ?_ ?_ hlen
  · simp only [Func.entry, Lanius.Open.HomeLendArgs.evalAll_map, List.map_append, List.map_cons]
    rw [List.getD_eq_getElem?_getD, List.getElem?_append_right (by simp)]
    simp only [List.length_map, Nat.sub_self, List.getElem?_cons_zero, Option.getD_some, pointer]
    exact addOff_eval rfl (by omega) |>.trans (by omega)
  · simp only [Func.entry, Lanius.Open.HomeLendArgs.evalAll_map, List.map_append, List.map_cons]
    rw [List.getD_eq_getElem?_getD, List.getElem?_append_right (by simp)]
    simp only [List.length_map, Nat.add_sub_cancel_left, List.getElem?_cons_succ, List.getElem?_cons_zero,
      Option.getD_some, Expr.eval, BitVec.toNat_ofNat]
    exact Nat.mod_eq_of_lt (by omega)
