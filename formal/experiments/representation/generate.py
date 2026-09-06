"""Untrusted pilot generator; every generated declaration is kernel checked."""
import json
from pathlib import Path
import sys

pack = json.loads(Path(sys.argv[1]).read_text())
source = sys.argv[3] if len(sys.argv) > 3 else 'token_scan'
unit_name = ''.join(part.capitalize() for part in source.split('_'))
unit = next(u for u in pack['units'] if u['sources'][0]['path'].endswith('/' + source + '.lani'))
nodes = unit['parse_nodes']
lines = ['import RepresentationRules',
 'import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.View',
 'import Lanius.Extraction.KernelReduction',
 'namespace Lanius.Extraction', 'open Reconstruction.Validated Representation',
 'set_option maxRecDepth 500000', 'set_option maxHeartbeats 0',
 'set_option profiler true', 'set_option profiler.threshold 100',
 'def comparisonSurface : SurfaceFile := verifiedFrontendTokenScanArtifact.surface.get (by kernel_rfl)']
stack = []
stacks = []
def lst(xs):
    return '[' + ', '.join(xs) + ']'
for i, node in enumerate(nodes):
    stacks.append(stack.copy())
    children = node['children']
    slots = [('ParseChild.node ' + str(c['node'])) if 'node' in c else ('ParseChild.token ' + str(c['token'])) for c in children]
    refs = [('some t' + str(c['node'])) if 'node' in c else 'none' for c in children]
    ids = [c['node'] for c in children if 'node' in c]
    assert list(reversed(stack[:len(ids)])) == ids
    tail = stack[len(ids):]
    lines += [f'def n{i} : ParseNode := ⟨{node["production"]}, {node["nonterminal"]}, {node["position_start"]}, {node["position_end"]}, {lst(slots)}⟩',
              f'def c{i} : List (Option ParseTree) := {lst(refs)}',
              f'def t{i} : ParseTree := .node {i} n{i} c{i}',
              f'def s{i} : List ParseTree := {lst(["t"+str(k) for k in stack])}',
              f'def tail{i} : List ParseTree := {lst(["t"+str(k) for k in tail])}',
              f'theorem consume{i} : ParseTree.consumeChildren n{i}.children s{i} = some (c{i}, tail{i}) := by kernel_rfl',
              f'theorem valid{i} : ParsePostorder.node laniusGrammar verifiedFrontendTokenScanParseView {i} n{i} (c{i}.filterMap fun child => child.map fun tree => (tree.id, tree.value)) = true := by kernel_rfl']
    stack = [i] + tail
n = len(nodes)
lines += [f'def s{n} : List ParseTree := {lst(["t"+str(k) for k in stack])}',
          f'def r{n} : List ParseNode := []',
          f'theorem p{n} : linkFrom laniusGrammar verifiedFrontendTokenScanParseView {n} r{n} s{n} = some s{n} := rfl']
for i in reversed(range(n)):
    lines += [f'def r{i} : List ParseNode := n{i} :: r{i+1}',
              f'theorem p{i} : linkFrom laniusGrammar verifiedFrontendTokenScanParseView {i} r{i} s{i} = some s{n} :=',
              f'  Representation.step laniusGrammar verifiedFrontendTokenScanParseView {i} n{i} r{i+1} s{i} c{i} tail{i} s{n} consume{i} valid{i} p{i+1}']
lines += ['theorem originalNodes : verifiedFrontendTokenScanArtifact.parse_nodes = r0 := by kernel_rfl',
          f'theorem linked : linkFrom laniusGrammar verifiedFrontendTokenScanParseView 0 verifiedFrontendTokenScanArtifact.parse_nodes [] = some s{n} := by rw [originalNodes]; exact p0',
          f'theorem finished : Representation.finish laniusGrammar verifiedFrontendTokenScanParseView s{n} linked = some comparisonSurface := by kernel_rfl',
          'theorem comparisonAccepted : checkedView laniusGrammar verifiedFrontendTokenScanParseView = some comparisonSurface :=',
          f'  (Representation.finish_eq laniusGrammar verifiedFrontendTokenScanParseView s{n} linked).trans finished',
          'theorem comparisonSound :',
          ' checkNodesFromParseView laniusGrammar verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanParseView 0 verifiedFrontendTokenScanArtifact.parse_nodes = true ∧',
          ' reconstructArtifactSurfaceView verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView = some comparisonSurface :=',
          ' checkedView_sound laniusGrammar verifiedFrontendTokenScanParseView comparisonSurface comparisonAccepted',
          '#print axioms comparisonSound', 'end Lanius.Extraction']
Path(sys.argv[2]).write_text(('\n'.join(lines)+'\n').replace('TokenScan', unit_name))
print(f'Generated {n} node proofs, {len(lines)} lines')

