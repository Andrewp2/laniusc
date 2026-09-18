import Lanius.FunctionalViewCoreStatefulRenaming
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Renaming

open FunctionalView

private def shift : Embedding 2 4 where
  slot index := ⟨index.val + 1, by omega⟩
  injective := by
    intro left right equal
    apply Fin.ext
    have values := congrArg Fin.val equal
    simp only at values
    omega

private def i32 : Lanius.Core.Ty := .scalar (.signed .i32)

private def term : Term Core.signature 2 :=
  .apply (.call 42 [i32, i32] i32) [
    .reference (.slot ⟨0, by decide⟩),
    .apply (.call 43 [i32] i32) [.reference (.slot ⟨1, by decide⟩)]]

private def command : Stateful.Command Core.signature Core.Stateful.actions 2 :=
  .letValue i32 (.reference (.slot ⟨0, by decide⟩))
    (.returnValue (some (.reference (.slot ⟨2, by decide⟩))))

private def cases : List Bool := [
  Core.toCoreExpr (fun index : Fin 4 => index.val) (term.rename shift) ==
    .call 42 [.local 1, .call 43 [.local 2]],
  Core.Stateful.toCoreStmt Core.Stateful.actionAdapter
      (fun index : Fin 4 => index.val) 4
      (command.rename Core.Stateful.actionRenamer shift) ==
    .letLocal 4 i32 (.local 1) (.returnValue (some (.local 4)))
]

private theorem cases_pass : cases.all id = true := by decide +kernel

#eval show IO Unit from do
  unless cases.all id do
    throw (IO.userError "Structural renaming disagrees with its kernel-checked cases")
  IO.println "Nested arguments and lexical renaming compute in the kernel and natively."

run_elab do
  for name in #[``Term.rename, ``Term.renameList_eq_map, ``Term.evaluate_rename,
      ``Stateful.Command.rename, ``Stateful.Command.Evaluates.rename,
      ``Core.Stateful.toCoreExpr_rename, ``Core.Stateful.toCoreStmt_rename,
      ``cases_pass] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Renaming {name} adds unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Renaming
