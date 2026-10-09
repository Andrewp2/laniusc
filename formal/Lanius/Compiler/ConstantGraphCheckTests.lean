import Lanius.Compiler.CoreBoundary
import Lanius.Compiler.ConstantGraphCheck

namespace Lanius.Compiler.ConstantGraphCheckTests

open Lanius

private def literal (text : String) : Surface.Expr := .literal (.integer text)
private def reference (name : String) : Surface.Expr := .path { segments := [.mk name []] }

private def accepts (definitions : List (String × Surface.Expr × Int)) : Except String Bool := do
  let items := definitions.map fun (name, expression, _) =>
    Surface.Item.constant name false (.path [.mk "i32" []]) expression
  let constants := definitions.zipIdx.map fun ((_, _, value), id) =>
    ({ id, type := .scalar (.signed .i32), value := .signed .i32 value } : Core.Constant)
  let pack : Declarations.SourcePack := { files := [{
    id := 0, moduleInfo := { id := 0, path := ["test"] }, origin := .synthetic
    contents := { items } }] }
  let program : Core.Program := { constants }
  let some catalog := CatalogSynthesis.check pack | throw "catalog setup failed"
  let some candidates := CoreBoundary.candidateRows? catalog.catalog | throw "row setup failed"
  let declarations ← (DeclarationCheck.checkDeclarations pack catalog.catalog
    catalog.wellFormed program candidates).mapError fun failure => reprStr failure
  let context := ContextSynthesis.synthesize pack catalog.catalog [] program
    declarations.rows declarations.aliases
  let checked := ConstantGraphCheck.check pack catalog.catalog program context.names context
    declarations.rows rfl rfl
  return checked.lowerings.length == definitions.length

def runChecks : IO Unit := do
  let cases : List (String × List (String × Surface.Expr × Int) × Bool) := [
    ("forward diamond", [
      ("RESULT", .binary .add (reference "LEFT") (reference "RIGHT"), 14),
      ("LEFT", reference "BASE", 7), ("RIGHT", reference "BASE", 7),
      ("BASE", literal "7", 7)], true),
    ("self cycle", [("SELF", reference "SELF", 7)], false),
    ("mutual cycle with consistent forged values", [
      ("LEFT", reference "RIGHT", 7), ("RIGHT", reference "LEFT", 7)], false),
    ("cycle behind an independent initializer", [
      ("BASE", literal "7", 7),
      ("LEFT", .binary .add (reference "RIGHT") (literal "0"), 7),
      ("RIGHT", .binary .add (reference "LEFT") (literal "0"), 7)], false),
    ("invented dependency value", [
      ("RESULT", reference "BASE", 8), ("BASE", literal "7", 8)], false),
    ("invented dependent value", [
      ("RESULT", reference "BASE", 8), ("BASE", literal "7", 7)], false),
    ("unknown dependency", [("RESULT", reference "MISSING", 7)], false)]
  for (label, definitions, expected) in cases do
    match accepts definitions with
    | .error failure => throw (IO.userError s!"{label}: {failure}")
    | .ok actual =>
        unless actual == expected do throw (IO.userError s!"{label}: got {actual}")
  IO.println s!"{cases.length} constant dependency checks passed, including forged cyclic values"
  let count := 1000
  let chain := (List.range count).map fun index =>
    (s!"C{index}", if index + 1 == count then literal "7" else reference s!"C{index + 1}", (7 : Int))
  let start ← IO.monoMsNow
  unless (accepts chain).toOption == some true do
    throw (IO.userError "long forward dependency chain rejected")
  IO.println s!"{count} forward constants checked in {(← IO.monoMsNow) - start} ms"

#print axioms ConstantGraphCheck.check

end Lanius.Compiler.ConstantGraphCheckTests

def main : IO Unit := Lanius.Compiler.ConstantGraphCheckTests.runChecks
