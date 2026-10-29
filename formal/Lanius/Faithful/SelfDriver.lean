import Lanius.Faithful.SelfFaithful
import Lanius.Faithful.Sim.Driver
import Lanius.Mini.TextWords

/-! # The self-host driver writes what the extraction computes (roadmap V1)

The self program's entry `w(input, words, output, room)` reads `words` i32
words from `input` into a list (`oracle_read`), runs the certified
`compile_words(front_end_words(grammar(), list))`, and writes the result's
words to `output` (`oracle_put`, `oracle_write`). These functions are outside
the pure subset, so this file proves them by hand at the Core level
(`driver_faithful`): a run of `w` that completes on input that reads `W`
returns -1 when `compileWords (frontEndWords grammar W)` is `none`, and
otherwise returns the result's length with the output reading the result. -/

namespace Lanius.Faithful.SelfDriver

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals readRawSliceIndex)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfCert
open Lanius.Faithful.SelfFaithful (boxes)

abbrev i32T : Core.Ty := .scalar (.signed .i32)

/-- Element `i` of the input view reads `W[i]`. -/
def Reads (st : State) (inp : Nat) (W : List (BitVec 32)) : Prop :=
  ∀ i (h : i < W.length), readRawSliceIndex prog.toCore st i32T inp W.length i = .ok (.signed .i32 (W[i]).toInt)

theorem Reads.step {st st' : State} {inp : Nat} {W : List (BitVec 32)} (r : Reads st inp W)
    (step : Step st st') : Reads st' inp W := fun i h => step.reads.rawSlice (r i h)

theorem take_split {α : Type} (W T : List α) {lo mid hi : Nat} (a : lo ≤ mid) (b : mid ≤ hi) :
    (W.drop lo).take (mid - lo) ++ ((W.drop mid).take (hi - mid) ++ T) = (W.drop lo).take (hi - lo) ++ T := by
  rw [← List.append_assoc, show hi - lo = (mid - lo) + (hi - mid) by omega, List.take_add, List.drop_drop,
    show lo + (mid - lo) = mid by omega]

theorem take_one {α : Type} (W : List α) {lo : Nat} (h : lo < W.length) : (W.drop lo).take 1 = [W[lo]] := by
  rw [List.drop_eq_getElem_cons h]; rfl

theorem fn_read : prog.funcs[1]? = some (src_app_main_oracle_read 1 9) := get_of_drop at_app_main_oracle_read

theorem read_params (a b c d : Value) :
    paramBindings (src_app_main_oracle_read 1 9).params [a, b, c, d] = [(12, a), (25, b), (36, c), (47, d)] := rfl

theorem callResult_ty1 {c : Completion} {v : Value} (h : CallResult ty1 c v) : c = .returned (some v) := by
  cases c with
  | next => exact absurd h.1 (by simp [ty1])
  | returned r =>
    cases r with
    | none => exact absurd h.1 (by simp [ty1])
    | some w => rw [show v = w from h]
  | breakLoop => exact h.elim
  | continueLoop => exact h.elim

/-- A call whose arguments are locals with known values: the callee's body
on those values. -/
theorem call_locals {st st' : State} {k callee : Nat} {f : SrcFunc} {v : Value} (bs : List (Nat × Value))
    (found : prog.funcs[callee]? = some f) (known : ∀ b ∈ bs, st.local? b.1 = some b.2)
    (h : evalExpr k prog.toCore st (.call callee (bs.map fun b => .local b.1)) = .done v st') :
    ∃ j completed c, execStmt j prog.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings f.params (bs.map Prod.snd))) f.body.toCore = .done c completed ∧ CallResult f.ret c v ∧
      st' = restoreLocals st completed :=
  call_pure found (fun run => exprs_locals bs known run) h

theorem i32_scalar (x : BitVec 32) : STy .i32 (.signed .i32 x.toInt) :=
  ⟨_, rfl, BitVec.le_toInt x, BitVec.toInt_lt⟩

/-- `oracle_read(data, lo, hi, tail)`'s body, on a view reading `W`: the list
of `W[lo..hi]` in front of `tail`. -/
theorem read_body {inp : Nat} {W : List (BitVec 32)} (len : W.length < 2 ^ 64) : ∀ (m : Nat) {k lo hi : Nat}
    {s completed : State} {c : Completion} {v tv tp : Value} {T : List (BitVec 32)},
    hi - lo = m → lo ≤ hi → hi ≤ W.length →
    Inv s → Reads s inp W → completed.heap.nextAddress ≤ 2 ^ 64 →
    VRel prog.toCore boxes s.heap ty1 tv tp → (RepList 0 RepI32) T tp →
    execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(12, .rawSlice i32T inp W.length), (25, .unsigned .usize lo), (36, .unsigned .usize hi), (47, tv)])
      (src_app_main_oracle_read 1 9).body.toCore = .done c completed →
    CallResult ty1 c v →
    ∃ p, VRel prog.toCore boxes completed.heap ty1 v p ∧ (RepList 0 RepI32) ((W.drop lo).take (hi - lo) ++ T) p ∧
      Inv completed ∧ Step s completed := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
  intro k lo hi s completed c v tv tp T hm le hle inv reads bound rel rep run result
  generalize hE : ({ s with locals := [] } : State).bindLocals [(12, .rawSlice i32T inp W.length),
    (25, .unsigned .usize lo), (36, .unsigned .usize hi), (47, tv)] = E at run
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
    SrcType.toCore, SrcOp.toCore, SrcDivOp.toCore, UintTy.toCore, List.map] at run
  obtain ⟨j1, s1, c1, -, first, rest⟩ := sequence_inv run
  obtain ⟨j2, s2, x, -, cond, branch⟩ := if_inv first
  obtain ⟨j3, l, s3, r, -, runL, runR, op⟩ := binary_inv (by decide) (by decide) cond
  obtain ⟨j4, a, s4, b, -, runA, runB, op2⟩ := binary_inv (by decide) (by decide) runL
  obtain ⟨rfl, rfl⟩ := local_eval l36 runA
  obtain ⟨rfl, rfl⟩ := local_eval l25 runB
  obtain ⟨rfl, rfl⟩ := value_inv runR
  rw [toCore_target', nat_sub le (by omega), Except.ok.injEq] at op2
  subst op2
  rw [toCore_target', show (1#64).toNat = 1 from rfl, nat_greater, Except.ok.injEq, Value.boolean.injEq] at op
  subst op
  by_cases big : hi - lo > 1
  · -- Split at the middle: the right half in front of the tail, then the left half.
    simp only [big, decide_true, if_true] at branch
    obtain ⟨j5, mv, s5, s6, -, midRun, body, rfl⟩ := letLocal_inv branch
    obtain ⟨j6, a1, s7, b1, -, r25, rdiv, opAdd⟩ := binary_inv (by decide) (by decide) midRun
    obtain ⟨rfl, rfl⟩ := local_eval l25 r25
    obtain ⟨j7, a2, s8, b2, -, rsub, r2, opDiv⟩ := binary_inv (by decide) (by decide) rdiv
    obtain ⟨j8, a3, s9, b3, -, r36', r25', opSub⟩ := binary_inv (by decide) (by decide) rsub
    obtain ⟨rfl, rfl⟩ := local_eval l36 r36'
    obtain ⟨rfl, rfl⟩ := local_eval l25 r25'
    obtain ⟨rfl, rfl⟩ := value_inv r2
    rw [toCore_target', nat_sub le (by omega), Except.ok.injEq] at opSub
    subst opSub
    rw [toCore_target', show (2#64).toNat = 2 from rfl, nat_half _ (by omega), Except.ok.injEq] at opDiv
    subst opDiv
    rw [toCore_target', nat_add (by omega), Except.ok.injEq] at opAdd
    subst opAdd
    have midLo : lo ≤ lo + (hi - lo) / 2 := Nat.le_add_right _ _
    have midHi : lo + (hi - lo) / 2 ≤ hi := by omega
    have inv1 := invE.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))
    obtain ⟨j9, rv, s10, s11, -, recRun, ret, rfl⟩ := letLocal_inv body
    obtain ⟨j10, done1, c10, recBody, recResult, rfl⟩ := call_locals [(12, .rawSlice i32T inp W.length),
        (146, .unsigned .usize (lo + (hi - lo) / 2)), (36, .unsigned .usize hi), (47, tv)] fn_read (by
      intro b mem
      simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
      rcases mem with rfl | rfl | rfl | rfl
      · exact local?_bindLocal_other (by simp) _ l12
      · exact local?_bindLocal_self invE _ _
      · exact local?_bindLocal_other (by simp) _ l36
      · exact local?_bindLocal_other (by simp) _ l47) recRun
    obtain ⟨j11, v2, -, run2, rfl⟩ := return_inv ret
    obtain ⟨-, rfl, rfl⟩ := rest.resolve_left (fun ⟨bad, _⟩ => by cases bad)
    obtain rfl : v2 = v := by simpa using callResult_ty1 result
    -- The rest of the body grows the heap, so the first call's heap is in range.
    have grows := execStmt_grows (sp := prog) (s := SrcStmt.returnEval (SrcEff.eCall 1
      [SrcEff.ePure (SrcExpr.local 12), SrcEff.ePure (SrcExpr.local 25), SrcEff.ePure (SrcExpr.local 146),
        SrcEff.ePure (SrcExpr.local 191)])) ret
    simp only [List.map_cons, List.map_nil, read_params] at recBody
    obtain ⟨views1, -⟩ := execStmt_grows recBody (Same.start inv1 _).views
    obtain ⟨-, le1⟩ := grows views1
    obtain ⟨p1, rel1, rep1, inv1', step1⟩ := ih (hi - (lo + (hi - lo) / 2)) (by omega)
      (lo := lo + (hi - lo) / 2) (hi := hi) rfl midHi hle inv1 (reads.step (stepE.trans (Step.bindLocal _ _ _)))
      (show done1.heap.nextAddress ≤ 2 ^ 64 from Nat.le_trans le1 bound) (heapE ▸ rel) rep recBody recResult
    have invS := (inv1'.restore (s5.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2)))).bindLocal 191 rv
    have back {id : Nat} {x : Value} (ne : 191 ≠ id)
        (h : (s5.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))).local? id = some x) :
        ((restoreLocals (s5.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))) done1).bindLocal 191 rv).local? id =
          some x :=
      local?_bindLocal_other ne _ (local?_prefix (st' := restoreLocals (s5.bindLocal 146 (.unsigned .usize (lo + (hi - lo) / 2))) done1)
        step1.cells rfl h)
    obtain ⟨j12, done2, c12, recBody2, recResult2, rfl⟩ := call_locals [(12, .rawSlice i32T inp W.length),
        (25, .unsigned .usize lo), (146, .unsigned .usize (lo + (hi - lo) / 2)), (191, rv)] fn_read (by
      intro b mem
      simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
      rcases mem with rfl | rfl | rfl | rfl
      · exact back (by simp) (local?_bindLocal_other (by simp) _ l12)
      · exact back (by simp) (local?_bindLocal_other (by simp) _ l25)
      · exact back (by simp) (local?_bindLocal_self invE _ _)
      · exact local?_bindLocal_self (inv1'.restore _) _ _) run2
    simp only [List.map_cons, List.map_nil, read_params] at recBody2
    obtain ⟨p2, rel2, rep2, inv2, step2⟩ := ih ((lo + (hi - lo) / 2) - lo) (by omega)
      (lo := lo) (hi := lo + (hi - lo) / 2) (T := (W.drop (lo + (hi - lo) / 2)).take (hi - (lo + (hi - lo) / 2)) ++ T)
      rfl midLo (by omega) invS
      ((reads.step (stepE.trans (Step.bindLocal _ _ _))).step
        (step1.trans (((Step.refl _).restore _).trans (Step.bindLocal _ _ _))))
      (show done2.heap.nextAddress ≤ 2 ^ 64 from bound) rel1 rep1 recBody2 recResult2
    refine ⟨p2, rel2, ?_, ((inv2.restore _).restore _).restore _, ?_⟩
    · rwa [take_split W T midLo midHi] at rep2
    · exact ((((stepE.trans (Step.bindLocal _ _ _)).trans (step1.trans (((Step.refl _).restore _).trans
        ((Step.bindLocal _ _ _).trans step2)))).restore _).restore _).restore _
  · simp only [big, decide_false, Bool.false_eq_true, if_false] at branch
    obtain ⟨rfl, rfl⟩ := skip_inv branch
    obtain ⟨-, rest⟩ := rest.resolve_right (fun ⟨ne, _, _⟩ => ne rfl)
    obtain ⟨j5, s5, c5, -, second, rest2⟩ := sequence_inv rest
    obtain ⟨j6, s6, y, -, cond2, branch2⟩ := if_inv second
    obtain ⟨j7, l2, s7, r2, -, rl, rr, op3⟩ := binary_inv (by decide) (by decide) cond2
    obtain ⟨rfl, rfl⟩ := local_eval l36 rl
    obtain ⟨rfl, rfl⟩ := local_eval l25 rr
    rw [toCore_target', nat_greater, Except.ok.injEq, Value.boolean.injEq] at op3
    subst op3
    by_cases one : hi > lo
    · -- One word: `cons(data[lo], tail)`.
      simp only [one, decide_true, if_true] at branch2
      obtain ⟨j8, cv, -, consRun, rfl⟩ := return_inv branch2
      rcases rest2 with ⟨bad, -⟩ | ⟨-, rfl, rfl⟩
      · cases bad
      obtain ⟨j9, f', values, afterArgs, done, cc, -, argsRun, found', lenOk, consBody, consResult, rfl⟩ :=
        call_inv' consRun
      obtain ⟨j10, iv, sa, more, -, idxRun, moreRun, rfl⟩ := exprs_cons_inv argsRun
      obtain ⟨j11, bv, sb, -, baseRun, idx⟩ := index_inv idxRun
      obtain ⟨rfl, rfl⟩ := local_eval l12 baseRun
      obtain ⟨pv, pos, posRun, posOk, readOk⟩ := idx _ _ _ rfl
      obtain ⟨rfl, rfl⟩ := local_eval l25 posRun
      simp only [Semantics.integerIndex, Except.ok.injEq] at posOk
      subst posOk
      have lt : lo < W.length := by omega
      have readW := Reads.step reads stepE lo lt
      rw [readW, Except.ok.injEq] at readOk
      subst readOk
      obtain ⟨j12, tv', sc, rest3, -, tRun, nilRun, rfl⟩ := exprs_cons_inv moreRun
      obtain ⟨rfl, rfl⟩ := local_eval l47 tRun
      obtain ⟨rfl, rfl⟩ := exprs_nil_inv nilRun
      rw [fn_cons_of_i32, Option.some.injEq] at found'
      subst found'
      have relArgs : VRels prog.toCore boxes _ ((src_cons_of_i32 33).params.map SrcParam.ty) _ _ :=
        .cons (.scalar (i32_scalar (W[lo]))) (.cons (heapE ▸ rel) .nil)
      obtain ⟨w, hw, rw, inv', step⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j9 fn_cons_of_i32
        (by decide +kernel) lenOk invE (show done.heap.nextAddress ≤ 2 ^ 64 from bound) relArgs consBody consResult
      obtain rfl : cv = v := by simpa using callResult_ty1 result
      refine ⟨w, rw, ?_, inv'.restore _, (stepE.trans step).restore _⟩
      have := cert_cons_of_i32 hw (RepI32.mk (W[lo])) rep
      rwa [show hi - lo = 1 by omega, take_one W lt]
    · -- No words: the tail.
      simp only [one, decide_false, Bool.false_eq_true, if_false] at branch2
      obtain ⟨rfl, rfl⟩ := skip_inv branch2
      obtain ⟨-, last⟩ := rest2.resolve_right (fun ⟨ne, _, _⟩ => ne rfl)
      obtain ⟨j8, tv', -, tRun, rfl⟩ := return_inv last
      obtain ⟨rfl, rfl⟩ := local_eval l47 tRun
      obtain rfl : tv' = v := by simpa using callResult_ty1 result
      obtain rfl : hi = lo := by omega
      refine ⟨tp, heapE ▸ rel, by simpa using rep, invE, stepE⟩

/-! ## Writing the output -/

/-- The output view reads `ws` from element `ofs`. -/
def Written (st : State) (outp room ofs : Nat) (ws : List (BitVec 32)) : Prop :=
  ∀ i (h : i < ws.length), readRawSliceIndex prog.toCore st i32T outp room (ofs + i) = .ok (.signed .i32 (ws[i]).toInt)

theorem write_params (a b c : Value) :
    paramBindings (src_app_main_oracle_write 4 10).params [a, b, c] = [(13, a), (25, b), (36, c)] := rfl

theorem write_one_params (a b c d : Value) :
    paramBindings (src_app_main_oracle_write_one 3).params [a, b, c, d] = [(17, a), (29, b), (40, c), (48, d)] := rfl

theorem fn_write : prog.funcs[3]? = some (src_app_main_oracle_write 4 10) := get_of_drop at_app_main_oracle_write
theorem fn_write_one : prog.funcs[4]? = some (src_app_main_oracle_write_one 3) :=
  get_of_drop at_app_main_oracle_write_one
theorem fn_unbox : prog.funcs[10]? = some (src_unbox_of_mini_selfhost_List_i32 34) :=
  get_of_drop at_unbox_of_mini_selfhost_List_i32

theorem callResult_usize {c : Completion} {v : Value} (h : CallResult (.uint .usize) c v) : c = .returned (some v) := by
  cases c with
  | next => exact absurd h.1 (by simp)
  | returned r =>
    cases r with
    | none => exact absurd h.1 (by simp)
    | some w => rw [show v = w from h]
  | breakLoop => exact h.elim
  | continueLoop => exact h.elim

theorem local?_heap {id : Nat} (st : State) (h : Memory.Heap) (vs : List Semantics.I32ArrayView) :
    ({ locals := st.locals, cells := st.cells, nextCell := st.nextCell, heap := h, world := st.world,
       i32ArrayViews := vs } : State).local? id = st.local? id := rfl

theorem _root_.BitVec.toInt_ofInt_toInt (x : BitVec 32) : (BitVec.ofInt 32 x.toInt).toInt = x.toInt := by
  rw [BitVec.ofInt_toInt]

theorem readRaw_heap {a b : State} {el : Core.Ty} {p n i : Nat} (h : a.heap = b.heap) :
    readRawSliceIndex prog.toCore a el p n i = readRawSliceIndex prog.toCore b el p n i := by
  simp only [readRawSliceIndex, h]

theorem i32Bytes_length (x : Int) : (Semantics.i32Bytes x).length = 4 := by
  simp [Semantics.i32Bytes]

theorem pcall_unbox {n : Nat} {p w : Value} (h : pcall prog prims (n + 1) 10 [p] = some w) : w = p := by
  simp only [pcall, show prims.isPrim 10 = true by decide +kernel, if_true, single, Option.some.injEq] at h
  exact h.symm

theorem vrel_ty1 {h : Memory.Heap} {lv lp : Value} (rel : VRel prog.toCore boxes h ty1 lv lp) :
    ∃ k vs ps fs, lv = .enumeration 0 k vs ∧ lp = .enumeration 0 k ps ∧
      ([[], [.i32, ty0]] : List (List SrcType))[k]? = some fs ∧ VRels prog.toCore boxes h fs vs ps := by
  cases rel with
  | scalar st => exact st.elim
  | enum hk rs => exact ⟨_, _, _, _, rfl, rfl, hk, rs⟩

/-- What `oracle_write(out, ofs, ws)` leaves: it returned `ofs + ws.length`, the
output reads `ws` from `ofs`, and the heap is one later writes can use. -/
def WriteDone (s completed : State) (v : Value) (outp room ofs : Nat) (ws : List (BitVec 32)) : Prop :=
  v = .unsigned .usize (ofs + ws.length) ∧ (ws = [] ∨ ofs + ws.length ≤ room) ∧ Written completed outp room ofs ws ∧
    s.cells <+: completed.cells ∧ Inv completed ∧ completed.heap.Readable outp (room * 4)

/-- `oracle_write`'s body does what `WriteDone` says, for the list `ws`. -/
def WriteSpec (outp room : Nat) (ws : List (BitVec 32)) : Prop :=
  ∀ {k ofs : Nat} {s completed : State} {c : Completion} {v lv lp : Value},
    Inv s → completed.heap.nextAddress ≤ 2 ^ 64 → s.heap.Readable outp (room * 4) →
    VRel prog.toCore boxes s.heap ty1 lv lp → (RepList 0 RepI32) ws lp →
    execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(13, .rawSlice i32T outp room), (25, .unsigned .usize ofs), (36, lv)])
      (src_app_main_oracle_write 4 10).body.toCore = .done c completed →
    CallResult (.uint .usize) c v → WriteDone s completed v outp room ofs ws

/-- `oracle_write_one(out, ofs, x, rest)`'s body: the rest from `ofs + 1`,
then `x` at `ofs`. -/
theorem write_one_body {outp room : Nat} (roomLt : room < 2 ^ 31) {x : BitVec 32} {rest : List (BitVec 32)}
    (ih : WriteSpec outp room rest) {k ofs : Nat} {s completed : State} {c : Completion} {v uv up : Value}
    (inv : Inv s) (bound : completed.heap.nextAddress ≤ 2 ^ 64) (readable : s.heap.Readable outp (room * 4))
    (rel : VRel prog.toCore boxes s.heap ty1 uv up) (rep : (RepList 0 RepI32) rest up)
    (run : execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(17, .rawSlice i32T outp room), (29, .unsigned .usize ofs), (40, .signed .i32 x.toInt), (48, uv)])
      (src_app_main_oracle_write_one 3).body.toCore = .done c completed)
    (result : CallResult (.uint .usize) c v) :
    WriteDone s completed v outp room ofs (x :: rest) := by
  generalize hE : ({ s with locals := [] } : State).bindLocals [(17, .rawSlice i32T outp room),
    (29, .unsigned .usize ofs), (40, .signed .i32 x.toInt), (48, uv)] = E at run
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
    UintTy.toCore, List.map] at run
  obtain ⟨j1, wv, s5, s6, -, wrun, rest5, rfl⟩ := letLocal_inv run
  -- The recursive call writes the rest from `ofs + 1`.
  obtain ⟨j2, f3, values, afterArgs, done3, c3, -, argsRun, found3, len3, body3, result3, rfl⟩ := call_inv' wrun
  rw [fn_write, Option.some.injEq] at found3
  subst found3
  obtain ⟨_, a1, t1, more1, -, r1, m1, rfl⟩ := exprs_cons_inv argsRun
  obtain ⟨rfl, rfl⟩ := local_eval l17 r1
  obtain ⟨_, a2, t2, more2, -, r2, m2, rfl⟩ := exprs_cons_inv m1
  obtain ⟨_, la, t3, ra, -, rl, rr1, op⟩ := binary_inv (by decide) (by decide) r2
  obtain ⟨rfl, rfl⟩ := local_eval l29 rl
  obtain ⟨rfl, rfl⟩ := value_inv rr1
  have add1 : Semantics.evalBinaryValue prog.toCore.target .add (.unsigned .usize ofs)
      (.unsigned .usize (1#64).toNat) = .ok (.unsigned .usize ((ofs + 1) % 2 ^ 64)) := rfl
  rw [add1, Except.ok.injEq] at op
  subst op
  obtain ⟨_, a3, t4, more3, -, r3, m3, rfl⟩ := exprs_cons_inv m2
  obtain ⟨rfl, rfl⟩ := local_eval l48 r3
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv m3
  simp only [write_params] at body3
  obtain ⟨views3, -⟩ := execStmt_grows body3 (Same.start invE _).views
  obtain ⟨-, le5⟩ := execStmt_grows (sp := prog) (s := SrcStmt.then (SrcStmt.setIndex 17 (SrcExpr.local 29)
    (SrcExpr.local 40)) (SrcStmt.return (SrcExpr.local 100))) rest5 views3
  obtain ⟨hw, hlen, written, cells3, inv3, readable3⟩ := ih invE
    (show done3.heap.nextAddress ≤ 2 ^ 64 from Nat.le_trans le5 bound) (heapE ▸ readable) (heapE ▸ rel) rep
    body3 result3
  subst hw
  have invS := (inv3.restore afterArgs).bindLocal 100 (.unsigned .usize ((ofs + 1) % 2 ^ 64 + rest.length))
  have back {id : Nat} {y : Value} (ne : 100 ≠ id) (h : afterArgs.local? id = some y) :
      ((restoreLocals afterArgs done3).bindLocal 100
        (.unsigned .usize ((ofs + 1) % 2 ^ 64 + rest.length))).local? id = some y :=
    local?_bindLocal_other ne _ (local?_prefix (st' := restoreLocals afterArgs done3) cells3 rfl h)
  -- `out[ofs] = x`: the place, the value, the store.
  obtain ⟨j6, s7, c7, -, first, last⟩ := sequence_inv rest5
  obtain ⟨j7, u, -, arun, rfl⟩ := expression_inv first
  obtain ⟨j8, r, s8, rv, s9, s10, -, placeRun, valRun, writtenRun, synced⟩ := assign_inv arun
  obtain ⟨j9, rb, s11, -, baseRun, idx⟩ := place_index_inv placeRun
  obtain ⟨hrb, rfl⟩ := place_local_read (back (by decide) l17) baseRun
  obtain ⟨iv, pos, base, idxRun, posOk, posLt, baseOk, rraw⟩ := idx _ _ _ hrb
  obtain ⟨rfl, rfl⟩ := local_eval (back (by decide) l29) idxRun
  simp only [Semantics.integerIndex, Except.ok.injEq] at posOk
  subst posOk
  simp only [Semantics.rawSliceElementAddress?, Except.ok.injEq] at baseOk
  subst baseOk
  obtain ⟨rfl, rfl⟩ := local_eval (back (by decide) l40) valRun
  have small : (ofs + 1) % 2 ^ 64 = ofs + 1 := Nat.mod_eq_of_lt (by omega)
  simp only [Semantics.writeResolvedPlaceNative, rraw, writeNative_i32] at writtenRun
  have hheap : ((restoreLocals afterArgs done3).bindLocal 100
      (.unsigned .usize ((ofs + 1) % 2 ^ 64 + rest.length))).heap = done3.heap := rfl
  have hviews : ((restoreLocals afterArgs done3).bindLocal 100
      (.unsigned .usize ((ofs + 1) % 2 ^ 64 + rest.length))).i32ArrayViews = [] := inv3.views
  rw [hheap] at writtenRun
  cases hst : done3.heap.storeBytes (outp + ofs * 4) (Semantics.i32Bytes x.toInt) with
  | error e => simp [hst, bind, Except.bind] at writtenRun
  | ok heap' =>
  simp only [hst, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at writtenRun
  subst writtenRun
  simp only [Semantics.ResolvedPlace.viewFreeRootWrite, rraw, Option.isNone_some, Bool.false_and, if_false,
    Bool.false_eq_true, Semantics.syncI32ViewsFromHeap, hviews, Semantics.syncI32ViewsFromHeapFrom,
    Except.ok.injEq] at synced
  subst synced
  have write := storeBytes_write inv3.unique
    (by rw [i32Bytes_length]; exact readable3.subrange (start := ofs * 4) (length := 4) (by omega)) hst
  obtain ⟨-, ret⟩ := last.resolve_right (fun ⟨ne, _, _⟩ => ne rfl)
  obtain ⟨j10, rv2, -, rrun, rfl⟩ := return_inv ret
  obtain ⟨rfl, rfl⟩ := local_eval ((local?_heap _ heap' []).trans
    (local?_bindLocal_self (inv3.restore afterArgs) 100 _)) rrun
  have hv := callResult_usize result
  simp only [Completion.returned.injEq, Option.some.injEq] at hv
  subst hv
  have fits : ∀ j, j < rest.length → ofs + (j + 1) < room := by
    intro j h
    rcases hlen with rfl | h'
    · simp at h
    · omega
  have slot : ∀ p, p < room → done3.heap.Readable (outp + p * 4) 4 := fun p lt =>
    readable3.subrange (start := p * 4) (length := 4) (by omega)
  refine ⟨?_, .inr ?_, ?_, stepE.cells.trans (cells3.trans (Step.bindLocal _ 100 _).cells),
    Inv.restore _ ⟨rfl, invS.fresh, write.below invS.below, write.unique⟩, write.readable readable3⟩
  · rw [small, List.length_cons, Nat.add_right_comm, Nat.add_assoc]
  · rcases hlen with rfl | h <;> simp <;> omega
  · intro i h
    cases i with
    | zero =>
      refine (readRaw_heap (b := { done3 with heap := heap' }) rfl).trans ?_
      have := Semantics.readRawSliceIndex_i32_afterStore (program := prog.toCore) (position := ofs) (previous := 0)
        (after := { done3 with heap := heap' }) write (BitVec.toInt_ofInt_toInt x) posLt (slot ofs posLt) (fun ne => absurd rfl ne)
      simpa using this
    | succ j =>
      have lt : j < rest.length := by simpa using h
      have old := written j lt
      rw [small, show ofs + 1 + j = ofs + (j + 1) by omega] at old
      refine (readRaw_heap (b := { done3 with heap := heap' }) rfl).trans ?_
      have := Semantics.readRawSliceIndex_i32_afterStore (program := prog.toCore) (position := ofs + (j + 1))
        (previous := (rest[j]).toInt) (after := { done3 with heap := heap' }) write (BitVec.toInt_ofInt_toInt x) (fits j lt) (slot _ (fits j lt)) (fun _ => old)
      simpa [show ofs + (j + 1) ≠ ofs by omega] using this

/-- `oracle_write(out, ofs, ws)`'s body: it returns `ofs + ws.length` and leaves
the output reading `ws` from `ofs`. -/
theorem write_body {outp room : Nat} (roomLt : room < 2 ^ 31) : ∀ ws, WriteSpec outp room ws := by
  intro ws
  induction ws with
  | nil =>
    intro k ofs s completed c v lv lp inv bound readable rel rep run result
    generalize hE : ({ s with locals := [] } : State).bindLocals [(13, .rawSlice i32T outp room),
      (25, .unsigned .usize ofs), (36, lv)] = E at run
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
      SrcExpr.toCore, SrcType.typeId, ty1, List.map] at run
    obtain ⟨j1, mv, -, mrun, rfl⟩ := return_inv run
    obtain ⟨j2, sv, s1, -, srun, arms⟩ := matchValue_inv mrun
    obtain ⟨rfl, rfl⟩ := local_eval l36 srun
    obtain ⟨j3, -, hit⟩ := arms_cons_inv arms
    rcases hit with ⟨miss, -⟩ | ⟨bs, s2, hbs, body, rfl⟩
    · simp [Semantics.matchPattern, Semantics.matchPatterns] at miss
    simp only [Semantics.matchPattern, Semantics.matchPatterns, beq_self_eq_true, Bool.and_self, if_true,
      Option.some.injEq] at hbs
    subst hbs
    obtain ⟨rfl, rfl⟩ := local_eval l25 body
    have hv := callResult_usize result
    simp only [Completion.returned.injEq, Option.some.injEq] at hv
    subst hv
    exact ⟨by simp, .inl rfl, fun i h => absurd h (by simp), stepE.cells, invE, heapE ▸ readable⟩
  | cons x rest ih =>
    intro k ofs s completed c v lv lp inv bound readable rel rep run result
    generalize hE : ({ s with locals := [] } : State).bindLocals [(13, .rawSlice i32T outp room),
      (25, .unsigned .usize ofs), (36, lv)] = E at run
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
    -- The list is `Cons(x, box)`, the box meaning the rest.
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
      SrcExpr.toCore, SrcType.typeId, ty1, List.map] at run
    obtain ⟨j1, mv, -, mrun, rfl⟩ := return_inv run
    obtain ⟨j2, sv, s1, -, srun, arms⟩ := matchValue_inv mrun
    obtain ⟨rfl, rfl⟩ := local_eval l36 srun
    obtain ⟨j3, -, hit⟩ := arms_cons_inv arms
    obtain ⟨-, arms2⟩ := hit.resolve_right (fun ⟨_, _, hbs, _⟩ => by simp [Semantics.matchPattern] at hbs)
    obtain ⟨j4, -, hit2⟩ := arms_cons_inv arms2
    rcases hit2 with ⟨miss, -⟩ | ⟨bs, s2, hbs, body, rfl⟩
    · simp [Semantics.matchPattern, Semantics.matchPatterns] at miss
    simp only [Semantics.matchPattern, Semantics.matchPatterns, beq_self_eq_true, Bool.and_self, if_true,
      List.cons_append, List.nil_append, Option.some.injEq] at hbs
    subst hbs
    have hv := callResult_usize result
    simp only [Completion.returned.injEq, Option.some.injEq] at hv
    subst hv
    have inv2 := invE.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]
    have m13 : (s1.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 13 =
        some (.rawSlice i32T outp room) := local?_bindLocals_other _ (by simp) l13
    have m25 : (s1.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 25 =
        some (.unsigned .usize ofs) := local?_bindLocals_other _ (by simp) l25
    have m134 : (s1.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 134 =
        some (.signed .i32 x.toInt) := local?_bindLocal_other (by simp) _ (local?_bindLocal_self invE 134 _)
    have m137 : (s1.bindLocals [(134, Value.signed .i32 x.toInt), (137, bv)]).local? 137 = some bv :=
      local?_bindLocal_self (invE.bindLocal 134 _) 137 bv
    -- `oracle_write_one(out, ofs, x, unbox(rest))`
    obtain ⟨j5, f4, values, afterArgs, done4, c4, -, argsRun, found4, len4, body4, result4, rfl⟩ := call_inv' body
    rw [fn_write_one, Option.some.injEq] at found4
    subst found4
    obtain ⟨_, a1, t1, more1, -, r1, n1, rfl⟩ := exprs_cons_inv argsRun
    obtain ⟨rfl, rfl⟩ := local_eval m13 r1
    obtain ⟨_, a2, t2, more2, -, r2, n2, rfl⟩ := exprs_cons_inv n1
    obtain ⟨rfl, rfl⟩ := local_eval m25 r2
    obtain ⟨_, a3, t3, more3, -, r3, n3, rfl⟩ := exprs_cons_inv n2
    obtain ⟨rfl, rfl⟩ := local_eval m134 r3
    obtain ⟨_, uv, sU, more4, -, r4, n4, rfl⟩ := exprs_cons_inv n3
    obtain ⟨rfl, rfl⟩ := exprs_nil_inv n4
    obtain ⟨jU, doneU, cU, bodyU, resultU, rfl⟩ := call_locals [(137, bv)] fn_unbox (by simpa using m137) r4
    obtain ⟨viewsU, -⟩ := execStmt_grows bodyU (Same.start inv2 _).views
    simp only [write_one_params] at body4
    obtain ⟨-, grow4⟩ := execStmt_grows body4 viewsU
    obtain ⟨w, hw, rw, invU, stepU⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims jU fn_unbox
      (by decide +kernel) rfl inv2 (show doneU.heap.nextAddress ≤ 2 ^ 64 from Nat.le_trans grow4 bound)
      (.cons (heapE ▸ rbox) .nil) bodyU resultU
    obtain rfl := pcall_unbox hw
    obtain ⟨d1, d2, d3, d4, d5, d6⟩ := write_one_body roomLt ih (invU.restore _)
      (show done4.heap.nextAddress ≤ 2 ^ 64 from bound) (stepU.reads.readable (heapE ▸ readable)) rw rrest
      body4 result4
    exact ⟨d1, d2, d3, stepE.cells.trans ((Step.bindLocals _ s1).cells.trans (stepU.cells.trans d4)),
      (d5.restore _).restore _, d6⟩
/-! ## The result -/

theorem fn_put : prog.funcs[2]? = some (src_app_main_oracle_put 3) := get_of_drop at_app_main_oracle_put

theorem put_params (a b : Value) : paramBindings (src_app_main_oracle_put 3).params [a, b] = [(11, a), (23, b)] := rfl

theorem vrel_ty3 {h : Memory.Heap} {rv rp : Value} (rel : VRel prog.toCore boxes h ty3 rv rp) :
    ∃ k vs ps fs, rv = .enumeration 2 k vs ∧ rp = .enumeration 2 k ps ∧
      ([[ty1], []] : List (List SrcType))[k]? = some fs ∧ VRels prog.toCore boxes h fs vs ps := by
  cases rel with
  | scalar st => exact st.elim
  | enum hk rs => exact ⟨_, _, _, _, rfl, rfl, hk, rs⟩

theorem callResult_i32 {c : Completion} {v : Value} (h : CallResult .i32 c v) : c = .returned (some v) := by
  cases c with
  | next => exact absurd h.1 (by simp)
  | returned r =>
    cases r with
    | none => exact absurd h.1 (by simp)
    | some w => rw [show v = w from h]
  | breakLoop => exact h.elim
  | continueLoop => exact h.elim

theorem wrap_i32 {n : Nat} (lt : n < 2 ^ 31) : Semantics.wrapSigned .x86_64 .i32 (n : Int) = n := by
  change (if (n : Int) % 4294967296 ≥ 2147483648 then (n : Int) % 4294967296 - 4294967296
    else (n : Int) % 4294967296) = n
  rw [if_neg (by omega)]
  omega

/-- What the driver returns for the compiler's result `r`: -1 for `none`; for
`some ws`, the length of `ws`, with the output view reading `ws`. -/
def Result (r : Option (List (BitVec 32))) (v : Value) (st : State) (outp room : Nat) : Prop :=
  match r with
  | none => v = .signed .i32 (-1)
  | some ws => v = .signed .i32 ws.length ∧ Written st outp room 0 ws

theorem Result.heap {r : Option (List (BitVec 32))} {v : Value} {a b : State} {outp room : Nat}
    (h : a.heap = b.heap) (out : Result r v a outp room) : Result r v b outp room := by
  cases r with
  | none => exact out
  | some ws => exact ⟨out.1, fun i hi => (readRaw_heap h.symm).trans (out.2 i hi)⟩

/-- `oracle_put(out, result)`'s body: -1 for `None`; for `Some(ws)`, the
length of `ws`, with the output reading `ws`. -/
theorem put_body {outp room : Nat} (roomLt : room < 2 ^ 31) {k : Nat} {s completed : State} {c : Completion}
    {v rv rp : Value} {r : Option (List (BitVec 32))}
    (inv : Inv s) (bound : completed.heap.nextAddress ≤ 2 ^ 64) (readable : s.heap.Readable outp (room * 4))
    (rel : VRel prog.toCore boxes s.heap ty3 rv rp) (rep : (RepOption 2 (RepList 0 RepI32)) r rp)
    (run : execStmt k prog.toCore (({ s with locals := [] } : State).bindLocals
      [(11, .rawSlice i32T outp room), (23, rv)]) (src_app_main_oracle_put 3).body.toCore = .done c completed)
    (result : CallResult .i32 c v) : Result r v completed outp room := by
  generalize hE : ({ s with locals := [] } : State).bindLocals [(11, .rawSlice i32T outp room), (23, rv)] = E at run
  have invE : Inv E := by rw [← hE]; exact Same.start inv _
  have heapE : E.heap = s.heap := by rw [← hE]; rfl
  have l11 : E.local? 11 = some (.rawSlice i32T outp room) := by
    rw [← hE]; exact local?_entry inv [] [(23, rv)] 11 _ rfl (by simp)
  have l23 : E.local? 23 = some rv := by
    rw [← hE]; exact local?_entry inv [(11, .rawSlice i32T outp room)] [] 23 _ rfl (by simp)
  simp only [src_app_main_oracle_put, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcEff.coreArms,
    SrcExpr.toCore, SrcType.typeId, SrcType.toScalar, SrcOp.toCore, ty3, List.map] at run
  obtain ⟨j1, mv, -, mrun, rfl⟩ := return_inv run
  have hv := callResult_i32 result
  simp only [Completion.returned.injEq, Option.some.injEq] at hv
  subst hv
  obtain ⟨j2, sv, s1, -, srun, arms⟩ := matchValue_inv mrun
  obtain ⟨rfl, rfl⟩ := local_eval l23 srun
  obtain ⟨kk, vs, ps, fs, rfl, hp, hk, rs⟩ := vrel_ty3 rel
  cases rep with
  | none =>
    simp only [Value.enumeration.injEq, true_and] at hp
    obtain ⟨rfl, rfl⟩ := hp
    simp only [List.getElem?_cons_succ, List.getElem?_cons_zero, Option.some.injEq] at hk
    subst hk
    cases rs
    obtain ⟨j3, -, hit⟩ := arms_cons_inv arms
    obtain ⟨-, arms2⟩ := hit.resolve_right (fun ⟨_, _, hbs, _⟩ => by simp [Semantics.matchPattern] at hbs)
    obtain ⟨j4, -, hit2⟩ := arms_cons_inv arms2
    rcases hit2 with ⟨miss, -⟩ | ⟨bs, s2, hbs, body, rfl⟩
    · simp [Semantics.matchPattern, Semantics.matchPatterns] at miss
    simp only [Semantics.matchPattern, Semantics.matchPatterns, beq_self_eq_true, Bool.and_self, if_true,
      Option.some.injEq] at hbs
    subst hbs
    obtain ⟨_, l, s3, r', -, rl, rr, op⟩ := binary_inv (by decide) (by decide) body
    obtain ⟨rfl, rfl⟩ := value_inv rl
    obtain ⟨rfl, rfl⟩ := value_inv rr
    rw [toCore_target'] at op
    have : Semantics.evalBinaryValue .x86_64 .subtract (.signed .i32 (0#32).toInt) (.signed .i32 (1#32).toInt) =
        .ok (.signed .i32 (-1)) := by
      simp only [Semantics.evalBinaryValue, beq_self_eq_true, if_true, Semantics.evalSignedBinary]
      rfl
    rw [this, Except.ok.injEq] at op
    exact op.symm
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
    obtain ⟨j3, -, hit⟩ := arms_cons_inv arms
    rcases hit with ⟨miss, -⟩ | ⟨bs, s2, hbs, body, rfl⟩
    · simp [Semantics.matchPattern, Semantics.matchPatterns] at miss
    simp only [Semantics.matchPattern, Semantics.matchPatterns, beq_self_eq_true, Bool.and_self, if_true,
      List.append_nil, Option.some.injEq] at hbs
    subst hbs
    have m11 : (s1.bindLocals [(153, lv)]).local? 11 = some (.rawSlice i32T outp room) :=
      local?_bindLocals_other _ (by simp) l11
    have m153 : (s1.bindLocals [(153, lv)]).local? 153 = some lv := local?_bindLocal_self invE _ _
    obtain ⟨j4, wv, -, crun, castOk⟩ := cast_inv body
    obtain ⟨j5, f3, values, afterArgs, done3, c3, -, argsRun, found3, len3, body3, result3, rfl⟩ := call_inv' crun
    rw [fn_write, Option.some.injEq] at found3
    subst found3
    obtain ⟨_, a1, t1, more1, -, r1, n1, rfl⟩ := exprs_cons_inv argsRun
    obtain ⟨rfl, rfl⟩ := local_eval m11 r1
    obtain ⟨_, a2, t2, more2, -, r2, n2, rfl⟩ := exprs_cons_inv n1
    obtain ⟨rfl, rfl⟩ := value_inv r2
    obtain ⟨_, a3, t3, more3, -, r3, n3, rfl⟩ := exprs_cons_inv n2
    obtain ⟨rfl, rfl⟩ := local_eval m153 r3
    obtain ⟨rfl, rfl⟩ := exprs_nil_inv n3
    simp only [write_params, show (0#64).toNat = 0 from rfl] at body3
    obtain ⟨d1, d2, d3, -, -, -⟩ := write_body roomLt ws (invE.bindLocals _)
      (show done3.heap.nextAddress ≤ 2 ^ 64 from bound) (heapE ▸ readable) (heapE ▸ rl) rws body3 result3
    subst d1
    have lenLt : ws.length < 2 ^ 31 := by rcases d2 with rfl | h <;> simp <;> omega
    simp only [toCore_target', Semantics.evalScalarCast, Nat.zero_add, Int.ofNat_eq_natCast, wrap_i32 lenLt,
      Except.ok.injEq] at castOk
    subst castOk
    exact ⟨rfl, d3⟩

/-! ## The driver -/

theorem fn_w : prog.funcs[0]? = some (src_app_main_w 1 2 5 6 7 8) := get_of_drop at_app_main_w

theorem w_params (a b c d : Value) :
    paramBindings (src_app_main_w 1 2 5 6 7 8).params [a, b, c, d] = [(2, a), (14, b), (26, c), (39, d)] := rfl

/-- **The driver.** A run of `w(input, words, output, room)` that completes,
on an input view reading `W` and an output view of `room` words, returns
what `Result` says for `compileWords (frontEndWords grammar W)`. -/
theorem driver_faithful {fuel : Nat} {st st' : State} {v : Value} {inp outp room : Nat} {W : List (BitVec 32)}
    (inv : Inv st) (bound : st'.heap.nextAddress ≤ 2 ^ 64) (wordsLt : W.length < 2 ^ 31) (roomLt : room < 2 ^ 31)
    (input : Reads st inp W) (output : st.heap.Readable outp (room * 4))
    (run : evalExpr fuel prog.toCore st (.call 0 [.value (.pointer inp), .value (.signed .i32 W.length),
      .value (.pointer outp), .value (.signed .i32 room)]) = .done v st') :
    Result (compileWords (frontEndWords grammar W)) v st' outp room := by
  obtain ⟨j0, f0, values, afterArgs, done0, c0, -, argsRun, found0, -, body0, result0, rfl⟩ := call_inv' run
  rw [fn_w, Option.some.injEq] at found0
  subst found0
  obtain ⟨rfl, hst⟩ := values_eval [.pointer inp, .signed .i32 W.length, .pointer outp, .signed .i32 room] argsRun
  subst afterArgs
  simp only [w_params] at body0
  generalize hE : ({ st with locals := [] } : State).bindLocals [(2, .pointer inp), (14, .signed .i32 W.length),
    (26, .pointer outp), (39, .signed .i32 room)] = E at body0
  have invE : Inv E := by rw [← hE]; exact Same.start inv _
  have stepE : Step st E := by rw [← hE]; exact (Step.clear st).trans (Step.bindLocals _ _)
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
    SrcType.sliceFrom, SrcType.toScalar, UintTy.toCore] at body0
  -- The two views.
  obtain ⟨j1, sv1, s1, s2, -, slice1, rest1, rfl⟩ := letLocal_inv body0
  obtain ⟨_, a1, t1, len1, -, p1, n1, -, rfl⟩ := i32Slice_inv slice1
  obtain ⟨h1, e1⟩ := local_eval l2 p1
  cases h1
  subst t1
  obtain ⟨h2, e2⟩ := local_eval l14 n1
  cases h2
  subst s1
  obtain ⟨j2, sv2, s3, s4, -, slice2, rest2, rfl⟩ := letLocal_inv rest1
  obtain ⟨_, a2, t2, len2, -, p2, n2, -, rfl⟩ := i32Slice_inv slice2
  obtain ⟨h3, e3⟩ := local_eval (local?_bindLocal_other (by decide) _ l26) p2
  cases h3
  subst t2
  obtain ⟨h4, e4⟩ := local_eval (local?_bindLocal_other (by decide) _ l39) n2
  cases h4
  subst s3
  simp only [Int.toNat_natCast] at rest2
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
  -- `let read = oracle_read(data, 0, words as usize, empty())`
  obtain ⟨j3, lv, s5, s6, -, readRun, rest3, rfl⟩ := letLocal_inv rest2
  obtain ⟨j4, fR, valsR, afterR, doneR, cR, -, argsR, foundR, -, bodyR, resultR, rfl⟩ := call_inv' readRun
  rw [fn_read, Option.some.injEq] at foundR
  subst foundR
  obtain ⟨_, a3, t3, more3, -, r3, m3, rfl⟩ := exprs_cons_inv argsR
  obtain ⟨rfl, rfl⟩ := local_eval k67 r3
  obtain ⟨_, a4, t4, more4, -, r4, m4, rfl⟩ := exprs_cons_inv m3
  obtain ⟨rfl, rfl⟩ := value_inv r4
  obtain ⟨_, a5, t5, more5, -, r5, m5, rfl⟩ := exprs_cons_inv m4
  obtain ⟨_, cw, -, castRun, castOk⟩ := cast_inv r5
  obtain ⟨rfl, rfl⟩ := local_eval k14 castRun
  rw [toCore_target', cast_usize_int (by omega) (by omega), Except.ok.injEq] at castOk
  subst castOk
  obtain ⟨_, a6, t6, more6, -, r6, m6, rfl⟩ := exprs_cons_inv m5
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv m6
  obtain ⟨j5, fE, valsE, afterE, doneE, cE, -, argsE, foundE, lenE, bodyE, resultE, rfl⟩ := call_inv' r6
  rw [fn_empty_of_i32, Option.some.injEq] at foundE
  subst foundE
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv argsE
  simp only [read_params, show (0#64).toNat = 0 from rfl, Int.toNat_natCast] at bodyR
  -- `return oracle_put(out, compile_words(front_end_words(grammar(), read)))`
  obtain ⟨j6, rv, -, putRun, rfl⟩ := return_inv rest3
  obtain ⟨j7, fP, valsP, afterP, doneP, cP, -, argsP, foundP, -, bodyP, resultP, rfl⟩ := call_inv' putRun
  rw [fn_put, Option.some.injEq] at foundP
  subst foundP
  obtain ⟨_, b1, u1, moreP, -, q1, n1, rfl⟩ := exprs_cons_inv argsP
  obtain ⟨f1, rfl⟩ := local_inv q1
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
  -- Each call's heap is below the next's, and the last is in range.
  obtain ⟨viewsE, -⟩ := execStmt_grows bodyE (Same.start inv2 _).views
  obtain ⟨viewsR, leR⟩ := execStmt_grows bodyR viewsE
  obtain ⟨viewsG, leG⟩ := execStmt_grows bodyG viewsR
  obtain ⟨viewsF, leF⟩ := execStmt_grows bodyF viewsG
  obtain ⟨viewsC, leC⟩ := execStmt_grows bodyC viewsF
  obtain ⟨-, leP⟩ := execStmt_grows bodyP viewsC
  have bC : doneC.heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans leP bound
  have bF : doneF.heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans leC bC
  have bG : doneG.heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans leF bF
  have bR : doneR.heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans leG bG
  have bE : doneE.heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans leR bR
  -- `empty()`, then `oracle_read`: the list of `W`.
  obtain ⟨we, hwe, rwe, invE', stepE'⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j5 fn_empty_of_i32
    (by decide +kernel) lenE inv2 bE .nil bodyE resultE
  have step2 : Step st ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)) :=
    stepE.trans ((Step.bindLocal _ _ _).trans (Step.bindLocal _ _ _))
  obtain ⟨p, relR, repR, invR, stepR⟩ := read_body (inp := inp) (W := W) (by omega) (W.length - 0) rfl
    (Nat.zero_le _) (Nat.le_refl _) (invE'.restore _) (input.step ((step2.trans stepE').restore _)) bR rwe
    (cert_empty_of_i32 hwe) bodyR resultR
  simp only [List.drop_zero, Nat.sub_zero, List.take_length, List.append_nil] at repR
  have stepR0 := (((step2.trans stepE').restore _).trans stepR).restore
    ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room))
  have invR0 := (invR.restore ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125
    (.rawSlice i32T outp room))).bindLocal 182 lv
  -- `grammar()`
  obtain ⟨wg, hwg, rwg, invG, stepG⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j10 fn_grammar
    (by decide +kernel) lenG invR0 bG .nil bodyG resultG
  obtain rfl : b5 = lv := Option.some.inj (f5.symm.trans (local?_prefix (st' := restoreLocals ((restoreLocals ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)) doneR).bindLocal 182 lv) doneG) stepG.cells rfl
    (local?_bindLocal_self (invR.restore _) 182 lv)))
  -- `front_end_words(grammar(), read)`
  obtain ⟨wf, hwf, rwf, invF, stepF⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j9 fn_front_end_words
    (by decide +kernel) lenF (invG.restore _) bF (.cons rwg (.cons (VRel.mono stepG.reads relR) .nil)) bodyF resultF
  -- `compile_words(..)`
  obtain ⟨wc, hwc, rwc, invC, stepC⟩ := func_sim SelfPure.selfPure SelfPure.selfPrims j8 fn_compile_words
    (by decide +kernel) lenC (invF.restore _) bC (.cons rwf .nil) bodyC resultC
  have repC := cert_compile_words hwc (cert_front_end_words hwf (cert_grammar hwg) repR)
  -- The output view is the local `out`, still there after the calls.
  obtain rfl : b1 = .rawSlice i32T outp room := Option.some.inj (f1.symm.trans (local?_bindLocal_other (by decide) _
    (local?_prefix (st' := restoreLocals ((E.bindLocal 67 (.rawSlice i32T inp W.length)).bindLocal 125 (.rawSlice i32T outp room)) doneR) ((stepE'.restore _).trans stepR).cells rfl k125)))
  have stepC' := (((((((step2.trans stepE').restore _).trans stepR).restore _).trans (Step.bindLocal _ _ _)).trans
    stepG).restore _).trans stepF |>.restore _ |>.trans stepC
  simp only [put_params] at bodyP
  have out := put_body roomLt (invC.restore _) (show doneP.heap.nextAddress ≤ 2 ^ 64 from bound) (stepC'.reads.readable output) rwc repC bodyP resultP
  have hv := callResult_i32 result0
  simp only [Completion.returned.injEq, Option.some.injEq] at hv
  subst hv
  exact Result.heap rfl out

#print axioms driver_faithful

/-- **The driver on source files.** On an input view reading the words of
files whose numbers fit (`filesWords`, `FilesFit`), a run of `w` that
completes returns what `Result` says for the words of `compileText`'s
binary: -1 when the verified compiler rejects the files, and otherwise the
length of the binary's words, with the output reading them. The words of
any input the driver accepts are the words of such files (`compileWords_some`). -/
theorem driver_files {fuel : Nat} {st st' : State} {v : Value} {inp outp room : Nat} {files : List SourceFile}
    (fit : FilesFit files) (inv : Inv st) (bound : st'.heap.nextAddress ≤ 2 ^ 64)
    (wordsLt : (filesWords files).length < 2 ^ 31) (roomLt : room < 2 ^ 31)
    (input : Reads st inp (filesWords files)) (output : st.heap.Readable outp (room * 4))
    (run : evalExpr fuel prog.toCore st (.call 0 [.value (.pointer inp), .value (.signed .i32 (filesWords files).length),
      .value (.pointer outp), .value (.signed .i32 room)]) = .done v st') :
    Result (binaryWords (compileText files)) v st' outp room := by
  rw [← compileWords_files fit]
  exact driver_faithful inv bound wordsLt roomLt input output run

#print axioms driver_files

end Lanius.Faithful.SelfDriver
