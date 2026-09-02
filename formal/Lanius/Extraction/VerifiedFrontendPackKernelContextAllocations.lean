import Lanius.Extraction.VerifiedFrontendPackKernelContextBase
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit0
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit1
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit2
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit3
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit4
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit5
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit6
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit7
import Lanius.Extraction.VerifiedFrontendPackKernelContextCountsUnit8

namespace Lanius.Extraction

open ArtifactPackContextChecker

def verifiedFrontendLexerAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendLexerProgramUnitKernel, 0, 0, 5, 8, 100⟩

def verifiedFrontendTokenScanAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendTokenScanProgramUnitKernel, 1, 1, 6, 15, 118⟩

def verifiedFrontendDigitsAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendDigitsProgramUnitKernel, 2, 2, 6, 15, 124⟩

def verifiedFrontendTokenAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendTokenProgramUnitKernel, 3, 3, 6, 15, 131⟩

def verifiedFrontendCanonicalTokensAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendCanonicalTokensProgramUnitKernel, 3, 3, 7, 97, 131⟩

def verifiedFrontendDecimalAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendDecimalProgramUnitKernel, 3, 3, 7, 97, 135⟩

def verifiedFrontendNumberAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendNumberProgramUnitKernel, 3, 3, 8, 97, 140⟩

def verifiedFrontendSymbolAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendSymbolProgramUnitKernel, 3, 3, 8, 97, 142⟩

def verifiedFrontendRawLexerAllocationKernel : UnitAllocation :=
  ⟨verifiedFrontendRawLexerProgramUnitKernel, 4, 4, 8, 97, 146⟩

def verifiedFrontendPackAllocationsExplicitKernel : List UnitAllocation := [
  verifiedFrontendLexerAllocationKernel,
  verifiedFrontendTokenScanAllocationKernel,
  verifiedFrontendDigitsAllocationKernel,
  verifiedFrontendTokenAllocationKernel,
  verifiedFrontendCanonicalTokensAllocationKernel,
  verifiedFrontendDecimalAllocationKernel,
  verifiedFrontendNumberAllocationKernel,
  verifiedFrontendSymbolAllocationKernel,
  verifiedFrontendRawLexerAllocationKernel
]

private theorem allocateFrontendShapedUnits
    (lexer tokenScan digits token canonicalTokens decimal number symbol rawLexer :
      ProgramUnit)
    (lexerCount :
      ((ArtifactContextChecker.collectStructures lexer.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases lexer.surface.items).length,
        (ArtifactContextChecker.collectConstants lexer.surface.items).length,
        (ArtifactContextChecker.collectFunctions lexer.surface.items).length) =
        (1, 1, 7, 18))
    (tokenScanCount :
      ((ArtifactContextChecker.collectStructures tokenScan.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases tokenScan.surface.items).length,
        (ArtifactContextChecker.collectConstants tokenScan.surface.items).length,
        (ArtifactContextChecker.collectFunctions tokenScan.surface.items).length) =
        (1, 0, 0, 6))
    (digitsCount :
      ((ArtifactContextChecker.collectStructures digits.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases digits.surface.items).length,
        (ArtifactContextChecker.collectConstants digits.surface.items).length,
        (ArtifactContextChecker.collectFunctions digits.surface.items).length) =
        (1, 0, 0, 7))
    (tokenCount :
      ((ArtifactContextChecker.collectStructures token.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases token.surface.items).length,
        (ArtifactContextChecker.collectConstants token.surface.items).length,
        (ArtifactContextChecker.collectFunctions token.surface.items).length) =
        (0, 1, 82, 0))
    (canonicalTokensCount :
      ((ArtifactContextChecker.collectStructures canonicalTokens.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases canonicalTokens.surface.items).length,
        (ArtifactContextChecker.collectConstants canonicalTokens.surface.items).length,
        (ArtifactContextChecker.collectFunctions canonicalTokens.surface.items).length) =
        (0, 0, 0, 4))
    (decimalCount :
      ((ArtifactContextChecker.collectStructures decimal.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases decimal.surface.items).length,
        (ArtifactContextChecker.collectConstants decimal.surface.items).length,
        (ArtifactContextChecker.collectFunctions decimal.surface.items).length) =
        (0, 1, 0, 5))
    (numberCount :
      ((ArtifactContextChecker.collectStructures number.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases number.surface.items).length,
        (ArtifactContextChecker.collectConstants number.surface.items).length,
        (ArtifactContextChecker.collectFunctions number.surface.items).length) =
        (0, 0, 0, 2))
    (symbolCount :
      ((ArtifactContextChecker.collectStructures symbol.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases symbol.surface.items).length,
        (ArtifactContextChecker.collectConstants symbol.surface.items).length,
        (ArtifactContextChecker.collectFunctions symbol.surface.items).length) =
        (1, 0, 0, 4))
    (rawLexerCount :
      ((ArtifactContextChecker.collectStructures rawLexer.surface.items).length,
        (ArtifactContextChecker.collectTypeAliases rawLexer.surface.items).length,
        (ArtifactContextChecker.collectConstants rawLexer.surface.items).length,
        (ArtifactContextChecker.collectFunctions rawLexer.surface.items).length) =
        (1, 0, 3, 8)) :
    allocateUnits [lexer, tokenScan, digits, token, canonicalTokens, decimal,
      number, symbol, rawLexer] = [
        ⟨lexer, 0, 0, 5, 8, 100⟩,
        ⟨tokenScan, 1, 1, 6, 15, 118⟩,
        ⟨digits, 2, 2, 6, 15, 124⟩,
        ⟨token, 3, 3, 6, 15, 131⟩,
        ⟨canonicalTokens, 3, 3, 7, 97, 131⟩,
        ⟨decimal, 3, 3, 7, 97, 135⟩,
        ⟨number, 3, 3, 8, 97, 140⟩,
        ⟨symbol, 3, 3, 8, 97, 142⟩,
        ⟨rawLexer, 4, 4, 8, 97, 146⟩] := by
  simp only [Prod.mk.injEq] at lexerCount tokenScanCount digitsCount tokenCount canonicalTokensCount decimalCount numberCount symbolCount rawLexerCount
  unfold allocateUnits totalStructures totalTypeAliases totalConstants
  simp_all only [List.map_cons, List.map_nil, List.sum_cons, List.sum_nil,
    allocateUnitsFrom, Nat.reduceAdd]

set_option maxRecDepth 100000 in
set_option maxHeartbeats 0 in
theorem verifiedFrontendPack_allocations_explicit_kernel :
    verifiedFrontendPackAllocationsKernel =
      verifiedFrontendPackAllocationsExplicitKernel := by
  simpa only [verifiedFrontendPackAllocationsKernel,
    verifiedFrontendPackDecodedUnitsKernel, verifiedFrontendPackDecodedKernel,
    verifiedFrontendPackDecodedExplicitKernel,
    verifiedFrontendPackAllocationsExplicitKernel,
    verifiedFrontendLexerAllocationKernel,
    verifiedFrontendTokenScanAllocationKernel,
    verifiedFrontendDigitsAllocationKernel,
    verifiedFrontendTokenAllocationKernel,
    verifiedFrontendCanonicalTokensAllocationKernel,
    verifiedFrontendDecimalAllocationKernel,
    verifiedFrontendNumberAllocationKernel,
    verifiedFrontendSymbolAllocationKernel,
    verifiedFrontendRawLexerAllocationKernel] using
    allocateFrontendShapedUnits
      verifiedFrontendLexerProgramUnitKernel
      verifiedFrontendTokenScanProgramUnitKernel
      verifiedFrontendDigitsProgramUnitKernel
      verifiedFrontendTokenProgramUnitKernel
      verifiedFrontendCanonicalTokensProgramUnitKernel
      verifiedFrontendDecimalProgramUnitKernel
      verifiedFrontendNumberProgramUnitKernel
      verifiedFrontendSymbolProgramUnitKernel
      verifiedFrontendRawLexerProgramUnitKernel
      verifiedFrontendLexer_context_counts_kernel
      verifiedFrontendTokenScan_context_counts_kernel
      verifiedFrontendDigits_context_counts_kernel
      verifiedFrontendToken_context_counts_kernel
      verifiedFrontendCanonicalTokens_context_counts_kernel
      verifiedFrontendDecimal_context_counts_kernel
      verifiedFrontendNumber_context_counts_kernel
      verifiedFrontendSymbol_context_counts_kernel
      verifiedFrontendRawLexer_context_counts_kernel

end Lanius.Extraction
