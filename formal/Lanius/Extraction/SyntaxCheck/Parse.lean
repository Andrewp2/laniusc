import Lanius.Extraction.GeneratedGrammar
import Lanius.Extraction.SyntaxCheck.Lexer

namespace Lanius.Extraction.SyntaxCheck

open Lanius.Compiler
open Lanius.Compiler.Lexer

/-! A parse certificate checks only the grammar lattice over an authenticated
    canonical lexer trace.  It does not certify parser completeness or any
    later Surface/Core interpretation. -/

def packedFlag : Nat := 2147483648
def packedLimit : Nat := 4294967296
def packedKindBase : Nat := 32768

def packed (code : Nat) : Bool := packedFlag ≤ code && code < packedLimit
def packedInner (code : Nat) : Nat := code % packedKindBase
def packedOuter (code : Nat) : Nat := (code / packedKindBase) % packedKindBase

def canonicalKind? (grammar : Grammar) (code : Nat) : Option Nat :=
  grammar.canonical_kinds[code]?

def semanticKindMatches (grammar : Grammar) (token : RawToken) (code : Nat) : Bool :=
  if packed code then
    token.kind.gpuCode = grammar.split_token_kind &&
      canonicalKind? grammar (packedInner code) = some grammar.split_component_kind &&
      canonicalKind? grammar (packedOuter code) = some grammar.split_component_kind
  else
    code < grammar.n_kinds &&
      canonicalKind? grammar code = some token.kind.gpuCode

def semanticKindsLoop (grammar : Grammar) (tokens : Array RawToken)
    (semantic : Array Nat) : Nat → Bool
  | 0 => true
  | remaining + 1 =>
      let index := tokens.size - (remaining + 1)
      match tokens[index]?, semantic[index]? with
      | some token, some code =>
          semanticKindMatches grammar token code &&
            semanticKindsLoop grammar tokens semantic remaining
      | _, _ => false

def semanticKindsValidArray (grammar : Grammar)
    (tokens : Array RawToken) (semantic : Array Nat) : Bool :=
  tokens.size = semantic.size && semanticKindsLoop grammar tokens semantic tokens.size

def semanticKindsValid (grammar : Grammar) (tokens : List RawToken)
    (semantic : List Nat) : Bool :=
  semanticKindsValidArray grammar tokens.toArray semantic.toArray

def advanceTerminal (_grammar : Grammar) (semantic : Array Nat)
    (position expected : Nat) : Option Nat := do
  let code ← semantic[position / 2]?
  if packed code then
    let actual := if position % 2 = 0 then packedInner code else packedOuter code
    if actual = expected then some (position + 1) else none
  else if position % 2 = 0 && code = expected then
    some (position + 2)
  else
    none

def checkChildren (grammar : Grammar) (semantic : Array Nat)
    (nodes : Array ParseNode) (current : Nat) :
    List Nat → List ParseChild → Nat → Option Nat
  | [], [], position => some position
  | symbol :: symbols, child :: children, position =>
      if symbol < grammar.n_kinds then
        match child with
        | .token tokenId => do
            if tokenId != position / 2 then none
            let next ← advanceTerminal grammar semantic position symbol
            checkChildren grammar semantic nodes current symbols children next
        | .node _ => none
      else
        let nonterminal := symbol - grammar.n_kinds
        if nonterminal >= grammar.n_nonterminals then none
        else match child with
        | .token _ => none
        | .node childId => do
            if childId >= current then none
            let childNode ← nodes[childId]?
            if childNode.nonterminal != nonterminal ||
                childNode.position_start != position then none
            checkChildren grammar semantic nodes current symbols children
              childNode.position_end
  | _, _, _ => none

def checkNode (grammar : Grammar) (productions : Array Production)
    (semantic : Array Nat) (nodes : Array ParseNode)
    (id : Nat) (node : ParseNode) : Bool :=
  match productions[node.production]? with
  | none => false
  | some production =>
      node.nonterminal = production.lhs &&
        node.position_start ≤ node.position_end &&
        node.position_end ≤ semantic.size * 2 &&
        checkChildren grammar semantic nodes id production.rhs node.children
          node.position_start = some node.position_end

def checkNodesLoop (grammar : Grammar) (productions : Array Production)
    (semantic : Array Nat) (nodes : Array ParseNode) : Nat → Bool
  | 0 => true
  | remaining + 1 =>
      let id := nodes.size - (remaining + 1)
      match nodes[id]? with
      | some node =>
          checkNode grammar productions semantic nodes id node &&
            checkNodesLoop grammar productions semantic nodes remaining
      | none => false

def parseNodesValidArray (grammar : Grammar) (semantic : Array Nat)
    (nodes : Array ParseNode) : Bool :=
  checkNodesLoop grammar grammar.productions.toArray semantic nodes nodes.size

def parseNodesValid (grammar : Grammar) (semantic : List Nat)
    (nodes : List ParseNode) : Bool :=
  parseNodesValidArray grammar semantic.toArray nodes.toArray

def rootValidArray (grammar : Grammar) (tokenCount : Nat)
    (nodes : Array ParseNode) (root : Nat) : Bool :=
  match nodes[root]? with
  | none => false
  | some node =>
      root + 1 = nodes.size && node.nonterminal = grammar.start_nonterminal &&
        node.position_start = 0 && node.position_end = tokenCount * 2

def rootValid (grammar : Grammar) (tokenCount : Nat)
    (nodes : List ParseNode) (root : Nat) : Bool :=
  rootValidArray grammar tokenCount nodes.toArray root

structure CheckedParseUnit
    {source : SourceFile} {rawWire canonicalWire : List Extraction.Token}
    (lexer : CheckedLexerUnit source rawWire canonicalWire)
    (grammar : Grammar) (semantic : List Nat) (nodes : List ParseNode)
    (parseRoot : Option ParseNodeId) where
  root : ParseNodeId
  rootFound : parseRoot = some root
  semanticAccepted : semanticKindsValid grammar lexer.canonical semantic = true
  nodesAccepted : parseNodesValid grammar semantic nodes = true
  rootAccepted : rootValid grammar lexer.canonical.length nodes root = true

inductive ParseCheckStage where
  | semanticKinds
  | nodes
  | root
deriving DecidableEq, Repr

def checkParseUnit
    {source : SourceFile} {rawWire canonicalWire : List Extraction.Token}
    (lexer : CheckedLexerUnit source rawWire canonicalWire)
    (grammar : Grammar) (semantic : List Nat) (nodes : List ParseNode)
    (parseRoot : Option ParseNodeId) :
    Except ParseCheckStage
      (CheckedParseUnit lexer grammar semantic nodes parseRoot) :=
  if semanticAccepted : semanticKindsValid grammar lexer.canonical semantic = true then
    if nodesAccepted : parseNodesValid grammar semantic nodes = true then
      match root : parseRoot with
      | none => .error .root
      | some rootId =>
          if rootAccepted : rootValid grammar lexer.canonical.length nodes rootId = true then
            .ok {
              root := rootId
              rootFound := by rfl
              semanticAccepted := semanticAccepted
              nodesAccepted := nodesAccepted
              rootAccepted := rootAccepted
            }
          else
            .error .root
    else
      .error .nodes
  else
    .error .semanticKinds

theorem checkParseUnit_sound
    {source : SourceFile} {rawWire canonicalWire : List Extraction.Token}
    {lexer : CheckedLexerUnit source rawWire canonicalWire}
    {grammar : Grammar} {semantic : List Nat} {nodes : List ParseNode}
    {parseRoot : Option ParseNodeId}
    {checked : CheckedParseUnit lexer grammar semantic nodes parseRoot}
    (_accepted : checkParseUnit lexer grammar semantic nodes parseRoot = .ok checked) :
    parseRoot = some checked.root ∧
      semanticKindsValid grammar lexer.canonical semantic = true ∧
      parseNodesValid grammar semantic nodes = true ∧
      rootValid grammar lexer.canonical.length nodes checked.root = true := by
  exact ⟨checked.rootFound, checked.semanticAccepted, checked.nodesAccepted,
    checked.rootAccepted⟩

end Lanius.Extraction.SyntaxCheck
