#!/bin/bash
# Runs every headless test, 4 at a time, and prints the lines that matter.
# Usage (from the project folder):  GODOT=/path/to/godot tests/run_all.sh
#   GAMES=50 tests/run_all.sh        quick run (50 games per simulation)
#   tests/run_all.sh war_test deal_test   only these tests
G=${GODOT:-godot}
OUT=${OUT:-/tmp/godot_tests}
mkdir -p "$OUT"
TESTS=${@:-$(cd tests && ls *_test.gd balance_state.gd | sed 's/\.gd$//')}
"$G" --headless --import >/dev/null 2>&1
printf '%s\n' $TESTS | xargs -P 4 -I{} sh -c "timeout 1500 '$G' --headless --script tests/{}.gd > '$OUT/{}.txt' 2>&1"
for t in $TESTS; do
	echo "== $t"
	grep -v "^Godot Engine" "$OUT/$t.txt" | grep -v "^$" | grep -E "Impossible|impossible|problems|Endings|endings|expect|Daughter with|swallowed|NO decision|SCRIPT ERROR|per game|quick mode" | head -16
done
