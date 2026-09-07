import Lanius.Core.Relocation
import Lanius.Core.Equality

namespace Lanius.Core.Relocation

/-- Exact lookup obligations for transporting successful executions into a
larger linked program. This is not itself the execution-transport theorem. -/
structure ProgramMatch (symbols : Symbols) (smaller larger : Program) : Type where
  target : smaller.target = larger.target
  constant : ∀ {id declaration}, smaller.constant? id = some declaration →
    larger.constant? (symbols.constantId id) = some (Relocation.constant symbols declaration)
  function : ∀ {id declaration}, smaller.function? id = some declaration →
    larger.function? (symbols.functionId id) = some (Relocation.function symbols declaration)

private def checkLookups? {α β : Type} (lookup : α → Option β) (expected : α → β)
    (equal : (left right : β) → Option (Equality.Evidence left right)) :
    (entries : List α) → Option (PLift (∀ entry ∈ entries, lookup entry = some (expected entry)))
  | [] => some ⟨by intro entry member; cases member⟩
  | entry :: rest =>
      match found : lookup entry with
      | none => none
      | some observed => do
          let ⟨same⟩ ← equal observed (expected entry)
          let ⟨tail⟩ ← checkLookups? lookup expected equal rest
          pure ⟨by
            intro candidate member
            rcases List.mem_cons.mp member with rfl | inRest
            · exact found.trans (congrArg some same)
            · exact tail candidate inRest⟩

/-- Produce kernel-typed equality and lookup evidence. No hash, unchecked
BEq result, old artifact acceptance, or semantic correctness is assumed here. -/
def checkProgram? (symbols : Symbols) (smaller larger : Program) :
    Option (ProgramMatch symbols smaller larger) := do
  let ⟨target⟩ ← Equality.atom? smaller.target larger.target
  let ⟨constants⟩ ← checkLookups?
    (fun declaration : Constant => larger.constant? (symbols.constantId declaration.id))
    (Relocation.constant symbols) Equality.constant? smaller.constants
  let ⟨functions⟩ ← checkLookups?
    (fun declaration : Function => larger.function? (symbols.functionId declaration.id))
    (Relocation.function symbols) Equality.function? smaller.functions
  pure {
    target
    constant := by
      intro id declaration found
      have same : declaration.id = id :=
        beq_iff_eq.mp (List.find?_some (p := fun entry : Constant => entry.id == id) found)
      subst id
      exact constants declaration (List.mem_of_find?_eq_some found)
    function := by
      intro id declaration found
      have same : declaration.id = id :=
        beq_iff_eq.mp (List.find?_some (p := fun entry : Function => entry.id == id) found)
      subst id
      exact functions declaration (List.mem_of_find?_eq_some found)
  }

end Lanius.Core.Relocation
