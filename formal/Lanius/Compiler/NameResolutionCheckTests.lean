import Lanius.Compiler.NameResolutionCheck

namespace Lanius.Compiler.NameResolutionCheckTests

open Lanius
open Lanius.Compiler.NameResolutionCheck

def app : Names.Module := { id := 1, path := ["app"] }
def lib : Names.Module := { id := 2, path := ["lib"] }
def other : Names.Module := { id := 3, path := ["other"] }

def localRun : Names.Symbol := {
  moduleId := 1, lookupNamespace := .value, name := "run",
  visibility := .modulePrivate, declaration := 10 }

def importedRun : Names.Symbol := {
  moduleId := 2, lookupNamespace := .value, name := "run",
  visibility := .exported, declaration := 20 }

def importedRunAgain : Names.Symbol := {
  moduleId := 3, lookupNamespace := .value, name := "run",
  visibility := .exported, declaration := 20 }

def conflictingRun : Names.Symbol := { importedRun with declaration := 21 }

def environment : Names.Environment := {
  modules := [app, lib, other]
  symbols := [localRun, importedRun, importedRunAgain]
  imports := [{ importer := 1, imported := 2 }, { importer := 1, imported := 3 }] }

def ambiguousEnvironment : Names.Environment :=
  { environment with symbols := [importedRun, conflictingRun] }

def importedEnvironment : Names.Environment :=
  { environment with symbols := [importedRun] }

def duplicateDeclarationEnvironment : Names.Environment :=
  { environment with symbols := [importedRun, importedRunAgain] }

def localReference : Names.Reference := .unqualified .value "run"
def importedReference : Names.Reference := .unqualified .value "run"
def ownReference : Names.Reference := .qualified .value ["app"] "run"
def qualifiedImportReference : Names.Reference := .qualified .value ["lib"] "run"

example : (check environment 1 localReference).isSome = true := by decide
example : (check environment 1 ownReference).isSome = true := by decide
example : (check importedEnvironment 1 importedReference).isSome = true := by decide
example : (check importedEnvironment 1 qualifiedImportReference).isSome = true := by decide
example : (check duplicateDeclarationEnvironment 1 importedReference).isSome = true := by decide

example : (check environment 1 (.unqualified .value "run")).isSome = true := by decide

example :
    (check { environment with symbols := [localRun, importedRun] } 1 localReference).isSome = true := by
  decide

example : (check ambiguousEnvironment 1 importedReference).isSome = false := by decide

example :
    (checkGlobal
      { names := environment, currentModule := 1,
        monomorphization := { resolveNominal := fun _ _ _ => none } }
      .value { segments := [.mk "run" []] }).isSome = true := by
  decide

example :
    (checkGlobal
      { names := environment, currentModule := 1,
        monomorphization := { resolveNominal := fun _ _ _ => none } }
      .value { segments := [.mk "lib" [], .mk "run" []] }).isSome = true := by
  decide

end Lanius.Compiler.NameResolutionCheckTests
