# lani_extract.py with the extractor binary as built (no `lake build extract`): for a
# tree whose extracted modules are mid-change, the built extractor is the same program.
import sys
sys.path.insert(0, '/home/andrew-peterson/code/laniusc-wt/leafC/formal/tools')
import lani_extract
lani_extract.build_extract = lambda: None
sys.exit(lani_extract.main(sys.argv[1:]))
