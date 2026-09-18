import Lanius.Extraction.Frontend.Storage.Output
import Lanius.Extraction.Frontend.Storage.Pack
import Lanius.Extraction.ExtractorContract

namespace Lanius.Extraction.Entry
open Lanius.Extraction.Frontend

/-- The fixed capacities of the authenticated `extract_syntax` call in
`File.Syntax.Stage.arguments`, not a claim about parser/tree/output space. -/
def TokenDomain (sources : List SourceFile) : Prop :=
  SourcesTokenStorage sources 65536 65536 65536

def SyntaxDomain (sources : List SourceFile) : Prop :=
  ∀ file ∈ sources, SourceSyntax file

def ParserDomain (sources : List SourceFile) : Prop := SourcesParserStorage sources 4194304

def TreeDomain (sources : List SourceFile) : Prop := SourcesTreeStorage sources 1048576 65536 1024

/-- Syntax and concrete resource conditions for one input file. No execution,
successful return, or accepted output is assumed. -/
structure SourceDomain (file : SourceFile) (bound : Nat) : Prop where
  tokens : SourceTokenStorage file 65536 65536 65536
  syntaxValid : SourceSyntax file
  parser : SourceParserStorage file 4194304
  tree : SourceTreeStorage file 1048576 65536 1024
  output : SourceOutputBound file bound

theorem SourceDomain.of_domains (tokens : TokenDomain sources) (syntaxValid : SyntaxDomain sources)
    (parser : ParserDomain sources) (tree : TreeDomain sources) (member : file ∈ sources)
    (output : SourceOutputBound file bound) : SourceDomain file bound :=
  ⟨tokens file member, syntaxValid file member, parser file member, tree file member, output⟩

theorem SourceDomain.singleton (domain : SourceDomain file bound) :
    TokenDomain [file] ∧ SyntaxDomain [file] ∧ ParserDomain [file] ∧ TreeDomain [file] := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · simpa only [TokenDomain, SourcesTokenStorage, List.mem_singleton, forall_eq] using domain.tokens
  · simpa only [SyntaxDomain, List.mem_singleton, forall_eq] using domain.syntaxValid
  · simpa only [ParserDomain, SourcesParserStorage, List.mem_singleton, forall_eq] using domain.parser
  · simpa only [TreeDomain, SourcesTreeStorage, List.mem_singleton, forall_eq] using domain.tree

/-- Preserve the correspondence between requested files and their budgets,
including repeated paths and their original order. -/
inductive SourceDomains : List SourceFile → List Nat → Prop where
  | nil : SourceDomains [] []
  | cons (head : SourceDomain file bound) (tail : SourceDomains files bounds) :
      SourceDomains (file :: files) (bound :: bounds)

theorem SourceDomains.of_bounds (bounds : SourcesOutputBounds files limits)
    (supported : ∀ file ∈ files, ∀ bound, SourceOutputBound file bound → SourceDomain file bound) :
    SourceDomains files limits := by
  induction bounds with
  | nil => exact .nil
  | cons head tail ih =>
      exact .cons (supported _ (by simp) _ head)
        (ih (fun file member bound output => supported file (by simp [member]) bound output))

theorem SourceDomains.of_domains (tokens : TokenDomain sources) (syntaxValid : SyntaxDomain sources)
    (parser : ParserDomain sources) (tree : TreeDomain sources) (bounds : SourcesOutputBounds sources limits) :
    SourceDomains sources limits :=
  .of_bounds bounds (fun _ member _ output => .of_domains tokens syntaxValid parser tree member output)

/-- The exact module wrapper and two eight-digit pack-header fields. -/
def moduleFramingBytes : Nat :=
  ExtractorContract.modulePrefix.toUTF8.size + 16 + ExtractorContract.moduleSuffix.toUTF8.size

/-- Successful-input conditions refer only to the requested source files,
their syntax, and concrete storage bounds. Loading and host assumptions are
separate; there is no execution or accepted-output premise. -/
def SuccessDomain (world : Lanius.World.State) : Prop :=
  ∃ sources bounds, ExtractorContract.requestedSources? world = some sources ∧
    SourceDomains sources bounds ∧ moduleFramingBytes + bounds.sum ≤ 16777216

end Lanius.Extraction.Entry
