import Lanius.Compiler.SignatureCheck
import Lanius.Typing.Check

namespace Lanius.Compiler.ExternalFunctionCheck

open Lanius
open Lanius.Compiler.ProgramLowering

/- The declaration checker supplies the source/catalog row.  This checker
   validates the remaining external-function boundary and returns the
   established lowering witness rather than introducing another relation. -/
inductive Failure where
  | sourceMismatch
  | catalogHeaderMissing
  | signature (failure : SignatureCheck.Failure)
  | abiMismatch
  | bodyMismatch
  | externalMismatch
  | illTyped
deriving DecidableEq, Repr

structure ExternalFunctionCandidate
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  declaration : Surface.ExternFunction
  sourceFound : pack.item? address = some (.externFunction declaration)
  source : row.occurrence = .item address
  core : Core.Function
  coreMap : row.core = .function core
  context : SurfaceElaboration.Context
  contextMatches : ContextMatches context baseContext environment row.header.moduleId

def check
    (resolver : ExternalBehaviorResolver)
    (candidate : ExternalFunctionCandidate pack catalog program environment
      baseContext rows) :
    Except Failure
      (ExternalFunctionLowering pack catalog program environment baseContext
        resolver rows) :=
  if _source : candidate.row.header.kind = .externalFunction then
    if _address : candidate.row.header.source = .item candidate.address then
      if _catalog : candidate.row.header ∈ catalog.headers then
        match _signature : SignatureCheck.checkExternFunction candidate.context
            candidate.declaration candidate.core with
        | .error failure => .error (.signature failure)
        | .ok checkedSignature =>
            if abi : candidate.declaration.abi = none then
              match body : candidate.core.body with
              | some _ => .error .bodyMismatch
              | none =>
                  if external : candidate.core.external = resolver candidate.row.header then
                    match _typed : Typing.Check.checkFunctionWellTyped program candidate.core with
                    | none => .error .illTyped
                    | some wellTyped =>
                        .ok {
                          row := candidate.row
                          rowMember := candidate.rowMember
                          address := candidate.address
                          declaration := candidate.declaration
                          sourceFound := candidate.sourceFound
                          source := candidate.source
                          core := candidate.core
                          coreMap := candidate.coreMap
                          context := candidate.context
                          parameters := checkedSignature.parameters.down
                          returnType := checkedSignature.returnType.down
                          contextMatches := candidate.contextMatches
                          abi := abi
                          behavior := external
                          coreShape := body
                          wellTyped := wellTyped.down }
                  else .error .externalMismatch
        else .error .abiMismatch
      else .error .catalogHeaderMissing
    else .error .sourceMismatch
  else .error .sourceMismatch

end Lanius.Compiler.ExternalFunctionCheck
