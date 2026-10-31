import Lanius.IEEE

/-! The SSE scalar instructions of the x86 model and their meaning.

The model holds the low 64 bits of each XMM register (`State.xmm`). The
instructions modeled never read the high 64 bits: MOVD/MOVQ to an XMM
register zero them, the scalar arithmetic, compare and convert instructions
keep them, and nothing reads them back. Within the low 64 bits each
instruction is exact:

* MOVD xmm, r32 (66 0F 6E /r) and MOVQ xmm, r64 (66 REX.W 0F 6E /r) zero-extend
  the general register into the XMM register; MOVD r32, xmm (66 0F 7E /r)
  writes its low 32 bits, zero-extended as every 32-bit write is, and
  MOVQ r64, xmm (66 REX.W 0F 7E /r) its low 64.
* ADDSS/SUBSS/MULSS/DIVSS (F3 0F 58/5C/59/5E /r) replace the destination's
  low 32 bits with the binary32 operation of the two low 32-bit fields, the
  destination being the first operand; the SD forms (F2) replace all 64 low
  bits with the binary64 operation.
* CMPSS/CMPSD xmm, xmm, imm8 (F3/F2 0F C2 /r ib) with predicates 0 (EQ_OQ),
  1 (LT_OS) and 2 (LE_OS) write all ones in the low 32 (single) or 64
  (double) bits when the IEEE comparison holds and zeros when it does not
  (false on a NaN).
* CVTSI2SS/CVTSI2SD xmm, r32/r64 (F3/F2 [REX.W] 0F 2A /r) round the signed
  integer to the nearest float.
* CVTSS2SD (F3 0F 5A /r) widens exactly, CVTSD2SS (F2 0F 5A /r) rounds.

That each instruction computes `Lanius.IEEE`'s operation is trusted base
(TRUSTED_BASE.md, "Floats"), under the default MXCSR (round to nearest,
exceptions masked, denormals neither flushed nor treated as zero), which
Linux gives a process at exec and the compiled code never changes.
`formal/tools/float_test.py` runs each of these instructions on this CPU
against the specification. -/

namespace Lanius.X86.Machine

open Lanius.IEEE

inductive SseArith where
  | add | sub | mul | div
  deriving DecidableEq, Repr

def SseArith.opcode : SseArith → Nat
  | .add => 88 | .mul => 89 | .sub => 92 | .div => 94

def SseArith.ofOpcode? : Nat → Option SseArith
  | 88 => some .add | 89 => some .mul | 92 => some .sub | 94 => some .div | _ => none

def SseArith.apply (F : Format) : SseArith → Nat → Nat → Nat
  | .add => F.add | .sub => F.sub | .mul => F.mul | .div => F.div

inductive SsePredicate where
  | eq | lt | le
  deriving DecidableEq, Repr

def SsePredicate.imm : SsePredicate → Nat
  | .eq => 0 | .lt => 1 | .le => 2

def SsePredicate.ofImm? : Nat → Option SsePredicate
  | 0 => some .eq | 1 => some .lt | 2 => some .le | _ => none

def SsePredicate.holds (F : Format) : SsePredicate → Nat → Nat → Bool
  | .eq => F.eq | .lt => F.lt | .le => F.le

/-- binary64 for a double (SD) instruction, binary32 for a single (SS) one. -/
def sseFormat (double : Bool) : Format := if double then binary64 else binary32

/-- The low 32 bits of `x` replaced by those of `v`. -/
def setLow32 (x : BitVec 64) (v : Nat) : BitVec 64 :=
  BitVec.ofNat 64 (x.toNat / 2 ^ 32 * 2 ^ 32 + v % 2 ^ 32)

/-- A scalar operand: the low 64 bits for a double, the low 32 for a single. -/
def sseOperand (double : Bool) (x : BitVec 64) : Nat := if double then x.toNat else x.toNat % 2 ^ 32

/-- A scalar result `v` written over `old`. -/
def sseResult (double : Bool) (old : BitVec 64) (v : Nat) : BitVec 64 :=
  if double then BitVec.ofNat 64 v else setLow32 old v

/-- The mask a compare writes. -/
def sseMask (double : Bool) (holds : Bool) : Nat :=
  if holds then (if double then 2 ^ 64 - 1 else 2 ^ 32 - 1) else 0

end Lanius.X86.Machine
