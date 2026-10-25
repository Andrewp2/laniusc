import Lanius.Faithful.Pure
import Lanius.Faithful.Gen.Self
import Lanius.Faithful.Simp

set_option linter.unusedSimpArgs false

namespace Lanius.Faithful.Pilot

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Semantics (evalBinaryValue)

def selfPrims : Prims :=
  { boxed := [53, 54, 55, 67, 105, 109, 121, 166, 221, 228, 253, 270, 326, 341, 342, 343, 344, 346, 348, 370, 375, 389, 512, 551, 585, 586, 712, 714, 742, 743, 751, 789, 804, 851, 853, 886, 904, 906, 909, 996, 1014, 1015, 1098, 1110, 1123, 1127, 1174, 1191, 1373, 1536, 1590, 1621, 1642],
    unbox := [18, 20, 59, 63, 68, 75, 106, 110, 124, 143, 145, 169, 223, 225, 278, 315, 319, 325, 328, 332, 345, 347, 351, 366, 382, 403, 405, 536, 542, 544, 588, 592, 593, 601, 615, 644, 658, 662, 734, 735, 791, 810, 901, 903, 938, 1069, 1105, 1108, 1405, 1489, 1582, 1589, 1618] }

/-! ## Representations -/

def RepNat (n : Nat) (v : Value) : Prop := v = .unsigned .usize n ∧ n < 2 ^ 64

@[rep_rule] theorem RepNat.mk {n : Nat} (h : n < 2 ^ 64) : RepNat n (.unsigned .usize n) := ⟨rfl, h⟩
@[rep_rule] theorem lt_pow64 {n : Nat} (h : Nat.blt n (2 ^ 64) = true) : n < 2 ^ 64 := Nat.blt_eq.mp h

def RepU64 (x : BitVec 64) (v : Value) : Prop := v = .unsigned .u64 x.toNat

@[rep_rule] theorem RepU64.mk (x : BitVec 64) : RepU64 x (.unsigned .u64 x.toNat) := rfl

def RepList {α : Type} (id : Nat) (r : α → Value → Prop) : List α → Value → Prop
  | [], v => v = .enumeration id 0 []
  | x :: xs, v => ∃ vx vxs, v = .enumeration id 1 [vx, vxs] ∧ r x vx ∧ RepList id r xs vxs

@[rep_rule] theorem RepList.nil {α : Type} {id : Nat} {r : α → Value → Prop} :
    RepList id r [] (.enumeration id 0 []) := rfl
@[rep_rule] theorem RepList.cons {α : Type} {id : Nat} {r : α → Value → Prop} {x : α} {xs : List α}
    {vx vxs : Value} (hx : r x vx) (hxs : RepList id r xs vxs) :
    RepList id r (x :: xs) (.enumeration id 1 [vx, vxs]) := ⟨vx, vxs, rfl, hx, hxs⟩

def RepWord : Word → Value → Prop
  | .s32, v => v = .enumeration 6 0 []
  | .u64, v => v = .enumeration 6 1 []

def RepBinOp : BinOp → Value → Prop
  | .add, v => v = .enumeration 7 0 []
  | .sub, v => v = .enumeration 7 1 []
  | .mul, v => v = .enumeration 7 2 []
  | .and, v => v = .enumeration 7 3 []
  | .or, v => v = .enumeration 7 4 []
  | .xor, v => v = .enumeration 7 5 []
  | .shl, v => v = .enumeration 7 6 []
  | .shr, v => v = .enumeration 7 7 []
  | .sar, v => v = .enumeration 7 8 []

def RepCmpOp : CmpOp → Value → Prop
  | .eq, v => v = .enumeration 8 0 []
  | .ne, v => v = .enumeration 8 1 []
  | .lt, v => v = .enumeration 8 2 []
  | .le, v => v = .enumeration 8 3 []
  | .gt, v => v = .enumeration 8 4 []
  | .ge, v => v = .enumeration 8 5 []

def RepExpr : Expr → Value → Prop
  | .lit x, v => ∃ v0, v = .enumeration 104 0 [v0] ∧ RepU64 x v0
  | .var i, v => ∃ v0, v = .enumeration 104 1 [v0] ∧ RepNat i v0
  | .neg e, v => ∃ v0, v = .enumeration 104 2 [v0] ∧ RepExpr e v0
  | .binary w op l r, v => ∃ v0 v1 v2 v3, v = .enumeration 104 3 [v0, v1, v2, v3] ∧ RepWord w v0 ∧
      RepBinOp op v1 ∧ RepExpr l v2 ∧ RepExpr r v3
  | .compare w op l r, v => ∃ v0 v1 v2 v3, v = .enumeration 104 4 [v0, v1, v2, v3] ∧ RepWord w v0 ∧
      RepCmpOp op v1 ∧ RepExpr l v2 ∧ RepExpr r v3

/-- Only the constructors `compile_expr` builds, for the pilot. -/
def RepInstr : Instr → Value → Prop
  | .imm x, v => ∃ v0, v = .enumeration 5 0 [v0] ∧ RepU64 x v0
  | .load i, v => ∃ v0, v = .enumeration 5 1 [v0] ∧ RepNat i v0
  | .store i, v => ∃ v0, v = .enumeration 5 2 [v0] ∧ RepNat i v0
  | .neg, v => v = .enumeration 5 3 []
  | .op w op s, v => ∃ v0 v1 v2, v = .enumeration 5 4 [v0, v1, v2] ∧ RepWord w v0 ∧ RepBinOp op v1 ∧ RepNat s v2
  | .cmp w op s, v => ∃ v0 v1 v2, v = .enumeration 5 5 [v0, v1, v2] ∧ RepWord w v0 ∧ RepCmpOp op v1 ∧ RepNat s v2
  | _, _ => False

@[rep_rule] theorem RepInstr.imm {x : BitVec 64} {v0 : Value} (h0 : RepU64 x v0) :
    RepInstr (.imm x) (.enumeration 5 0 [v0]) := ⟨v0, rfl, h0⟩
@[rep_rule] theorem RepInstr.load {i : Nat} {v0 : Value} (h0 : RepNat i v0) :
    RepInstr (.load i) (.enumeration 5 1 [v0]) := ⟨v0, rfl, h0⟩
@[rep_rule] theorem RepInstr.store {i : Nat} {v0 : Value} (h0 : RepNat i v0) :
    RepInstr (.store i) (.enumeration 5 2 [v0]) := ⟨v0, rfl, h0⟩
@[rep_rule] theorem RepInstr.neg : RepInstr .neg (.enumeration 5 3 []) := rfl
@[rep_rule] theorem RepInstr.op {w : Word} {op : BinOp} {s : Nat} {v0 v1 v2 : Value} (h0 : RepWord w v0)
    (h1 : RepBinOp op v1) (h2 : RepNat s v2) : RepInstr (.op w op s) (.enumeration 5 4 [v0, v1, v2]) :=
  ⟨v0, v1, v2, rfl, h0, h1, h2⟩
@[rep_rule] theorem RepInstr.cmp {w : Word} {op : CmpOp} {s : Nat} {v0 v1 v2 : Value} (h0 : RepWord w v0)
    (h1 : RepCmpOp op v1) (h2 : RepNat s v2) : RepInstr (.cmp w op s) (.enumeration 5 5 [v0, v1, v2]) :=
  ⟨v0, v1, v2, rfl, h0, h1, h2⟩

/-! ## Facts about the program -/

@[pure_rule] theorem usize_add (a b : Nat) :
    evalBinaryValue target .add (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize ((a + b) % 2 ^ 64)) := rfl

@[pure_rule] theorem usize_greater (a b : Nat) :
    evalBinaryValue target .greater (.unsigned .usize a) (.unsigned .usize b) = .ok (.boolean (a > b)) := rfl

set_option maxRecDepth 100000 in
theorem fn792 : prog.funcs[792]? = some src792 := rfl
set_option maxRecDepth 100000 in
theorem fn1600 : prog.funcs[1600]? = some src1600 := rfl

@[pure_rule] theorem ty109_typeId : ty109.typeId = 104 := rfl
@[pure_rule] theorem ty8_typeId : ty8.typeId = 5 := rfl
@[pure_rule] theorem ty10_typeId : ty10.typeId = 4 := rfl
@[pure_rule] theorem ty58_typeId : ty58.typeId = 52 := rfl
@[pure_rule] theorem ty5_typeId : ty5.typeId = 9 := rfl

/-! ## Certificates -/

theorem cert82 {n : Nat} {vs : List Value} {w : Value} (h : pcall prog selfPrims n 82 vs = some w) : False := by
  rcases n with _ | n
  · simp [pcall] at h
  · rw [pcall_succ (c := 82) (f := src82) rfl rfl] at h
    simp [src82, pstmt, peff, pexpr, asBool] at h

theorem cert50 {n a b : Nat} {va vb v : Value}
    (h : pcall prog selfPrims n 50 [va, vb] = some v) (ra : RepNat a va) (rb : RepNat b vb) :
    RepNat (a + b) v := by
  obtain ⟨rfl, ha⟩ := ra
  obtain ⟨rfl, hb⟩ := rb
  rcases n with _ | n
  · simp [pcall] at h
  rw [pcall_succ (c := 50) (f := src50) rfl rfl] at h
  simp only [src50] at h
  pure_simp at h
  by_cases hc : a > (a + b) % 18446744073709551616
  · simp only [hc, decide_true, if_true, pcall_bind] at h
    destruct
    exact (cert82 (by assumption)).elim
  · simp only [hc, decide_false, Bool.false_eq_true, if_false, Option.some.injEq] at h
    subst h
    have : a + b < 2 ^ 64 := by omega
    exact ⟨by rw [Nat.mod_eq_of_lt this], this⟩

/-- A prim's certificate: `boxed` and `unbox` give back their argument. -/
theorem prim_cert {c n : Nat} {α : Type} {r : α → Value → Prop} {x : α} {v w : Value}
    (prim : selfPrims.isPrim c = true) (h : pcall prog selfPrims n c [v] = some w) (hr : r x v) : r x w := by
  rcases n with _ | n
  · simp [pcall] at h
  · have : w = v := by simpa [pcall, prim, single] using h.symm
    exact this ▸ hr

theorem cert592 {n : Nat} {e : Expr} {v w : Value} (h : pcall prog selfPrims n 592 [v] = some w)
    (r : RepExpr e v) : RepExpr e w := prim_cert rfl h r
theorem cert789 {n : Nat} {xs : List Instr} {v w : Value} (h : pcall prog selfPrims n 789 [v] = some w)
    (r : RepList 4 RepInstr xs v) : RepList 4 RepInstr xs w := prim_cert rfl h r
theorem cert791 {n : Nat} {xs : List Instr} {v w : Value} (h : pcall prog selfPrims n 791 [v] = some w)
    (r : RepList 4 RepInstr xs v) : RepList 4 RepInstr xs w := prim_cert rfl h r

set_option maxRecDepth 100000 in
theorem fn793 : prog.funcs[793]? = some src793 := rfl
set_option maxRecDepth 100000 in
theorem fn582 : prog.funcs[582]? = some src582 := rfl

theorem cert793 {n : Nat} {x : Instr} {v w : Value} (h : pcall prog selfPrims n 793 [v] = some w)
    (r : RepInstr x v) : RepList 4 RepInstr [x] w := by
  rcases n with _ | n
  · simp [pcall] at h
  rw [pcall_succ (c := 793) (f := src793) rfl fn793] at h
  simp only [src793] at h
  pure_simp at h
  destruct
  subst_vars
  certs Lanius.Faithful.Pilot
  rep

def Cert582 (n : Nat) : Prop :=
  ∀ {xs ys : List Instr} {vx vy w : Value}, pcall prog selfPrims n 582 [vx, vy] = some w →
    RepList 4 RepInstr xs vx → RepList 4 RepInstr ys vy → RepList 4 RepInstr (xs ++ ys) w

theorem cert582_all : ∀ n, Cert582 n := by
  intro n
  induction n with
  | zero => intro _ _ _ _ _ h; simp [pcall] at h
  | succ n ih582 =>
    intro xs ys vx vy w h rx ry
    rw [pcall_succ (c := 582) (f := src582) rfl fn582] at h
    simp only [src582] at h
    cases xs with
    | nil =>
      simp only [RepList] at rx
      subst_vars
      pure_simp at h
      subst_vars
      simpa using ry
    | cons x xs =>
      simp only [RepList] at rx
      destruct
      subst_vars
      pure_simp at h
      destruct
      subst_vars
      certs Lanius.Faithful.Pilot
      simp only [List.cons_append]
      rep

theorem cert582 {n : Nat} : Cert582 n := cert582_all n

def Cert792 (n : Nat) : Prop :=
  ∀ {base : Nat} {e : Expr} {depth : Nat} {vb ve vd w : Value},
    pcall prog selfPrims n 792 [vb, ve, vd] = some w → RepNat base vb → RepExpr e ve → RepNat depth vd →
      RepList 4 RepInstr (compileExpr base e depth) w

theorem cert792_all : ∀ n, Cert792 n := by
  intro n
  induction n with
  | zero => intro _ _ _ _ _ _ _ h; simp [pcall] at h
  | succ n ih792 =>
    intro base e depth vb ve vd w h rb re rd
    rw [pcall_succ (c := 792) (f := src792) rfl fn792] at h
    simp only [src792] at h
    simp only [RepNat] at rb rd
    destruct
    subst_vars
    cases e <;> simp only [RepExpr, RepU64, RepNat] at re <;> destruct <;> subst_vars <;> pure_simp at h <;>
      destruct <;> subst_vars <;> certs Lanius.Faithful.Pilot <;> simp only [compileExpr] <;> rep

end Lanius.Faithful.Pilot

#print axioms Lanius.Faithful.Pilot.cert792_all
