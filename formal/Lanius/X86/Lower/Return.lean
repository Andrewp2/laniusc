import Lanius.X86.Lower.Parameter
import Lanius.X86.Machine.Scalar

namespace Lanius.X86.Lower.Parameter

/-- System V AMD64 integer argument registers, in architectural encoding order. -/
def argumentRegister (position : Fin 6) : Machine.Register :=
  match position.val with
  | 0 => ⟨7, by decide⟩ | 1 => ⟨6, by decide⟩ | 2 => ⟨2, by decide⟩
  | 3 => ⟨1, by decide⟩ | 4 => ⟨8, by decide⟩ | _ => ⟨9, by decide⟩

def moveBytes (position : Fin 6) : List UInt8 :=
  let register := (argumentRegister position).val
  if register < 8 then [137, UInt8.ofNat (192 + register * 8)]
  else [68, 137, UInt8.ofNat (192 + (register - 8) * 8)]

def bytes (position : Fin 6) : List UInt8 := moveBytes position ++ [195]

theorem move_decodes (position : Fin 6) :
    Machine.decode (moveBytes position) = some (.move32 0 (argumentRegister position), (moveBytes position).length) := by
  decide +revert

theorem machine_returns (position : Fin 6) (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip (bytes position)) :
    ∃ middle after, Machine.Step before middle ∧ Machine.Step middle after ∧
      after.registers 0 = ((before.registers (argumentRegister position)).setWidth 32).setWidth 64 ∧
      after.rip = Machine.read64 before.memory (before.registers 4) ∧
      after.registers 4 = before.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags := by
  let middle := before.move32 0 (argumentRegister position) (moveBytes position).length
  let after := middle.returnNear
  refine ⟨middle, after, .decoded (moveBytes position) loaded.prefix _ _ (move_decodes position) rfl,
    .decoded [195] loaded.suffix .returnNear 1 rfl rfl, ?_, ?_, ?_, ?_, rfl, rfl⟩
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32]
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32]
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32]
  · intro register notResult notStack
    simp [after, middle, Machine.State.returnNear, Machine.State.move32, notResult, notStack]

def Checked.argument (checked : Checked function) : Fin 6 :=
  ⟨checked.position.val, Nat.lt_of_lt_of_le checked.position.isLt checked.registerArguments⟩

/-- A certificate for the concrete machine bytes. Initially this independently
validates the untrusted GPU-bootstrapped Lanius backend's output. It does not
claim that the compiler implementation has yet been proved for all inputs. -/
structure Certified (function : Lanius.Core.Function) (emitted : List UInt8) where
  selected : Checked function
  bytesExact : emitted = bytes selected.argument

def certify? (function : Lanius.Core.Function) (emitted : List UInt8) : Option (Certified function emitted) := do
  let selected ← check? function
  if same : emitted = bytes selected.argument then some ⟨selected, same⟩ else none

/-- Connect the actual Core body and actual loaded machine bytes. The state
relation maps the selected Core local to the low 32 bits of its ABI register.
The result is the same i32; the stack is popped and all other registers,
memory, and flags are preserved. The Machine.Scalar environment is explicit. -/
theorem Certified.preserves (certified : Certified function emitted) (program : Lanius.Core.Program)
    (coreBefore : Lanius.Semantics.State) (machineBefore : Machine.State) (value : Int)
    (localValue : coreBefore.local? (function.parameters.get certified.selected.position).1 =
      some (.signed .i32 value))
    (represented : ((machineBefore.registers (argumentRegister certified.selected.argument)).setWidth 32).toInt = value)
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip emitted) :
    function.body = some (body (function.parameters.get certified.selected.position).1 certified.selected.trailingSkip) ∧
    Lanius.Semantics.Executes program coreBefore
        (body (function.parameters.get certified.selected.position).1 certified.selected.trailingSkip)
        (.returned (some (.signed .i32 value))) coreBefore ∧
      ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
        ((after.registers 0).setWidth 32).toInt = value ∧
        after.rip = Machine.read64 machineBefore.memory (machineBefore.registers 4) ∧
        after.registers 4 = machineBefore.registers 4 + 8 ∧
        (∀ register, register ≠ 0 → register ≠ 4 → after.registers register = machineBefore.registers register) ∧
        after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  refine ⟨certified.selected.bodyExact, certified.selected.executes program localValue, ?_⟩
  rw [certified.bytesExact] at loaded
  obtain ⟨middle, after, first, second, result, target, stack, frame, memory, flags⟩ :=
    machine_returns certified.selected.argument machineBefore loaded
  refine ⟨middle, after, first, second, ?_, target, stack, frame, memory, flags⟩
  rw [result]
  simpa using represented

end Lanius.X86.Lower.Parameter
