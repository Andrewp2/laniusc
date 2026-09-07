import Lanius.Extraction.OutputPacking

namespace Lanius.Extraction.OutputPacking

open Lanius.Core Lanius.Semantics

/-- Unsigned value of the last unfinished word after processing a byte processed.
Completed words no longer participate in the next loop iteration. -/
def pendingBits : List UInt8 → Nat
  | [] => 0
  | [a] => a.toNat
  | [a, b] => a.toNat + b.toNat * 256
  | [a, b, c] => a.toNat + b.toNat * 256 + c.toNat * 65536
  | _ :: _ :: _ :: _ :: rest => pendingBits rest

theorem pendingBits_bound (processed : List UInt8) :
    pendingBits processed < 2 ^ (processed.length % 4 * 8) := by
  match processed with
  | [] => decide
  | [a] => simpa [pendingBits] using UInt8.toNat_lt a
  | [a, b] =>
      have ha := UInt8.toNat_lt a
      have hb := UInt8.toNat_lt b
      simp only [pendingBits, List.length_cons, List.length_nil]
      change a.toNat + b.toNat * 256 < 65536
      omega
  | [a, b, c] =>
      have ha := UInt8.toNat_lt a
      have hb := UInt8.toNat_lt b
      have hc := UInt8.toNat_lt c
      simp only [pendingBits, List.length_cons, List.length_nil]
      change a.toNat + b.toNat * 256 + c.toNat * 65536 < 16777216
      omega
  | a :: b :: c :: d :: rest =>
      have modulo : (rest.length + 1 + 1 + 1 + 1) % 4 = rest.length % 4 := by omega
      simpa only [pendingBits, List.length_cons, modulo] using pendingBits_bound rest
termination_by processed.length

theorem decode_four_eq_wrap (target : Target) (a b c d : UInt8) :
    decodeI32 [a, b, c, d] = wrapSigned target .i32
      (a.toNat + b.toNat * 256 + c.toNat * 65536 + d.toNat * 16777216 : Nat) := by
  let bits := a.toNat + b.toNat * 256 + c.toNat * 65536 + d.toNat * 16777216
  have ha := UInt8.toNat_lt a
  have hb := UInt8.toNat_lt b
  have hc := UInt8.toNat_lt c
  have hd := UInt8.toNat_lt d
  have bound : bits < 4294967296 := by dsimp [bits]; omega
  have modulo : (bits : Int) % 4294967296 = bits := by omega
  change (if bits ≥ 2147483648 then (bits : Int) - 4294967296 else bits) =
    (if (bits : Int) % 4294967296 ≥ 2147483648 then
      (bits : Int) % 4294967296 - 4294967296 else (bits : Int) % 4294967296)
  rw [modulo]
  by_cases high : bits ≥ 2147483648
  · have highInt : (bits : Int) ≥ 2147483648 := by omega
    simp [high, highInt]
  · have highInt : ¬ (bits : Int) ≥ 2147483648 := by omega
    simp [high, highInt]

/-- Loop invariant for the reused parser workspace: packed processed bytes,
zeroed future output words, and an untouched remainder of the allocation. -/
def workspace (words : Nat) (processed : List UInt8) (tail : List Value) : List Value :=
  pack processed ++ List.replicate (words - (pack processed).length) (.signed .i32 0) ++ tail

theorem workspace_four (words : Nat) (a b c d : UInt8)
    (rest : List UInt8) (tail : List Value) :
    workspace (words + 1) (a :: b :: c :: d :: rest) tail =
      .signed .i32 (decodeI32 [a, b, c, d]) :: workspace words rest tail := by
  simp [workspace, pack]

/-- The array update performed by one packing iteration establishes the next
processed invariant. This includes all four lane transitions and crossing into
the next word; no completed word or unused tail is changed. -/
theorem workspace_insert_byte
    (target : Target) (words : Nat) (processed : List UInt8) (byte : UInt8)
    (tail : List Value) (room : (processed.length + 4) / 4 ≤ words) :
    setValue (workspace words processed tail) (processed.length / 4)
      (.signed .i32 (wrapSigned target .i32
        (pendingBits processed + byte.toNat * 2 ^ (processed.length % 4 * 8) : Nat))) =
      workspace words (processed ++ [byte]) tail := by
  match processed with
  | [] =>
      cases words with
      | zero => simp at room
      | succ words =>
          simp [workspace, pack, pendingBits, List.replicate_succ, setValue,
            decode_four_eq_wrap target]
  | [a] =>
      cases words with
      | zero => simp at room
      | succ words =>
          simp [workspace, pack, pendingBits, setValue, decode_four_eq_wrap target]
  | [a, b] =>
      cases words with
      | zero => simp at room
      | succ words =>
          simp [workspace, pack, pendingBits, setValue, decode_four_eq_wrap target]
  | [a, b, c] =>
      cases words with
      | zero => simp at room
      | succ words =>
          simp [workspace, pack, pendingBits, setValue, decode_four_eq_wrap target]
  | a :: b :: c :: d :: rest =>
      cases words with
      | zero => simp only [List.length_cons] at room; omega
      | succ words =>
          have nextRoom : (rest.length + 4) / 4 ≤ words := by
            simp only [List.length_cons] at room
            omega
          have division : (rest.length + 1 + 1 + 1 + 1) / 4 = rest.length / 4 + 1 := by omega
          have modulo : (rest.length + 1 + 1 + 1 + 1) % 4 = rest.length % 4 := by omega
          simp only [List.cons_append, workspace_four, List.length_cons,
            division, modulo, pendingBits, setValue]
          rw [workspace_insert_byte target words rest byte tail nextRoom]
termination_by processed.length

theorem workspace_length (words : Nat) (processed : List UInt8) (tail : List Value)
    (room : (pack processed).length ≤ words) :
    (workspace words processed tail).length = words + tail.length := by
  simp only [workspace, List.length_append, List.length_replicate]
  omega

theorem workspace_current_word
    (target : Target) (words : Nat) (processed : List UInt8) (tail : List Value)
    (room : (processed.length + 4) / 4 ≤ words) :
    (workspace words processed tail)[processed.length / 4]? =
      some (.signed .i32 (wrapSigned target .i32 (pendingBits processed))) := by
  match processed with
  | [] =>
      cases words with
      | zero => simp at room
      | succ words =>
          simp [workspace, pack, pendingBits, List.replicate_succ, wrapSigned,
            signedModulus, signedSignBit, SignedIntTy.bits]
  | [a] =>
      simp [workspace, pack, pendingBits, decode_four_eq_wrap target]
  | [a, b] =>
      simp [workspace, pack, pendingBits, decode_four_eq_wrap target]
  | [a, b, c] =>
      simp [workspace, pack, pendingBits, decode_four_eq_wrap target]
  | a :: b :: c :: d :: rest =>
      cases words with
      | zero => simp only [List.length_cons] at room; omega
      | succ words =>
          have nextRoom : (rest.length + 4) / 4 ≤ words := by
            simp only [List.length_cons] at room
            omega
          have division : (rest.length + 1 + 1 + 1 + 1) / 4 = rest.length / 4 + 1 := by omega
          simpa only [workspace_four, List.length_cons, division,
            List.getElem?_cons_succ, pendingBits] using
            workspace_current_word target words rest tail nextRoom
termination_by processed.length

end Lanius.Extraction.OutputPacking
