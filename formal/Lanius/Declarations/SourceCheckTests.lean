import Lanius.Declarations.SourceCheck

namespace Lanius.Declarations.SourceCheckTests
open Lanius

-- These decisions must reduce in the kernel, not only after native proof
-- erasure. The former simp/transport instances fail these regressions.
example (path : Surface.Path) : decide (IsModuleItem (.module path)) = true := rfl
example (path : Surface.Path) : decide (IsModuleItem (.importPath path)) = false := rfl
example (function : Surface.Function) : decide (IsModuleItem (.function function)) = false := rfl
example (path : Surface.Path) : decide (IsImportItem (.importPath path)) = true := rfl
example (text : String) : decide (IsImportItem (.importString text)) = true := rfl
example (path : Surface.Path) : decide (IsImportItem (.module path)) = false := rfl
example (function : Surface.Function) : decide (IsImportItem (.function function)) = false := rfl

private def file (items : List Surface.Item) : SourceFile :=
  { id := 0, moduleInfo := { id := 0, path := ["app"] }, contents := { items }, origin := .declared }

example (path : Surface.Path) (function : Surface.Function) :
    (checkImportsLeading (file [.module path, .importPath path, .function function])).isSome = true := rfl
example (path : Surface.Path) (function : Surface.Function) :
    (checkImportsLeading (file [.module path, .function function, .importPath path])).isSome = false := rfl

end Lanius.Declarations.SourceCheckTests
