import Lanius.Faithful.SelfPanics
import Lanius.Faithful.Sim.Agree

/-! # `progW`'s runs without wrapping are the self program's runs

`progW` (`SelfPanics.lean`) is the self program with the prelude's `plus`
and `times` replaced by their wrapping operators. Where a call of `plus` or
`times` has `usize` arguments whose sum or product is below `2 ^ 64`
(`safeW`), the wrapped body and the prelude's give the same value: the
prelude's overflow check fails, so it does not call `panic`. So a run of
`progW` in which no such call wraps (`pcallG progW prims safeW`) is a run of
the self program with the same fuel and value (`pcall_of_safe`). -/

namespace Lanius.Faithful.SelfAgree

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfCert
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfPanics
open Lanius.Faithful.Termination

/-- `op a b` of two `usize` arguments `a` and `b` is below `2 ^ 64`. -/
def NoWrap (op : Nat → Nat → Nat) (vs : List Value) : Prop :=
  ∃ a b, vs = [.unsigned .usize a, .unsigned .usize b] ∧ op a b < 2 ^ 64

/-- A call of `plus` or `times` does not wrap; any other call is safe. -/
def safeW (c : Nat) (vs : List Value) : Prop :=
  (c = SelfPure.ixPlus → NoWrap (· + ·) vs) ∧ (c = SelfPure.ixTimes → NoWrap (· * ·) vs)

theorem plus_body (call : Calls) {a b : Nat} (h : a + b < 2 ^ 64) :
    (pstmt call (paramEnv (src_plus 50).params [.unsigned .usize a, .unsigned .usize b]) (src_plus 50).body).bind
      (doneValue (src_plus 50).ret) = some (.unsigned .usize (a + b)) := by
  simp [src_plus, pstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary, usize_add,
    unsigned_greater, asBool, SrcOp.toCore, Nat.mod_eq_of_lt h, Except.toOption]
  rw [if_neg (by omega)]
  rfl

theorem plus_wrapped (call : Calls) (a b : Nat) :
    (pstmt call (paramEnv (src_plus 50).params [.unsigned .usize a, .unsigned .usize b])
        (wrapFunc .plus (src_plus 50)).body).bind
      (doneValue (src_plus 50).ret) = some (.unsigned .usize ((a + b) % 2 ^ 64)) := by
  simp [src_plus, wrapFunc, pstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary,
    usize_add, SrcOp.toCore, Except.toOption]
  rfl

theorem times_body (call : Calls) {a b : Nat} (h : a * b < 2 ^ 64) :
    (pstmt call (paramEnv (src_times 50).params [.unsigned .usize a, .unsigned .usize b]) (src_times 50).body).bind
      (doneValue (src_times 50).ret) = some (.unsigned .usize (a * b)) := by
  by_cases a0 : a = 0
  · subst a0
    simp [src_times, pstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary,
      unsigned_equal, asBool, Done.then, doneValue, SrcOp.toCore, Except.toOption, UintTy.toCore]
    done
  · have hb : b < 2 ^ 64 := Nat.lt_of_le_of_lt (Nat.le_mul_of_pos_left b (Nat.pos_of_ne_zero a0)) h
    have hd : a * b / a = b := Nat.mul_div_cancel_left b (Nat.pos_of_ne_zero a0)
    simp [src_times, pstmt, pexpr, peff, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary,
      unsigned_equal, unsigned_notEqual, usize_multiply, usize_divide, asBool, Done.then, doneValue, SrcOp.toCore,
      SrcDivOp.toCore, Except.toOption, UintTy.toCore, a0, Nat.mod_eq_of_lt h, hd,
      Nat.mod_eq_of_lt hb]
    done

theorem times_wrapped (call : Calls) (a b : Nat) :
    (pstmt call (paramEnv (src_times 50).params [.unsigned .usize a, .unsigned .usize b])
        (wrapFunc .times (src_times 50)).body).bind
      (doneValue (src_times 50).ret) = some (.unsigned .usize (a * b % 2 ^ 64)) := by
  simp [src_times, wrapFunc, pstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary,
    usize_multiply, SrcOp.toCore, Except.toOption]
  rfl

/-- `plus` in the self program agrees with `progW`'s where it does not wrap. -/
theorem agrees_plus : Agrees prog (wrapAt prog SelfPure.ixPlus .plus) safeW := by
  refine agrees_wrapAt fun f hf vs hs call call' v _ hv => ?_
  rw [show SelfPure.ixPlus = 75 from rfl, fn_plus] at hf
  cases hf
  obtain ⟨a, b, rfl, h⟩ := hs.1 rfl
  have hw : (pstmt call (paramEnv (src_plus 50).params [.unsigned .usize a, .unsigned .usize b])
      (wrapFunc .plus (src_plus 50)).body).bind (doneValue (src_plus 50).ret) =
        some (.unsigned .usize (a + b)) := by
    rw [plus_wrapped, Nat.mod_eq_of_lt h]
  rw [hw] at hv
  cases hv
  exact plus_body call' h

/-- `times` likewise, in `progW`'s first step. -/
theorem agrees_times :
    Agrees (wrapAt prog SelfPure.ixPlus .plus) progW safeW := by
  refine agrees_wrapAt fun f hf vs hs call call' v _ hv => ?_
  rw [wrapAt_ne plus_ne_times, show SelfPure.ixTimes = 105 from rfl, fn_times] at hf
  cases hf
  obtain ⟨a, b, rfl, h⟩ := hs.2 rfl
  have hw : (pstmt call (paramEnv (src_times 50).params [.unsigned .usize a, .unsigned .usize b])
      (wrapFunc .times (src_times 50)).body).bind (doneValue (src_times 50).ret) =
        some (.unsigned .usize (a * b)) := by
    rw [times_wrapped, Nat.mod_eq_of_lt h]
  rw [hw] at hv
  cases hv
  exact times_body call' h

theorem agreesW : Agrees prog progW safeW := agrees_trans agrees_plus agrees_times

/-- **A run of `progW` in which no `plus` or `times` wraps is a run of the
self program**, with the same fuel and value. -/
theorem pcall_of_safe {n c : Nat} {vs : List Value} {v : Value}
    (h : pcallG progW prims safeW n c vs = some v) : pcall prog prims n c vs = some v :=
  pcall_of_pcallG agreesW n h

/-! ## Costs: the bodies of `plus` and `times` cost nothing -/

theorem qplus_body (call : QCalls) {a b : Nat} (h : a + b < 2 ^ 64) :
    qthen (qstmt call (paramEnv (src_plus 50).params [.unsigned .usize a, .unsigned .usize b]) (src_plus 50).body)
      (fun d => qfree (doneValue (src_plus 50).ret d)) = some (.unsigned .usize (a + b), 0) := by
  simp [src_plus, qstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary, usize_add,
    unsigned_greater, asBool, SrcOp.toCore, Nat.mod_eq_of_lt h, Except.toOption, qthen, addC, qfree]
  rw [if_neg (by omega)]
  rfl

theorem qplus_wrapped (call : QCalls) (a b : Nat) :
    qthen (qstmt call (paramEnv (src_plus 50).params [.unsigned .usize a, .unsigned .usize b])
        (wrapFunc .plus (src_plus 50)).body)
      (fun d => qfree (doneValue (src_plus 50).ret d)) = some (.unsigned .usize ((a + b) % 2 ^ 64), 0) := by
  simp [src_plus, wrapFunc, qstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary,
    usize_add, SrcOp.toCore, Except.toOption, qthen, addC, qfree]
  rfl

theorem qtimes_body (call : QCalls) {a b : Nat} (h : a * b < 2 ^ 64) :
    qthen (qstmt call (paramEnv (src_times 50).params [.unsigned .usize a, .unsigned .usize b]) (src_times 50).body)
      (fun d => qfree (doneValue (src_times 50).ret d)) = some (.unsigned .usize (a * b), 0) := by
  by_cases a0 : a = 0
  · subst a0
    simp [src_times, qstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary,
      unsigned_equal, asBool, Done.qthen, doneValue, SrcOp.toCore, Except.toOption, UintTy.toCore, qthen, addC, qfree]
    done
  · have hb : b < 2 ^ 64 := Nat.lt_of_le_of_lt (Nat.le_mul_of_pos_left b (Nat.pos_of_ne_zero a0)) h
    have hd : a * b / a = b := Nat.mul_div_cancel_left b (Nat.pos_of_ne_zero a0)
    simp [src_times, qstmt, pexpr, qeff, qbinary, qapplyOp, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp,
      binary, unsigned_equal, unsigned_notEqual, usize_multiply, usize_divide, asBool, Done.qthen, doneValue,
      SrcOp.toCore, SrcDivOp.toCore, Except.toOption, UintTy.toCore, a0, Nat.mod_eq_of_lt h, hd,
      Nat.mod_eq_of_lt hb, qthen, addC, qfree]
    done

theorem qtimes_wrapped (call : QCalls) (a b : Nat) :
    qthen (qstmt call (paramEnv (src_times 50).params [.unsigned .usize a, .unsigned .usize b])
        (wrapFunc .times (src_times 50)).body)
      (fun d => qfree (doneValue (src_times 50).ret d)) = some (.unsigned .usize (a * b % 2 ^ 64), 0) := by
  simp [src_times, wrapFunc, qstmt, pexpr, paramEnv, paramBindings, Env.bindAll, Env.get?, applyOp, binary,
    usize_multiply, SrcOp.toCore, Except.toOption, qthen, addC, qfree]
  rfl

theorem qagrees_plus : QAgrees prog (wrapAt prog SelfPure.ixPlus .plus) safeW := by
  refine qagrees_wrapAt fun f hf vs hs call call' p _ hv => ?_
  rw [show SelfPure.ixPlus = 75 from rfl, fn_plus] at hf
  cases hf
  obtain ⟨a, b, rfl, h⟩ := hs.1 rfl
  rw [qplus_wrapped, Nat.mod_eq_of_lt h] at hv
  cases hv
  exact qplus_body call' h

theorem qagrees_times : QAgrees (wrapAt prog SelfPure.ixPlus .plus) progW safeW := by
  refine qagrees_wrapAt fun f hf vs hs call call' p _ hv => ?_
  rw [wrapAt_ne plus_ne_times, show SelfPure.ixTimes = 105 from rfl, fn_times] at hf
  cases hf
  obtain ⟨a, b, rfl, h⟩ := hs.2 rfl
  rw [qtimes_wrapped, Nat.mod_eq_of_lt h] at hv
  cases hv
  exact qtimes_body call' h

theorem qagreesW : QAgrees prog progW safeW := qagrees_trans qagrees_plus qagrees_times

/-- **Where no `plus` or `times` of a `progW` run wraps, the self program has
the run's value at the same heap cost.** -/
theorem qcall_of_safe (cost : Nat → Nat) {n c : Nat} {vs : List Value} {v : Value}
    (h : pcallG progW prims safeW n c vs = some v) :
    ∃ k, qcall prog prims cost n c vs = some (v, k) ∧ qcall progW prims cost n c vs = some (v, k) :=
  qcall_both qagreesW h

end Lanius.Faithful.SelfAgree
