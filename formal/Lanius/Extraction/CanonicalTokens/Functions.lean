import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.ArtifactQuote
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.CanonicalTokens.Functions

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

def isTriviaFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", "is_trivia")

def keywordKindFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", "keyword_kind")

def canonicalKindFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", "canonical_kind")

def canonicalizeInPlaceFunction : Function :=
  CoreDecode.function (artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani",
    "canonicalize_in_place")

theorem isTriviaFunction_body_present : isTriviaFunction.body.isSome := by
  native_decide

theorem keywordKindFunction_body_present : keywordKindFunction.body.isSome := by
  native_decide

theorem canonicalKindFunction_body_present :
    canonicalKindFunction.body.isSome := by
  native_decide

theorem canonicalizeInPlaceFunction_body_present :
    canonicalizeInPlaceFunction.body.isSome := by
  native_decide

def isTriviaBody : Stmt :=
  isTriviaFunction.body.get isTriviaFunction_body_present

def keywordKindBody : Stmt :=
  keywordKindFunction.body.get keywordKindFunction_body_present

def canonicalKindBody : Stmt :=
  canonicalKindFunction.body.get canonicalKindFunction_body_present

def canonicalizeInPlaceBody : Stmt :=
  canonicalizeInPlaceFunction.body.get canonicalizeInPlaceFunction_body_present

theorem isTriviaFunction_has_body :
    isTriviaFunction.body = some isTriviaBody := by
  simp [isTriviaBody]

theorem keywordKindFunction_has_body :
    keywordKindFunction.body = some keywordKindBody := by
  simp [keywordKindBody]

theorem canonicalKindFunction_has_body :
    canonicalKindFunction.body = some canonicalKindBody := by
  simp [canonicalKindBody]

theorem canonicalizeInPlaceFunction_has_body :
    canonicalizeInPlaceFunction.body = some canonicalizeInPlaceBody := by
  simp [canonicalizeInPlaceBody]

theorem verifiedFrontendCore_finds_isTrivia :
    verifiedFrontendCore.function? isTriviaFunction.id =
      some isTriviaFunction := by
  rfl

theorem verifiedFrontendCore_finds_keywordKind :
    verifiedFrontendCore.function? keywordKindFunction.id =
      some keywordKindFunction := by
  rfl

theorem verifiedFrontendCore_finds_canonicalKind :
    verifiedFrontendCore.function? canonicalKindFunction.id =
      some canonicalKindFunction := by
  rfl

theorem verifiedFrontendCore_finds_canonicalizeInPlace :
    verifiedFrontendCore.function? canonicalizeInPlaceFunction.id =
      some canonicalizeInPlaceFunction := by
  rfl

def reification1? (function : Function) (body : Stmt) :=
  reifyCommand? verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := 1)) 1 body

def reification3? (function : Function) (body : Stmt) :=
  reifyCommand? verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := 3)) 3 body

def reification4? (function : Function) (body : Stmt) :=
  reifyCommand? verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := 4)) 4 body

theorem isTriviaReification_exists :
    (reification1? isTriviaFunction isTriviaBody).isSome := by
  native_decide

theorem keywordKindReification_exists :
    (reification3? keywordKindFunction keywordKindBody).isSome := by
  native_decide

theorem canonicalKindReification_exists :
    (reification4? canonicalKindFunction canonicalKindBody).isSome := by
  native_decide

theorem canonicalizeInPlaceReification_exists :
    (reification3? canonicalizeInPlaceFunction
      canonicalizeInPlaceBody).isSome := by
  native_decide

def isTriviaView :=
  (reification1? isTriviaFunction isTriviaBody).get
    isTriviaReification_exists

def keywordKindView :=
  (reification3? keywordKindFunction keywordKindBody).get
    keywordKindReification_exists

def canonicalKindView :=
  (reification4? canonicalKindFunction canonicalKindBody).get
    canonicalKindReification_exists

def canonicalizeInPlaceView :=
  (reification3? canonicalizeInPlaceFunction canonicalizeInPlaceBody).get
    canonicalizeInPlaceReification_exists

theorem isTriviaView_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 1)) 1
        isTriviaView.command = isTriviaBody :=
  isTriviaView.toCoreExactly

theorem keywordKindView_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 3)) 3
        keywordKindView.command = keywordKindBody :=
  keywordKindView.toCoreExactly

theorem canonicalKindView_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 4)) 4
        canonicalKindView.command = canonicalKindBody :=
  canonicalKindView.toCoreExactly

theorem canonicalizeInPlaceView_toCore_exactly :
    toCoreStmt actionAdapter (identityLayout (arity := 3)) 3
        canonicalizeInPlaceView.command = canonicalizeInPlaceBody :=
  canonicalizeInPlaceView.toCoreExactly

end Lanius.Extraction.CanonicalTokens.Functions
