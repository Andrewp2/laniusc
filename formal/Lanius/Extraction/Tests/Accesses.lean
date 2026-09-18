import Lanius.SymbolicCore
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Accesses

open Core SymbolicCore

/- The dispatch refactor preserves the original equation for every operation,
place, and value, including unknown operators in symbolic proofs. -/
theorem assignment (op : AssignOp) (place : Place) (value : Expr) :
    Expr.accesses (.assign op place value) =
      Place.assignmentAccesses op place ++ Expr.accesses value := by
  cases op <;> rfl

private def cases : List Bool := [
  Expr.accesses (.assign .set (.local 7) (.local 9)) ==
    [LocalAccess.write 7, LocalAccess.read 9],
  Expr.accesses (.assign .set (.field (.local 7) 2) (.local 9)) ==
    [LocalAccess.readWrite 7, LocalAccess.read 9],
  Expr.accesses (.assign .add (.index (.local 8) (.local 9)) (.local 10)) ==
    [LocalAccess.readWrite 8, LocalAccess.read 9, LocalAccess.read 10],
  Expr.accesses (.matchValue (.local 1)
      [(.enumVariant 3 4 [.bind 2], .binary .add (.local 2) (.local 3))]) ==
    [LocalAccess.read 1, LocalAccess.read 3],
  Stmt.freeAccesses (.letLocal 2 (.scalar (.signed .i32)) (.local 3)
      (.expression (.binary .add (.local 2) (.local 4)))) ==
    [LocalAccess.read 3, LocalAccess.read 4],
  Stmt.freeAccesses (.forRange 2 (.local 4) (some (.local 5)) false
      (.expression (.binary .add (.local 2) (.local 6)))) ==
    [LocalAccess.read 4, LocalAccess.read 5, LocalAccess.read 6]
]

private theorem cases_pass : cases.all id = true := by decide +kernel

#eval show IO Unit from do
  unless cases.all id do
    throw (IO.userError "Core access analysis disagrees with its kernel-checked cases")
  IO.println "6 binder-aware access cases agree under kernel and native evaluation."

run_elab do
  for name in #[``Pattern.boundLocals, ``Expr.accesses, ``Place.readAccesses,
      ``Place.writeAccesses, ``Place.readWriteAccesses, ``Stmt.freeAccesses,
      ``assignment, ``cases_pass] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Core access analysis {name} adds unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Accesses
