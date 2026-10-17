#!/bin/sh
# Runs both self-checking testbenches on Linux / macOS with GHDL or nvc.
#   sh sim/run_sim.sh            (uses ghdl if found, else nvc)
#   SIM=nvc sh sim/run_sim.sh
# On Windows use sim\run_sim.bat (Vivado xsim or GHDL).
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SRC="rtl/Tone_Config.vhd rtl/ADC_LTC.vhd rtl/DAC8043FP2.vhd rtl/Tone_Recognition.vhd
     sim/Tone_Generator.vhd sim/tb_ADC_DAC.vhd sim/tb_Tone_Recognition.vhd"
W=${TMPDIR:-/tmp}/uut_tester_sim
rm -rf "$W" && mkdir -p "$W"

if [ -z "$SIM" ]; then
  if command -v ghdl >/dev/null 2>&1; then SIM=ghdl
  elif command -v nvc >/dev/null 2>&1; then SIM=nvc
  else echo "No VHDL simulator found: install GHDL or nvc."; exit 1; fi
fi
echo "Simulator: $SIM   work folder: $W"

run_tb() {
  echo "--- $1"
  if [ "$SIM" = ghdl ]; then
    (cd "$W" && ghdl --elab-run --std=08 "$1") > "$W/$1.log" 2>&1 || true
  else
    (cd "$W" && nvc --std=2008 -e "$1" -r) > "$W/$1.log" 2>&1 || true
  fi
  grep -E "PASS|FAIL|tones:|ALL TESTS|FAILED" "$W/$1.log" | sed -E 's/^.*: (PASS|FAIL|tones:|tb_)/\1/'
  grep -q "ALL TESTS PASSED" "$W/$1.log"
}

cd "$W"
files=""
for f in $SRC; do files="$files $ROOT/$f"; done
if [ "$SIM" = ghdl ]; then ghdl -a --std=08 $files; else nvc --std=2008 -a $files; fi

run_tb tb_ADC_DAC
echo "(tb_Tone_Recognition simulates about 7 s of signals - GHDL takes seconds, nvc a minute or two)"
run_tb tb_Tone_Recognition
echo
echo "*** All testbenches passed"
