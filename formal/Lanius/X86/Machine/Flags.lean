import Lanius.X86.Machine.State

namespace Lanius.X86.Machine

/-- Intel arithmetic status flags. Other RFLAGS bits, including DF, are
retained. Parity is even parity of the result's low byte. -/
def arithmeticFlags (before : BitVec 64) (carry parity auxiliary zero sign overflow : Bool) : BitVec 64 :=
  (before &&& ~~~(2261#64)) ||| BitVec.ofNat 64
    (carry.toNat + 4 * parity.toNat + 16 * auxiliary.toNat + 64 * zero.toNat +
      128 * sign.toNat + 2048 * overflow.toNat)

def evenParity (value : BitVec width) : Bool :=
  decide (((List.range 8).filter fun bit => value.getLsbD bit).length % 2 = 0)

def subtractFlags (before : BitVec 64) (left right : BitVec width) : BitVec 64 :=
  let result := left - right
  arithmeticFlags before (decide (left.toNat < right.toNat)) (evenParity result)
    ((left ^^^ right ^^^ result).getLsbD 4) (result == 0) result.msb
    ((left.msb != right.msb) && (result.msb != left.msb))

/-- TEST32 discards its AND result; CF/OF are zero and SF/ZF/PF describe
that 32-bit result. AF is architecturally undefined, so the caller supplies
an arbitrary choice rather than this model prescribing its value.
Intel SDM Vol. 2B, TEST, 4-703–4-704:
https://cdrdv2-public.intel.com/782151/253667-sdm-vol-2b.pdf -/
def logical32Flags (before : BitVec 64) (result : BitVec 32) (auxiliary : Bool) : BitVec 64 :=
  arithmeticFlags before false (evenParity result) auxiliary (result == 0) result.msb false

/-- Intel condition-code order, shared by Jcc and future SETcc lowering. -/
def condition (flags : BitVec 64) (code : Fin 16) : Bool :=
  let cf := flags.getLsbD 0
  let pf := flags.getLsbD 2
  let zf := flags.getLsbD 6
  let sf := flags.getLsbD 7
  let of := flags.getLsbD 11
  match code.val with
  | 0 => of | 1 => !of | 2 => cf | 3 => !cf
  | 4 => zf | 5 => !zf | 6 => cf || zf | 7 => !(cf || zf)
  | 8 => sf | 9 => !sf | 10 => pf | 11 => !pf
  | 12 => sf != of | 13 => sf == of
  | 14 => zf || (sf != of) | 15 => !zf && (sf == of)
  | _ => false

theorem arithmeticFlags_carry (before : BitVec 64) (carry parity auxiliary zero sign overflow : Bool) :
    (arithmeticFlags before carry parity auxiliary zero sign overflow).getLsbD 0 = carry := by
  cases carry <;> cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;> cases overflow <;>
    simp [arithmeticFlags]

theorem compare_below (before : BitVec 64) (left right : BitVec width) :
    condition (subtractFlags before left right) 2 = decide (left.toNat < right.toNat) := by
  exact arithmeticFlags_carry _ _ _ _ _ _ _

theorem arithmeticFlags_direction (before : BitVec 64) (carry parity auxiliary zero sign overflow : Bool) :
    (arithmeticFlags before carry parity auxiliary zero sign overflow).getLsbD 10 = before.getLsbD 10 := by
  cases carry <;> cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;> cases overflow <;>
    simp [arithmeticFlags]

theorem subtractFlags_direction (before : BitVec 64) (left right : BitVec width) :
    (subtractFlags before left right).getLsbD 10 = before.getLsbD 10 :=
  arithmeticFlags_direction _ _ _ _ _ _ _

theorem logical32Flags_greaterEqual (before : BitVec 64) (result : BitVec 32) (auxiliary : Bool) :
    condition (logical32Flags before result auxiliary) 13 = !result.msb := by
  change ((logical32Flags before result auxiliary).getLsbD 7 ==
    (logical32Flags before result auxiliary).getLsbD 11) = !result.msb
  unfold logical32Flags
  generalize evenParity result = parity
  generalize (result == 0) = zero
  generalize result.msb = sign
  cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;>
    simp [arithmeticFlags]

theorem logical32Flags_direction (before : BitVec 64) (result : BitVec 32) (auxiliary : Bool) :
    (logical32Flags before result auxiliary).getLsbD 10 = before.getLsbD 10 :=
  arithmeticFlags_direction _ _ _ _ _ _ _

end Lanius.X86.Machine
