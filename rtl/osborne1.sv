// Osborne 1 - máquina completa
// Shaeon (Carlos Palmero)
//
// Referencias: driver osborne1 de MAME (Wilbert Pol, Vas Crabb) y
// Osborne 1 Technical Manual.
//
// clk_sys = 31.9512 MHz (~2 x 15.9744 MHz; 50*131/5/41, +76 ppm)
//   CPU   : clk_sys/8 = 3.9936 MHz
//   píxel : clk_sys/4 = 7.9872 MHz, 512 x 260 => 15.6 kHz / 60 Hz
//
// Mapa de memoria
//   Modo RAM : 64 KB de RAM
//   Modo ROM : 0000-1FFF BIOS (4 KB, espejada), escrituras ignoradas
//              2000-3FFF periféricos (decodificación parcial, ver más abajo)
//   BIT 9    : F000-FFFF lee/escribe la RAM de atributos (1 bit, D7)
// E/S (solo A1:A0): OUT 0 = modo ROM, OUT 1 = modo RAM, OUT 2 = BIT 9 on, OUT 3 = BIT 9 off
// Interrupciones en IM 2: vectores F0 (PIA IEEE), F8 (PIA vídeo), FC (ACIA)

module osborne1
(
	input         clk_sys,
	input         reset,

	// teclado
	input  [10:0] ps2_key,

	// vídeo
	output        ce_pix,
	output reg    hsync,
	output reg    vsync,
	output reg    hblank,
	output reg    vblank,
	output  [7:0] video,

	// sonido
	output        speaker,

	// puerto serie (señales de módem activas a nivel bajo)
	input   [1:0] serial_cfg,    // 0=300/1200 1=600/2400 2=1200/4800 3=2400/9600
	input         ser_rxd,
	output        ser_txd,
	input         ser_cts_n,
	input         ser_dcd_n,
	input         ser_ri_n,
	output        ser_rts_n,

	// disquetes (2 unidades)
	input   [1:0] img_mounted,
	input         img_readonly,
	input  [63:0] img_size,
	output [31:0] sd_lba[2],
	output  [1:0] sd_rd,
	output  [1:0] sd_wr,
	input   [1:0] sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[2],
	input         sd_buff_wr,

	output  [1:0] fdd_led
);

//////////////////////////////////////////////////////////////////
// Relojes

reg [2:0] div;
always @(posedge clk_sys) div <= div + 1'd1;

wire cpu_ce = (div == 7);
assign ce_pix = (div[1:0] == 3);

//////////////////////////////////////////////////////////////////
// CPU

wire [15:0] addr;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;
wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire        int_n, nmi_n;

T80s cpu  // Mode 0 (Z80), T2Write 1, IOWait 1 (valores por defecto)
(
	.RESET_n(~reset),
	.CLK(clk_sys),
	.CEN(cpu_ce),
	.WAIT_n(1'b1),
	.INT_n(int_n),
	.NMI_n(nmi_n),
	.BUSRQ_n(1'b1),
	.M1_n(m1_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.RFSH_n(rfsh_n),
	.HALT_n(),
	.BUSAK_n(),
	.A(addr),
	.DI(cpu_din),
	.DO(cpu_dout)
);

wire mem_rd  = ~mreq_n & ~rd_n & rfsh_n;
wire mem_wr  = ~mreq_n & ~wr_n;
wire fetch   = ~m1_n & ~mreq_n;
wire inta    = ~m1_n & ~iorq_n;
wire io_wr   =  m1_n & ~iorq_n & ~wr_n;

reg old_mem_rd, old_mem_wr, old_fetch, old_inta, old_io_wr;
always @(posedge clk_sys) begin
	old_mem_rd <= mem_rd;
	old_mem_wr <= mem_wr;
	old_fetch  <= fetch;
	old_inta   <= inta;
	old_io_wr  <= io_wr;
end

wire mem_rd_stb = mem_rd & ~old_mem_rd;
wire mem_wr_stb = mem_wr & ~old_mem_wr;
wire fetch_stb  = fetch  & ~old_fetch;
wire inta_stb   = inta   & ~old_inta;
wire io_wr_stb  = io_wr  & ~old_io_wr;

//////////////////////////////////////////////////////////////////
// Bancos (biestables UB4A/UB6A del esquema, como en MAME)

reg rom_mode, bit9, ub4a, ub6a;
wire reset_key;

always @(posedge clk_sys) begin
	if(reset) begin
		rom_mode <= 1;
		bit9     <= 0;
		ub4a     <= 0;
		ub6a     <= 1;
	end
	else begin
		if(fetch_stb) begin
			if(~rom_mode) begin
				rom_mode <= ~ub4a;
				ub4a     <= ub6a;
			end
			ub6a <= ~reset_key;
		end

		if(inta_stb) begin
			if(~rom_mode) rom_mode <= ~ub4a;
			ub4a <= 0;
			ub6a <= ~reset_key;
		end

		if(io_wr_stb) begin
			case(addr[1:0])
				0: if(~rom_mode) begin rom_mode <= 1; ub4a <= ub6a; end
				1: begin rom_mode <= 0; ub4a <= 1; ub6a <= 1; end
				2: bit9 <= 1;
				3: bit9 <= 0;
			endcase
		end
	end
end

assign nmi_n = ~(~ub6a & reset_key);

//////////////////////////////////////////////////////////////////
// Decodificación

wire sel_rom  = rom_mode & (addr[15:13] == 3'b000);
wire sel_io   = rom_mode & (addr[15:13] == 3'b001);
wire sel_attr = bit9     & (addr[15:12] == 4'hF);
wire sel_ram  = ~sel_rom & ~sel_io & ~sel_attr;

// Periféricos: cada uno solo mira dos bits (offset = addr[11:0])
wire cs_fdc  = sel_io & (addr[11] == 1'b0) & (addr[8]  == 1'b1);
wire cs_ieee = sel_io & (addr[11] == 1'b1) & (addr[8]  == 1'b1);
wire cs_kbd  = sel_io & (addr[11] == 1'b0) & (addr[9]  == 1'b1);
wire cs_acia = sel_io & (addr[11] == 1'b1) & (addr[9]  == 1'b1);
wire cs_vpia = sel_io & (addr[11] == 1'b1) & (addr[10] == 1'b1);

//////////////////////////////////////////////////////////////////
// Memorias

reg [7:0] bios[4096];
initial $readmemh("rom/osborne1_bios144.hex", bios);
reg [7:0] bios_q;
always @(posedge clk_sys) bios_q <= bios[addr[11:0]];

reg [7:0] chargen[2048];
initial $readmemh("rom/osborne1_char.hex", chargen);

// RAM principal 64 KB, puerto B para vídeo
reg  [7:0] ram[65536];
reg  [7:0] ram_q;
reg [15:0] vaddr;
reg  [7:0] vram_q;

always @(posedge clk_sys) begin
	if(mem_wr & sel_ram) ram[addr] <= cpu_dout;
	ram_q <= ram[addr];
end
always @(posedge clk_sys) vram_q <= ram[vaddr];

// RAM de atributos 4K x 1
reg        attr[4096];
reg        attr_q, vattr_q;
always @(posedge clk_sys) begin
	if(mem_wr & sel_attr) attr[addr[11:0]] <= cpu_dout[7];
	attr_q <= attr[addr[11:0]];
end
always @(posedge clk_sys) vattr_q <= attr[vaddr[11:0]];

//////////////////////////////////////////////////////////////////
// Periféricos

wire [63:0] kbd_rows;
osb_keyboard keyboard
(
	.clk(clk_sys),
	.reset(reset),
	.ps2_key(ps2_key),
	.rows(kbd_rows),
	.reset_key(reset_key)
);

// A0..A7 seleccionan las filas 0,1,3,4,5,2,6,7 (nomenclatura de MAME)
wire [7:0] kbd_q = (addr[0] ? kbd_rows[0*8 +: 8] : 8'hFF) &
                   (addr[1] ? kbd_rows[1*8 +: 8] : 8'hFF) &
                   (addr[2] ? kbd_rows[3*8 +: 8] : 8'hFF) &
                   (addr[3] ? kbd_rows[4*8 +: 8] : 8'hFF) &
                   (addr[4] ? kbd_rows[5*8 +: 8] : 8'hFF) &
                   (addr[5] ? kbd_rows[2*8 +: 8] : 8'hFF) &
                   (addr[6] ? kbd_rows[6*8 +: 8] : 8'hFF) &
                   (addr[7] ? kbd_rows[7*8 +: 8] : 8'hFF);

// PIA del vídeo (2C00)
wire [7:0] vpia_q, vpia_pa, vpia_pb;
wire       vpia_irq;
reg        vbl_int;

pia6821 video_pia
(
	.clk(clk_sys),
	.reset(reset),
	.cs(cs_vpia),
	.rd(mem_rd_stb),
	.wr(mem_wr_stb),
	.rs(addr[1:0]),
	.din(cpu_dout),
	.dout(vpia_q),
	.pa_i(8'hFF),
	.pa_o(vpia_pa),
	.pb_i(8'hFF),
	.pb_o(vpia_pb),
	.ca1(vbl_int),
	.ca2_i(ser_ri_n),          // RI del RS-232
	.ca2_o(),
	.cb1(1'b1),
	.cb2_i(1'b1),
	.cb2_o(),
	.irqa(vpia_irq),
	.irqb()
);

// PIA IEEE-488 (2900): sin nada conectado el bus queda en reposo (alto)
wire [7:0] ieee_q;
wire       ieee_irq;

pia6821 ieee_pia
(
	.clk(clk_sys),
	.reset(reset),
	.cs(cs_ieee),
	.rd(mem_rd_stb),
	.wr(mem_wr_stb),
	.rs(addr[1:0]),
	.din(cpu_dout),
	.dout(ieee_q),
	.pa_i(8'hFF),
	.pa_o(),
	.pb_i(8'hFF),
	.pb_o(),
	.ca1(1'b1),
	.ca2_i(1'b1),
	.ca2_o(),
	.cb1(1'b1),
	.cb2_i(1'b1),
	.cb2_o(),
	.irqa(ieee_irq),
	.irqb()
);

// ACIA 6850 (2A00)
// RxC/TxC sale del reloj maestro (15,9744 MHz) según los puentes de velocidad:
// periodo = (p_low + p_high) * div ciclos maestros (MAME, Technical Manual).
// 300/1200: 52*16, 600/2400: 24*16 (bug original, va un 8 % rápido),
// 1200/4800: 13*16, 2400/9600: 13*8. clk_sys = 2 x maestro.
reg [10:0] baud_cnt;
reg        rxc_ce;
wire [10:0] baud_div = (serial_cfg == 0) ? 11'd1663 :
                       (serial_cfg == 1) ? 11'd767  :
                       (serial_cfg == 2) ? 11'd415  : 11'd207;
always @(posedge clk_sys) begin
	rxc_ce <= 0;
	if(baud_cnt >= baud_div) begin
		baud_cnt <= 0;
		rxc_ce   <= 1;
	end
	else baud_cnt <= baud_cnt + 1'd1;
end

wire [7:0] acia_q;
wire       acia_irq;

acia6850 acia
(
	.clk(clk_sys),
	.reset(reset),
	.cs(cs_acia),
	.rd(mem_rd_stb),
	.wr(mem_wr_stb),
	.rs(addr[0]),
	.din(cpu_dout),
	.dout(acia_q),
	.irq(acia_irq),
	.rxc_ce(rxc_ce),
	.rxd(ser_rxd),
	.txd(ser_txd),
	.cts_n(ser_cts_n),
	.dcd_n(ser_dcd_n),
	.rts_n(ser_rts_n)
);

// Controlador de disquete MB8877/WD1793, una instancia por unidad
wire       dden_n = vpia_pa[0];          // 1 = simple densidad
reg        drv_sel;                      // última unidad seleccionada
wire       drv_a  = vpia_pb[6];
wire       drv_b  = ~vpia_pb[6] & vpia_pb[7];
always @(posedge clk_sys) begin
	if(reset) drv_sel <= 0;
	else if(drv_a) drv_sel <= 0;
	else if(drv_b) drv_sel <= 1;
end

reg  [1:0] mounted, is_dd, wprot;
always @(posedge clk_sys) begin
	integer d;
	for(d = 0; d < 2; d = d + 1) begin
		if(img_mounted[d]) begin
			mounted[d] <= (img_size != 0);
			is_dd[d]   <= (img_size > 64'd150000);
			wprot[d]   <= img_readonly;
		end
	end
end

wire [7:0] fdc_q[2];
wire [1:0] fdc_busy;
genvar gd;
generate
	for(gd = 0; gd < 2; gd = gd + 1) begin : fdc
		wd1793 #(.RWMODE(1), .EDSK(0)) wd
		(
			.clk_sys(clk_sys),
			.ce(cpu_ce),
			.reset(reset),
			.io_en(cs_fdc & (drv_sel == gd)),
			.rd(mem_rd),
			.wr(mem_wr),
			.addr(addr[1:0]),
			.din(cpu_dout),
			.dout(fdc_q[gd]),
			.drq(),
			.intrq(),
			.busy(fdc_busy[gd]),

			.wp(wprot[gd]),
			.size_code(is_dd[gd] ? 3'd3 : 3'd5),
			.layout(1'b1),          // una cara: pista = posición lineal
			.side(1'b0),
			.ready(1'b1),
			.rnf(~mounted[gd] | (is_dd[gd] == dden_n)),

			.img_mounted(img_mounted[gd]),
			.img_size(img_size[19:0]),
			.prepare(),
			.sd_lba(sd_lba[gd]),
			.sd_rd(sd_rd[gd]),
			.sd_wr(sd_wr[gd]),
			.sd_ack(sd_ack[gd]),
			.sd_buff_addr(sd_buff_addr),
			.sd_buff_dout(sd_buff_dout),
			.sd_buff_din(sd_buff_din[gd]),
			.sd_buff_wr(sd_buff_wr),

			.input_active(1'b0),
			.input_addr(20'd0),
			.input_data(8'd0),
			.input_wr(1'b0),
			.buff_addr(),
			.buff_read(),
			.buff_din(8'd0)
		);
	end
endgenerate

assign fdd_led = fdc_busy;

// Lectura del área de periféricos: AND de todo lo que responde
wire [7:0] io_q = (cs_fdc  ? fdc_q[drv_sel] : 8'hFF) &
                  (cs_ieee ? ieee_q         : 8'hFF) &
                  (cs_kbd  ? kbd_q          : 8'hFF) &
                  (cs_acia ? acia_q         : 8'hFF) &
                  (cs_vpia ? vpia_q         : 8'hFF);

//////////////////////////////////////////////////////////////////
// Interrupciones (IM 2)

assign int_n = ~(ieee_irq | vpia_irq | acia_irq);
wire [7:0] int_vec = ieee_irq ? 8'hF0 : vpia_irq ? 8'hF8 : acia_irq ? 8'hFC : 8'hFE;

//////////////////////////////////////////////////////////////////
// Bus de datos de la CPU

always @(*) begin
	if(inta)                  cpu_din = int_vec;
	else if(~iorq_n)          cpu_din = 8'hFF;
	else if(sel_rom)          cpu_din = bios_q;
	else if(sel_io)           cpu_din = io_q;
	else if(sel_attr)         cpu_din = {attr_q, 7'h7F};
	else                      cpu_din = ram_q;
end

//////////////////////////////////////////////////////////////////
// Vídeo: 52 x 24 caracteres de 8x10 sobre una pantalla virtual de 128 x 32

reg  [8:0] hcnt;    // 0..511
reg  [8:0] vcnt;    // 0..259
reg  [3:0] ra;      // línea dentro del carácter
reg  [4:0] trow;    // fila de texto
reg  [4:0] scroll_y;

wire [6:0] scroll_x = vpia_pa[7:1];
wire [6:0] col0     = scroll_x + 7'h0B;

reg  [7:0] gfx_next, shift;
reg        attr_next, attr_cur, ul_next;
reg [10:0] cg_addr;
reg  [7:0] cg_q;
always @(posedge clk_sys) cg_q <= chargen[cg_addr];

always @(posedge clk_sys) begin
	if(ce_pix) begin
		// contadores
		if(hcnt == 511) begin
			hcnt <= 0;
			if(vcnt == 259) begin
				vcnt     <= 0;
				ra       <= 0;
				trow     <= 0;
				scroll_y <= vpia_pb[4:0];
			end
			else begin
				vcnt <= vcnt + 1'd1;
				if(ra == 9) begin
					ra   <= 0;
					trow <= trow + 1'd1;
				end
				else ra <= ra + 1'd1;
			end
		end
		else hcnt <= hcnt + 1'd1;

		// búsqueda del carácter de la celda siguiente (celda visible 1..52)
		case(hcnt[2:0])
			1: vaddr <= {4'hF, scroll_y + trow, col0 + hcnt[8:3]};
			3: begin
					cg_addr   <= {ra, vram_q[6:0]};
					ul_next   <= vram_q[7];
					attr_next <= vattr_q;
				end
			5: gfx_next <= (ul_next && ra == 9) ? 8'hFF : cg_q;
			default:;
		endcase

		if(hcnt[2:0] == 7) begin
			shift    <= gfx_next;
			attr_cur <= attr_next;
		end
		else shift <= {shift[6:0], 1'b0};

		// sincronismos (valores de la posición siguiente)
		hblank <= (hcnt < 7) || (hcnt >= 423);
		hsync  <= (hcnt >= 455 && hcnt < 495);
		if(hcnt == 511) begin
			vblank <= (vcnt >= 239 && vcnt != 259);
			vsync  <= (vcnt >= 243 && vcnt < 246);
		end
	end
end

// CA1 de la PIA de vídeo: flanco de subida al empezar el borrado vertical
always @(posedge clk_sys) vbl_int <= vblank;

assign video = (~hblank & ~vblank & shift[7]) ? (attr_cur ? 8'hFF : 8'hB0) : 8'h00;

// Zumbador: activo 4 de cada 10 líneas cuando PB5 = 1
assign speaker = vpia_pb[5] & ra[2];

endmodule
