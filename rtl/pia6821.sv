// Motorola MC6821 PIA - implementación compacta para el core Osborne 1
// Shaeon (Carlos Palmero)
//
// - Registros ORA/DDRA/CRA/ORB/DDRB/CRB con selección por CRx[2]
// - CA1/CB1 como entradas de interrupción (flanco configurable)
// - CA2/CB2 como entradas de interrupción cuando CRx[5]=0; en modo salida
//   se entrega el nivel programado (modo manual) por ca2_o/cb2_o
// - La lectura de PRA/PRB borra los flags de interrupción correspondientes

module pia6821
(
	input            clk,
	input            reset,

	input            cs,       // chip seleccionado (nivel)
	input            rd,       // pulso de lectura (1 ciclo de clk)
	input            wr,       // pulso de escritura (1 ciclo de clk)
	input      [1:0] rs,
	input      [7:0] din,
	output reg [7:0] dout,

	input      [7:0] pa_i,
	output     [7:0] pa_o,     // valor de los pines de salida (ORA & DDRA, entradas a 1)
	input      [7:0] pb_i,
	output     [7:0] pb_o,

	input            ca1,
	input            ca2_i,
	output           ca2_o,
	input            cb1,
	input            cb2_i,
	output           cb2_o,

	output           irqa,
	output           irqb
);

reg [7:0] ora, ddra;
reg [7:0] orb, ddrb;
reg [5:0] cra, crb;
reg       irqa1, irqa2, irqb1, irqb2;

assign pa_o = (ora & ddra) | ~ddra;
assign pb_o = (orb & ddrb) | ~ddrb;

wire [7:0] pa_rd = (ora & ddra) | (pa_i & ~ddra);
wire [7:0] pb_rd = (orb & ddrb) | (pb_i & ~ddrb);

assign ca2_o = cra[5] ? cra[3] : 1'b1;
assign cb2_o = crb[5] ? crb[3] : 1'b1;

assign irqa = (irqa1 & cra[0]) | (irqa2 & cra[3] & ~cra[5]);
assign irqb = (irqb1 & crb[0]) | (irqb2 & crb[3] & ~crb[5]);

always @(*) begin
	case(rs)
		0: dout = cra[2] ? pa_rd : ddra;
		1: dout = {irqa1, irqa2 & ~cra[5], cra};
		2: dout = crb[2] ? pb_rd : ddrb;
		3: dout = {irqb1, irqb2 & ~crb[5], crb};
	endcase
end

always @(posedge clk) begin
	reg old_ca1, old_ca2, old_cb1, old_cb2;

	old_ca1 <= ca1;
	old_ca2 <= ca2_i;
	old_cb1 <= cb1;
	old_cb2 <= cb2_i;

	if(reset) begin
		ora  <= 0; ddra <= 0; cra <= 0;
		orb  <= 0; ddrb <= 0; crb <= 0;
		{irqa1, irqa2, irqb1, irqb2} <= 0;
	end
	else begin
		// Detección de flancos activos
		if(cra[1] ? (~old_ca1 & ca1) : (old_ca1 & ~ca1)) irqa1 <= 1;
		if(crb[1] ? (~old_cb1 & cb1) : (old_cb1 & ~cb1)) irqb1 <= 1;
		if(~cra[5] && (cra[4] ? (~old_ca2 & ca2_i) : (old_ca2 & ~ca2_i))) irqa2 <= 1;
		if(~crb[5] && (crb[4] ? (~old_cb2 & cb2_i) : (old_cb2 & ~cb2_i))) irqb2 <= 1;

		if(cs & rd) begin
			if(rs == 0 && cra[2]) {irqa1, irqa2} <= 0;
			if(rs == 2 && crb[2]) {irqb1, irqb2} <= 0;
		end

		if(cs & wr) begin
			case(rs)
				0: if(cra[2]) ora <= din; else ddra <= din;
				1: cra <= din[5:0];
				2: if(crb[2]) orb <= din; else ddrb <= din;
				3: crb <= din[5:0];
			endcase
		end
	end
end

endmodule
