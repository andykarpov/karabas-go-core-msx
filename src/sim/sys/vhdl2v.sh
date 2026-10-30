#!/bin/bash
# The VHDL of the machine as Verilog netlists (ghdl --synth), for verilator: T80 (t80pa), vdp18_core,
# cv_clock, keyboard and the SCC (scc_wave, with ram and scc_wave_mul). Output: $1 (a directory).
set -eu
OUT=${1:?output dir}
R=$(cd "$(dirname "$0")/../../rtl/msx" && pwd)
mkdir -p "$OUT"
cd "$OUT"
G="--std=93c -fexplicit --ieee=synopsys -frelaxed"
SRC="$R/T80/T80_Pack.vhd $R/T80/T80_ALU.vhd $R/T80/T80_MCode.vhd $R/T80/T80_Reg.vhd $R/T80/T80.vhd $R/T80/T80pa.vhd
 $R/vdp18/vdp18_pack-p.vhd $R/vdp18/vdp18_col_pack-p.vhd $R/vdp18/vdp18_clk_gen.vhd $R/vdp18/vdp18_hor_vert.vhd
 $R/vdp18/vdp18_ctrl.vhd $R/vdp18/vdp18_cpuio.vhd $R/vdp18/vdp18_addr_mux.vhd $R/vdp18/vdp18_pattern.vhd
 $R/vdp18/vdp18_sprite.vhd $R/vdp18/vdp18_col_mux.vhd $R/vdp18/vdp18_core.vhd
 $R/cv_clock.vhd $R/keyboard.vhd $R/cart/ram.vhd $R/cart/scc_wave.vhd"
# T80.vhd: its signal ALU_Q and the output Q of its instance alu both become alu_q in the netlist
# of ghdl: a copy with the signal renamed (for the simulation only)
sed -E 's/\bALU_Q\b/ALU_Q_s/g' "$R/T80/T80.vhd" > T80_sim.vhd
SRC=${SRC/$R\/T80\/T80.vhd/T80_sim.vhd}
ghdl -a $G $SRC
for e in t80pa vdp18_core cv_clock keyboard scc_wave; do
	# "release" is a keyword of Verilog (a signal of keyboard.vhd); ghdl writes the escaped name of an
	# instance signal after its prefix ("u0_\reg "), which is no identifier: "u0_reg_x"
	ghdl --synth $G --out=verilog $e | sed -E -e "s/\brelease\b/release_s/g" -e 's/(\w)\\(\w+) /\1\2_x /g' > $e.v
done
# the generics are fixed in the netlists (their defaults, the values msx1.v sets): parameters for the
# instances; T80pa keeps the case of its VHDL name, msx1.v instantiates t80pa
python3 - <<'PY'
import re
for f, mod, par in (('vdp18_core.v', 'vdp18_core', 'compat_rgb_g'), ('t80pa.v', 'T80pa', 'Mode')):
    s = open(f).read()
    m = re.search(r'\nmodule ' + mod + r'\b[^;]*;', s)
    s = s[:m.end()] + '\n  parameter ' + par + ' = 0;' + s[m.end():]
    s = s.replace('\nmodule T80pa', '\nmodule t80pa')
    open(f, 'w').write(s)
PY
