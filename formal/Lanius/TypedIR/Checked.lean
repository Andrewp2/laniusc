import Lanius.TypedIR
import Lanius.Typing.Check

namespace Lanius.TypedIR

/-- A linked semantic program with the existing kernel-checkable typing
    judgment. The generated representation erases once into `Core.Program`. -/
structure Program where
  entry : FunctionId
  core : Core.Program
  wellTyped : Typing.ProgramWellTyped core
  validEntry : entryValid core entry = true

def require (entry : FunctionId) (core : Core.Program)
    (accepted : (Typing.Check.checkProgramWellTyped core).isSome = true)
    (entryAccepted : entryValid core entry = true) : Program :=
  ⟨entry, core, ((Typing.Check.checkProgramWellTyped core).get accepted).down,
    entryAccepted⟩

def link (entry : FunctionId) (declarations : Core.Program)
    (functions : List AnyFunction)
    (accepted : (Typing.Check.checkProgramWellTyped
      (assemble declarations functions)).isSome = true)
    (entryAccepted : entryValid (assemble declarations functions) entry = true) : Program :=
  require entry (assemble declarations functions) accepted entryAccepted

/-- Turn the one emitted Core embedding into a proof-carrying program only
    when the Lean checker accepts its typing and entrypoint. This does not
    trust the extractor's claim that either check succeeds. -/
def link? (entry : FunctionId) (core : Core.Program) : Option Program :=
  if accepted : (Typing.Check.checkProgramWellTyped core).isSome = true then
    if entryAccepted : entryValid core entry = true then
      some (require entry core accepted entryAccepted)
    else none
  else none

/-- Linking adds evidence; it never changes the emitted program. -/
theorem link?_core (entry : FunctionId) (core : Core.Program)
    {linked : Program} (accepted : link? entry core = some linked) :
    linked.core = core := by
  unfold link? at accepted
  split at accepted
  · split at accepted
    · cases Option.some.inj accepted
      rfl
    · cases accepted
  · cases accepted

@[simp] theorem require_core (entry : FunctionId) (core : Core.Program)
    (accepted : (Typing.Check.checkProgramWellTyped core).isSome = true)
    (entryAccepted : entryValid core entry = true) :
    (require entry core accepted entryAccepted).core = core := rfl

end Lanius.TypedIR
