namespace Lanius

abbrev ModuleId := Nat
abbrev FileId := Nat
abbrev TypeId := Nat
abbrev TraitId := Nat
abbrev ImplId := Nat
abbrev TypeParameterId := Nat
abbrev ConstParameterId := Nat
abbrev VariantId := Nat
abbrev FunctionId := Nat
abbrev ExternId := Nat
abbrev ConstantId := Nat
abbrev VarId := Nat
abbrev CellId := Nat
abbrev FieldId := Nat
abbrev Address := Nat

inductive Capability where
  | clock
  | network
  | thread
  | gpu
  | testHarness
deriving DecidableEq, Repr

/-- Traps are observable language outcomes, not undefined host behavior. -/
inductive Trap where
  | arrayBounds
  | invalidShift
  | divisionByZero
  | signedDivisionOverflow
  | invalidPointer
  | rawMemoryBounds
  | doubleFree
  | allocatorContract
  | allocationFailure
  | entropyExhausted
  | assertionFailed
  | nonExhaustiveMatch
  | uninitializedLocal
  | missingReturn
  | serviceUnavailable (capability : Capability)
  | panic
  | reachedUnreachable
  | unmodeledExtern (id : ExternId)
  | typeMismatch
  deriving DecidableEq, Repr

end Lanius
