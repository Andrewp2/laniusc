import Lanius.Faithful.SelfDriver
import Lanius.Faithful.Safe.Func

/-! # The self-host driver traps only definedly (roadmap V7b)

Beside `driver_faithful`: no Core run of `w` on the views `selfStart` lays
out traps undefinedly within the heap bound. `oracle_read` reads the input
view below its length, `oracle_write` and `oracle_write_one` write the output
view where it is readable (an index past `room` traps `arrayBounds`), and the
calls into the pure subset trap definedly by `func_safe`. -/

namespace Lanius.Faithful.SelfDriver

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals readRawSliceIndex)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfCert
open Lanius.Faithful.SelfFaithful (boxes)

theorem funcs_safe : ∀ m, FuncSafe prog prims SelfPure.outside m :=
  func_safe SelfPure.selfPure SelfPure.selfPrims

/-! ## Reading the input -/

/-- `oracle_read(data, lo, hi, tail)`'s body, on a view reading `W`. -/
theorem read_safe {inp : Nat} {W : List (BitVec 32)} (len : W.length < 2 ^ 64) : ∀ (m : Nat) {lo hi : Nat}
    {s : State} {tv tp : Value} {T : List (BitVec 32)},
    hi - lo = m → lo ≤ hi → hi ≤ W.length →
    Inv s → Reads s inp W →
    VRel prog.toCore boxes s.heap ty1 tv tp → (RepList 0 RepI32) T tp →
    SafeS prog.toCore (({ s with locals := [] } : State).bindLocals
      [(12, .rawSlice i32T inp W.length), (25, .unsigned .usize lo), (36, .unsigned .usize hi), (47, tv)])
      (src_app_main_oracle_read 1 9).body.toCore := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
  intro lo hi s tv tp T hm le hle inv reads rel rep
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
  have diff := known_binary (P := prog.toCore) (op := .subtract) (by decide) (by decide) (known_local l36)
    (known_local l25) (by rw [toCore_target', nat_sub le (by omega)])
  have cond := known_binary (P := prog.toCore) (op := .greater) (by decide) (by decide) diff
    (known_value (.unsigned .usize (1#64).toNat)) (by rw [toCore_target', show (1#64).toNat = 1 from rfl, nat_greater])
  by_cases big : hi - lo > 1
  · -- Split at the middle: the right half in front of the tail, then the left half.
    rw [show decide (hi - lo > 1) = true from decide_eq_true big] at cond
    have mid := known_binary (P := prog.toCore) (op := .add) (by decide) (by decide) (known_local l25)
      (known_binary (op := .divide) (by decide) (by decide) diff (known_value (.unsigned .usize (2#64).toNat))
        (by rw [toCore_target', show (2#64).toNat = 2 from rfl, nat_half _ (by omega)]))
      (by rw [toCore_target', nat_add (by omega)])
    have midLo : lo ≤ lo + (hi - lo) / 2 := Nat.le_add_right _ _
    have midHi : lo + (hi - lo) / 2 ≤ hi := by omega
    refine safeS_seq (safeS_if_known cond ?_) fun {k s'} h => ?_
    · simp only [if_true]
      refine safeS_let_known mid ?_
      have inv1 := invE.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))
      have m12 := local?_bindLocal_other (id := 146) (by decide) (.unsigned .usize (lo + (hi - lo) / 2)) l12
      have m146 := local?_bindLocal_self invE 146 (.unsigned .usize (lo + (hi - lo) / 2))
      have m36 := local?_bindLocal_other (id := 146) (by decide) (.unsigned .usize (lo + (hi - lo) / 2)) l36
      have m47 := local?_bindLocal_other (id := 146) (by decide) (.unsigned .usize (lo + (hi - lo) / 2)) l47
      have args1 := knowns_cons (known_local (P := prog.toCore) m12) (knowns_cons (known_local m146)
        (knowns_cons (known_local m36) (knowns_cons (known_local m47) knowns_nil)))
      refine safeS_let (safeE_call fn_read args1.safeEs fun {k values s1} h1 => ?_) fun {k rv s5} recRun => ?_
      · obtain ⟨rfl, hs1⟩ := args1.done h1
        subst s1
        refine ⟨rfl, ?_⟩
        simp only [read_params]
        exact ih (hi - (lo + (hi - lo) / 2)) (by omega) rfl midHi hle inv1
          (reads.step (stepE.trans (Step.bindLocal _ _ _))) (heapE ▸ rel) rep
      -- The second call runs past the first, so the first's cursor is in bounds.
      obtain ⟨j10, done1, c10, recBody, recResult, rfl⟩ := call_locals [(12, .rawSlice i32T inp W.length),
          (146, .unsigned .usize (lo + (hi - lo) / 2)), (36, .unsigned .usize hi), (47, tv)] fn_read (by
        intro b mem
        simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
        rcases mem with rfl | rfl | rfl | rfl
        · exact m12
        · exact m146
        · exact m36
        · exact m47) recRun
      simp only [List.map_cons, List.map_nil, read_params] at recBody
      obtain ⟨views1, -⟩ := execStmt_grows recBody (Same.start inv1 _).views
      refine SafeS.of_bound (sp := prog) (s := SrcStmt.returnEval (SrcEff.eCall 1
        [SrcEff.ePure (SrcExpr.local 12), SrcEff.ePure (SrcExpr.local 25), SrcEff.ePure (SrcExpr.local 146),
          SrcEff.ePure (SrcExpr.local 191)])) views1 fun bound => ?_
      obtain ⟨p1, rel1, rep1, inv1', step1⟩ := read_body (inp := inp) (W := W) len (hi - (lo + (hi - lo) / 2))
        (lo := lo + (hi - lo) / 2) (hi := hi) rfl midHi hle inv1 (reads.step (stepE.trans (Step.bindLocal _ _ _)))
        (show done1.heap.nextAddress ≤ 2 ^ 64 from bound) (heapE ▸ rel) rep recBody recResult
      have back {id : Nat} {x : Value} (ne : 191 ≠ id)
          (h : (E.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))).local? id = some x) :
          ((restoreLocals (E.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))) done1).bindLocal 191 rv).local?
            id = some x :=
        local?_bindLocal_other ne _ (local?_prefix
          (st' := restoreLocals (E.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))) done1) step1.cells rfl h)
      have args2 := knowns_cons (known_local (P := prog.toCore) (back (by decide) m12))
        (knowns_cons (known_local (back (by decide) (local?_bindLocal_other (by decide) _ l25)))
          (knowns_cons (known_local (back (by decide) m146))
            (knowns_cons (known_local (local?_bindLocal_self (inv1'.restore _) 191 rv)) knowns_nil)))
      refine safeS_return (safeE_call fn_read args2.safeEs fun {k values s1} h2 => ?_)
      obtain ⟨rfl, hs1⟩ := args2.done h2
      subst s1
      refine ⟨rfl, ?_⟩
      simp only [read_params]
      exact ih ((lo + (hi - lo) / 2) - lo) (by omega) (lo := lo) (hi := lo + (hi - lo) / 2)
        (T := (W.drop (lo + (hi - lo) / 2)).take (hi - (lo + (hi - lo) / 2)) ++ T) rfl midLo (by omega)
        ((inv1'.restore (E.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2)))).bindLocal 191 rv)
        ((reads.step (stepE.trans (Step.bindLocal _ _ _))).step
          (step1.trans (((Step.refl _).restore _).trans (Step.bindLocal _ _ _)))) rel1 rep1
    · obtain ⟨j, -, h⟩ := if_known_done cond h
      simp only [if_true] at h
      obtain ⟨_, v1, s2, s3, -, -, h, -⟩ := letLocal_inv h
      obtain ⟨_, v2, s4, s6, -, -, h, -⟩ := letLocal_inv h
      exact (return_not_next h).elim
  · rw [show decide (hi - lo > 1) = false from decide_eq_false big] at cond
    refine safeS_seq (safeS_if_known cond safeS_skip) fun {k s'} h => ?_
    obtain ⟨j, -, h⟩ := if_known_done cond h
    obtain ⟨-, hs⟩ := skip_inv h
    subst s'
    have cond2 := known_binary (P := prog.toCore) (op := .greater) (by decide) (by decide) (known_local l36)
      (known_local l25) (by rw [toCore_target', nat_greater])
    by_cases one : hi > lo
    · -- One word: `cons(data[lo], tail)`.
      rw [show decide (hi > lo) = true from decide_eq_true one] at cond2
      refine safeS_seq (safeS_if_known cond2 ?_) fun {k s'} h => ?_
      · simp only [if_true]
        have lt : lo < W.length := by omega
        have idx := known_index_raw (known_local l12) (known_local l25) (pos := lo)
          (v := .signed .i32 (W[lo]).toInt) (by simp [Semantics.integerIndex]) (Reads.step reads stepE lo lt)
        have args := knowns_cons idx (knowns_cons (known_local l47) knowns_nil)
        refine safeS_return (safeE_call_pure funcs_safe fn_cons_of_i32 (by decide +kernel) args.safeEs
          fun {k values s1} h1 => ?_)
        obtain ⟨rfl, hs1⟩ := args.done h1
        subst s1
        exact ⟨invE, _, .cons (.scalar (i32_scalar (W[lo]))) (.cons (heapE ▸ rel) .nil)⟩
      · obtain ⟨j, -, h⟩ := if_known_done cond2 h
        simp only [if_true] at h
        exact (return_not_next h).elim
    · -- No words: the tail.
      rw [show decide (hi > lo) = false from decide_eq_false one] at cond2
      refine safeS_seq (safeS_if_known cond2 safeS_skip) fun {k s'} h => ?_
      obtain ⟨j, -, h⟩ := if_known_done cond2 h
      obtain ⟨-, hs⟩ := skip_inv h
      subst s'
      exact safeS_return (known_local l47).safeE

/-! ## Writing the output -/

/-- `oracle_write(out, ofs, ws)`'s body traps definedly, for the list `ws`. -/
def WriteSafe (outp room : Nat) (ws : List (BitVec 32)) : Prop :=
  ∀ {ofs : Nat} {s : State} {lv lp : Value}, Inv s → s.heap.Readable outp (room * 4) →
    VRel prog.toCore boxes s.heap ty1 lv lp → (RepList 0 RepI32) ws lp →
    SafeS prog.toCore (({ s with locals := [] } : State).bindLocals
      [(13, .rawSlice i32T outp room), (25, .unsigned .usize ofs), (36, lv)]) (src_app_main_oracle_write 4 10).body.toCore

/-- `oracle_write_one(out, ofs, x, rest)`'s body: the recursive call traps
definedly, and the store `out[ofs] = x` either traps `arrayBounds` or lands in
the readable output. -/
theorem write_one_safe {outp room : Nat} (roomLt : room < 2 ^ 31) {x : BitVec 32} {rest : List (BitVec 32)}
    (ih : WriteSafe outp room rest) {ofs : Nat} {s : State} {uv up : Value}
    (inv : Inv s) (readable : s.heap.Readable outp (room * 4))
    (rel : VRel prog.toCore boxes s.heap ty1 uv up) (rep : (RepList 0 RepI32) rest up) :
    SafeS prog.toCore (({ s with locals := [] } : State).bindLocals
      [(17, .rawSlice i32T outp room), (29, .unsigned .usize ofs), (40, .signed .i32 x.toInt), (48, uv)])
      (src_app_main_oracle_write_one 3).body.toCore := by
  generalize hE : ({ s with locals := [] } : State).bindLocals [(17, .rawSlice i32T outp room),
    (29, .unsigned .usize ofs), (40, .signed .i32 x.toInt), (48, uv)] = E
  have invE : Inv E := by rw [← hE]; exact Same.start inv _
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
  have next := known_binary (P := prog.toCore) (op := .add) (by decide) (by decide) (known_local l29)
    (known_value (.unsigned .usize (1#64).toNat)) (v := .unsigned .usize ((ofs + 1) % 2 ^ 64)) rfl
  have args := knowns_cons (known_local (P := prog.toCore) l17) (knowns_cons next
    (knowns_cons (known_local l48) knowns_nil))
  refine safeS_let (safeE_call fn_write args.safeEs fun {k values s1} h1 => ?_) fun {k rv s5} recRun => ?_
  · obtain ⟨rfl, hs1⟩ := args.done h1
    subst s1
    refine ⟨rfl, ?_⟩
    simp only [write_params]
    exact ih invE (heapE ▸ readable) (heapE ▸ rel) rep
  obtain ⟨j2, f3, values, afterArgs, done3, c3, -, argsRun, found3, -, body3, result3, rfl⟩ := call_inv' recRun
  rw [fn_write, Option.some.injEq] at found3
  subst found3
  obtain ⟨rfl, hA⟩ := args.done argsRun
  subst afterArgs
  simp only [write_params] at body3
  obtain ⟨views3, -⟩ := execStmt_grows body3 (Same.start invE _).views
  refine SafeS.of_bound (sp := prog) (s := SrcStmt.then (SrcStmt.setIndex 17 (SrcExpr.local 29)
    (SrcExpr.local 40)) (SrcStmt.return (SrcExpr.local 100))) views3 fun bound => ?_
  obtain ⟨-, hlen, -, cells3, inv3, readable3⟩ := write_body roomLt rest invE
    (show done3.heap.nextAddress ≤ 2 ^ 64 from bound) (heapE ▸ readable) (heapE ▸ rel) rep body3 result3
  have back {id : Nat} {y : Value} (ne : 100 ≠ id) (h : E.local? id = some y) :
      ((restoreLocals E done3).bindLocal 100 rv).local? id = some y :=
    local?_bindLocal_other ne _ (local?_prefix (st' := restoreLocals E done3) cells3 rfl h)
  have k17 := back (by decide) l17
  have k29 := back (by decide) l29
  have k40 := back (by decide) l40
  have viewsQ : ((restoreLocals E done3).bindLocal 100 rv).i32ArrayViews = [] := inv3.views
  refine safeS_seq (safeS_expression fun k r s' h bound' => ?_) fun {k s'} h => ?_
  · obtain ⟨rfl, ⟨-, rfl⟩ | ⟨lt, write⟩⟩ := set_raw_trap (P := prog.toCore) (pos := ofs) (base := outp + ofs * 4)
      viewsQ k17 (known_local k29) k40 (by simp [Semantics.integerIndex])
      (fun _ => by simp [Semantics.rawSliceElementAddress?]) h
    · rfl
    rw [writeNative_i32] at write
    have room : done3.heap.Readable (outp + ofs * 4) (Semantics.i32Bytes x.toInt).length := by
      rw [i32Bytes_length]; exact readable3.subrange (start := ofs * 4) (length := 4) (by omega)
    obtain ⟨after, ok, -⟩ := Memory.Heap.storeBytes_of_readable (Semantics.i32Bytes x.toInt) inv3.unique
      (fun i lt => room i lt)
    rw [show ((restoreLocals E done3).bindLocal 100 rv).heap = done3.heap from rfl, ok] at write
    cases write
  · obtain ⟨j7, u, -, arun, -⟩ := expression_inv h
    obtain ⟨H, rfl⟩ := set_raw_done (P := prog.toCore) viewsQ k17 (known_local k29) k40 arun
    exact safeS_return (known_local ((local?_heap _ H _).trans
      (local?_bindLocal_self (inv3.restore E) 100 rv))).safeE

/-- `oracle_write(out, ofs, ws)`'s body traps definedly. -/
theorem write_safe {outp room : Nat} (roomLt : room < 2 ^ 31) : ∀ ws, WriteSafe outp room ws := by
  intro ws
  induction ws with
  | nil =>
    intro ofs s lv lp inv readable rel rep
    generalize hE : ({ s with locals := [] } : State).bindLocals [(13, .rawSlice i32T outp room),
      (25, .unsigned .usize ofs), (36, lv)] = E
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
    exact safeS_return (safeE_match (known_local l36) (safeArms_hit (bs := [])
      (by simp [Semantics.matchPattern, Semantics.matchPatterns]) (known_local l25).safeE))
  | cons x rest ih =>
    intro ofs s lv lp inv readable rel rep
    generalize hE : ({ s with locals := [] } : State).bindLocals [(13, .rawSlice i32T outp room),
      (25, .unsigned .usize ofs), (36, lv)] = E
    have invE : Inv E := by rw [← hE]; exact Same.start inv _
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
    refine safeS_return (safeE_match (known_local l36) (safeArms_miss
      (by simp [Semantics.matchPattern]) (safeArms_hit (bs := [(134, Value.signed .i32 x.toInt), (137, bv)])
        (by simp [Semantics.matchPattern, Semantics.matchPatterns]) ?_)))
    have inv2 := invE.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]
    have m13 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 13 =
        some (.rawSlice i32T outp room) := local?_bindLocals_other _ (by simp) l13
    have m25 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 25 =
        some (.unsigned .usize ofs) := local?_bindLocals_other _ (by simp) l25
    have m134 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 134 =
        some (.signed .i32 x.toInt) := local?_bindLocal_other (by simp) _ (local?_bindLocal_self invE 134 _)
    have m137 : (E.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 137 = some bv :=
      local?_bindLocal_self (invE.bindLocal 134 _) 137 bv
    have kU := knowns_cons (known_local (P := prog.toCore) m137) knowns_nil
    have unboxSafe := safeE_call_pure funcs_safe fn_unbox (by decide +kernel) kU.safeEs
      fun {k values s1} h1 => by
        obtain ⟨rfl, hs1⟩ := kU.done h1
        subst s1
        exact ⟨inv2, _, .cons (heapE ▸ rbox) .nil⟩
    refine safeE_call fn_write_one (safeEs_cons (known_local m13).safeE fun {k v1 s1} h1 => ?_)
      fun {k values s1} h1 => ?_
    · obtain ⟨rfl, hs1⟩ := (known_local m13).done h1
      subst s1
      refine safeEs_cons (known_local m25).safeE fun {k v2 s2} h2 => ?_
      obtain ⟨rfl, hs2⟩ := (known_local m25).done h2
      subst s2
      refine safeEs_cons (known_local m134).safeE fun {k v3 s3} h3 => ?_
      obtain ⟨rfl, hs3⟩ := (known_local m134).done h3
      subst s3
      exact safeEs_cons unboxSafe fun _ => safeEs_nil
    obtain ⟨_, a1, t1, more1, -, r1, n1, rfl⟩ := exprs_cons_inv h1
    obtain ⟨rfl, rfl⟩ := local_eval m13 r1
    obtain ⟨_, a2, t2, more2, -, r2, n2, rfl⟩ := exprs_cons_inv n1
    obtain ⟨rfl, rfl⟩ := local_eval m25 r2
    obtain ⟨_, a3, t3, more3, -, r3, n3, rfl⟩ := exprs_cons_inv n2
    obtain ⟨rfl, rfl⟩ := local_eval m134 r3
    obtain ⟨_, uv, sU, more4, -, r4, n4, rfl⟩ := exprs_cons_inv n3
    obtain ⟨rfl, rfl⟩ := exprs_nil_inv n4
    obtain ⟨jU, doneU, cU, bodyU, resultU, rfl⟩ := call_locals [(137, bv)] fn_unbox (by simpa using m137) r4
    obtain ⟨viewsU, -⟩ := execStmt_grows bodyU (Same.start inv2 _).views
    refine ⟨rfl, ?_⟩
    simp only [write_one_params]
    refine SafeS.of_bound (sp := prog) (s := (src_app_main_oracle_write_one 3).body) viewsU fun bound => ?_
    obtain ⟨w, hw, rw, invU, stepU⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims jU fn_unbox
      (by decide +kernel) rfl inv2 (show doneU.heap.nextAddress ≤ 2 ^ 64 from bound)
      (.cons (heapE ▸ rbox) .nil) bodyU resultU
    obtain rfl := pcall_unbox hw
    exact write_one_safe roomLt ih (invU.restore _) (stepU.reads.readable (heapE ▸ readable)) rw rrest

/-! ## The driver -/

theorem i32Slice_trap_inv {P : Core.Program} {st : State} {p n : Core.Expr} {k : Nat} {r : Lanius.Trap} {st' : State}
    (h : evalExpr k P st (.i32SliceFromRawParts p n) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st p = .trapped r st' ∨
      (∃ w, evalExpr j P st p = .done w st' ∧ (∀ a, w ≠ .pointer a) ∧ r = .typeMismatch) ∨
      ∃ a s1, evalExpr j P st p = .done (.pointer a) s1 ∧ (evalExpr j P s1 n = .trapped r st' ∨
        (∃ w, evalExpr j P s1 n = .done w st' ∧ (∀ c, w ≠ .signed .i32 c) ∧ r = .typeMismatch) ∨
        ∃ c s2, evalExpr j P s1 n = .done (.signed .i32 c) s2 ∧
          Semantics.mapRawI32Slice s2 a c = .trapped r st')) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i a s1 runP
      split at h
      · rename_i c s2 runN
        exact ⟨j, rfl, .inr (.inr ⟨a, s1, runP, .inr (.inr ⟨c, s2, runN, h⟩)⟩)⟩
      · rename_i w s2 notI runN
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr (.inr ⟨a, s1, runP, .inr (.inl ⟨w, runN, fun c e => notI c (by rw [e]), rfl⟩)⟩)⟩
      · rename_i reason s2 runN
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr (.inr ⟨a, s1, runP, .inl runN⟩)⟩
      all_goals simp at h
    · rename_i w s1 notP runP
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inr (.inl ⟨w, runP, fun a e => notP a (by rw [e]), rfl⟩)⟩
    · rename_i reason s1 runP
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl runP⟩
    all_goals simp at h

/-- An i32 view of `c ≥ 0` words at `a`, where the heap holds them when there are any. -/
theorem known_i32Slice {P : Core.Program} {st : State} {p n : Core.Expr} {a : Nat} {c : Int}
    (kp : Known P st p (.pointer a)) (kn : Known P st n (.signed .i32 c)) (nonneg : 0 ≤ c)
    (range : c = 0 ∨ st.heap.checkRange a (c.toNat * 4) 4 = .ok ()) :
    Known P st (.i32SliceFromRawParts p n) (.rawSlice (.scalar (.signed .i32)) a c.toNat) := by
  constructor
  · intro k r s h
    obtain ⟨j, -, hp' | ⟨w, hw, notP, -⟩ | ⟨a', s1, hp, hn' | ⟨w, hw, notI, -⟩ | ⟨c', s2, hn, bad⟩⟩⟩ :=
      i32Slice_trap_inv h
    · exact kp.safe hp'
    · obtain ⟨rfl, rfl⟩ := kp.done hw; exact notP a rfl
    · obtain ⟨-, rfl⟩ := kp.done hp; exact kn.safe hn'
    · obtain ⟨-, rfl⟩ := kp.done hp
      obtain ⟨rfl, rfl⟩ := kn.done hw; exact notI c rfl
    · obtain ⟨ha, rfl⟩ := kp.done hp
      obtain ⟨hc, rfl⟩ := kn.done hn
      simp only [Value.pointer.injEq, Value.signed.injEq, true_and] at ha hc
      subst ha hc
      unfold Semantics.mapRawI32Slice at bad
      rcases range with rfl | ok
      · simp at bad
      · simp only [Int.not_lt.mpr nonneg, if_false, ok] at bad
        split at bad <;> simp at bad
  · intro k u s h
    obtain ⟨j, a', s1, len, -, hp, hn, -, rfl⟩ := i32Slice_inv h
    obtain ⟨ha, rfl⟩ := kp.done hp
    obtain ⟨hc, rfl⟩ := kn.done hn
    simp only [Value.pointer.injEq, Value.signed.injEq, true_and] at ha hc
    subst ha hc
    exact ⟨rfl, rfl⟩

/-- A pure expression the checker types, from a state whose locals mean the
types' values: its runs trap definedly (`eff_safe`). -/
theorem safeE_of_eff {tenv : TEnv} {env : Env} {st : State} {e : SrcEff} {t : SrcType}
    (ht : effTy prog SelfPure.outside boxes tenv e = some t) (inv : Inv st)
    (rel : EnvRel prog.toCore boxes st.heap tenv env st) : SafeE prog.toCore st e.toCore :=
  fun k _ _ h bound =>
    (eff_safe (func_sim SelfPure.selfPure SelfPure.selfPrims) k (fun j _ => funcs_safe j)).1 h ht inv rel bound

/-- `oracle_put(out, result)`'s body traps definedly. -/
theorem put_safe {outp room : Nat} (roomLt : room < 2 ^ 31) {s : State} {rv rp : Value}
    {r : Option (List (BitVec 32))} (inv : Inv s) (readable : s.heap.Readable outp (room * 4))
    (rel : VRel prog.toCore boxes s.heap ty3 rv rp) (rep : (RepOption 2 (RepList 0 RepI32)) r rp) :
    SafeS prog.toCore (({ s with locals := [] } : State).bindLocals [(11, .rawSlice i32T outp room), (23, rv)])
      (src_app_main_oracle_put 3).body.toCore := by
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
    refine safeS_return (safeE_match (known_local l23) (safeArms_miss (by simp [Semantics.matchPattern])
      (safeArms_hit (bs := []) (by simp [Semantics.matchPattern, Semantics.matchPatterns]) ?_)))
    exact (known_binary (P := prog.toCore) (op := .subtract) (by decide) (by decide) (known_value _) (known_value _)
      (v := .signed .i32 (-1)) (by
        rw [toCore_target']
        simp only [Semantics.evalBinaryValue, beq_self_eq_true, if_true, Semantics.evalSignedBinary]
        rfl)).safeE
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
    refine safeS_return (safeE_match (known_local l23) (safeArms_hit (bs := [(153, lv)])
      (by simp [Semantics.matchPattern, Semantics.matchPatterns]) ?_))
    have m11 : (E.bindLocals [(153, lv)]).local? 11 = some (.rawSlice i32T outp room) :=
      local?_bindLocals_other _ (by simp) l11
    have m153 : (E.bindLocals [(153, lv)]).local? 153 = some lv := local?_bindLocal_self invE _ _
    have args := knowns_cons (known_local (P := prog.toCore) m11)
      (knowns_cons (known_value (.unsigned .usize (0#64).toNat)) (knowns_cons (known_local m153) knowns_nil))
    refine safeE_cast (safeE_call fn_write args.safeEs fun {k values s1} h1 => ?_) fun {k v s1} h1 bound => ?_
    · obtain ⟨rfl, hs1⟩ := args.done h1
      subst s1
      refine ⟨rfl, ?_⟩
      simp only [write_params]
      exact write_safe roomLt ws (invE.bindLocals _) (heapE ▸ readable) (heapE ▸ rl) rws
    · obtain ⟨j5, f3, values, afterArgs, done3, c3, -, argsRun, found3, -, body3, result3, rfl⟩ := call_inv' h1
      rw [fn_write, Option.some.injEq] at found3
      subst found3
      obtain ⟨rfl, hA⟩ := args.done argsRun
      subst afterArgs
      simp only [write_params] at body3
      obtain ⟨d1, -⟩ := write_body roomLt ws (invE.bindLocals _) (show done3.heap.nextAddress ≤ 2 ^ 64 from bound)
        (heapE ▸ readable) (heapE ▸ rl) rws body3 result3
      subst d1
      rw [toCore_target']
      exact ⟨_, rfl⟩

/-- **The driver traps definedly.** No run of `w(input, words, output, room)`,
on an input view reading `W` and an output view of `room` words that the heap
holds, traps undefinedly within the heap bound. -/
theorem driver_safe {st : State} {inp outp room : Nat} {W : List (BitVec 32)}
    (inv : Inv st) (wordsLt : W.length < 2 ^ 31) (roomLt : room < 2 ^ 31)
    (input : Reads st inp W) (output : st.heap.Readable outp (room * 4))
    (inRange : W.length = 0 ∨ st.heap.checkRange inp (W.length * 4) 4 = .ok ())
    (outRange : room = 0 ∨ st.heap.checkRange outp (room * 4) 4 = .ok ()) :
    SafeE prog.toCore st (.call 0 [.value (.pointer inp), .value (.signed .i32 W.length),
      .value (.pointer outp), .value (.signed .i32 room)]) := by
  have args0 := knowns_cons (known_value (P := prog.toCore) (st := st) (.pointer inp))
    (knowns_cons (known_value (.signed .i32 W.length)) (knowns_cons (known_value (.pointer outp))
      (knowns_cons (known_value (.signed .i32 room)) knowns_nil)))
  refine safeE_call fn_w args0.safeEs fun {k values s0} h0 => ?_
  obtain ⟨rfl, hs0⟩ := args0.done h0
  subst s0
  refine ⟨rfl, ?_⟩
  simp only [w_params]
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
  simp only [src_app_main_w, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcExpr.toCore, SrcType.toCore,
    SrcType.sliceFrom, SrcType.toScalar, UintTy.toCore]
  -- The two views.
  have v1 := known_i32Slice (P := prog.toCore) (known_local l2) (known_local l14) (by omega) (by
    rcases inRange with h | h
    · left; exact_mod_cast h
    · right; rw [heapE, Int.toNat_natCast]; exact h)
  rw [Int.toNat_natCast] at v1
  refine safeS_let_known v1 ?_
  have v2 := known_i32Slice (P := prog.toCore) (known_local (local?_bindLocal_other (id := 67) (by decide)
    (.rawSlice i32T inp W.length) l26)) (known_local (local?_bindLocal_other (id := 67) (by decide)
    (.rawSlice i32T inp W.length) l39)) (by omega) (by
    rcases outRange with h | h
    · left; exact_mod_cast h
    · right; rw [show (E.bindLocal 67 (.rawSlice i32T inp W.length)).heap = E.heap from rfl, heapE,
        Int.toNat_natCast]; exact h)
  rw [Int.toNat_natCast] at v2
  refine safeS_let_known v2 ?_
  have inv2 := (invE.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)
  have k67 : ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)).local? 67 =
      some (.rawSlice i32T inp W.length) :=
    local?_bindLocal_other (by decide) _ (local?_bindLocal_self invE _ _)
  have k14 : ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)).local? 14 =
      some (.signed .i32 W.length) :=
    local?_bindLocal_other (by decide) _ (local?_bindLocal_other (by decide) _ l14)
  have k125 : ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)).local? 125 =
      some (.rawSlice i32T outp room) :=
    local?_bindLocal_self (invE.bindLocal 67 _) _ _
  have step2 : Step st ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)) :=
    stepE.trans ((Step.bindLocal _ _ _).trans (Step.bindLocal _ _ _))
  have kc := known_cast (P := prog.toCore) (ty := .unsigned .usize) (known_local k14) (v := .unsigned .usize W.length)
    (by rw [toCore_target', cast_usize_int (by omega) (by omega), Int.toNat_natCast])
  have emptySafe : SafeE prog.toCore ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125
      (.rawSlice i32T outp room)) (.call 5 []) :=
    safeE_call_pure funcs_safe fn_empty_of_i32 (by decide +kernel) safeEs_nil fun {k values s} h => by
      obtain ⟨rfl, rfl⟩ := exprs_nil_inv h
      exact ⟨inv2, [], .nil⟩
  -- `let read = oracle_read(data, 0, words as usize, empty())`
  refine safeS_let (safeE_call fn_read (safeEs_cons (known_local k67).safeE fun {k v1 s1} h1 => ?_)
    fun {k values s1} h1 => ?_) fun {k lv s6} readRun => ?_
  · obtain ⟨rfl, hs1⟩ := (known_local k67).done h1
    subst s1
    refine safeEs_cons (known_value _).safeE fun {k v2 s2} h2 => ?_
    obtain ⟨rfl, hs2⟩ := (known_value (P := prog.toCore) _).done h2
    subst s2
    refine safeEs_cons kc.safeE fun {k v3 s3} h3 => ?_
    obtain ⟨rfl, hs3⟩ := kc.done h3
    subst s3
    exact safeEs_cons emptySafe fun _ => safeEs_nil
  · obtain ⟨_, a3, t3, more3, -, r3, m3, rfl⟩ := exprs_cons_inv h1
    obtain ⟨rfl, rfl⟩ := local_eval k67 r3
    obtain ⟨_, a4, t4, more4, -, r4, m4, rfl⟩ := exprs_cons_inv m3
    obtain ⟨rfl, rfl⟩ := value_inv r4
    obtain ⟨_, a5, t5, more5, -, r5, m5, rfl⟩ := exprs_cons_inv m4
    obtain ⟨rfl, rfl⟩ := kc.done r5
    obtain ⟨_, a6, t6, more6, -, r6, m6, rfl⟩ := exprs_cons_inv m5
    obtain ⟨rfl, rfl⟩ := exprs_nil_inv m6
    obtain ⟨j5, fE, valsE, afterE, doneE, cE, -, argsE, foundE, lenE, bodyE, resultE, rfl⟩ := call_inv' r6
    rw [fn_empty_of_i32, Option.some.injEq] at foundE
    subst foundE
    obtain ⟨rfl, rfl⟩ := exprs_nil_inv argsE
    obtain ⟨viewsE, -⟩ := execStmt_grows bodyE (Same.start inv2 _).views
    refine ⟨rfl, ?_⟩
    simp only [read_params, show (0#64).toNat = 0 from rfl]
    refine SafeS.of_bound (sp := prog) (s := (src_app_main_oracle_read 1 9).body) viewsE fun bE => ?_
    obtain ⟨we, hwe, rwe, invE', stepE'⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j5 fn_empty_of_i32
      (by decide +kernel) lenE inv2 (show doneE.heap.nextAddress ≤ 2 ^ 64 from bE) .nil bodyE resultE
    exact read_safe (by omega) (W.length - 0) rfl (Nat.zero_le _) (Nat.le_refl _) (invE'.restore _)
      (input.step ((step2.trans stepE').restore _)) rwe (cert_empty_of_i32 hwe)
  -- `return oracle_put(out, compile_words(front_end_words(grammar(), read)))`
  obtain ⟨j4, fR, valsR, afterR, doneR, cR, -, argsR, foundR, -, bodyR, resultR, rfl⟩ := call_inv' readRun
  rw [fn_read, Option.some.injEq] at foundR
  subst foundR
  obtain ⟨_, a3, t3, more3, -, r3, m3, rfl⟩ := exprs_cons_inv argsR
  obtain ⟨rfl, rfl⟩ := local_eval k67 r3
  obtain ⟨_, a4, t4, more4, -, r4, m4, rfl⟩ := exprs_cons_inv m3
  obtain ⟨rfl, rfl⟩ := value_inv r4
  obtain ⟨_, a5, t5, more5, -, r5, m5, rfl⟩ := exprs_cons_inv m4
  obtain ⟨rfl, rfl⟩ := kc.done r5
  obtain ⟨_, a6, t6, more6, -, r6, m6, rfl⟩ := exprs_cons_inv m5
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv m6
  obtain ⟨j5, fE, valsE, afterE, doneE, cE, -, argsE, foundE, lenE, bodyE, resultE, rfl⟩ := call_inv' r6
  rw [fn_empty_of_i32, Option.some.injEq] at foundE
  subst foundE
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv argsE
  simp only [read_params, show (0#64).toNat = 0 from rfl] at bodyR
  obtain ⟨viewsE, -⟩ := execStmt_grows bodyE (Same.start inv2 _).views
  obtain ⟨viewsR, leR⟩ := execStmt_grows bodyR viewsE
  refine SafeS.of_bound (sp := prog) (s := SrcStmt.returnEval (SrcEff.eCall 2 [SrcEff.ePure (SrcExpr.local 125),
    SrcEff.eCall 6 [SrcEff.eCall 7 [SrcEff.eCall 8 [], SrcEff.ePure (SrcExpr.local 182)]]])) viewsR fun bR => ?_
  obtain ⟨we, hwe, rwe, invE', stepE'⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j5 fn_empty_of_i32
    (by decide +kernel) lenE inv2 (show doneE.heap.nextAddress ≤ 2 ^ 64 from Nat.le_trans leR bR) .nil bodyE
    resultE
  obtain ⟨p, relR, repR, invR, stepR⟩ := read_body (inp := inp) (W := W) (by omega) (W.length - 0) rfl
    (Nat.zero_le _) (Nat.le_refl _) (invE'.restore _) (input.step ((step2.trans stepE').restore _))
    (show doneR.heap.nextAddress ≤ 2 ^ 64 from bR) rwe
    (cert_empty_of_i32 hwe) bodyR resultR
  simp only [List.drop_zero, Nat.sub_zero, List.take_length, List.append_nil] at repR
  have invR0 := (invR.restore ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125
    (.rawSlice i32T outp room))).bindLocal 182 lv
  have k182 := local?_bindLocal_self (invR.restore ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125
    (.rawSlice i32T outp room))) 182 lv
  have k125' := local?_bindLocal_other (id := 182) (by decide) lv (local?_prefix
    (st' := restoreLocals ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room))
      doneR) ((stepE'.restore _).trans stepR).cells rfl k125)
  have envR : EnvRel prog.toCore boxes doneR.heap [(182, ty1)] [(182, p)]
      ((restoreLocals ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room))
        doneR).bindLocal 182 lv) := by
    intro x t hx
    by_cases e : x = 182
    · subst e
      simp [TEnv.get?] at hx
      subst hx
      exact ⟨lv, p, k182, by simp [Env.get?], relR⟩
    · simp [TEnv.get?, Ne.symm e] at hx
  have effSafe := safeE_of_eff (e := SrcEff.eCall 6 [SrcEff.eCall 7 [SrcEff.eCall 8 [], SrcEff.ePure (SrcExpr.local 182)]])
    (t := ty3) rfl invR0 envR
  refine safeS_return (safeE_call fn_put (safeEs_cons (known_local k125').safeE fun {k v1 s1} h1 => ?_)
    fun {k values s1} h1 => ?_)
  · obtain ⟨rfl, hs1⟩ := (known_local k125').done h1
    subst s1
    exact safeEs_cons effSafe fun _ => safeEs_nil
  obtain ⟨_, b1, u1, moreP, -, q1, n1, rfl⟩ := exprs_cons_inv h1
  obtain ⟨rfl, rfl⟩ := local_eval k125' q1
  obtain ⟨_, b2, u2, moreP2, -, q2, n2, rfl⟩ := exprs_cons_inv n1
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv n2
  obtain ⟨j8, fC, valsC, afterC, doneC, cC, -, argsC, foundC, lenC, bodyC, resultC, rfl⟩ := call_inv' q2
  rw [fn_compile_words, Option.some.injEq] at foundC
  subst foundC
  obtain ⟨_, b3, u3, moreC, -, q3, n3, rfl⟩ := exprs_cons_inv argsC
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv n3
  obtain ⟨j9, fF, valsF, afterF, doneF, cF, -, argsF, foundF, lenF, bodyF, resultF, rfl⟩ := call_inv' q3
  rw [fn_front_end_words, Option.some.injEq] at foundF
  subst foundF
  obtain ⟨_, b4, u4, moreF, -, q4, n4, rfl⟩ := exprs_cons_inv argsF
  obtain ⟨_, b5, u5, moreF2, -, q5, n5, rfl⟩ := exprs_cons_inv n4
  obtain ⟨f5, rfl⟩ := local_inv q5
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv n5
  obtain ⟨j10, fG, valsG, afterG, doneG, cG, -, argsG, foundG, lenG, bodyG, resultG, rfl⟩ := call_inv' q4
  rw [fn_grammar, Option.some.injEq] at foundG
  subst foundG
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv argsG
  obtain ⟨viewsG, leG⟩ := execStmt_grows bodyG viewsR
  obtain ⟨viewsF, leF⟩ := execStmt_grows bodyF viewsG
  obtain ⟨viewsC, leC⟩ := execStmt_grows bodyC viewsF
  refine ⟨rfl, ?_⟩
  simp only [put_params]
  refine SafeS.of_bound (sp := prog) (s := (src_app_main_oracle_put 3).body) viewsC fun bC => ?_
  have bF : doneF.heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans leC bC
  have bG : doneG.heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans leF bF
  obtain ⟨wg, hwg, rwg, invG, stepG⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j10 fn_grammar
    (by decide +kernel) lenG invR0 bG .nil bodyG resultG
  obtain rfl : b5 = lv := Option.some.inj (f5.symm.trans (local?_prefix (st' := restoreLocals ((restoreLocals
    ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)) doneR).bindLocal 182
      lv) doneG) stepG.cells rfl k182))
  obtain ⟨wf, hwf, rwf, invF, stepF⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j9 fn_front_end_words
    (by decide +kernel) lenF (invG.restore _) bF (.cons rwg (.cons (VRel.mono stepG.reads stepG.ranges relR) .nil))
    bodyF resultF
  obtain ⟨wc, hwc, rwc, invC, stepC⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j8 fn_compile_words
    (by decide +kernel) lenC (invF.restore _) (show doneC.heap.nextAddress ≤ 2 ^ 64 from bC) (.cons rwf .nil)
    bodyC resultC
  have repC := cert_compile_words hwc (cert_front_end_words hwf (cert_grammar hwg) repR)
  have stepC' := (((((((step2.trans stepE').restore _).trans stepR).restore _).trans (Step.bindLocal _ _ _)).trans
    stepG).restore _).trans stepF |>.restore _ |>.trans stepC
  exact put_safe roomLt (invC.restore _) (stepC'.reads.readable output) rwc repC

#print axioms driver_safe

end Lanius.Faithful.SelfDriver
