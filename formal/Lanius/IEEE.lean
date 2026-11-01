module

@[expose] public section

/-! IEEE 754 binary floating point on bit patterns: Core's `f32` and `f64`.

A value of format `F` is its bit pattern, a natural below `2 ^ (1 + F.e + F.f)`:
the sign bit, `F.e` exponent bits and `F.f` fraction bits. Every operation is
defined on exact integers and rationals, so the kernel can evaluate and reason
about it; there is no native float anywhere (Lean's `Float` is opaque to the
kernel). The rounding is IEEE's default: to nearest, ties to even, with
gradual underflow (subnormals are neither flushed nor treated as zero) and
overflow to infinity.

NaN results follow x86 SSE with the default MXCSR (TRUSTED_BASE.md, "Floats"):
an operation on a NaN returns its first NaN operand quieted (the quiet bit,
the fraction's top bit, set; sign and payload kept); an invalid operation on
non-NaN operands (inf - inf, 0 * inf, 0 / 0, inf / inf) returns the default NaN,
x86's "real indefinite": sign set, exponent all ones, only the quiet bit in the
fraction. A conversion between formats keeps a NaN's sign and the top bits of
its payload, quieted, as `cvtss2sd` and `cvtsd2ss` do.

This file is trusted base: it is the meaning of Core's float operations and of
the SSE instructions in the x86 model. `formal/tools/float_test.py` tests it
against this machine's CPU. -/

namespace Lanius.IEEE

/-- A binary interchange format: `e` exponent bits and `f` fraction bits. -/
structure Format where
  e : Nat
  f : Nat
  deriving DecidableEq, Repr

def binary32 : Format := ⟨8, 23⟩
def binary64 : Format := ⟨11, 52⟩

namespace Format

variable (F : Format)

/-- The sign bit. -/
def signBit : Nat := 2 ^ (F.e + F.f)
/-- Positive infinity: the exponent field all ones, the fraction zero. -/
def infBits : Nat := (2 ^ F.e - 1) * 2 ^ F.f
/-- The fraction's top bit, set in a quiet NaN. -/
def quietBit : Nat := 2 ^ (F.f - 1)
def bias : Nat := 2 ^ (F.e - 1) - 1
/-- The exponent of the unit in the last place of the subnormals and of the
least normal binade: `1 - bias - f` (-149 for binary32, -1074 for binary64). -/
def uMin : Int := 1 - (F.bias : Int) - F.f
/-- x86's default NaN ("real indefinite"). -/
def defaultNaN : Nat := F.signBit + F.infBits + F.quietBit

def negative (x : Nat) : Bool := x / F.signBit % 2 == 1
def magnitude (x : Nat) : Nat := x % F.signBit
def isNaN (x : Nat) : Bool := decide (F.infBits < F.magnitude x)
def isInf (x : Nat) : Bool := F.magnitude x == F.infBits
def isZero (x : Nat) : Bool := F.magnitude x == 0
/-- The sign bit of `x`, as a pattern. -/
def signOf (x : Nat) : Nat := if F.negative x then F.signBit else 0

/-- `x` with its quiet bit set. -/
def quiet (x : Nat) : Nat := if x / F.quietBit % 2 == 1 then x else x + F.quietBit

/-- Negation flips the sign bit, NaNs included. -/
def neg (x : Nat) : Nat := if F.negative x then x - F.signBit else x + F.signBit

/-- The integer significand of a finite `x`: its value is
`± significand x * 2 ^ unitExp x`. -/
def significand (x : Nat) : Nat :=
  let field := F.magnitude x / 2 ^ F.f
  let fraction := F.magnitude x % 2 ^ F.f
  if field == 0 then fraction else fraction + 2 ^ F.f

def unitExp (x : Nat) : Int :=
  ((max (F.magnitude x / 2 ^ F.f) 1 : Nat) : Int) + F.uMin - 1

end Format

/-- `⌊log2 (num / den)⌋` for positive `num` and `den`. -/
def floorLog2Ratio (num den : Nat) : Int :=
  let t : Int := (Nat.log2 num : Int) - (Nat.log2 den : Int)
  if den * 2 ^ t.toNat ≤ num * 2 ^ (-t).toNat then t else t - 1

namespace Format

variable (F : Format)

/-- The pattern of `(-1)^s * num / den * 2 ^ exp`, rounded to nearest with
ties to even, for positive `num` and `den`. `u` is the result's unit in the
last place: `f` below the value's binade, or `uMin` when that is lower (a
subnormal). The pattern is `(u - uMin) * 2^f + q` for the rounded significand
`q`; a carry out of the significand (`q = 2^(f+1)`) is the next binade's
pattern, and a pattern at or past infinity's is infinity. -/
def roundRatio (s : Bool) (num den : Nat) (exp : Int) : Nat :=
  let u : Int := max F.uMin (floorLog2Ratio num den + exp - F.f)
  let k : Int := exp - u
  let n := num * 2 ^ k.toNat
  let d := den * 2 ^ (-k).toNat
  let q := n / d
  let r := n % d
  let q := if d < 2 * r || (2 * r == d && q % 2 == 1) then q + 1 else q
  let bits := (u - F.uMin).toNat * 2 ^ F.f + q
  let bits := if F.infBits ≤ bits then F.infBits else bits
  if s then bits + F.signBit else bits

/-- The nearest pattern to an integer; zero is `+0`. -/
def ofInt (i : Int) : Nat :=
  if i == 0 then 0 else F.roundRatio (decide (i < 0)) i.natAbs 1 0

/-- The nearest pattern to `m * 10 ^ e`, a decimal literal's value. Past
`10 ^ 400` every format overflows, and below `10 ^ -400` every format rounds
to zero; those two tests only avoid computing huge powers. -/
def ofDecimal (m : Nat) (e : Int) : Nat :=
  if m == 0 then 0
  else if 400 < e then F.infBits
  else if e + (Nat.log2 m : Int) + 1 < -400 then 0
  else if 0 ≤ e then F.roundRatio false (m * 10 ^ e.toNat) 1 0
  else F.roundRatio false m (10 ^ (-e).toNat) 0

def add (a b : Nat) : Nat :=
  if F.isNaN a then F.quiet a
  else if F.isNaN b then F.quiet b
  else if F.isInf a then
    if F.isInf b && F.negative a != F.negative b then F.defaultNaN else a
  else if F.isInf b then b
  else
    let ua := F.unitExp a
    let ub := F.unitExp b
    let u := min ua ub
    let x : Int := ((F.significand a * 2 ^ (ua - u).toNat : Nat) : Int)
    let y : Int := ((F.significand b * 2 ^ (ub - u).toNat : Nat) : Int)
    let sum := (if F.negative a then -x else x) + (if F.negative b then -y else y)
    if sum == 0 then (if F.negative a && F.negative b then F.signBit else 0)
    else F.roundRatio (decide (sum < 0)) sum.natAbs 1 u

def sub (a b : Nat) : Nat :=
  if F.isNaN a then F.quiet a
  else if F.isNaN b then F.quiet b
  else F.add a (F.neg b)

def mul (a b : Nat) : Nat :=
  if F.isNaN a then F.quiet a
  else if F.isNaN b then F.quiet b
  else
    let s := F.negative a != F.negative b
    let sign := if s then F.signBit else 0
    if F.isInf a || F.isInf b then
      if F.isZero a || F.isZero b then F.defaultNaN else sign + F.infBits
    else
      let q := F.significand a * F.significand b
      if q == 0 then sign else F.roundRatio s q 1 (F.unitExp a + F.unitExp b)

def div (a b : Nat) : Nat :=
  if F.isNaN a then F.quiet a
  else if F.isNaN b then F.quiet b
  else
    let s := F.negative a != F.negative b
    let sign := if s then F.signBit else 0
    if F.isInf a then (if F.isInf b then F.defaultNaN else sign + F.infBits)
    else if F.isInf b then sign
    else if F.isZero b then (if F.isZero a then F.defaultNaN else sign + F.infBits)
    else if F.isZero a then sign
    else F.roundRatio s (F.significand a) (F.significand b) (F.unitExp a - F.unitExp b)

/-- A non-NaN pattern's place in value order: both zeros are 0. -/
def key (x : Nat) : Int := if F.negative x then -(F.magnitude x : Int) else (F.magnitude x : Int)

/-- IEEE comparisons: false when either operand is a NaN (`ne` is their
negation, true then). -/
def eq (a b : Nat) : Bool := !F.isNaN a && !F.isNaN b && F.key a == F.key b
def lt (a b : Nat) : Bool := !F.isNaN a && !F.isNaN b && decide (F.key a < F.key b)
def le (a b : Nat) : Bool := !F.isNaN a && !F.isNaN b && decide (F.key a ≤ F.key b)

/-- The pattern of `x` in format `G`: exact when `G` is wider, rounded when
narrower. A NaN keeps its sign and its payload's top bits, quieted. -/
def convert (G : Format) (x : Nat) : Nat :=
  let sign := if F.negative x then G.signBit else 0
  if F.isNaN x then
    let fraction := F.quiet x % 2 ^ F.f
    let payload := if F.f ≤ G.f then fraction * 2 ^ (G.f - F.f) else fraction / 2 ^ (F.f - G.f)
    sign + G.infBits + payload
  else if F.isInf x then sign + G.infBits
  else if F.isZero x then sign
  else G.roundRatio (F.negative x) (F.significand x) 1 (F.unitExp x)

/-- `x` truncated toward zero, saturated to `[lo, hi]`, NaN to zero: Rust's
`as` from a float to an integer type. -/
def truncSat (x : Nat) (lo hi : Int) : Int :=
  if F.isNaN x then 0
  else if F.isInf x then (if F.negative x then lo else hi)
  else
    let u := F.unitExp x
    let q := F.significand x
    let m : Nat := if 0 ≤ u then q * 2 ^ u.toNat else q / 2 ^ (-u).toNat
    let v : Int := if F.negative x then -(m : Int) else (m : Int)
    if v < lo then lo else if hi < v then hi else v

end Format

/-! binary32 on `UInt32` patterns. -/
namespace F32
def add (a b : UInt32) : UInt32 := .ofNat (binary32.add a.toNat b.toNat)
def sub (a b : UInt32) : UInt32 := .ofNat (binary32.sub a.toNat b.toNat)
def mul (a b : UInt32) : UInt32 := .ofNat (binary32.mul a.toNat b.toNat)
def div (a b : UInt32) : UInt32 := .ofNat (binary32.div a.toNat b.toNat)
def neg (a : UInt32) : UInt32 := .ofNat (binary32.neg a.toNat)
def eq (a b : UInt32) : Bool := binary32.eq a.toNat b.toNat
def lt (a b : UInt32) : Bool := binary32.lt a.toNat b.toNat
def le (a b : UInt32) : Bool := binary32.le a.toNat b.toNat
def ofInt (i : Int) : UInt32 := .ofNat (binary32.ofInt i)
def ofDecimal (m : Nat) (e : Int) : UInt32 := .ofNat (binary32.ofDecimal m e)
def toF64 (a : UInt32) : UInt64 := .ofNat (binary32.convert binary64 a.toNat)
def truncSat (a : UInt32) (lo hi : Int) : Int := binary32.truncSat a.toNat lo hi
end F32

/-! binary64 on `UInt64` patterns. -/
namespace F64
def add (a b : UInt64) : UInt64 := .ofNat (binary64.add a.toNat b.toNat)
def sub (a b : UInt64) : UInt64 := .ofNat (binary64.sub a.toNat b.toNat)
def mul (a b : UInt64) : UInt64 := .ofNat (binary64.mul a.toNat b.toNat)
def div (a b : UInt64) : UInt64 := .ofNat (binary64.div a.toNat b.toNat)
def neg (a : UInt64) : UInt64 := .ofNat (binary64.neg a.toNat)
def eq (a b : UInt64) : Bool := binary64.eq a.toNat b.toNat
def lt (a b : UInt64) : Bool := binary64.lt a.toNat b.toNat
def le (a b : UInt64) : Bool := binary64.le a.toNat b.toNat
def ofInt (i : Int) : UInt64 := .ofNat (binary64.ofInt i)
def ofDecimal (m : Nat) (e : Int) : UInt64 := .ofNat (binary64.ofDecimal m e)
def toF32 (a : UInt64) : UInt32 := .ofNat (binary64.convert binary32 a.toNat)
def truncSat (a : UInt64) (lo hi : Int) : Int := binary64.truncSat a.toNat lo hi
end F64

end Lanius.IEEE
