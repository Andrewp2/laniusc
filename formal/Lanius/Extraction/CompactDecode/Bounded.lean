import Lanius.Extraction.CompactDecode.Validation

namespace Lanius.Extraction.CompactDecode.Bounded
open SemanticTokens Lanius.Compiler.Parser

/-! Typed quotation data for compact scalar fields. This changes neither the serializer
nor the authoritative decoder: `Unit.data` uses their existing proof view.
List lengths remain checked; no native proposal supplies proof authority. -/

inductive Child where
  | token (id : UInt32)
  | node (id : UInt32)

def Child.visit : Child → ChildVisit
  | .token id => .token ⟨0, 0, id.toNat, 0⟩
  | .node id => .node id.toNat 0 0

theorem Child.payloadFit (child : Child) :
    (childPayload child.visit.reference).toNat < 4294967296 := by
  cases child with
  | token id => exact id.toNat_lt
  | node id => exact id.toNat_lt

structure Node where
  production : Fin laniusGrammar.productions.length
  start : UInt32
  finish : UInt32
  children : List Child

/-- Keep the symbolic bound in the quoted constructor's type. A quotation of
`Fin` at its evaluated numeric size otherwise makes every declaration reduce
the complete grammar list just to compare those two types. -/
def productionIndex (value : Nat) : Fin laniusGrammar.productions.length :=
  ⟨value % laniusGrammar.productions.length, Nat.mod_lt _ (by decide +kernel)⟩

def Node.visit (node : Node) : RecordVisit :=
  ⟨0, node.production.val, node.start.toNat, node.finish.toNat, node.children.map Child.visit⟩

theorem Node.encodable (node : Node) (count : node.children.length < 4294967296) :
    NodeEncodable node.visit := by
  apply (NodeEncodable.iff_bounds node.visit).mpr
  refine ⟨node.production.isLt,
    Nat.lt_trans node.production.isLt (by decide +kernel),
    node.start.toNat_lt, node.finish.toNat_lt, ?_, ?_⟩
  · simpa only [Node.visit, List.length_map] using count
  · intro child member
    obtain ⟨original, _, rfl⟩ := List.mem_map.mp member
    exact original.payloadFit

structure Token where
  kind : Lanius.Compiler.TokenKind
  start : UInt32
  finish : UInt32

def Token.raw (token : Token) : Lanius.Compiler.Lexer.RawToken :=
  ⟨token.kind, token.start.toNat, token.finish.toNat⟩

theorem Token.fields (token : Token) :
    token.raw.kind.gpuCode < 4294967296 ∧ token.raw.start < 4294967296 ∧
      token.raw.finish < 4294967296 := by
  refine ⟨?_, token.start.toNat_lt, token.finish.toNat_lt⟩
  change token.kind.gpuCode < 4294967296
  cases token.kind <;> decide +kernel

structure Kinds where
  first : UInt32
  second : Option (Fin 4294967295)

def Kinds.assignment (kinds : Kinds) : Assignment :=
  ⟨kinds.first.toNat, kinds.second.map Fin.val⟩

theorem Kinds.fields (kinds : Kinds) :
    kinds.assignment.first < 4294967296 ∧
      (CompactOutput.Assignments.secondWord kinds.assignment + 1).toNat < 4294967296 := by
  refine ⟨kinds.first.toNat_lt, ?_⟩
  cases found : kinds.second with
  | none => simp [Kinds.assignment, CompactOutput.Assignments.secondWord, found]
  | some second =>
    have bound := second.isLt
    simp only [Kinds.assignment, found, Option.map_some, CompactOutput.Assignments.secondWord]
    omega

structure Unit where
  path : String
  source : ByteArray
  raw : List Token
  tokens : List Token
  assignments : List Kinds
  nodes : List Node

def Unit.data (unit : Unit) : UnitData :=
  ⟨unit.path, unit.source, unit.raw.map Token.raw, unit.tokens.map Token.raw,
    unit.assignments.map Kinds.assignment, unit.nodes.map Node.visit⟩

def Unit.check (unit : Unit) : Bool :=
  Nat.blt unit.path.toUTF8.size 4294967296 && Nat.blt unit.source.size 4294967296 &&
  Nat.blt unit.raw.length 4294967296 && Nat.blt unit.tokens.length 4294967296 &&
  Nat.blt unit.nodes.length 4294967296 &&
  unit.assignments.length == unit.tokens.length &&
  unit.nodes.all (fun node => Nat.blt node.children.length 4294967296)

theorem Unit.encodable (unit : Unit) (checked : unit.check = true) : unit.data.Encodable := by
  simp only [Unit.check, Bool.and_eq_true, Nat.blt_eq, List.all_eq_true, beq_iff_eq] at checked
  rcases checked with ⟨⟨⟨⟨⟨⟨path, source⟩, raw⟩, tokens⟩, nodes⟩, assignments⟩, children⟩
  refine ⟨path, source, by simpa [Unit.data] using raw,
    by simpa [Unit.data] using tokens, by simpa [Unit.data] using nodes, ?_, ?_, ?_,
    by simpa [Unit.data] using assignments, ?_⟩
  · intro token member
    obtain ⟨original, _, rfl⟩ := List.mem_map.mp member
    exact original.fields
  · intro token member
    obtain ⟨original, _, rfl⟩ := List.mem_map.mp member
    exact original.fields
  · intro kinds member
    obtain ⟨original, _, rfl⟩ := List.mem_map.mp member
    exact original.fields
  · intro node member
    obtain ⟨original, inNodes, rfl⟩ := List.mem_map.mp member
    exact original.encodable (children original inNodes)

def checkPack (units : List Unit) : Bool :=
  !units.isEmpty && Nat.blt units.length 4294967296 &&
  units.all (fun unit => unit.check && !unit.nodes.isEmpty)

theorem packEncodable (units : List Unit) (checked : checkPack units = true) :
    PackEncodable (units.map Unit.data) := by
  simp only [checkPack, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff,
    Nat.blt_eq, List.all_eq_true] at checked
  refine ⟨by simpa using checked.1.1, by simpa using checked.1.2, ?_⟩
  intro unit member
  obtain ⟨original, inUnits, rfl⟩ := List.mem_map.mp member
  have valid := checked.2 original inUnits
  exact ⟨original.encodable valid.1, by simpa [Unit.data] using valid.2⟩

end Lanius.Extraction.CompactDecode.Bounded
