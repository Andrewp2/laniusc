import Lanius.Compiler.ExternalFunctionCheck

namespace Lanius.Compiler.ExternalFunctionCheckTests

open Lanius
open Lanius.Compiler.ProgramLowering
open Lanius.Compiler.ExternalFunctionCheck

def declaration : Surface.ExternFunction := { name := "panic_fn" }
def address : Declarations.ItemAddress := { file := 0, index := 0 }
def file : Declarations.SourceFile := {
  id := 0
  moduleInfo := { id := 0, path := ["test"] }
  contents := { items := [.externFunction declaration] }
  origin := .synthetic }
def pack : Declarations.SourcePack := { files := [file] }
def header : Declarations.DeclarationHeader := {
  source := .item address
  moduleId := 0
  declaration := 0
  kind := .externalFunction
  lookupNamespace := some .value
  name := some declaration.name
  visibility := .modulePrivate }
def catalog : Declarations.Catalog := { headers := [header] }
def core : Core.Function := {
  id := 0
  parameters := []
  returnType := .unit
  body := none
  external := some .panic }
def program : Core.Program := { functions := [core] }
def environment : Names.Environment := {}
def context : SurfaceElaboration.Context := {
  target := .x86_64
  names := environment
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  locals := [] }

def row : DeclarationLowering pack catalog program := {
  occurrence := .item address
  header := header
  core := .function core
  occurs := .externalFunction (address := address) (declaration := declaration)
    (file := file)
    (by change pack.file? 0 = some file; simp [pack, file, Declarations.SourcePack.file?])
    (by change pack.item? address = some (.externFunction declaration)
        simp [pack, file, address, Declarations.SourcePack.item?, Declarations.SourcePack.file?])
  inCatalog := by simp [catalog]
  source := rfl
  headerMatches := by
    exact .externalFunction (address := address) (function := declaration)
      (file := file)
      (by change pack.file? 0 = some file
          simp [pack, file, Declarations.SourcePack.file?])
      (by change pack.item? address = some (.externFunction declaration)
          simp [pack, file, address, Declarations.SourcePack.item?,
            Declarations.SourcePack.file?])
  member := by simp [CoreDeclaration.member, program]
  identified := by simp [CoreDeclaration.matches, header, core] }

def candidate : ExternalFunctionCandidate pack catalog program environment context [row] := {
  row := row
  rowMember := by simp
  address := address
  declaration := declaration
  sourceFound := by
    simp [pack, file, address, Declarations.SourcePack.item?,
      Declarations.SourcePack.file?]
  source := rfl
  core := core
  coreMap := by simp [row]
  context := context
  contextMatches := by simp [ContextMatches, environment, context, row, header] }

def resolver : ExternalBehaviorResolver := fun _ => some .panic
def wrongResolver : ExternalBehaviorResolver := fun _ => some .unreachable

example : (check resolver candidate).isOk = true := by
  decide

example : (check wrongResolver candidate).isOk = false := by
  decide

def bodyCore : Core.Function := { core with body := some .skip }

example :
    (Typing.Check.checkFunctionWellTyped program bodyCore).isSome = false := by
  rfl

end Lanius.Compiler.ExternalFunctionCheckTests
