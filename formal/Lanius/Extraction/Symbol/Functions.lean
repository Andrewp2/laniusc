import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.ArtifactQuote
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.Symbol.Functions

set_option maxRecDepth 1000000

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! Mechanically reified FunctionalViews of every function in `symbol.lani`. -/

private def tokenMatchKindWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", "token_match_kind"

private def tokenMatchLengthWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", "token_match_length"

private def tokenMatchWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", "token_match"

private def matchSymbolHeadWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", "match_symbol_head"

def tokenMatchKindFunction : Function :=
  CoreDecode.function tokenMatchKindWire

def tokenMatchLengthFunction : Function :=
  CoreDecode.function tokenMatchLengthWire

def tokenMatchFunction : Function :=
  CoreDecode.function tokenMatchWire

def matchSymbolHeadFunction : Function :=
  CoreDecode.function matchSymbolHeadWire

theorem tokenMatchKind_body_present : tokenMatchKindFunction.body.isSome := by
  native_decide

theorem tokenMatchLength_body_present :
    tokenMatchLengthFunction.body.isSome := by
  native_decide

theorem tokenMatch_body_present : tokenMatchFunction.body.isSome := by
  native_decide

theorem matchSymbolHead_body_present : matchSymbolHeadFunction.body.isSome := by
  native_decide

def tokenMatchKindBody : Stmt :=
  tokenMatchKindFunction.body.get tokenMatchKind_body_present

def tokenMatchLengthBody : Stmt :=
  tokenMatchLengthFunction.body.get tokenMatchLength_body_present

def tokenMatchBody : Stmt :=
  tokenMatchFunction.body.get tokenMatch_body_present

def matchSymbolHeadBody : Stmt :=
  matchSymbolHeadFunction.body.get matchSymbolHead_body_present

def i32Type : Ty := .scalar (.signed .i32)
def tokenMatchType : Ty := .structure 3

def accessorBody (field : FieldId) : Stmt :=
  .sequence (.returnValue (some (.field (.local 0) field))) .skip

def tokenMatchCoreBody : Stmt :=
  .sequence (.returnValue (some (.structValue 3 [.local 0, .local 1]))) .skip

theorem tokenMatchKind_shape :
    tokenMatchKindFunction.id = 42 ∧
      tokenMatchKindFunction.parameters = [(0, tokenMatchType)] ∧
      tokenMatchKindFunction.returnType = i32Type ∧
      tokenMatchKindFunction.body = some (accessorBody 0) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem tokenMatchLength_shape :
    tokenMatchLengthFunction.id = 43 ∧
      tokenMatchLengthFunction.parameters = [(0, tokenMatchType)] ∧
      tokenMatchLengthFunction.returnType = i32Type ∧
      tokenMatchLengthFunction.body = some (accessorBody 1) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem tokenMatch_shape :
    tokenMatchFunction.id = 44 ∧
      tokenMatchFunction.parameters = [(0, i32Type), (1, i32Type)] ∧
      tokenMatchFunction.returnType = tokenMatchType ∧
      tokenMatchFunction.body = some tokenMatchCoreBody := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem matchSymbolHead_shape :
    matchSymbolHeadFunction.id = 45 ∧
      matchSymbolHeadFunction.parameters =
        [(0, .slice i32Type), (1, i32Type), (2, i32Type)] ∧
      matchSymbolHeadFunction.returnType = tokenMatchType := by
  exact ⟨rfl, rfl, rfl⟩

theorem tokenMatchKind_has_body :
    tokenMatchKindFunction.body = some tokenMatchKindBody := by
  simp [tokenMatchKindBody]

theorem tokenMatchLength_has_body :
    tokenMatchLengthFunction.body = some tokenMatchLengthBody := by
  simp [tokenMatchLengthBody]

theorem tokenMatch_has_body :
    tokenMatchFunction.body = some tokenMatchBody := by
  simp [tokenMatchBody]

theorem matchSymbolHead_has_body :
    matchSymbolHeadFunction.body = some matchSymbolHeadBody := by
  simp [matchSymbolHeadBody]

theorem verifiedFrontendCore_finds_tokenMatchKind :
    verifiedFrontendCore.function? tokenMatchKindFunction.id =
      some tokenMatchKindFunction := by
  rfl

theorem verifiedFrontendCore_finds_tokenMatchLength :
    verifiedFrontendCore.function? tokenMatchLengthFunction.id =
      some tokenMatchLengthFunction := by
  rfl

theorem verifiedFrontendCore_finds_tokenMatch :
    verifiedFrontendCore.function? tokenMatchFunction.id =
      some tokenMatchFunction := by
  rfl

theorem verifiedFrontendCore_finds_matchSymbolHead :
    verifiedFrontendCore.function? matchSymbolHeadFunction.id =
      some matchSymbolHeadFunction := by
  rfl

private def reification? {arity : Nat} (function : Function) (body : Stmt) :=
  reifyCommand? verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := arity)) arity body

theorem tokenMatchKind_reification_exists :
    (reification? (arity := 1) tokenMatchKindFunction tokenMatchKindBody).isSome := by
  native_decide

theorem tokenMatchLength_reification_exists :
    (reification? (arity := 1) tokenMatchLengthFunction tokenMatchLengthBody).isSome := by
  native_decide

theorem tokenMatch_reification_exists :
    (reification? (arity := 2) tokenMatchFunction tokenMatchBody).isSome := by
  native_decide

theorem matchSymbolHead_reification_exists :
    (reification? (arity := 3) matchSymbolHeadFunction matchSymbolHeadBody).isSome := by
  native_decide

def tokenMatchKindView :=
  (reification? (arity := 1) tokenMatchKindFunction tokenMatchKindBody).get
    tokenMatchKind_reification_exists

def tokenMatchLengthView :=
  (reification? (arity := 1) tokenMatchLengthFunction tokenMatchLengthBody).get
    tokenMatchLength_reification_exists

def tokenMatchView :=
  (reification? (arity := 2) tokenMatchFunction tokenMatchBody).get
    tokenMatch_reification_exists

def matchSymbolHeadView :=
  (reification? (arity := 3) matchSymbolHeadFunction matchSymbolHeadBody).get
    matchSymbolHead_reification_exists

theorem tokenMatchKind_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 1)) 1
        tokenMatchKindView.command = tokenMatchKindBody :=
  tokenMatchKindView.toCoreExactly

theorem tokenMatchLength_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 1)) 1
        tokenMatchLengthView.command = tokenMatchLengthBody :=
  tokenMatchLengthView.toCoreExactly

theorem tokenMatch_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 2)) 2
        tokenMatchView.command = tokenMatchBody :=
  tokenMatchView.toCoreExactly

theorem matchSymbolHead_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 3)) 3
        matchSymbolHeadView.command = matchSymbolHeadBody :=
  matchSymbolHeadView.toCoreExactly

end Lanius.Extraction.Symbol.Functions
