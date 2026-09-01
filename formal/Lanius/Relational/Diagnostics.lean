import Lanius.Relational.CheckedProgram

namespace Lanius.Relational.Diagnostics

open Lanius.Relational

inductive Kind where
  | missingSpecification
  | missingRepresentation (fact : String)
  | missingLoopInvariant
deriving DecidableEq, Repr

/-- A source-oriented verification-condition failure.  The identity is a
checked handle projection, never a numeric Core function identifier. -/
structure Diagnostic where
  kind : Kind
  source : SourceIdentity
deriving DecidableEq, Repr

def location (source : SourceIdentity) : String :=
  match source.span with
  | none => source.path
  | some span =>
      s!"{source.path}:{span.start.line}:{span.start.column}"

def Diagnostic.render (diagnostic : Diagnostic) : String :=
  let location := location diagnostic.source
  match diagnostic.kind with
  | .missingSpecification =>
      s!"missing Lanius specification for {diagnostic.source.name} at {location}"
  | .missingRepresentation fact =>
      s!"missing representation fact '{fact}' for {diagnostic.source.name} at {location}"
  | .missingLoopInvariant =>
      s!"missing loop invariant for {diagnostic.source.name} at {location}"

def missingSpecification (source : SourceIdentity) : Diagnostic :=
  ⟨.missingSpecification, source⟩

def missingRepresentation (source : SourceIdentity)
    (fact : String) : Diagnostic :=
  ⟨.missingRepresentation fact, source⟩

def missingLoopInvariant (source : SourceIdentity) : Diagnostic :=
  ⟨.missingLoopInvariant, source⟩

/-- Resolve a generated specification table entry or emit exactly one
source-local VC instead of exposing a failed numeric dispatch. -/
def requireSpecification (source : SourceIdentity) (entry : Option α) :
    Except Diagnostic α :=
  match entry with
  | some value => .ok value
  | none => .error (missingSpecification source)

def requireRepresentation (source : SourceIdentity) (fact : String)
    (evidence : Option α) : Except Diagnostic α :=
  match evidence with
  | some value => .ok value
  | none => .error (missingRepresentation source fact)

def requireLoopInvariant (source : SourceIdentity) (invariant : Option α) :
    Except Diagnostic α :=
  match invariant with
  | some value => .ok value
  | none => .error (missingLoopInvariant source)

theorem missingSpecification_render_example :
    (missingSpecification {
      path := "verified_compiler/src/verified/lexer.lani"
      name := "verified::lexer::is_identifier_continue"
      span := some ⟨⟨22, 1, none⟩, ⟨22, 1, none⟩⟩
    }).render =
      "missing Lanius specification for verified::lexer::is_identifier_continue at verified_compiler/src/verified/lexer.lani:22:1" := by
  decide +kernel

end Lanius.Relational.Diagnostics
