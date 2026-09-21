import Lean.Elab.Tactic.Omega
import Lanius.Extraction.SyntaxCheck.Parse

namespace Lanius.Extraction.SyntaxCheck

open Lanius.Compiler
open Lanius.Compiler.Lexer

def SemanticWitness (grammar : Grammar) (tokens : List RawToken)
    (semantic : List Nat) : Prop :=
  tokens.length = semantic.length ∧
    ∀ (index : Nat) token code, tokens[index]? = some token → semantic[index]? = some code →
      semanticKindMatches grammar token code = true

theorem semanticKindsLoop_suffix
    (grammar : Grammar) (tokens : Array RawToken) (semantic : Array Nat)
    (sizes : tokens.size = semantic.size) :
    ∀ remaining, remaining ≤ tokens.size →
      semanticKindsLoop grammar tokens semantic remaining = true →
      ∀ index, tokens.size - remaining ≤ index → index < tokens.size →
        ∃ token code, tokens[index]? = some token ∧ semantic[index]? = some code ∧
          semanticKindMatches grammar token code = true := by
  intro remaining
  induction remaining with
  | zero =>
      intro bound valid index lower upper
      omega
  | succ remaining ih =>
      intro bound valid index lower upper
      change (match tokens[tokens.size - (remaining + 1)]?, semantic[tokens.size - (remaining + 1)]? with
          | some token, some code =>
              semanticKindMatches grammar token code &&
                semanticKindsLoop grammar tokens semantic remaining
          | _, _ => false) = true at valid
      split at valid
      next tokenFound codeFound =>
        simp only [Bool.and_eq_true] at valid
        rcases valid with ⟨current, rest⟩
        by_cases same : index = tokens.size - (remaining + 1)
        · subst index
          exact ⟨_, _, tokenFound, codeFound, current⟩
        · have later : tokens.size - remaining ≤ index := by omega
          exact ih (by omega) rest index later upper
      next => simp at valid

theorem semanticKindsValid_witness
    (grammar : Grammar) (tokens : List RawToken) (semantic : List Nat)
    (accepted : semanticKindsValid grammar tokens semantic = true) :
    SemanticWitness grammar tokens semantic := by
  unfold SemanticWitness
  constructor
  · unfold semanticKindsValid semanticKindsValidArray at accepted
    simp only [Bool.and_eq_true] at accepted
    have arrayEq : tokens.toArray.size = semantic.toArray.size :=
      of_decide_eq_true accepted.1
    simpa using arrayEq
  · intro index token code tokenAt codeAt
    unfold semanticKindsValid semanticKindsValidArray at accepted
    simp only [Bool.and_eq_true] at accepted
    have sizeEq : tokens.length = semantic.length := by
      have arrayEq : tokens.toArray.size = semantic.toArray.size :=
        of_decide_eq_true accepted.1
      simpa using arrayEq
    have indexBound : index < tokens.length := List.getElem?_eq_some_iff.mp tokenAt |>.1
    have tokenAt' : tokens.toArray[index]? = some token := by simpa using tokenAt
    have codeAt' : semantic.toArray[index]? = some code := by simpa using codeAt
    obtain ⟨foundToken, foundCode, foundTokenAt, foundCodeAt, sound⟩ :=
      semanticKindsLoop_suffix grammar tokens.toArray semantic.toArray (by simpa using sizeEq)
        tokens.length (by simp) (by simpa using accepted.2) index (by simp [sizeEq])
        (by simpa using indexBound)
    have sameToken : foundToken = token := Option.some.inj (foundTokenAt.symm.trans tokenAt')
    have sameCode : foundCode = code := Option.some.inj (foundCodeAt.symm.trans codeAt')
    simpa [sameToken, sameCode] using sound

theorem token_of_semanticAt
    (witness : SemanticWitness grammar tokens semantic) (index code : Nat)
    (codeAt : semantic.toArray[index]? = some code) :
    ∃ token, tokens[index]? = some token ∧
      semanticKindMatches grammar token code = true := by
  have codeAt' : semantic[index]? = some code := by simpa using codeAt
  have semBound : index < semantic.length := List.getElem?_eq_some_iff.mp codeAt' |>.1
  have sizes : tokens.length = semantic.length := witness.1
  have tokBound : index < tokens.length := by omega
  refine ⟨tokens[index], ?_, ?_⟩
  · simp [tokBound]
  · exact witness.2 index tokens[index] code (by simp [tokBound]) codeAt'

theorem checkNodesLoop_suffix
    (grammar : Grammar) (productions : Array Production) (semantic : Array Nat)
    (nodes : Array ParseNode) :
    ∀ remaining, remaining ≤ nodes.size →
      checkNodesLoop grammar productions semantic nodes remaining = true →
      ∀ index, nodes.size - remaining ≤ index → index < nodes.size →
        ∃ node, nodes[index]? = some node ∧
          checkNode grammar productions semantic nodes index node = true := by
  intro remaining
  induction remaining with
  | zero =>
      intro bound valid index lower upper
      omega
  | succ remaining ih =>
      intro bound valid index lower upper
      change (match nodes[nodes.size - (remaining + 1)]? with
        | some node => checkNode grammar productions semantic nodes
            (nodes.size - (remaining + 1)) node &&
              checkNodesLoop grammar productions semantic nodes remaining
        | none => false) = true at valid
      split at valid
      next nodeFound =>
        simp only [Bool.and_eq_true] at valid
        rcases valid with ⟨current, rest⟩
        by_cases same : index = nodes.size - (remaining + 1)
        · subst index
          exact ⟨_, nodeFound, current⟩
        · have later : nodes.size - remaining ≤ index := by omega
          exact ih (by omega) rest index later upper
      next => simp at valid

inductive TerminalStep (grammar : Grammar) (tokens : List RawToken)
    (semantic : List Nat) : Nat → Nat → Nat → Prop where
  | plain (position expected tokenId code : Nat) (token : RawToken)
      (tokenIdEq : tokenId = position / 2) (even : position % 2 = 0)
      (tokenAt : tokens[tokenId]? = some token)
      (codeAt : semantic[tokenId]? = some code) (codeEq : code = expected)
      (semanticMatch : semanticKindMatches grammar token code = true) :
      TerminalStep grammar tokens semantic position expected (position + 2)
  | packed (position expected tokenId code : Nat) (token : RawToken)
      (tokenIdEq : tokenId = position / 2) (packedCode : packed code)
      (tokenAt : tokens[tokenId]? = some token)
      (codeAt : semantic[tokenId]? = some code)
      (actual : (if position % 2 = 0 then packedInner code else packedOuter code) = expected)
      (semanticMatch : semanticKindMatches grammar token code = true) :
      TerminalStep grammar tokens semantic position expected (position + 1)

mutual
  inductive Derivation (grammar : Grammar) (tokens : List RawToken)
      (semantic : List Nat) (nodes : List ParseNode) :
      Nat → Nat → Nat → Nat → Prop where
    | node (id nonterminal start finish : Nat) (value : ParseNode) (production : Production)
        (found : nodes[id]? = some value)
        (productionFound : grammar.productions[value.production]? = some production)
        (sameNonterminal : value.nonterminal = nonterminal)
        (productionLhs : production.lhs = nonterminal)
        (sameStart : value.position_start = start) (sameFinish : value.position_end = finish)
        (bounds : start ≤ finish ∧ finish ≤ semantic.length * 2)
        (children : ChildrenDerivation grammar tokens semantic nodes id production.rhs
          value.children start finish) :
        Derivation grammar tokens semantic nodes id nonterminal start finish

  inductive ChildrenDerivation (grammar : Grammar) (tokens : List RawToken)
      (semantic : List Nat) (nodes : List ParseNode) :
      Nat → List Nat → List ParseChild → Nat → Nat → Prop where
    | nil (position : Nat) :
        ChildrenDerivation grammar tokens semantic nodes current [] [] position position
    | terminal (symbol : Nat) (symbols : List Nat) (tokenId : Nat)
        (children : List ParseChild) (position finish next : Nat)
        (step : TerminalStep grammar tokens semantic position symbol next)
        (tail : ChildrenDerivation grammar tokens semantic nodes current symbols children next finish) :
        ChildrenDerivation grammar tokens semantic nodes current
          (symbol :: symbols) (.token tokenId :: children) position finish
    | nonterminal (symbol : Nat) (symbols : List Nat) (childId : Nat)
        (children : List ParseChild) (position finish childFinish : Nat)
        (nonterminalBound : grammar.n_kinds ≤ symbol ∧
          symbol - grammar.n_kinds < grammar.n_nonterminals)
        (childBefore : childId < current)
        (child : Derivation grammar tokens semantic nodes childId
          (symbol - grammar.n_kinds) position childFinish)
        (tail : ChildrenDerivation grammar tokens semantic nodes current symbols children childFinish finish) :
        ChildrenDerivation grammar tokens semantic nodes current
          (symbol :: symbols) (.node childId :: children) position finish
end

theorem terminalStep_of_advance
    (witness : SemanticWitness grammar tokens semantic)
    (position expected finish : Nat)
    (accepted : advanceTerminal grammar semantic.toArray position expected = some finish) :
    TerminalStep grammar tokens semantic position expected finish := by
  unfold advanceTerminal at accepted
  cases codeAt : semantic[position / 2]? with
  | none => simp [codeAt] at accepted
  | some code =>
    have arrayCodeAt : semantic.toArray[position / 2]? = some code := by simpa using codeAt
    by_cases packedCode : packed code
    · rw [arrayCodeAt] at accepted
      simp [packedCode] at accepted
      rcases accepted with ⟨actualEq, finishEq⟩
      subst finish
      obtain ⟨token, tokenAt, semanticMatch⟩ :=
        token_of_semanticAt witness (position / 2) code arrayCodeAt
      exact .packed position expected (position / 2) code token rfl packedCode
        tokenAt codeAt actualEq semanticMatch
    ·
      rw [arrayCodeAt] at accepted
      simp [packedCode] at accepted
      rcases accepted with ⟨⟨even, codeEq⟩, finishEq⟩
      subst finish
      obtain ⟨token, tokenAt, semanticMatch⟩ :=
        token_of_semanticAt witness (position / 2) code arrayCodeAt
      exact .plain position expected (position / 2) code token rfl even
        tokenAt codeAt codeEq semanticMatch

theorem children_of_check
    (witness : SemanticWitness grammar tokens semantic)
    (current : Nat)
    (resolve : ∀ id, id < current →
      ∃ node production, nodes[id]? = some node ∧
        grammar.productions[node.production]? = some production ∧
        Derivation grammar tokens semantic nodes id node.nonterminal
          node.position_start node.position_end) :
    ∀ symbols children position finish,
      checkChildren grammar semantic.toArray nodes.toArray current symbols children position =
        some finish →
      ChildrenDerivation grammar tokens semantic nodes current symbols children position finish := by
  intro symbols
  induction symbols with
  | nil =>
      intro children position finish checked
      cases children with
      | nil =>
          simp [checkChildren] at checked
          subst finish
          exact .nil position
      | cons child children => simp [checkChildren] at checked
  | cons symbol symbols ih =>
      intro children position finish checked
      cases children with
      | nil => simp [checkChildren] at checked
      | cons child children =>
          by_cases kind : symbol < grammar.n_kinds
          · cases child with
            | node childId => simp [checkChildren, kind] at checked
            | token tokenId =>
                by_cases tokenEq : tokenId = position / 2
                · subst tokenId
                  simp [checkChildren, kind] at checked
                  cases advance : advanceTerminal grammar semantic.toArray position symbol with
                  | none => simp [advance] at checked
                  | some next =>
                      simp [advance] at checked
                      have step := terminalStep_of_advance witness position symbol next advance
                      exact .terminal symbol symbols (position / 2) children position finish next step
                        (ih children next finish checked)
                · simp [checkChildren, kind, tokenEq] at checked
          · cases child with
            | token tokenId => simp [checkChildren, kind] at checked
            | node childId =>
                have symbolBound : grammar.n_kinds ≤ symbol := by omega
                by_cases before : childId < current
                · cases childFound : nodes.toArray[childId]? with
                  | none => simp [checkChildren, kind, childFound] at checked
                  | some childNode =>
                  have childListFound : nodes[childId]? = some childNode := by
                    simpa using childFound
                  by_cases nonterminalEq : childNode.nonterminal = symbol - grammar.n_kinds
                  · by_cases startEq : childNode.position_start = position
                    · simp [checkChildren, kind, before, childFound, nonterminalEq, startEq]
                        at checked
                      have tailChecked := checked.2
                      obtain ⟨node, production, nodeFound, productionFound, childDerivation⟩ :=
                        resolve childId before
                      have sameNode : node = childNode :=
                        Option.some.inj (nodeFound.symm.trans childListFound)
                      subst node
                      have childDerivation' : Derivation grammar tokens semantic nodes childId
                          (symbol - grammar.n_kinds) position childNode.position_end := by
                        simpa [nonterminalEq, startEq] using childDerivation
                      exact .nonterminal symbol symbols childId children position finish
                        childNode.position_end ⟨symbolBound, checked.1⟩ before childDerivation'
                        (ih children childNode.position_end finish tailChecked)
                    · simp [checkChildren, kind, childFound, nonterminalEq, startEq] at checked
                  · simp [checkChildren, kind, childFound, nonterminalEq] at checked
                · simp [checkChildren, kind, before] at checked

theorem node_derivation_of_valid
    (witness : SemanticWitness grammar tokens semantic)
    (accepted : parseNodesValid grammar semantic nodes = true) :
    ∀ id, id < nodes.length →
      ∃ node production, nodes[id]? = some node ∧
        grammar.productions[node.production]? = some production ∧
        Derivation grammar tokens semantic nodes id node.nonterminal
          node.position_start node.position_end := by
  have allAccepted :
      checkNodesLoop grammar grammar.productions.toArray semantic.toArray nodes.toArray
          nodes.toArray.size = true := by
    simpa [parseNodesValid, parseNodesValidArray] using accepted
  intro id
  induction id using Nat.strongRecOn with
  | ind id ih =>
      intro idBound
      have arrayBound : id < nodes.toArray.size := by simpa using idBound
      obtain ⟨node, nodeFoundArray, nodeCheck⟩ :=
        checkNodesLoop_suffix grammar grammar.productions.toArray semantic.toArray
          nodes.toArray nodes.toArray.size (by simp) allAccepted id (by omega) arrayBound
      have nodeFound : nodes[id]? = some node := by simpa using nodeFoundArray
      unfold checkNode at nodeCheck
      split at nodeCheck
      next => simp at nodeCheck
      next production productionAt =>
          have productionFound : grammar.productions[node.production]? = some production := by
            simpa using productionAt
          simp at nodeCheck
          have sameNonterminal := nodeCheck.1.1.1
          have bounds : node.position_start ≤ node.position_end ∧
              node.position_end ≤ semantic.length * 2 :=
            ⟨nodeCheck.1.1.2, nodeCheck.1.2⟩
          have childCheck := nodeCheck.2
          have children := children_of_check witness id
            (fun childId childBound => ih childId (by omega) (by omega))
            production.rhs node.children node.position_start node.position_end childCheck
          exact ⟨node, production, nodeFound, productionFound,
            .node id node.nonterminal node.position_start node.position_end node production
              nodeFound productionFound rfl sameNonterminal.symm rfl rfl bounds children⟩

theorem checkedParseUnit_derivation
    {source : SourceFile} {rawWire canonicalWire : List Extraction.Token}
    {lexer : CheckedLexerUnit source rawWire canonicalWire}
    {grammar : Grammar} {semantic : List Nat} {nodes : List ParseNode}
    {parseRoot : Option ParseNodeId}
    (checked : CheckedParseUnit lexer grammar semantic nodes parseRoot) :
    SemanticWitness grammar lexer.canonical semantic ∧
      Derivation grammar lexer.canonical semantic nodes checked.root
        grammar.start_nonterminal 0 (lexer.canonical.length * 2) := by
  have semanticWitness := semanticKindsValid_witness grammar lexer.canonical semantic
    checked.semanticAccepted
  have rootAccepted := checked.rootAccepted
  unfold rootValid rootValidArray at rootAccepted
  cases rootFound : nodes.toArray[checked.root]? with
  | none => simp [rootFound] at rootAccepted
  | some rootNode =>
      have rootListFound : nodes[checked.root]? = some rootNode := by simpa using rootFound
      simp [rootFound] at rootAccepted
      have rootLast := rootAccepted.1.1.1
      have rootNonterminal := rootAccepted.1.1.2
      have rootStart := rootAccepted.1.2
      have rootFinish := rootAccepted.2
      obtain ⟨node, production, nodeFound, productionFound, derivation⟩ :=
        node_derivation_of_valid semanticWitness checked.nodesAccepted checked.root (by omega)
      have sameNode : node = rootNode := Option.some.inj (nodeFound.symm.trans rootListFound)
      subst node
      constructor
      · exact semanticWitness
      · simpa [rootNonterminal, rootStart, rootFinish] using derivation

end Lanius.Extraction.SyntaxCheck
