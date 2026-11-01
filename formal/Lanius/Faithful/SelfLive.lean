import Lanius.Faithful.SafeDriver
import Lanius.Faithful.Fwd.Func

/-! # The self-host driver completes in Core (review #5 step 3, piece (c))

The converse of `driver_faithful`: Core's run of `w(input, words, output,
room)` completes when the cost semantics gives the pure compile a value
within the heap (`selfCost`) and the result's words fit in the output room.
`oracle_read`'s `cons` calls cost `boxCost prog 33` each (one box of a
`List<i32>`), and `grammar()`, `front_end_words` and `compile_words` cost
what `qcall` says; nothing else `w` runs allocates. -/

namespace Lanius.Faithful.SelfLive

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals readRawSliceIndex)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfCert
open Lanius.Faithful.SelfFaithful (boxes)
open Lanius.Faithful.SelfDriver

/-! ## The pure values and costs of the driver's calls -/

/-- The pure list of `xs` in front of `tail`, as `cons` builds it. -/
def listOnto : List (BitVec 32) → Value → Value
  | [], tail => tail
  | x :: xs, tail => .enumeration 0 1 [.signed .i32 x.toInt, listOnto xs tail]

/-- The pure empty list, `empty()`'s value. -/
def nilVal : Value := .enumeration 0 0 []

/-- The pure list of `W`, `oracle_read`'s value. -/
def listVal (W : List (BitVec 32)) : Value := listOnto W nilVal

theorem listOnto_append (a b : List (BitVec 32)) (t : Value) : listOnto (a ++ b) t = listOnto a (listOnto b t) := by
  induction a with
  | nil => rfl
  | cons x xs ih => simp only [List.cons_append, listOnto, ih]

/-- The heap cost of one `cons`: one box of a `List<i32>`. -/
def consCost : Nat := boxCost prog 33

/-- The cost semantics of `w` on `W` with fuel `N`: the `cons` calls of
`oracle_read`, then `grammar()`, `front_end_words(grammar(), list)` and
`compile_words(..)`. -/
def selfCost (N : Nat) (W : List (BitVec 32)) : Option Nat :=
  (qcall prog prims (boxCost prog) N 8 []).bind fun g =>
  (qcall prog prims (boxCost prog) N 7 [g.1, listVal W]).bind fun fe =>
  (qcall prog prims (boxCost prog) N 6 [fe.1]).bind fun cw =>
  some (W.length * consCost + g.2 + fe.2 + cw.2)

theorem qcall_cons (N : Nat) (x t : Value) :
    qcall prog prims (boxCost prog) (N + 2) 9 [x, t] = some (.enumeration 0 1 [x, t], consCost) := by
  have b33 : 33 ∈ prims.boxed := by decide +kernel
  simp [qcall, np_cons_of_i32, fn_cons_of_i32, src_cons_of_i32, qstmt, qeff, qeffs, qthen, qfree, addC,
    np_boxed_of_mini_selfhost_List_i32, b33, single, pexpr, paramEnv, ty1, SrcType.typeId, paramBindings,
    Env.bindAll, Env.get?, doneValue, consCost]

theorem qcall_empty (N : Nat) : qcall prog prims (boxCost prog) (N + 1) 5 [] = some (nilVal, 0) := by
  simp [qcall, np_empty_of_i32, fn_empty_of_i32, src_empty_of_i32, qstmt, qeff, qeffs, qthen, qfree, addC,
    ty1, SrcType.typeId, nilVal, doneValue]

/-! ## `oracle_read` -/

theorem exprs_locals_fwd {P : Core.Program} {st : State} :
    ∀ (bs : List (Nat × Value)), (∀ b ∈ bs, st.local? b.1 = some b.2) →
      Ev (fun k => evalExprs k P st (bs.map fun b => .local b.1)) (bs.map Prod.snd) st
  | [], _ => exprs_nil_fwd
  | b :: bs, known => exprs_cons_fwd (local_fwd (known b (List.mem_cons_self ..)))
      (exprs_locals_fwd bs fun b' mem => known b' (List.mem_cons_of_mem _ mem))

theorem notOut (c : Nat) (h : SelfPure.outside.contains c = false := by decide +kernel) :
    SelfPure.outside.contains c = false := h

theorem if_true_fwd {P : Core.Program} {st : State} {cond : Core.Expr} {a b : Core.Stmt} {c : Completion}
    {s1 s2 : State} (test : Ev (fun k => evalExpr k P st cond) (.boolean true) s1)
    (branch : Ev (fun k => execStmt k P s1 a) c s2) : Ev (fun k => execStmt k P st (.ifThenElse cond a b)) c s2 :=
  if_fwd test (by simpa using branch)

theorem if_false_fwd {P : Core.Program} {st : State} {cond : Core.Expr} {a b : Core.Stmt} {c : Completion}
    {s1 s2 : State} (test : Ev (fun k => evalExpr k P st cond) (.boolean false) s1)
    (branch : Ev (fun k => execStmt k P s1 b) c s2) : Ev (fun k => execStmt k P st (.ifThenElse cond a b)) c s2 :=
  if_fwd test (by simpa using branch)

/-- What `oracle_read(data, lo, hi, tail)`'s body completes with. -/
def ReadLive (inp : Nat) (W : List (BitVec 32)) (m : Nat) : Prop :=
  ∀ {lo hi : Nat} {s : State} {tv tp : Value},
    hi - lo = m → lo ≤ hi → hi ≤ W.length → Inv s → Reads s inp W →
    VRel prog.toCore boxes s.heap ty1 tv tp → s.heap.nextAddress + (hi - lo) * consCost ≤ 2 ^ 64 →
    s.heap.remaining = none →
    ∃ c completed v, Ev (fun k => execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(12, .rawSlice i32T inp W.length), (25, .unsigned .usize lo), (36, .unsigned .usize hi), (47, tv)])
      (src_app_main_oracle_read 1 9).body.toCore) c completed ∧ CallResult ty1 c v ∧
      VRel prog.toCore boxes completed.heap ty1 v (listOnto ((W.drop lo).take (hi - lo)) tp) ∧
      Inv completed ∧ Step s completed ∧
      completed.heap.nextAddress ≤ s.heap.nextAddress + (hi - lo) * consCost ∧ completed.heap.remaining = none

theorem read_live {inp : Nat} {W : List (BitVec 32)} (len : W.length < 2 ^ 64) : ∀ m, ReadLive inp W m := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
  intro lo hi s tv tp hm le hle inv reads rel budget fr
  generalize hE : ({ s with locals := [] } : State).bindLocals [(12, .rawSlice i32T inp W.length),
    (25, .unsigned .usize lo), (36, .unsigned .usize hi), (47, tv)] = E
  have invE : Inv E := by rw [← hE]; exact Same.start inv _
  have stepE : Step s E := by rw [← hE]; exact (Step.clear s).trans (Step.bindLocals _ _)
  have heapE : E.heap = s.heap := by rw [← hE]; rfl
  have l12 : E.local? 12 = some (.rawSlice i32T inp W.length) := by
    rw [← hE]; exact local?_entry inv [] [(25, .unsigned .usize lo), (36, .unsigned .usize hi), (47, tv)] 12
      (.rawSlice i32T inp W.length) rfl (by simp)
  have l25 : E.local? 25 = some (.unsigned .usize lo) := by
    rw [← hE]; exact local?_entry inv [(12, .rawSlice i32T inp W.length)] [(36, .unsigned .usize hi), (47, tv)] 25
      (.unsigned .usize lo) rfl (by simp)
  have l36 : E.local? 36 = some (.unsigned .usize hi) := by
    rw [← hE]; exact local?_entry inv [(12, .rawSlice i32T inp W.length), (25, .unsigned .usize lo)] [(47, tv)] 36
      (.unsigned .usize hi) rfl (by simp)
  have l47 : E.local? 47 = some tv := by
    rw [← hE]; exact local?_entry inv [(12, .rawSlice i32T inp W.length), (25, .unsigned .usize lo),
      (36, .unsigned .usize hi)] [] 47 tv rfl (by simp)
  simp only [src_app_main_oracle_read, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcExpr.toCore,
    SrcType.toCore, SrcOp.toCore, SrcDivOp.toCore, UintTy.toCore, List.map]
  have diff : Ev (fun k => evalExpr k prog.toCore E (.binary .subtract (.local 36) (.local 25)))
      (.unsigned .usize (hi - lo)) E :=
    binary_fwd (by decide) (by decide) (local_fwd l36) (local_fwd l25) (by rw [toCore_target', nat_sub le (by omega)])
  by_cases big : hi - lo > 1
  · -- Split at the middle: the right half in front of the tail, then the left half.
    have test : Ev (fun k => evalExpr k prog.toCore E (.binary .greater (.binary .subtract (.local 36) (.local 25))
        (.value (.unsigned .usize (1#64).toNat)))) (.boolean true) E :=
      binary_fwd (by decide) (by decide) diff (value_fwd _)
        (by rw [toCore_target', show (1#64).toNat = 1 from rfl, nat_greater, decide_eq_true big])
    generalize hmid : lo + (hi - lo) / 2 = mid
    have midLo : lo ≤ mid := by omega
    have midHi : mid ≤ hi := by omega
    have midE : Ev (fun k => evalExpr k prog.toCore E (.binary .add (.local 25) (.binary .divide
        (.binary .subtract (.local 36) (.local 25)) (.value (.unsigned .usize (2#64).toNat)))))
        (.unsigned .usize mid) E := by
      refine binary_fwd (by decide) (by decide) (local_fwd l25) (binary_fwd (by decide) (by decide) diff (value_fwd _)
        (by rw [toCore_target', show (2#64).toNat = 2 from rfl, nat_half _ (by omega)])) ?_
      rw [toCore_target', nat_add (by omega), hmid]
    have inv1 := invE.bindLocal 146 (.unsigned .usize mid)
    have step1 : Step s (E.bindLocal 146 (.unsigned .usize mid)) := stepE.trans (Step.bindLocal _ _ _)
    have hsplit : (hi - lo) * consCost = (mid - lo) * consCost + (hi - mid) * consCost := by
      rw [← Nat.add_mul]; congr 1; omega
    have hle1 : (hi - mid) * consCost ≤ (hi - lo) * consCost := by rw [hsplit]; exact Nat.le_add_left _ _
    obtain ⟨c1, done1, v1, body1, res1, rel1, invD1, stepD1, grown1, fr1⟩ := ih (hi - mid) (by omega)
      (lo := mid) (hi := hi) (s := E.bindLocal 146 (.unsigned .usize mid)) (tv := tv) (tp := tp) rfl midHi hle inv1
      (reads.step step1) (heapE ▸ rel)
      (by show E.heap.nextAddress + _ ≤ _; rw [heapE]; exact Nat.le_trans (Nat.add_le_add_left hle1 _) budget)
      (by rw [← fr]; exact congrArg _ heapE)
    have g1 : done1.heap.nextAddress ≤ s.heap.nextAddress + (hi - mid) * consCost := by
      simpa only [show (E.bindLocal 146 (.unsigned .usize mid)).heap = s.heap from heapE] using grown1
    have total : s.heap.nextAddress + (hi - mid) * consCost + (mid - lo) * consCost =
        s.heap.nextAddress + (hi - lo) * consCost := by
      rw [hsplit, Nat.add_assoc, Nat.add_comm ((hi - mid) * consCost)]
    have call1 := call_fwd (exprs_locals_fwd [(12, .rawSlice i32T inp W.length), (146, .unsigned .usize mid),
        (36, .unsigned .usize hi), (47, tv)] (by
      intro b mem
      simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
      rcases mem with rfl | rfl | rfl | rfl
      · exact local?_bindLocal_other (by simp) _ l12
      · exact local?_bindLocal_self invE _ _
      · exact local?_bindLocal_other (by simp) _ l36
      · exact local?_bindLocal_other (by simp) _ l47)) fn_read rfl body1 res1
    generalize hR1 : restoreLocals (E.bindLocal 146 (.unsigned .usize mid)) done1 = R1 at call1
    have invR1 : Inv R1 := by rw [← hR1]; exact invD1.restore _
    have stepR1 : Step s R1 := by rw [← hR1]; exact step1.trans (stepD1.restore _)
    have heapR1 : R1.heap = done1.heap := by rw [← hR1]; rfl
    have back {id : Nat} {x : Value} (ne : 191 ≠ id) (h : (E.bindLocal 146 (.unsigned .usize mid)).local? id = some x) :
        (R1.bindLocal 191 v1).local? id = some x := by
      refine local?_bindLocal_other ne _ ?_
      rw [← hR1]
      exact local?_prefix (st' := restoreLocals (E.bindLocal 146 (.unsigned .usize mid)) done1) stepD1.cells rfl h
    have stepE2 : Step s (R1.bindLocal 191 v1) := stepR1.trans (Step.bindLocal _ _ _)
    obtain ⟨c2, done2, v2, body2, res2, rel2, invD2, stepD2, grown2, fr2⟩ := ih (mid - lo) (by omega)
      (lo := lo) (hi := mid) (s := R1.bindLocal 191 v1) (tv := v1) (tp := listOnto ((W.drop mid).take (hi - mid)) tp)
      rfl midLo (by omega) (invR1.bindLocal 191 v1) (reads.step stepE2) (heapR1 ▸ rel1)
      (by
        show R1.heap.nextAddress + _ ≤ _
        rw [heapR1]
        exact Nat.le_trans (Nat.add_le_add_right g1 _) (by rw [total]; exact budget)) (by show R1.heap.remaining = none; rw [heapR1]; exact fr1)
    have call2 := call_fwd (exprs_locals_fwd [(12, .rawSlice i32T inp W.length), (25, .unsigned .usize lo),
        (146, .unsigned .usize mid), (191, v1)] (by
      intro b mem
      simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
      rcases mem with rfl | rfl | rfl | rfl
      · exact back (by simp) (local?_bindLocal_other (by simp) _ l12)
      · exact back (by simp) (local?_bindLocal_other (by simp) _ l25)
      · exact back (by simp) (local?_bindLocal_self invE _ _)
      · exact local?_bindLocal_self invR1 _ _)) fn_read rfl body2 res2
    refine ⟨.returned (some v2), _, _,
      sequence_ret_fwd (if_true_fwd test (letLocal_fwd midE (letLocal_fwd call1 (return_fwd call2)))), rfl, ?_, ((invD2.restore _).restore _).restore _, ?_, ?_, fr2⟩
    · show VRel prog.toCore boxes done2.heap ty1 v2 _
      have e : listOnto ((W.drop lo).take (hi - lo)) tp =
          listOnto ((W.drop lo).take (mid - lo)) (listOnto ((W.drop mid).take (hi - mid)) tp) := by
        have := take_split W [] midLo midHi
        simp only [List.append_nil] at this
        rw [← this, listOnto_append]
      rw [e]
      exact rel2
    · exact (((stepE2.trans stepD2).restore _).restore _).restore _
    · show done2.heap.nextAddress ≤ _
      have g2 : done2.heap.nextAddress ≤ done1.heap.nextAddress + (mid - lo) * consCost := by
        simpa only [show (R1.bindLocal 191 v1).heap = done1.heap from heapR1] using grown2
      exact Nat.le_trans g2 (by rw [← total]; exact Nat.add_le_add_right g1 _)
  · have test : Ev (fun k => evalExpr k prog.toCore E (.binary .greater (.binary .subtract (.local 36) (.local 25))
        (.value (.unsigned .usize (1#64).toNat)))) (.boolean false) E :=
      binary_fwd (by decide) (by decide) diff (value_fwd _)
        (by rw [toCore_target', show (1#64).toNat = 1 from rfl, nat_greater, decide_eq_false big])
    by_cases one : hi > lo
    · -- One word: `cons(data[lo], tail)`.
      have test2 : Ev (fun k => evalExpr k prog.toCore E (.binary .greater (.local 36) (.local 25))) (.boolean true) E :=
        binary_fwd (by decide) (by decide) (local_fwd l36) (local_fwd l25)
          (by rw [toCore_target', nat_greater, decide_eq_true one])
      have lt : lo < W.length := by omega
      have hl1 : hi - lo = 1 := by omega
      have args : Ev (fun k => evalExprs k prog.toCore E [(Core.Expr.local 12).index (.local 25), .local 47])
          [.signed .i32 (W[lo]).toInt, tv] E :=
        exprs_cons_fwd (index_fwd (local_fwd l12) (local_fwd l25) (by simp [Semantics.integerIndex])
          (Reads.step reads stepE lo lt)) (exprs_cons_fwd (local_fwd l47) exprs_nil_fwd)
      obtain ⟨w, v, st', hw, callE, relW, invW, stepW, grownW, frW, -⟩ := pure_call_fwd SelfPure.selfPure
        SelfPure.selfPrims (N := 2) fn_cons_of_i32 (notOut 9) args invE
        (.cons (.scalar (i32_scalar (W[lo]))) (.cons (heapE ▸ rel) .nil))
        (h := consCost) (by simp only [ccall, qcall_cons 0, Option.map_some]) (by rw [heapE]; rw [hl1, Nat.one_mul] at budget; exact budget)
        (by rw [heapE]; exact fr)
      have hw' : pcall prog prims 2 9 [.signed .i32 (W[lo]).toInt, tp] =
          some (.enumeration 0 1 [.signed .i32 (W[lo]).toInt, tp]) := by
        rw [pcall_eq_qcall _ _ (boxCost prog), qcall_cons 0]; rfl
      rw [hw', Option.some.injEq] at hw
      subst hw
      refine ⟨.returned (some v), _, _, sequence_next_fwd (if_false_fwd test skip_fwd)
        (sequence_ret_fwd (if_true_fwd test2 (return_fwd callE))), rfl, ?_, invW, stepE.trans stepW, ?_, frW⟩
      · rw [hl1, take_one W lt]
        exact relW
      · rw [hl1, Nat.one_mul, ← heapE]; exact grownW
    · -- No words: the tail.
      have test2 : Ev (fun k => evalExpr k prog.toCore E (.binary .greater (.local 36) (.local 25))) (.boolean false) E :=
        binary_fwd (by decide) (by decide) (local_fwd l36) (local_fwd l25)
          (by rw [toCore_target', nat_greater, decide_eq_false one])
      have hz : hi - lo = 0 := by omega
      refine ⟨.returned (some tv), _, _, sequence_next_fwd (if_false_fwd test skip_fwd)
        (sequence_next_fwd (if_false_fwd test2 skip_fwd) (return_fwd (local_fwd l47))), rfl, ?_, invE, stepE, ?_, ?_⟩
      · rw [hz]; exact heapE ▸ rel
      · rw [heapE]; exact Nat.le_add_right _ _
      · rw [heapE]; exact fr

end Lanius.Faithful.SelfLive
