// Motorola MC6850 ACIA para el core Osborne 1
// Shaeon (Carlos Palmero)
//
// - Divisor ÷1/÷16/÷64 sobre el reloj RxC/TxC (entrada rxc_ce: un pulso por ciclo)
// - Formatos de palabra 7/8 bits, paridad par/impar/ninguna, 1/2 bits de parada
// - Estado: RDRF, TDRE, /DCD, /CTS, FE, OVRN, PE, IRQ
// - /CTS a 1 inhibe TDRE; flanco de subida de /DCD genera interrupción
//   (se borra leyendo estado y luego datos), como el chip real
// - Las señales de módem son activas a nivel bajo

module acia6850
(
	input            clk,
	input            reset,

	input            cs,
	input            rd,        // pulso de lectura
	input            wr,        // pulso de escritura
	input            rs,
	input      [7:0] din,
	output reg [7:0] dout,
	output           irq,

	input            rxc_ce,    // flanco activo del reloj RxC/TxC

	input            rxd,
	output reg       txd,
	input            cts_n,
	input            dcd_n,
	output           rts_n
);

reg  [7:0] cr;
reg        mreset;

wire [1:0] cdiv  = cr[1:0];
wire [2:0] wsel  = cr[4:2];
wire [1:0] tctl  = cr[6:5];
wire       rie   = cr[7];

wire       bits8   = wsel[2];
// tabla de formatos (CR4..CR2)
//   000 7E2  001 7O2  010 7E1  011 7O1  100 8N2  101 8N1  110 8E1  111 8O1
reg        f_par, f_odd, f_stop2;
always @(*) begin
	case(wsel)
		3'b000: {f_par, f_odd, f_stop2} = 3'b101;
		3'b001: {f_par, f_odd, f_stop2} = 3'b111;
		3'b010: {f_par, f_odd, f_stop2} = 3'b100;
		3'b011: {f_par, f_odd, f_stop2} = 3'b110;
		3'b100: {f_par, f_odd, f_stop2} = 3'b001;
		3'b101: {f_par, f_odd, f_stop2} = 3'b000;
		3'b110: {f_par, f_odd, f_stop2} = 3'b100;
		3'b111: {f_par, f_odd, f_stop2} = 3'b110;
	endcase
end

assign rts_n = (tctl == 2'b10) | mreset;
wire   tie   = (tctl == 2'b01);
wire   brk   = (tctl == 2'b11);

// Estado
reg  [7:0] rdr, tdr;
reg        rdrf, tdre, fe, ovrn, pe;
reg        dcd_irq, dcd_lat, sr_read_dcd;

wire       tdre_st = tdre & ~cts_n;
wire       irq_rx  = rie & (rdrf | ovrn | dcd_irq);
wire       irq_tx  = tie & tdre_st;
assign     irq     = ~mreset & (irq_rx | irq_tx);

always @(*) begin
	if(~rs) dout = {irq, pe, ovrn, fe, cts_n, dcd_lat, tdre_st, rdrf};
	else    dout = rdr;
end

// Número de ciclos de rxc por bit
wire [6:0] div_n = (cdiv == 2'b00) ? 7'd1 : (cdiv == 2'b01) ? 7'd16 : 7'd64;

//////////////////////////////////////////////////////////////////
// Transmisor

reg  [3:0] tx_bit;     // 0 = reposo
reg  [6:0] tx_cnt;
reg [10:0] tx_shift;
reg  [3:0] tx_len;

//////////////////////////////////////////////////////////////////
// Receptor

reg  [3:0] rx_bit;     // 0 = esperando bit de inicio
reg  [6:0] rx_cnt;
reg  [9:0] rx_shift;
reg  [3:0] rx_len;
reg  [2:0] rxd_s;
always @(posedge clk) rxd_s <= {rxd_s[1:0], rxd};
wire       rx_in = rxd_s[2];

wire [3:0] data_len = bits8 ? 4'd8 : 4'd7;

function parity(input [7:0] d, input b8, input odd);
	parity = (^(b8 ? d : {1'b0, d[6:0]})) ^ odd;
endfunction

// Extracción de la trama recibida
reg  rx_valid;  // la trama terminó por longitud (no por falso inicio)
always @(posedge clk) begin
	if(rxc_ce && rx_bit != 0 && rx_cnt == 0) rx_valid <= (rx_bit == rx_len);
end

reg  rx_busy_d;
always @(posedge clk) rx_busy_d <= (rx_bit != 0);
wire rx_done = rx_busy_d & (rx_bit == 0) & ~reset & ~mreset & rx_valid;

// rx_shift tiene los rx_len bits recibidos en la parte alta (10 bits de ventana)
wire [9:0] rx_frame = rx_shift >> (4'd10 - rx_len);
wire [7:0] rx_data  = bits8 ? rx_frame[8:1] : {1'b0, rx_frame[7:1]};
wire       rx_pbit  = bits8 ? rx_frame[9]   : rx_frame[8];
wire       rx_stop  = rx_frame[rx_len - 1'd1];
wire       rx_perr  = f_par & (rx_pbit != parity(rx_data, bits8, f_odd));


always @(posedge clk) begin
	reg old_dcd;
	old_dcd <= dcd_n;

	if(reset) begin
		cr      <= 8'h03;
		mreset  <= 1;
	end

	if(reset | mreset) begin
		rdrf <= 0; tdre <= 1; fe <= 0; ovrn <= 0; pe <= 0;
		dcd_irq <= 0; dcd_lat <= dcd_n; sr_read_dcd <= 0;
		tx_bit <= 0; txd <= 1;
		rx_bit <= 0;
	end
	else begin
		// /DCD: flanco de subida -> interrupción y estado retenido
		if(dcd_n & ~old_dcd) begin
			dcd_lat <= 1;
			if(rie) dcd_irq <= 1;
		end
		else if(~dcd_irq) dcd_lat <= dcd_n;

		// transmisor
		if(rxc_ce) begin
			if(tx_bit == 0) begin
				txd <= ~brk;
				if(~tdre & ~brk) begin
					// trama: inicio, datos, [paridad], parada(s)
					case({bits8, f_par})
						2'b00: tx_shift <= {3'b111, tdr[6:0], 1'b0};
						2'b01: tx_shift <= {2'b11, parity(tdr, 1'b0, f_odd), tdr[6:0], 1'b0};
						2'b10: tx_shift <= {2'b11, tdr, 1'b0};
						2'b11: tx_shift <= {1'b1, parity(tdr, 1'b1, f_odd), tdr, 1'b0};
					endcase
					tx_len  <= 4'd2 + data_len + f_par + f_stop2;
					tdre    <= 1;
					tx_bit  <= 1;
					tx_cnt  <= 0;
				end
			end
			else begin
				if(tx_cnt == 0) begin
					txd      <= tx_shift[0];
					tx_shift <= {1'b1, tx_shift[10:1]};
				end
				if(tx_cnt == div_n - 1'd1) begin
					tx_cnt <= 0;
					if(tx_bit == tx_len) tx_bit <= 0;
					else tx_bit <= tx_bit + 1'd1;
				end
				else tx_cnt <= tx_cnt + 1'd1;
			end

			// receptor
			if(rx_bit == 0) begin
				if(~rx_in) begin
					rx_bit <= 1;
					rx_cnt <= (div_n == 1) ? 7'd0 : {1'b0, div_n[6:1]} - 1'd1;
					rx_len <= 4'd1 + data_len + f_par + 4'd1;
				end
			end
			else begin
				if(rx_cnt == 0) begin
					rx_cnt <= div_n - 1'd1;
					if(rx_bit == 1 && rx_in) rx_bit <= 0;      // falso inicio
					else begin
						rx_shift <= {rx_in, rx_shift[9:1]};
						if(rx_bit == rx_len) begin
							rx_bit <= 0;
						end
						else rx_bit <= rx_bit + 1'd1;
					end
				end
				else rx_cnt <= rx_cnt - 1'd1;
			end
		end

		// fin de recepción (un ciclo después de capturar el bit de parada)
		if(rx_done) begin
			if(rdrf) ovrn <= 1;
			else begin
				rdr  <= rx_data;
				fe   <= ~rx_stop;
				pe   <= rx_perr;
				rdrf <= 1;
			end
		end

		// accesos de la CPU
		if(cs & rd) begin
			if(~rs) sr_read_dcd <= dcd_irq;
			else begin
				rdrf <= 0;
				ovrn <= 0;
				if(sr_read_dcd) begin dcd_irq <= 0; sr_read_dcd <= 0; end
			end
		end

		if(cs & wr & rs) begin
			tdr  <= din;
			tdre <= 0;
		end
	end

	if(cs & wr & ~rs) begin
		cr     <= din;
		mreset <= (din[1:0] == 2'b11);
	end
end

endmodule
