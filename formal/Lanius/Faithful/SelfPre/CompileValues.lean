import Lanius.Faithful.SelfPre.Values
import Lanius.Faithful.SelfPre.NB

/-! # Byte lists of the compile side (F14)

The compiler's encoders build long literal byte lists (`bumpBytes` has 42
literal bytes and two `le64`s). `post_auto` bounds each cons cell's height
by its own `omega` call over every cost atom so far, about a minute for one
such function; these lemmas let the hand proofs in `tools/pre_certs.py`
(`POST_HAND`, compile section) count lengths instead: a byte list is as high
as it is long, a list primitive's cost does not depend on its arguments and
is at least 1, and an `le32`/`le64` costs at least its 4/8 bytes. -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

theorem pc_hb_u8 : ∀ l : List UInt8, hb l = l.length
  | [] => rfl
  | a :: l => by simp only [hb_cons, hb_uint8, List.length_cons, pc_hb_u8 l]; omega

/-- A list primitive's cost, which does not depend on its arguments (a constant
of its own, so that `simp` does not take the rewrite for a permutation). -/
def pcCons (n : Nat) : Nat := Cost_cons_of_u8 n 0 []
def pcSingle (n : Nat) : Nat := Cost_single_of_u8 n 0
def pcLe64 (n : Nat) : Nat := Cost_le64 n 0
def pcLe32 (n : Nat) : Nat := Cost_le32 n 0

theorem pc_cons_u8 (n : Nat) (a : UInt8) (l : List UInt8) : Cost_cons_of_u8 n a l = pcCons n := by
  cases n <;> rfl

theorem pc_single_u8 (n : Nat) (a : UInt8) : Cost_single_of_u8 n a = pcSingle n := by
  cases n <;> rfl

theorem pc_cons_u8_pos (n : Nat) : 1 ≤ pcCons n := by
  cases n <;> simp only [pcCons, Cost_cons_of_u8] <;> omega

theorem pc_single_u8_pos (n : Nat) : 1 ≤ pcSingle n := by
  cases n <;> simp only [pcSingle, Cost_single_of_u8] <;> omega

theorem pc_len_le64 (v : BitVec 64) : (le64 v).length = 8 := rfl
theorem pc_len_le32 (v : BitVec 32) : (le32 v).length = 4 := rfl

theorem pc_le64 (n : Nat) (v : BitVec 64) : Cost_le64 n v = pcLe64 n := by
  rcases n with _ | n
  · rfl
  · simp only [pcLe64, Cost_le64, pc_cons_u8, pc_single_u8]

theorem pc_le32 (n : Nat) (v : BitVec 32) : Cost_le32 n v = pcLe32 n := by
  rcases n with _ | n
  · rfl
  · simp only [pcLe32, Cost_le32, pc_cons_u8, pc_single_u8]

theorem pc_le64_ge (n : Nat) (h : pcLe64 n < 18446744073709551616) : 8 ≤ pcLe64 n := by
  rcases n with _ | n
  · exact absurd h (Nat.lt_irrefl _)
  · simp only [pcLe64, Cost_le64, pc_cons_u8, pc_single_u8] at h ⊢
    have := pc_cons_u8_pos n
    have := pc_single_u8_pos n
    omega

theorem pc_le32_ge (n : Nat) (h : pcLe32 n < 18446744073709551616) : 4 ≤ pcLe32 n := by
  rcases n with _ | n
  · exact absurd h (Nat.lt_irrefl _)
  · simp only [pcLe32, Cost_le32, pc_cons_u8, pc_single_u8] at h ⊢
    have := pc_cons_u8_pos n
    have := pc_single_u8_pos n
    omega

/-! The encoder's small numbers (for `valueFacts`, as `val_<T>_<f>`). -/

theorem val_FloatTy_number (x : FloatTy) : FloatTy.number x ≤ 1 := by cases x <;> decide
theorem val_FArith_number (x : FArith) : FArith.number x ≤ 3 := by cases x <;> decide
theorem val_FCmp_number (x : FCmp) : FCmp.number x ≤ 2 := by cases x <;> decide
theorem val_Word_number (x : Word) : Word.number x ≤ 1 := by cases x <;> decide
theorem val_Word_prefix (x : Word) : Word.prefix x ≤ 1 := by cases x <;> decide
theorem val_MemWidth_prefix (x : MemWidth) : MemWidth.prefix x ≤ 1 := by cases x <;> decide
theorem val_FloatTy_rexSize (x : FloatTy) : FloatTy.rexSize x ≤ 1 := by cases x <;> decide
theorem val_BinOp_size (x : BinOp) : BinOp.size x ≤ 13 := by cases x <;> decide
theorem val_DivOp_size (x : DivOp) (w : Word) : DivOp.size x w ≤ 5 := by cases x <;> cases w <;> decide
theorem val_FOp_size (x : FOp) : FOp.size x ≤ 22 := by
  cases x <;> simp only [FOp.size] <;>
    first | omega | (rename_i a b; cases a <;> cases b <;> decide) | (rename_i a _; cases a <;> decide)
theorem val_FOp_number (x : FOp) : FOp.number x ≤ 19 := by
  cases x <;> simp only [FOp.number] <;>
    first | omega | (rename_i a b; cases a <;> cases b <;> decide)

end Lanius.Faithful.SelfPre
