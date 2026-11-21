#!/bin/bash
# Simulación del core con Verilator (el T80 en VHDL se pasa a Verilog con GHDL)
# Uso: cd sim && ./build.sh && ./obj/vsim -a disco.img -t 6 -k 1.0 $'\n'
set -e
R=../rtl
ghdl -a --std=08 -fsynopsys $R/T80/T80_Pack.vhd $R/T80/T80_ALU.vhd $R/T80/T80_MCode.vhd $R/T80/T80_Reg.vhd $R/T80/T80.vhd $R/T80/T80s.vhd
ghdl --synth --std=08 -fsynopsys --out=verilog T80s > t80s.v 2>/dev/null
# Arreglos de la salida de GHDL: identificadores escapados y choque de nombres en la ALU
sed -i -E 's/\\([A-Za-z_][A-Za-z0-9_]*) /\1_esc /g' t80s.v
L=$(grep -n '^  wire \[7:0\] alu_q;' t80s.v | sed -n 2p | cut -d: -f1)
sed -i "${L}s/alu_q;/alu_q_inst;/; s/assign alu_n371 = alu_q;/assign alu_n371 = alu_q_inst;/; s/\.q(alu_q)/.q(alu_q_inst)/" t80s.v
ln -sfn ../rom rom
verilator --savable --cc --exe --build -O3 --x-assign fast --x-initial fast -j 4 --top-module osborne1 +1364-2005ext+v \
  -Wno-fatal -Wno-lint -Wno-style -CFLAGS -O2 -Mdir obj pub.vlt t80s.v \
  $R/pia6821.sv $R/acia6850.sv $R/osb_keyboard.sv $R/wd1793.sv $R/osborne1.sv tb.cpp -o vsim
