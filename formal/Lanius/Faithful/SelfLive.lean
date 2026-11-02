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
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals readRawSliceIndex ResolvedPlace)
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
    Env.bindAll, Env.get?, outValue, consCost]

theorem qcall_empty (N : Nat) : qcall prog prims (boxCost prog) (N + 1) 5 [] = some (nilVal, 0) := by
  simp [qcall, np_empty_of_i32, fn_empty_of_i32, src_empty_of_i32, qstmt, qeff, qeffs, qthen, qfree, addC,
    ty1, SrcType.typeId, nilVal, outValue]

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

/-! ## `oracle_write`, `oracle_write_one`, `oracle_put` -/

/-- What `oracle_write(out, ofs, ws)`'s body completes with, when `ws` fits
in the output room from `ofs`. -/
def WriteLive (outp room : Nat) (ws : List (BitVec 32)) : Prop :=
  ∀ {ofs : Nat} {s : State} {lv lp : Value},
    Inv s → s.heap.Readable outp (room * 4) → VRel prog.toCore boxes s.heap ty1 lv lp → (RepList 0 RepI32) ws lp →
    ofs + ws.length ≤ room → s.heap.nextAddress ≤ 2 ^ 64 → s.heap.remaining = none →
    ∃ c completed, Ev (fun k => execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(13, .rawSlice i32T outp room), (25, .unsigned .usize ofs), (36, lv)])
      (src_app_main_oracle_write 4 10).body.toCore) c completed ∧
      CallResult (.uint .usize) c (.unsigned .usize (ofs + ws.length)) ∧
      Inv completed ∧ completed.heap.Readable outp (room * 4) ∧
      completed.heap.nextAddress ≤ s.heap.nextAddress ∧ completed.heap.remaining = none ∧ s.cells <+: completed.cells

theorem write_one_live {outp room : Nat} (roomLt : room < 2 ^ 31) {x : BitVec 32} {rest : List (BitVec 32)}
    (ih : WriteLive outp room rest) {ofs : Nat} {s : State} {uv up : Value}
    (inv : Inv s) (readable : s.heap.Readable outp (room * 4))
    (rel : VRel prog.toCore boxes s.heap ty1 uv up) (rep : (RepList 0 RepI32) rest up)
    (fits : ofs + (rest.length + 1) ≤ room) (bound : s.heap.nextAddress ≤ 2 ^ 64) (fr : s.heap.remaining = none) :
    ∃ c completed, Ev (fun k => execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(17, .rawSlice i32T outp room), (29, .unsigned .usize ofs), (40, .signed .i32 x.toInt), (48, uv)])
      (src_app_main_oracle_write_one 3).body.toCore) c completed ∧
      CallResult (.uint .usize) c (.unsigned .usize (ofs + (rest.length + 1))) ∧
      Inv completed ∧ completed.heap.Readable outp (room * 4) ∧
      completed.heap.nextAddress ≤ s.heap.nextAddress ∧ completed.heap.remaining = none ∧ s.cells <+: completed.cells := by
  generalize hE : ({ s with locals := [] } : State).bindLocals [(17, .rawSlice i32T outp room),
    (29, .unsigned .usize ofs), (40, .signed .i32 x.toInt), (48, uv)] = E
  have invE : Inv E := by rw [← hE]; exact Same.start inv _
  have stepE : Step s E := by rw [← hE]; exact (Step.clear s).trans (Step.bindLocals _ _)
  have heapE : E.heap = s.heap := by rw [← hE]; rfl
  have l17 : E.local? 17 = some (.rawSlice i32T outp room) := by
    rw [← hE]; exact local?_entry inv [] [(29, .unsigned .usize ofs), (40, .signed .i32 x.toInt), (48, uv)] 17 _
      rfl (by simp)
  have l29 : E.local? 29 = some (.unsigned .usize ofs) := by
    rw [← hE]; exact local?_entry inv [(17, .rawSlice i32T outp room)] [(40, .signed .i32 x.toInt), (48, uv)] 29 _
      rfl (by simp)
  have l40 : E.local? 40 = some (.signed .i32 x.toInt) := by
    rw [← hE]; exact local?_entry inv [(17, .rawSlice i32T outp room), (29, .unsigned .usize ofs)] [(48, uv)] 40 _
      rfl (by simp)
  have l48 : E.local? 48 = some uv := by
    rw [← hE]; exact local?_entry inv [(17, .rawSlice i32T outp room), (29, .unsigned .usize ofs),
      (40, .signed .i32 x.toInt)] [] 48 _ rfl (by simp)
  simp only [src_app_main_oracle_write_one, SrcStmt.toCore, SrcExpr.toCore, SrcType.toCore, SrcOp.toCore,
    UintTy.toCore, List.map]
  -- The rest from `ofs + 1`.
  have addE : Ev (fun k => evalExpr k prog.toCore E (.binary .add (.local 29)
      (.value (.unsigned .usize (1#64).toNat)))) (.unsigned .usize (ofs + 1)) E :=
    binary_fwd (by decide) (by decide) (local_fwd l29) (value_fwd _)
      (by rw [toCore_target', show (1#64).toNat = 1 from rfl, nat_add (by omega)])
  obtain ⟨c1, done1, body1, res1, inv1, read1, next1, fr1, cells1⟩ := ih (ofs := ofs + 1) (s := E) invE
    (heapE ▸ readable) (heapE ▸ rel) rep (by omega) (heapE ▸ bound) (heapE ▸ fr)
  have call1 := call_fwd (exprs_cons_fwd (local_fwd l17) (exprs_cons_fwd addE (exprs_cons_fwd (local_fwd l48)
    exprs_nil_fwd))) fn_write rfl body1 res1
  generalize hv1 : (Value.unsigned .usize (ofs + 1 + rest.length)) = v1 at call1
  have invR := (inv1.restore E).bindLocal 100 v1
  have back {id : Nat} {y : Value} (ne : 100 ≠ id) (h : E.local? id = some y) :
      ((restoreLocals E done1).bindLocal 100 v1).local? id = some y :=
    local?_bindLocal_other ne _ (local?_prefix (st' := restoreLocals E done1) cells1 rfl h)
  generalize hR : (restoreLocals E done1).bindLocal 100 v1 = R at invR back
  have heapR : R.heap = done1.heap := by rw [← hR]; rfl
  have viewsR : R.i32ArrayViews = [] := invR.views
  -- `out[ofs] = x`
  obtain ⟨rb, hrb, baseRun⟩ := place_local_fwd (P := prog.toCore) (back (by decide) l17)
  have placeRun := place_index_fwd baseRun hrb (local_fwd (back (by decide) l29))
    (show Semantics.integerIndex (.unsigned .usize ofs) = .ok ofs from rfl) (show ofs < room by omega)
    (show Semantics.rawSliceElementAddress? prog.toCore i32T outp ofs = .ok (outp + ofs * 4) by
      simp [Semantics.rawSliceElementAddress?])
  generalize hr : ({ rb with
      value := none, raw := some (i32T, outp + ofs * 4), rawByte := Semantics.isByte i32T } :
    ResolvedPlace) = rp at placeRun
  have rraw : rp.raw = some (i32T, outp + ofs * 4) := by rw [← hr]
  have rbyte : rp.rawByte = false := by rw [← hr]; rfl
  have slot : done1.heap.Readable (outp + ofs * 4) 4 := read1.subrange (start := ofs * 4) (length := 4) (by omega)
  obtain ⟨heap', stored, bw⟩ := Memory.Heap.storeBytes_of_readable (Semantics.i32Bytes x.toInt) inv1.unique
    (fun i lt => slot i (by rw [i32Bytes_length] at lt; exact lt))
  have written : Semantics.writeResolvedPlaceNative prog.toCore R rp (.signed .i32 x.toInt) =
      .ok { R with heap := heap' } := by
    simp only [Semantics.writeResolvedPlaceNative, rraw, Semantics.writeRawNative, rbyte, Bool.false_eq_true,
      if_false, writeNative_i32, heapR, stored]
    rfl
  have synced : (if rp.viewFreeRootWrite (.signed .i32 x.toInt) then .ok { R with heap := heap' } else match rp.raw with
      | none => Semantics.syncI32ViewsToHeap { R with heap := heap' }
      | some _ => Semantics.syncI32ViewsFromHeap { R with heap := heap' }) = .ok { R with heap := heap' } := by
    simp only [Semantics.ResolvedPlace.viewFreeRootWrite, rraw, Option.isNone_some, Bool.false_and,
      Bool.false_eq_true, if_false]
    exact syncFrom_ok (st := { R with heap := heap' }) viewsR
  have assignE := expression_fwd (assign_fwd placeRun (local_fwd (back (by decide) l40)) written synced)
  have l100 : ({ R with heap := heap' } : State).local? 100 = some v1 := by
    show R.local? 100 = some v1
    rw [← hR]; exact local?_bindLocal_self (inv1.restore E) 100 v1
  refine ⟨.returned (some v1), _, letLocal_fwd call1 (by
      rw [hR]; exact sequence_next_fwd assignE (return_fwd (local_fwd l100))), ?_, ?_, ?_, ?_, ?_, ?_⟩
  · show _ = v1
    rw [← hv1]; congr 1; omega
  · exact Inv.restore _ ⟨viewsR, invR.fresh, bw.below (heapR ▸ invR.below), bw.unique⟩
  · exact bw.readable read1
  · show heap'.nextAddress ≤ _
    rw [bw.frontier]; exact heapE ▸ next1
  · show heap'.remaining = none
    rw [bw.budget]; exact fr1
  · show s.cells <+: R.cells
    rw [← hR]
    exact stepE.cells.trans (cells1.trans (Step.bindLocal _ 100 _).cells)

theorem write_live {outp room : Nat} (roomLt : room < 2 ^ 31) : ∀ ws, WriteLive outp room ws := by
  intro ws
  induction ws with
  | nil =>
    intro ofs s lv lp inv readable rel rep fits bound fr
    generalize hE : ({ s with locals := [] } : State).bindLocals [(13, .rawSlice i32T outp room),
      (25, .unsigned .usize ofs), (36, lv)] = E
    have invE : Inv E := by rw [← hE]; exact Same.start inv _
    have stepE : Step s E := by rw [← hE]; exact (Step.clear s).trans (Step.bindLocals _ _)
    have heapE : E.heap = s.heap := by rw [← hE]; rfl
    have l25 : E.local? 25 = some (.unsigned .usize ofs) := by
      rw [← hE]; exact local?_entry inv [(13, .rawSlice i32T outp room)] [(36, lv)] 25 _ rfl (by simp)
    have l36 : E.local? 36 = some lv := by
      rw [← hE]; exact local?_entry inv [(13, .rawSlice i32T outp room), (25, .unsigned .usize ofs)] [] 36 _ rfl
        (by simp)
    cases rep
    obtain ⟨kk, vs, ps, fs, rfl, hp, hk, rs⟩ := vrel_ty1 rel
    simp only [Value.enumeration.injEq, true_and] at hp
    obtain ⟨rfl, rfl⟩ := hp
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hk
    subst hk
    cases rs
    simp only [src_app_main_oracle_write, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcEff.coreArms,
      SrcExpr.toCore, SrcType.typeId, ty1, List.map]
    refine ⟨.returned (some (.unsigned .usize ofs)), _,
      return_fwd (match_fwd (local_fwd l36) (arms_hit_fwd (bs := [])
        (by simp [Semantics.matchPattern, Semantics.matchPatterns]) (local_fwd l25))), by simp [CallResult], invE.restore _, heapE ▸ readable, by rw [← heapE]; exact Nat.le_refl _,
      heapE ▸ fr, stepE.cells⟩
  | cons x rest ih =>
    intro ofs s lv lp inv readable rel rep fits bound fr
    generalize hE : ({ s with locals := [] } : State).bindLocals [(13, .rawSlice i32T outp room),
      (25, .unsigned .usize ofs), (36, lv)] = E
    have invE : Inv E := by rw [← hE]; exact Same.start inv _
    have stepE : Step s E := by rw [← hE]; exact (Step.clear s).trans (Step.bindLocals _ _)
    have heapE : E.heap = s.heap := by rw [← hE]; rfl
    have l13 : E.local? 13 = some (.rawSlice i32T outp room) := by
      rw [← hE]; exact local?_entry inv [] [(25, .unsigned .usize ofs), (36, lv)] 13 _ rfl (by simp)
    have l25 : E.local? 25 = some (.unsigned .usize ofs) := by
      rw [← hE]; exact local?_entry inv [(13, .rawSlice i32T outp room)] [(36, lv)] 25 _ rfl (by simp)
    have l36 : E.local? 36 = some lv := by
      rw [← hE]; exact local?_entry inv [(13, .rawSlice i32T outp room), (25, .unsigned .usize ofs)] [] 36 _ rfl
        (by simp)
    cases rep with
    | cons rx rrest =>
    rename_i vx vxs
    cases rx
    obtain ⟨kk, vs, ps, fs, rfl, hp, hk, rs⟩ := vrel_ty1 rel
    simp only [Value.enumeration.injEq, true_and] at hp
    obtain ⟨rfl, rfl⟩ := hp
    simp only [List.getElem?_cons_succ, List.getElem?_cons_zero, Option.some.injEq] at hk
    subst hk
    cases rs with
    | cons rxv rs2 =>
    cases rs2 with
    | cons rbox rnil =>
    cases rnil
    rename_i xv bv
    cases rxv with
    | scalar _ =>
    simp only [src_app_main_oracle_write, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcEff.coreArms,
      SrcExpr.toCore, SrcType.typeId, ty1, List.map]
    have inv2 := invE.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]
    have step2 : Step s (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]) :=
      stepE.trans (Step.bindLocals _ _)
    have heap2 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).heap = s.heap :=
      (bindLocals_same _ _).1.trans heapE
    have m13 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 13 =
        some (.rawSlice i32T outp room) := local?_bindLocals_other _ (by simp) l13
    have m25 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 25 =
        some (.unsigned .usize ofs) := local?_bindLocals_other _ (by simp) l25
    have m134 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 134 =
        some (.signed .i32 x.toInt) := local?_bindLocal_other (by simp) _ (local?_bindLocal_self invE 134 _)
    have m137 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 137 = some bv :=
      local?_bindLocal_self (invE.bindLocal 134 _) 137 bv
    -- `unbox(rest)`
    obtain ⟨w, uv, sU, hw, unboxE, relU, invU, stepU, nextU, frU, -⟩ := pure_call_fwd SelfPure.selfPure
      SelfPure.selfPrims (N := 1) (h := 0) fn_unbox (notOut 10) (exprs_cons_fwd (local_fwd m137) exprs_nil_fwd) inv2
      (.cons (heap2 ▸ rbox) .nil) (by
        have nb : 10 ∉ prims.boxed := by decide +kernel
        simp [ccall, qcall, np_unbox_of_mini_selfhost_List_i32, nb, single])
      (by rw [heap2]; simpa using bound) (by rw [heap2]; exact fr)
    obtain rfl := pcall_unbox (n := 0) hw
    obtain ⟨c1, done1, body1, res1, inv1, read1, next1, fr1, cells1⟩ := write_one_live roomLt ih (x := x) (ofs := ofs)
      invU (stepU.reads.readable (heap2 ▸ readable)) relU rrest (by simpa using fits)
      (Nat.le_trans nextU (by rw [heap2]; simpa using bound)) frU
    have call1 := call_fwd (exprs_cons_fwd (local_fwd m13) (exprs_cons_fwd (local_fwd m25) (exprs_cons_fwd
      (local_fwd m134) (exprs_cons_fwd unboxE exprs_nil_fwd)))) fn_write_one rfl body1 res1
    refine ⟨.returned (some (.unsigned .usize (ofs + (rest.length + 1)))), _,
      return_fwd (match_fwd (local_fwd l36) (arms_skip_fwd (by simp [Semantics.matchPattern])
        (arms_hit_fwd (by simp [Semantics.matchPattern, Semantics.matchPatterns]) call1))),
      by simp [CallResult], ((inv1.restore _).restore _).restore _, read1, ?_, fr1, ?_⟩
    · show done1.heap.nextAddress ≤ _
      refine Nat.le_trans next1 (Nat.le_trans nextU ?_)
      rw [heap2]; exact Nat.le_refl _
    · exact step2.cells.trans (stepU.cells.trans cells1)


/-- `oracle_put(out, result)`'s body completes when the result's words fit in
the output room. -/
theorem put_live {outp room : Nat} (roomLt : room < 2 ^ 31) {s : State} {rv rp : Value}
    {r : Option (List (BitVec 32))} (inv : Inv s) (readable : s.heap.Readable outp (room * 4))
    (rel : VRel prog.toCore boxes s.heap ty3 rv rp) (rep : (RepOption 2 (RepList 0 RepI32)) r rp)
    (fits : ∀ ws, r = some ws → ws.length ≤ room) (bound : s.heap.nextAddress ≤ 2 ^ 64)
    (fr : s.heap.remaining = none) :
    ∃ c completed v, Ev (fun k => execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(11, .rawSlice i32T outp room), (23, rv)]) (src_app_main_oracle_put 3).body.toCore) c completed ∧
      CallResult .i32 c v ∧ completed.heap.nextAddress ≤ s.heap.nextAddress := by
  generalize hE : ({ s with locals := [] } : State).bindLocals [(11, .rawSlice i32T outp room), (23, rv)] = E
  have invE : Inv E := by rw [← hE]; exact Same.start inv _
  have heapE : E.heap = s.heap := by rw [← hE]; rfl
  have l11 : E.local? 11 = some (.rawSlice i32T outp room) := by
    rw [← hE]; exact local?_entry inv [] [(23, rv)] 11 _ rfl (by simp)
  have l23 : E.local? 23 = some rv := by
    rw [← hE]; exact local?_entry inv [(11, .rawSlice i32T outp room)] [] 23 _ rfl (by simp)
  simp only [src_app_main_oracle_put, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcEff.coreArms,
    SrcExpr.toCore, SrcType.typeId, SrcType.toScalar, SrcOp.toCore, ty3, List.map]
  obtain ⟨kk, vs, ps, fs, rfl, hp, hk, rs⟩ := vrel_ty3 rel
  cases rep with
  | none =>
    simp only [Value.enumeration.injEq, true_and] at hp
    obtain ⟨rfl, rfl⟩ := hp
    simp only [List.getElem?_cons_succ, List.getElem?_cons_zero, Option.some.injEq] at hk
    subst hk
    cases rs
    have minus : Semantics.evalBinaryValue prog.toCore.target .subtract (.signed .i32 (0#32).toInt)
        (.signed .i32 (1#32).toInt) = .ok (.signed .i32 (-1)) := by
      rw [toCore_target']
      simp only [Semantics.evalBinaryValue, beq_self_eq_true, if_true, Semantics.evalSignedBinary]
      rfl
    refine ⟨.returned (some (.signed .i32 (-1))), _, _,
      return_fwd (match_fwd (local_fwd l23) (arms_skip_fwd (by simp [Semantics.matchPattern])
        (arms_hit_fwd (bs := []) (by simp [Semantics.matchPattern, Semantics.matchPatterns])
          (binary_fwd (by decide) (by decide) (value_fwd _) (value_fwd _) minus)))), rfl, ?_⟩
    show E.heap.nextAddress ≤ _
    rw [heapE]; exact Nat.le_refl _
  | some rws =>
    rename_i ws vws
    simp only [Value.enumeration.injEq, true_and] at hp
    obtain ⟨rfl, rfl⟩ := hp
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hk
    subst hk
    cases rs with
    | cons rl rnil =>
    cases rnil
    rename_i lv
    have m11 : (E.bindLocals [(153, lv)]).local? 11 = some (.rawSlice i32T outp room) :=
      local?_bindLocals_other _ (by simp) l11
    have m153 : (E.bindLocals [(153, lv)]).local? 153 = some lv := local?_bindLocal_self invE _ _
    have heap1 : (E.bindLocals [(153, lv)]).heap = s.heap := (bindLocals_same _ _).1.trans heapE
    have lenLe := fits ws rfl
    obtain ⟨c1, done1, body1, res1, -, -, next1, -, -⟩ := write_live roomLt ws (ofs := 0) (invE.bindLocals _)
      (heap1 ▸ readable) (heap1 ▸ rl) rws (by omega) (heap1 ▸ bound) (heap1 ▸ fr)
    have call1 := call_fwd (exprs_cons_fwd (local_fwd m11) (exprs_cons_fwd (value_fwd (.unsigned .usize 0))
      (exprs_cons_fwd (local_fwd m153) exprs_nil_fwd))) fn_write rfl body1 res1
    have castOk : Semantics.evalScalarCast prog.toCore.target (.signed .i32) (.unsigned .usize (0 + ws.length)) =
        .ok (.signed .i32 ws.length) := by
      simp only [toCore_target', Semantics.evalScalarCast, Nat.zero_add, Int.ofNat_eq_natCast,
        SelfDriver.wrap_i32 (show ws.length < 2 ^ 31 by omega)]
    refine ⟨.returned (some (.signed .i32 ws.length)), _, _,
      return_fwd (match_fwd (local_fwd l23) (arms_hit_fwd (bs := [(153, lv)])
        (by simp [Semantics.matchPattern, Semantics.matchPatterns]) (cast_fwd (by simpa only [UintTy.toCore, show (0#64).toNat = 0 from rfl] using call1) castOk))), rfl, ?_⟩
    show done1.heap.nextAddress ≤ _
    exact heap1 ▸ next1

/-! ## The driver -/

theorem i32Slice_fwd {P : Core.Program} {st : State} {p n : Core.Expr} {a : Nat} {c : Int} {v : Value}
    {s1 s2 s3 : State} (hp : Ev (fun k => evalExpr k P st p) (.pointer a) s1)
    (hn : Ev (fun k => evalExpr k P s1 n) (.signed .i32 c) s2) (m : Semantics.mapRawI32Slice s2 a c = .done v s3) :
    Ev (fun k => evalExpr k P st (.i32SliceFromRawParts p n)) v s3 := by
  obtain ⟨K1, h1⟩ := hp
  obtain ⟨K2, h2⟩ := hn
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega), m]

theorem map_i32 {s : State} {a n : Nat} (range : n = 0 ∨ s.heap.checkRange a (n * 4) 4 = .ok ()) :
    Semantics.mapRawI32Slice s a (n : Int) = .done (.rawSlice i32T a n) s := by
  unfold Semantics.mapRawI32Slice
  rcases range with rfl | ok
  · rfl
  · by_cases zero : n = 0
    · subst zero; rfl
    · simp only [show ¬ ((n : Int) < 0) by omega, if_false, show ¬ ((n : Int) = 0) by omega, Int.toNat_natCast, ok]

theorem listVal_rep (W : List (BitVec 32)) : (RepList 0 RepI32) W (listVal W) := by
  induction W with
  | nil => exact .nil
  | cons x xs ih => exact .cons (.mk x) ih

/-- **The driver completes.** On an input view reading `W` and an output view
of `room` words, with an unbounded allocator: when the cost semantics gives
`w`'s run the cost `h` with some fuel, the heap has `h` bytes below `2 ^ 64`,
and the result's words fit in the room, Core completes `w`'s call with the
heap grown by at most `h`. -/
theorem driver_live {N h : Nat} {st : State} {inp outp room : Nat} {W : List (BitVec 32)}
    (inv : Inv st) (wordsLt : W.length < 2 ^ 31) (roomLt : room < 2 ^ 31)
    (input : Reads st inp W) (output : st.heap.Readable outp (room * 4))
    (inRange : W.length = 0 ∨ st.heap.checkRange inp (W.length * 4) 4 = .ok ())
    (outRange : room = 0 ∨ st.heap.checkRange outp (room * 4) 4 = .ok ())
    (fr : st.heap.remaining = none) (cost : selfCost N W = some h) (budget : st.heap.nextAddress + h ≤ 2 ^ 64)
    (fits : ∀ ws, compileWords (frontEndWords grammar W) = some ws → ws.length ≤ room) :
    ∃ v st', Ev (fun k => evalExpr k prog.toCore st (.call 0 [.value (.pointer inp), .value (.signed .i32 W.length),
      .value (.pointer outp), .value (.signed .i32 room)])) v st' ∧ st'.heap.nextAddress ≤ st.heap.nextAddress + h := by
  simp only [selfCost, Option.bind_eq_some_iff, Option.some.injEq] at cost
  obtain ⟨⟨g, hg⟩, hG, ⟨fe, hf⟩, hF, ⟨cw, hc⟩, hC, rfl⟩ := cost
  generalize hR : W.length * consCost = R at budget ⊢
  generalize hE : ({ st with locals := [] } : State).bindLocals [(2, .pointer inp), (14, .signed .i32 W.length),
    (26, .pointer outp), (39, .signed .i32 room)] = E
  have invE : Inv E := by rw [← hE]; exact Same.start inv _
  have stepE : Step st E := by rw [← hE]; exact (Step.clear st).trans (Step.bindLocals _ _)
  have heapE : E.heap = st.heap := by rw [← hE]; rfl
  have l2 : E.local? 2 = some (.pointer inp) := by
    rw [← hE]; exact local?_entry inv [] [(14, .signed .i32 W.length), (26, .pointer outp), (39, .signed .i32 room)]
      2 _ rfl (by simp)
  have l14 : E.local? 14 = some (.signed .i32 W.length) := by
    rw [← hE]; exact local?_entry inv [(2, .pointer inp)] [(26, .pointer outp), (39, .signed .i32 room)] 14 _ rfl
      (by simp)
  have l26 : E.local? 26 = some (.pointer outp) := by
    rw [← hE]; exact local?_entry inv [(2, .pointer inp), (14, .signed .i32 W.length)] [(39, .signed .i32 room)] 26 _
      rfl (by simp)
  have l39 : E.local? 39 = some (.signed .i32 room) := by
    rw [← hE]; exact local?_entry inv [(2, .pointer inp), (14, .signed .i32 W.length), (26, .pointer outp)] [] 39 _
      rfl (by simp)
  -- The two views.
  have slice1 : Ev (fun k => evalExpr k prog.toCore E (.i32SliceFromRawParts (.local 2) (.local 14)))
      (.rawSlice i32T inp W.length) E :=
    i32Slice_fwd (local_fwd l2) (local_fwd l14) (map_i32 (by rw [heapE]; exact inRange))
  generalize hE1 : E.bindLocal 67 (.rawSlice i32T inp W.length) = E1
  have invE1 : Inv E1 := by rw [← hE1]; exact invE.bindLocal _ _
  have slice2 : Ev (fun k => evalExpr k prog.toCore E1 (.i32SliceFromRawParts (.local 26) (.local 39)))
      (.rawSlice i32T outp room) E1 :=
    i32Slice_fwd (local_fwd (by rw [← hE1]; exact local?_bindLocal_other (by decide) _ l26))
      (local_fwd (by rw [← hE1]; exact local?_bindLocal_other (by decide) _ l39))
      (map_i32 (by rw [← hE1]; exact heapE ▸ outRange))
  generalize hE2 : E1.bindLocal 125 (.rawSlice i32T outp room) = E2
  have invE2 : Inv E2 := by rw [← hE2]; exact invE1.bindLocal _ _
  have stepE2 : Step st E2 := by
    rw [← hE2, ← hE1]; exact stepE.trans ((Step.bindLocal _ _ _).trans (Step.bindLocal _ _ _))
  have heapE2 : E2.heap = st.heap := by rw [← hE2, ← hE1]; exact heapE
  have k67 : E2.local? 67 = some (.rawSlice i32T inp W.length) := by
    rw [← hE2, ← hE1]; exact local?_bindLocal_other (by decide) _ (local?_bindLocal_self invE _ _)
  have k14 : E2.local? 14 = some (.signed .i32 W.length) := by
    rw [← hE2, ← hE1]; exact local?_bindLocal_other (by decide) _ (local?_bindLocal_other (by decide) _ l14)
  have k125 : E2.local? 125 = some (.rawSlice i32T outp room) := by
    rw [← hE2]; exact local?_bindLocal_self invE1 _ _
  -- `empty()`
  obtain ⟨we, ev, sE, hwe, emptyE, relE, invSE, stepSE, nextSE, frSE, locSE⟩ := pure_call_fwd SelfPure.selfPure
    SelfPure.selfPrims (N := 1) (h := 0) fn_empty_of_i32 (notOut 5) (exprs_nil_fwd (st := E2)) invE2 .nil
    (by simp only [ccall, qcall_empty 0, Option.map_some]) (by rw [heapE2]; aomega) (by rw [heapE2]; exact fr)
  have hwe' : pcall prog prims 1 5 [] = some nilVal := by rw [pcall_eq_qcall _ _ (boxCost prog), qcall_empty 0]; rfl
  rw [hwe', Option.some.injEq] at hwe
  subst hwe
  -- `oracle_read(data, 0, words as usize, empty())`
  have castE : Ev (fun k => evalExpr k prog.toCore E2 (.cast (.unsigned .usize) (.local 14)))
      (.unsigned .usize W.length) E2 :=
    cast_fwd (local_fwd k14) (by rw [toCore_target', cast_usize_int (by aomega) (by aomega)]; simp)
  have argsR : Ev (fun k => evalExprs k prog.toCore E2 [.local 67, .value (.unsigned .usize (0#64).toNat),
      .cast (.unsigned .usize) (.local 14), .call 5 []]) [.rawSlice i32T inp W.length, .unsigned .usize 0,
      .unsigned .usize W.length, ev] sE :=
    exprs_cons_fwd (local_fwd k67) (exprs_cons_fwd (value_fwd _) (exprs_cons_fwd castE
      (exprs_cons_fwd emptyE exprs_nil_fwd)))
  have nextSE' : sE.heap.nextAddress ≤ st.heap.nextAddress := by
    rw [← heapE2]; simpa using nextSE
  obtain ⟨cR, doneR, lv, bodyR, resR, relR, invR, stepR, nextR, frR⟩ := read_live (inp := inp) (W := W) (by aomega)
    (W.length - 0) (lo := 0) (hi := W.length) (s := sE) (tv := ev) (tp := nilVal) rfl (Nat.zero_le _) (Nat.le_refl _)
    invSE (input.step (stepE2.trans stepSE)) relE
    (by rw [Nat.sub_zero, hR]; aomega) frSE
  simp only [List.drop_zero, Nat.sub_zero, List.take_length] at relR nextR
  rw [hR] at nextR
  have readE := call_fwd argsR fn_read rfl bodyR resR
  generalize hE3 : (restoreLocals sE doneR).bindLocal 182 lv = E3
  have invE3 : Inv E3 := by rw [← hE3]; exact (invR.restore _).bindLocal _ _
  have stepE3 : Step st E3 := by
    rw [← hE3]; exact ((stepE2.trans (stepSE.trans stepR)).restore _).trans (Step.bindLocal _ _ _)
  have heapE3 : E3.heap = doneR.heap := by rw [← hE3]; rfl
  have k182 : E3.local? 182 = some lv := by rw [← hE3]; exact local?_bindLocal_self (invR.restore _) _ _
  have k125' : E3.local? 125 = some (.rawSlice i32T outp room) := by
    rw [← hE3]
    refine local?_bindLocal_other (by decide) _ (local?_prefix (st' := restoreLocals sE doneR)
      (stepSE.cells.trans stepR.cells) (by show sE.locals = E2.locals; exact locSE) k125)
  have relL : VRel prog.toCore boxes E3.heap ty1 lv (listVal W) := heapE3 ▸ relR
  -- `grammar()`
  have nG : E3.heap.nextAddress ≤ st.heap.nextAddress + R := by rw [heapE3]; aomega
  obtain ⟨wg, gv, sG, hwg, gramE, relG, invG, stepG, nextG, frG, locG⟩ := pure_call_fwd SelfPure.selfPure
    SelfPure.selfPrims (N := N) (h := hg) fn_grammar (notOut 8) (exprs_nil_fwd (st := E3)) invE3 .nil
    (by simp only [ccall, hG, Option.map_some]) (by aomega) (by rw [heapE3]; exact frR)
  have hwg' : pcall prog prims N 8 [] = some g := by rw [pcall_eq_qcall _ _ (boxCost prog), hG]; rfl
  rw [hwg', Option.some.injEq] at hwg
  subst hwg
  -- `front_end_words(grammar(), read)`
  have k182G : sG.local? 182 = some lv := local?_prefix stepG.cells locG k182
  obtain ⟨wf, fv, sF, hwf, feE, relF, invF, stepF, nextF, frF, locF⟩ := pure_call_fwd SelfPure.selfPure
    SelfPure.selfPrims (N := N) (h := hf) fn_front_end_words (notOut 7)
    (exprs_cons_fwd gramE (exprs_cons_fwd (local_fwd k182G) exprs_nil_fwd)) invG
    (.cons relG (.cons (VRel.mono stepG.reads stepG.ranges relL) .nil))
    (by simp only [ccall, hF, Option.map_some]) (by aomega) frG
  have hwf' : pcall prog prims N 7 [g, listVal W] = some fe := by rw [pcall_eq_qcall _ _ (boxCost prog), hF]; rfl
  rw [hwf', Option.some.injEq] at hwf
  subst hwf
  -- `compile_words(..)`
  obtain ⟨wc, cv, sC, hwc, cwE, relC, invC, stepC, nextC, frC, locC⟩ := pure_call_fwd SelfPure.selfPure
    SelfPure.selfPrims (N := N) (h := hc) fn_compile_words (notOut 6) (exprs_cons_fwd feE exprs_nil_fwd) invF
    (.cons relF .nil) (by simp only [ccall, hC, Option.map_some]) (by aomega) frF
  have repC := cert_compile_words hwc (cert_front_end_words hwf' (cert_grammar hwg') (listVal_rep W))
  -- `oracle_put(out, ..)`
  have stepAll : Step st sC := stepE3.trans (stepG.trans (stepF.trans stepC))
  obtain ⟨cP, doneP, vP, bodyP, resP, nextP⟩ := put_live roomLt invC (stepAll.reads.readable output) relC repC fits
    (by aomega) frC
  have k125C : E3.local? 125 = some (.rawSlice i32T outp room) := k125'
  have putE := call_fwd (exprs_cons_fwd (local_fwd k125C) (exprs_cons_fwd cwE exprs_nil_fwd)) fn_put rfl bodyP resP
  obtain ⟨sW, bodyW, boundW⟩ : ∃ sW, Ev (fun k => execStmt k prog.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings (src_app_main_w 1 2 5 6 7 8).params [.pointer inp, .signed .i32 W.length, .pointer outp,
        .signed .i32 room])) (src_app_main_w 1 2 5 6 7 8).body.toCore) (.returned (some vP)) sW ∧
      sW.heap.nextAddress ≤ st.heap.nextAddress + (R + hg + hf + hc) := by
    refine ⟨?s, ?ev, ?b⟩
    case ev =>
      rw [w_params, hE]
      simp only [src_app_main_w, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcExpr.toCore, SrcType.toCore,
        SrcType.sliceFrom, SrcType.toScalar, UintTy.toCore]
      have e3 := return_fwd (P := prog.toCore) putE
      rw [← hE3] at e3
      have e2 := letLocal_fwd (ty := ty1.toCore) readE e3
      rw [← hE2] at e2
      have e1 := letLocal_fwd (ty := (Core.Ty.scalar (.signed .i32)).slice) slice2 e2
      rw [← hE1] at e1
      exact letLocal_fwd (ty := (Core.Ty.scalar (.signed .i32)).slice) slice1 e1
    case b =>
      show doneP.heap.nextAddress ≤ _
      aomega
  exact ⟨vP, _, call_fwd (exprs_cons_fwd (value_fwd _) (exprs_cons_fwd (value_fwd _) (exprs_cons_fwd (value_fwd _)
    (exprs_cons_fwd (value_fwd _) exprs_nil_fwd)))) fn_w rfl bodyW rfl, boundW⟩

end Lanius.Faithful.SelfLive
