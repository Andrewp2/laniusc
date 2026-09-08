import Lanius.Semantics.CellRenaming.Syntax
import Lanius.Semantics

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

/-- Program facts needed for transport of internal frontend calls. A missing
body is not treated as a pure call: external services need a separate proof. -/
structure ProgramInvariant (rename : CellId → CellId) (program : Program) : Prop where
  constant : ∀ id declaration, program.constant? id = some declaration →
    value rename declaration.value = declaration.value
  function : ∀ id declaration, program.function? id = some declaration →
    ∃ body, declaration.body = some body ∧ statement rename body = body

end Lanius.Semantics.CellRenaming.Execution
