import Lanius.SurfaceElaboration
import Lanius.Typing.Check

namespace Lanius.Compiler.NamedTypeCheck

open Lanius

/- A named type is intentionally checked from semantic evidence rather than
  by reimplementing name lookup here.  The caller owns the qualified/imported
  `ResolvesGlobal` witness and the catalog's scheme/instance membership; this
  checker only assembles those facts into the existing TypeGrounds relation. -/
structure Candidate (context : SurfaceElaboration.Context)
    (path : Surface.Path) where
  symbol : Names.Symbol
  scheme : Static.NominalScheme
  resolvedInstance : Static.NominalInstance
  notBuiltin : Elaboration.builtinTypePath? path = none
  notShadowed : SurfaceElaboration.GlobalTypePathNotShadowed context path
  resolved : SurfaceElaboration.ResolvesGlobal context .type path symbol
  schemeMember : scheme ∈ context.nominalSchemes
  declaration : scheme.declaration = symbol.declaration
  surfaceArguments : List Surface.TypeExpr
  argumentsFound : SurfaceElaboration.pathTypeArguments? path = some surfaceArguments
  arguments : SurfaceElaboration.NominalArgumentsGround context
    scheme.genericParameters surfaceArguments resolvedInstance.typeArguments
    resolvedInstance.constArguments
  instantiated : SurfaceElaboration.NominalConstructorInstantiates context
    scheme.declaration scheme.type scheme.kind scheme.genericParameters
    scheme.requirements context.substitution resolvedInstance
  mapped : Static.NominalInstanceMapped context.monomorphization resolvedInstance

theorem nominal_arguments_unique
    (left : Static.NominalArgumentsBound substitution parameters
      leftTypes leftConstants)
    (right : Static.NominalArgumentsBound substitution parameters
      rightTypes rightConstants) :
    leftTypes = rightTypes ∧ leftConstants = rightConstants := by
  induction left generalizing rightTypes rightConstants with
  | nil => cases right; exact ⟨rfl, rfl⟩
  | @typeParameter parameter leftType leftTail leftTypes leftConstants
      leftFound leftRest induction =>
      cases right with
      | typeParameter rightFound rightRest =>
          have head : leftType = _ :=
            Option.some.inj (leftFound.symm.trans rightFound)
          cases head
          obtain ⟨types, constants⟩ := induction rightRest
          exact ⟨by simp [types], constants⟩
  | @constParameter parameter leftConstant leftTail leftTypes leftConstants
      leftFound leftRest induction =>
      cases right with
      | constParameter rightFound rightRest =>
          have head : leftConstant = _ :=
            Option.some.inj (leftFound.symm.trans rightFound)
          cases head
          obtain ⟨types, constants⟩ := induction rightRest
          exact ⟨types, by simp [constants]⟩

structure Checked (context : SurfaceElaboration.Context)
    (path : Surface.Path) (core : Core.Ty) where
  groundType : Static.GroundTy
  typed : Typing.Check.ProofOf
    (SurfaceElaboration.TypeGrounds context (.path path.segments) groundType)
  grounded : groundType.toCore context.monomorphization = some core
  candidate : Candidate context path

private theorem grounded_of_shape
    (candidate : Candidate context path)
    (shape : candidate.resolvedInstance.coreTy = core) :
    (Static.GroundTy.nominal candidate.scheme.type
        candidate.resolvedInstance.typeArguments candidate.resolvedInstance.constArguments).toCore
        context.monomorphization = some core := by
  have sourceType : candidate.scheme.type = candidate.resolvedInstance.sourceType :=
    candidate.instantiated.2.2.1.symm
  have mapped := candidate.mapped
  simp only [Static.GroundTy.toCore] at mapped ⊢
  rw [sourceType]
  rw [mapped]
  simpa [Static.NominalInstance.coreTy] using shape

/- The artifact relation already carries a coherence clause for all instances
   with the same source and arguments.  Exposing it here makes the resolver's
   uniqueness contract explicit and keeps downstream checkers from selecting
   a core type by list order. -/
theorem instance_coreType_unique
    (leftResolved rightResolved : Static.NominalInstance)
    (left : SurfaceElaboration.NominalConstructorInstantiates context declaration
      sourceType kind parameters requirements substitution leftResolved)
    (right : SurfaceElaboration.NominalConstructorInstantiates context declaration
      sourceType kind parameters requirements substitution rightResolved) :
    leftResolved.coreType = rightResolved.coreType := by
  have args := nominal_arguments_unique left.2.2.2.2.1 right.2.2.2.2.1
  exact (left.2.2.2.2.2.2 rightResolved right.1
    right.2.2.1 args.1.symm args.2.symm).symm

theorem instance_coreTy_unique
    (leftResolved rightResolved : Static.NominalInstance)
    (left : SurfaceElaboration.NominalConstructorInstantiates context declaration
      sourceType kind parameters requirements substitution leftResolved)
    (right : SurfaceElaboration.NominalConstructorInstantiates context declaration
      sourceType kind parameters requirements substitution rightResolved) :
    leftResolved.coreTy = rightResolved.coreTy := by
  have coreType := instance_coreType_unique (leftResolved := leftResolved)
    (rightResolved := rightResolved) left right
  have kind : leftResolved.kind = rightResolved.kind :=
    left.2.2.2.1.trans right.2.2.2.1.symm
  cases leftResolved with
  | mk leftDeclaration leftSource leftKind leftTypes leftConstants leftCore =>
      cases rightResolved with
      | mk rightDeclaration rightSource rightKind rightTypes rightConstants rightCore =>
          simp_all [Static.NominalInstance.coreTy]

def check (context : SurfaceElaboration.Context)
    (path : Surface.Path) (core : Core.Ty)
    (candidate : Candidate context path) :
    Option (Checked context path core) :=
  if coreShape : candidate.resolvedInstance.coreTy = core then
    some {
      groundType := .nominal candidate.scheme.type
        candidate.resolvedInstance.typeArguments candidate.resolvedInstance.constArguments
      typed := ⟨.nominal candidate.symbol candidate.notBuiltin
        candidate.notShadowed candidate.resolved candidate.schemeMember
        candidate.declaration candidate.argumentsFound candidate.arguments⟩
      grounded := grounded_of_shape candidate coreShape
      candidate := candidate }
  else none

end Lanius.Compiler.NamedTypeCheck
