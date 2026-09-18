import Lanius.X86.Machine.Sequence

namespace Lanius.X86.Machine.Boolean

/-- The RAX forms used by `backend::operation::boolean`. These are byte
descriptions, not substitutes for proving that the Lanius emitter runs. -/
def setByte (code : Fin 16) : ReadOnly where
  instruction := .setCondition code 0
  bytes := [15, UInt8.ofNat (144 + code.val), 192]
  decoded := (by decide : ∀ code : Fin 16,
    decode [15, UInt8.ofNat (144 + code.val), 192] = some (.setCondition code 0, 3)) code
  memory _ := rfl
  rip _ := rfl

def widen : ReadOnly where
  instruction := .zeroExtendByte 0 0
  bytes := [15, 182, 192]
  decoded := by decide
  memory _ := rfl
  rip _ := rfl

def materialize (code : Fin 16) : List ReadOnly := [setByte code, widen]

/-- Arbitrary dirty upper bits are discarded, not assumed to be zero. -/
theorem materialize_run (code : Fin 16) (before : State) :
    ReadOnly.run (materialize code) before = { before with
      registers := fun register => if register = 0 then
        (if condition before.flags code then 1 else 0) else before.registers register
      rip := before.rip + 6 } := by
  have low (high : BitVec 56) (byte : BitVec 8) : (high ++ byte).setWidth 8 = byte :=
    BitVec.setWidth_append_eq_right
  simp [materialize, setByte, widen, ReadOnly.run, execute, State.setCondition,
    State.zeroExtendByte, BitVec.add_assoc]
  split <;> funext register <;>
    by_cases same : register = 0 <;> simp [same, low]

def compare : ReadOnly where
  instruction := .compare64 1 0
  bytes := [72, 57, 193]
  decoded := by decide
  memory _ := rfl
  rip _ := rfl

def comparison (code : Fin 16) : List ReadOnly := compare :: materialize code

/-- The integer backend holds the left operand in EAX and the right in ECX,
opposite to the pointer window above. Upper register bits are irrelevant. -/
def compare32 : ReadOnly where
  instruction := .compare32 0 1
  bytes := [57, 200]
  decoded := by decide
  memory _ := rfl
  rip _ := rfl

def comparison32 (code : Fin 16) : List ReadOnly := compare32 :: materialize code

/-- The complete CMP RCX,RAX; SETcc AL; MOVZX EAX,AL window. Code loading is
the only execution premise: the three decoded steps are derived here. -/
theorem comparison_steps (code : Fin 16) (before : State)
    (loaded : CodeAt before.memory before.rip (ReadOnly.code (comparison code))) :
    ∃ after, Steps 3 before after ∧
      after.registers 0 = (if condition
        (subtractFlags before.flags (before.registers 1) (before.registers 0)) code then 1 else 0) ∧
      (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.rip = before.rip + 9 ∧
      after.flags = subtractFlags before.flags (before.registers 1) (before.registers 0) := by
  refine ⟨ReadOnly.run (comparison code) before, ReadOnly.steps _ _ loaded, ?_⟩
  simp [comparison, ReadOnly.run, materialize_run, compare, execute, State.compare64,
    BitVec.add_assoc]
  intro register different same
  exact (different same).elim

end Lanius.X86.Machine.Boolean
