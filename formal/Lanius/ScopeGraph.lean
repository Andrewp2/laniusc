import Lanius.Names

namespace Lanius.ScopeGraph

open Lanius

/-!
Proof-facing name resolution for located Lanius syntax.

The source AST keeps user spellings and source identities. This graph makes
lexical scope a first-class object and gives every accepted reference a path to
its declaration. Numeric Core locals deliberately do not appear here: they are
assigned only when a checked scoped program is elaborated to Core.
-/

/-- Stable, source-derived identities for lexical regions. A declaration
    extends the scope of the statements after it; branch and loop bodies form
    distinct children even when the Core allocator later reuses local IDs. -/
inductive ScopeId where
  | functionBody (declaration : Nat)
  | afterLocal (declaration : Nat)
  | thenBody (declaration : Nat)
  | elseBody (declaration : Nat)
  | loopBody (declaration : Nat)
  | blockBody (declaration : Nat)
deriving BEq, DecidableEq, Repr

/-- Surface identities are local to one source-pack unit. -/
structure DeclarationId where
  unit : Nat
  node : Nat
deriving BEq, DecidableEq, Repr

structure Declaration where
  id : DeclarationId
  lookupNamespace : Names.LookupNamespace
  name : String
deriving BEq, DecidableEq, Repr

structure Scope where
  id : ScopeId
  parent : Option ScopeId
  declarations : List Declaration := []
deriving BEq, DecidableEq, Repr

structure Graph where
  scopes : List Scope
deriving BEq, DecidableEq, Repr

structure Reference where
  unit : Nat
  node : Nat
  scope : ScopeId
  target : Names.Reference
deriving BEq, DecidableEq, Repr

def Reference.lookupNamespace : Reference → Names.LookupNamespace
  | ⟨_, _, _, .unqualified lookupNamespace _⟩ => lookupNamespace
  | ⟨_, _, _, .qualified lookupNamespace _ _⟩ => lookupNamespace

def Reference.name : Reference → String
  | ⟨_, _, _, .unqualified _ name⟩ => name
  | ⟨_, _, _, .qualified _ _ name⟩ => name

def Graph.scope? (graph : Graph) (id : ScopeId) : Option Scope :=
  graph.scopes.find? (fun scope => scope.id == id)

def declarationMatches
    (lookupNamespace : Names.LookupNamespace) (name : String)
    (declaration : Declaration) : Bool :=
  declaration.lookupNamespace == lookupNamespace && declaration.name == name

def Scope.declaration?
    (scope : Scope) (lookupNamespace : Names.LookupNamespace)
    (name : String) : Option Declaration :=
  scope.declarations.find? (declarationMatches lookupNamespace name)

def allDistinct [BEq α] : List α → Bool
  | [] => true
  | head :: tail => !tail.contains head && allDistinct tail

def Scope.declarationKeys (scope : Scope) :
    List (Names.LookupNamespace × String) :=
  scope.declarations.map fun declaration =>
    (declaration.lookupNamespace, declaration.name)

def parentsPrecede : List ScopeId → List Scope → Bool
  | _, [] => true
  | earlier, scope :: tail =>
      (match scope.parent with
       | none => earlier.isEmpty
       | some parent => earlier.contains parent) &&
        parentsPrecede (scope.id :: earlier) tail

def Graph.declarationIds (graph : Graph) : List DeclarationId :=
  graph.scopes.flatMap fun scope => scope.declarations.map (·.id)

/-- The executable resolver's structural precondition. Builders emit the root
    first and every child after its parent, ruling out missing parents and
    cycles without a separate graph search. -/
def Graph.wellFormed (graph : Graph) : Bool :=
  allDistinct (graph.scopes.map (·.id)) &&
    allDistinct graph.declarationIds &&
    graph.scopes.all (allDistinct ·.declarationKeys) &&
    parentsPrecede [] graph.scopes

structure CheckedGraph where
  graph : Graph
  wellFormed : graph.wellFormed = true

/-- Declarative lexical resolution. The path starts at the reference scope
    and ends at the first enclosing scope with a matching declaration. -/
inductive ResolvesFrom (graph : Graph)
    (lookupNamespace : Names.LookupNamespace) (name : String) :
    ScopeId → Declaration → List ScopeId → Prop where
  | here
      (scopeFound : graph.scope? scopeId = some scope)
      (selected : scope.declaration? lookupNamespace name = some declaration) :
      ResolvesFrom graph lookupNamespace name scopeId declaration [scopeId]
  | parent
      (scopeFound : graph.scope? scopeId = some scope)
      (absent : scope.declaration? lookupNamespace name = none)
      (parentFound : scope.parent = some parentId)
      (outer : ResolvesFrom graph lookupNamespace name parentId declaration path) :
      ResolvesFrom graph lookupNamespace name scopeId declaration (scopeId :: path)

def Resolves
    (graph : Graph) (reference : Reference)
    (declaration : Declaration) (path : List ScopeId) : Prop :=
  match reference.target with
  | .unqualified lookupNamespace name =>
      ResolvesFrom graph lookupNamespace name reference.scope declaration path
  | .qualified _ _ _ => False

/-- Executable resolution is fuelled so malformed cyclic graphs remain total.
    A graph constructor proves acyclicity separately. -/
def resolveFrom? (graph : Graph) :
    Nat → ScopeId → Names.LookupNamespace → String →
      Option (Declaration × List ScopeId)
  | 0, _, _, _ => none
  | fuel + 1, scopeId, lookupNamespace, name => do
      let scope ← graph.scope? scopeId
      match scope.declaration? lookupNamespace name with
      | some declaration => some (declaration, [scopeId])
      | none =>
          let parentId ← scope.parent
          let (declaration, path) ←
            resolveFrom? graph fuel parentId lookupNamespace name
          some (declaration, scopeId :: path)

def resolve? (graph : Graph) (reference : Reference) :
    Option (Declaration × List ScopeId) :=
  match reference.target with
  | .unqualified lookupNamespace name =>
      resolveFrom? graph (graph.scopes.length + 1) reference.scope
        lookupNamespace name
  | .qualified _ _ _ => none

/-- Canonical lexical path from a scope to its function root. This is also
    the path recorded for a reference that leaves lexical lookup and proceeds
    to module/global lookup. -/
def enclosingPathFrom? (graph : Graph) : Nat → ScopeId → Option (List ScopeId)
  | 0, _ => none
  | fuel + 1, scopeId => do
      let scope ← graph.scope? scopeId
      match scope.parent with
      | none => some [scopeId]
      | some parentId =>
          let outer ← enclosingPathFrom? graph fuel parentId
          some (scopeId :: outer)

def enclosingPath? (graph : Graph) (scopeId : ScopeId) : Option (List ScopeId) :=
  enclosingPathFrom? graph (graph.scopes.length + 1) scopeId

theorem resolveFrom?_sound
    (accepted : resolveFrom? graph fuel scopeId lookupNamespace name =
      some (declaration, path)) :
    ResolvesFrom graph lookupNamespace name scopeId declaration path := by
  induction fuel generalizing scopeId declaration path with
  | zero => simp [resolveFrom?] at accepted
  | succ fuel inductionHypothesis =>
      simp only [resolveFrom?] at accepted
      cases scopeFound : graph.scope? scopeId with
      | none => simp [scopeFound] at accepted
      | some scope =>
          rw [scopeFound] at accepted
          change (match scope.declaration? lookupNamespace name with
            | some selected => some (selected, [scopeId])
            | none => do
                let parentId ← scope.parent
                let (outerDeclaration, outerPath) ←
                  resolveFrom? graph fuel parentId lookupNamespace name
                some (outerDeclaration, scopeId :: outerPath)) =
              some (declaration, path) at accepted
          cases declarationFound : scope.declaration? lookupNamespace name with
          | some selected =>
              have pairEquality :
                  (selected, [scopeId]) = (declaration, path) :=
                Option.some.inj (by
                  simpa [declarationFound] using accepted)
              cases pairEquality
              exact .here scopeFound declarationFound
          | none =>
              cases parentFound : scope.parent with
              | none => simp [declarationFound, parentFound] at accepted
              | some parentId =>
                  cases recursiveFound :
                      resolveFrom? graph fuel parentId lookupNamespace name with
                  | none =>
                      simp [declarationFound, parentFound, recursiveFound]
                        at accepted
                  | some result =>
                      obtain ⟨outerDeclaration, outerPath⟩ := result
                      have pairEquality :
                          (outerDeclaration, scopeId :: outerPath) =
                            (declaration, path) :=
                        Option.some.inj (by
                          simpa [declarationFound, parentFound, recursiveFound]
                            using accepted)
                      cases pairEquality
                      exact .parent scopeFound declarationFound parentFound
                        (inductionHypothesis recursiveFound)

theorem resolve?_sound
    (accepted : resolve? graph reference = some (declaration, path)) :
    Resolves graph reference declaration path := by
  cases reference with
  | mk unit node scope target =>
      cases target with
      | unqualified lookupNamespace name =>
          exact resolveFrom?_sound accepted
      | qualified lookupNamespace modulePath name =>
          simp [resolve?] at accepted

theorem resolveFrom?_complete
    (resolved : ResolvesFrom graph lookupNamespace name scopeId declaration path) :
    resolveFrom? graph path.length scopeId lookupNamespace name =
      some (declaration, path) := by
  induction resolved with
  | here scopeFound selected => simp [resolveFrom?, scopeFound, selected]
  | parent scopeFound absent parentFound outer inductionHypothesis =>
      simp [resolveFrom?, scopeFound, absent, parentFound,
        inductionHypothesis]

/-- A checked reference is the proof-producing result consumed by later
    frontend phases. -/
structure CheckedReference (graph : Graph) (reference : Reference) where
  declaration : Declaration
  path : List ScopeId
  accepted : resolve? graph reference = some (declaration, path)

def checkReference? (graph : Graph) (reference : Reference) :
    Option (CheckedReference graph reference) :=
  match accepted : resolve? graph reference with
  | none => none
  | some (declaration, path) => some ⟨declaration, path, accepted⟩

theorem CheckedReference.sound
    (checked : CheckedReference graph reference) :
    Resolves graph reference checked.declaration checked.path :=
  resolve?_sound checked.accepted

/-! Focused executable contracts. -/

private def outerX : Declaration :=
  ⟨⟨0, 10⟩, .value, "x"⟩

private def innerX : Declaration :=
  ⟨⟨0, 20⟩, .value, "x"⟩

private def exampleGraph : Graph := ⟨[
  ⟨.functionBody 1, none, [outerX]⟩,
  ⟨.thenBody 2, some (.functionBody 1), []⟩,
  ⟨.afterLocal 20, some (.thenBody 2), [innerX]⟩,
  ⟨.elseBody 2, some (.functionBody 1), []⟩
]⟩

example : resolve? exampleGraph
    ⟨0, 30, .afterLocal 20, .unqualified .value "x"⟩ =
    some (innerX, [ScopeId.afterLocal 20]) := by native_decide

example : resolve? exampleGraph
    ⟨0, 31, .thenBody 2, .unqualified .value "x"⟩ =
    some (outerX, [ScopeId.thenBody 2, ScopeId.functionBody 1]) := by native_decide

example : resolve? exampleGraph
    ⟨0, 32, .elseBody 2, .unqualified .value "x"⟩ =
    some (outerX, [ScopeId.elseBody 2, ScopeId.functionBody 1]) := by native_decide

example : resolve? exampleGraph
    ⟨0, 33, .elseBody 2, .unqualified .value "missing"⟩ =
    none := by native_decide

example : resolve? exampleGraph
    ⟨0, 34, .afterLocal 20, .qualified .value ["other"] "x"⟩ =
    none := by native_decide

end Lanius.ScopeGraph
