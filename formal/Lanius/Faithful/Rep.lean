module

public import Lanius.Faithful.Simp

@[expose] public section

/-! # Representations

How a Lean value of an extracted type is a value of the pure semantics: one
inductive relation per type, `Rep..`, whose constructors are `rep_rule`s, so
`rep` builds a representation and `cases` takes one apart. The scalars and
the prelude's generic types are here; each program's structs and enums get
theirs from `formal/tools/faithful_certs.py`. A `List` or `Option` takes the
enum id of its instance in the program, and the element's relation. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)

/-- A `usize` that fits. Lean's `Nat` has no bound; the prelude's `plus`,
`minus` and `times` panic rather than leave it. The bound is `2 ^ 64` as
`pure_simp` writes it. -/
inductive RepNat : Nat → Value → Prop where
  | mk {n : Nat} : n < 18446744073709551616 → RepNat n (.unsigned .usize n)

inductive RepU64 : BitVec 64 → Value → Prop where
  | mk (x : BitVec 64) : RepU64 x (.unsigned .u64 x.toNat)

inductive RepU32 : BitVec 32 → Value → Prop where
  | mk (x : BitVec 32) : RepU32 x (.unsigned .u32 x.toNat)

inductive RepI32 : BitVec 32 → Value → Prop where
  | mk (x : BitVec 32) : RepI32 x (.signed .i32 x.toInt)

inductive RepU8 : UInt8 → Value → Prop where
  | mk (x : UInt8) : RepU8 x (.unsigned .u8 x.toNat)

inductive RepBool : Bool → Value → Prop where
  | mk (b : Bool) : RepBool b (.boolean b)

/-- `Nil` is variant 0, `Cons(x, rest)` variant 1 (the `Box` is the list). -/
inductive RepList {α : Type} (id : Nat) (r : α → Value → Prop) : List α → Value → Prop where
  | nil : RepList id r [] (.enumeration id 0 [])
  | cons {x : α} {xs : List α} {vx vxs : Value} :
      r x vx → RepList id r xs vxs → RepList id r (x :: xs) (.enumeration id 1 [vx, vxs])

/-- core::option's `Some(x)` is variant 0, `None` variant 1. -/
inductive RepOption {α : Type} (id : Nat) (r : α → Value → Prop) : Option α → Value → Prop where
  | some {x : α} {v : Value} : r x v → RepOption id r (some x) (.enumeration id 0 [v])
  | none : RepOption id r none (.enumeration id 1 [])

attribute [rep_rule] RepNat.mk RepU64.mk RepU32.mk RepI32.mk RepU8.mk RepBool.mk RepList.nil RepList.cons
  RepOption.some RepOption.none

/-- A `usize` the pure semantics computed as some other term of the same
number (`rep` proves the equation with `omega`). -/
theorem RepNat.of_eq {t e : Nat} (h : e = t) (b : t < 18446744073709551616) : RepNat t (.unsigned .usize e) :=
  h ▸ RepNat.mk (h ▸ b)

/-- A literal byte or `u32`: the pure value is the number. -/
theorem RepU8.lit {n : Nat} (b : n < 256) : RepU8 (UInt8.ofNat n) (.unsigned .u8 n) := by
  have := RepU8.mk (UInt8.ofNat n)
  rwa [show (UInt8.ofNat n).toNat = n by simp [Nat.mod_eq_of_lt b]] at this

theorem RepU32.lit {n : Nat} (b : n < 4294967296) : RepU32 (BitVec.ofNat 32 n) (.unsigned .u32 n) := by
  have := RepU32.mk (BitVec.ofNat 32 n)
  rwa [show (BitVec.ofNat 32 n).toNat = n by simp [BitVec.toNat_ofNat, Nat.mod_eq_of_lt b]] at this

@[rep_rule] theorem lt_pow64 {n : Nat} (h : Nat.blt n 18446744073709551616 = true) : n < 18446744073709551616 :=
  Nat.blt_eq.mp h

/-- A prim's certificate: `boxed` and `unbox` give back their argument. -/
theorem prim_cert {sp : SrcProgram} {prims : Prims} {c n : Nat} {α : Type} {r : α → Value → Prop} {x : α}
    {v w : Value} (prim : prims.isPrim c = true) (h : pcall sp prims n c [v] = some w) (hr : r x v) : r x w := by
  rcases n with _ | n
  · simp [pcall] at h
  · have : w = v := by simpa [pcall, prim, single] using h.symm
    exact this ▸ hr

end Lanius.Faithful
