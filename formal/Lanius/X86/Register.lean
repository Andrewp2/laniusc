import Std.Tactic

namespace Lanius.X86.Register

inductive Width where
  | w32 | w64
  deriving DecidableEq, Repr

def Width.bits : Width → Nat
  | .w32 => 32
  | .w64 => 64

inductive Validation where
  | register | width
  deriving DecidableEq

def Validation.accepts : Validation → Int → Bool
  | .register, value => decide (0 ≤ value ∧ value < 16)
  | .width, value => decide (value = 32 ∨ value = 64)

theorem register_domain (value : Int) :
    Validation.register.accepts value = true ↔ ∃ reg : Fin 16, value = reg.val := by
  simp only [Validation.accepts, decide_eq_true_eq]
  constructor
  · intro ⟨low, high⟩
    exact ⟨⟨value.toNat, by omega⟩, (Int.toNat_of_nonneg low).symm⟩
  · rintro ⟨reg, rfl⟩
    exact ⟨Int.natCast_nonneg _, Int.ofNat_lt.mpr reg.isLt⟩

theorem width_domain (value : Int) :
    Validation.width.accepts value = true ↔ ∃ width : Width, value = width.bits := by
  simp only [Validation.accepts, decide_eq_true_eq]
  constructor
  · rintro (rfl | rfl)
    · exact ⟨.w32, rfl⟩
    · exact ⟨.w64, rfl⟩
  · rintro ⟨width, rfl⟩
    cases width <;> simp [Width.bits]

/-- Intel SDM vol. 2A §2.2.1, Table 2-4: the byte is 0100WRXB.
This describes a prefix in 64-bit mode, not its effect on every opcode. -/
structure Rex where
  w : Bool
  r : Bool
  x : Bool
  b : Bool
  deriving DecidableEq, Repr

def Rex.encode (fields : Rex) : Nat :=
  64 + 8 * fields.w.toNat + 4 * fields.r.toNat + 2 * fields.x.toNat + fields.b.toNat

def Rex.decode? (byte : Nat) : Option Rex :=
  if 64 ≤ byte ∧ byte < 80 then
    some ⟨decide (byte / 8 % 2 = 1), decide (byte / 4 % 2 = 1),
      decide (byte / 2 % 2 = 1), decide (byte % 2 = 1)⟩
  else none

theorem Rex.decode_encode (fields : Rex) : Rex.decode? fields.encode = some fields := by
  rcases fields with ⟨w, r, x, b⟩
  cases w <;> cases r <;> cases x <;> cases b <;> rfl

theorem Rex.encode_bounds (fields : Rex) : 64 ≤ fields.encode ∧ fields.encode < 80 := by
  rcases fields with ⟨w, r, x, b⟩
  cases w <;> cases r <;> cases x <;> cases b <;> decide

/-- The shared register/base helper leaves X clear. Indexed SIB emission
adds the index extension bit separately. -/
def fields (width : Width) (reg base : Fin 16) : Rex :=
  ⟨decide (width = .w64), decide (8 ≤ reg.val), false, decide (8 ≤ base.val)⟩

def initial (reg base : Fin 16) : Nat := 64 + (reg.val / 8) * 4 + base.val / 8

theorem initial_bounds (reg base : Fin 16) : 64 ≤ initial reg base ∧ initial reg base ≤ 69 := by
  have := reg.isLt
  have := base.isLt
  simp only [initial]
  omega

theorem fields_arithmetic (width : Width) (reg base : Fin 16) :
    (fields width reg base).encode = initial reg base + (if width = .w64 then 8 else 0) := by
  have := reg.isLt
  have := base.isLt
  cases width <;> by_cases hr : 8 ≤ reg.val <;> by_cases hb : 8 ≤ base.val <;>
    simp [fields, Rex.encode, initial, hr, hb, Bool.toNat] <;> omega

/-- Zero is the Lanius helper's sentinel for absence, not a REX byte. -/
def value (width : Width) (reg base : Fin 16) (forceByte : Bool) : Nat :=
  let byte := (fields width reg base).encode
  if byte = 64 ∧ forceByte = false then 0 else byte

theorem value_bounds (width : Width) (reg base : Fin 16) (forceByte : Bool) :
    value width reg base forceByte = 0 ∨
      (64 ≤ value width reg base forceByte ∧ value width reg base forceByte < 80) := by
  by_cases omitted : (fields width reg base).encode = 64 ∧ forceByte = false
  · exact Or.inl (by simp [value, omitted])
  · exact Or.inr (by simpa only [value, if_neg omitted] using Rex.encode_bounds (fields width reg base))

theorem omitted_iff (width : Width) (reg base : Fin 16) (forceByte : Bool) :
    value width reg base forceByte = 0 ↔
      width = .w32 ∧ reg.val < 8 ∧ base.val < 8 ∧ forceByte = false := by
  have := reg.isLt
  have := base.isLt
  cases width <;> cases forceByte <;>
    by_cases hr : 8 ≤ reg.val <;> by_cases hb : 8 ≤ base.val <;>
    simp [value, fields, Rex.encode, hr, hb, Bool.toNat] <;> omega

theorem present_decodes (width : Width) (reg base : Fin 16) (forceByte : Bool)
    (present : value width reg base forceByte ≠ 0) :
    Rex.decode? (value width reg base forceByte) = some (fields width reg base) := by
  by_cases omitted : (fields width reg base).encode = 64 ∧ forceByte = false
  · simp [value, omitted] at present
  · simpa only [value, if_neg omitted] using Rex.decode_encode (fields width reg base)

end Lanius.X86.Register
