// Teclado del Osborne 1: matriz 8x8 activa a nivel bajo a partir de ps2_key de MiSTer
// Shaeon (Carlos Palmero)
//
// Distribución de filas/bits tomada del driver osborne1 de MAME.
// rows[8*r + b] = 0 cuando la tecla de la fila r, bit b está pulsada.
//
// Correspondencias especiales:
//   Retroceso  -> cursor izquierda (como en MAME)
//   ]          -> tecla [ ] con SHIFT forzado
//   Bloq Mayús -> ALPHA LOCK (tecla con enclavamiento)
//   F10        -> botón RESET del frontal (genera NMI)

module osb_keyboard
(
	input             clk,
	input             reset,
	input      [10:0] ps2_key,
	output     [63:0] rows,       // activo a 0
	output reg        reset_key   // 1 = pulsado
);

reg [63:0] keys;          // activo a 1
reg        alpha_lock;
reg        force_shift;

// SHIFT es fila 0 bit 4
wire [63:0] k = keys | ({63'd0, alpha_lock} << (7*8+3)) | ({63'd0, force_shift} << 4);
assign rows = ~k;

wire       pressed = ps2_key[9];
wire       ext     = ps2_key[8];
wire [7:0] code    = ps2_key[7:0];

`define K(r,b) keys[(r)*8+(b)] <= pressed

always @(posedge clk) begin
	reg old_stb;
	old_stb <= ps2_key[10];

	if(reset) begin
		keys        <= 0;
		alpha_lock  <= 0;
		force_shift <= 0;
		reset_key   <= 0;
	end
	else if(old_stb != ps2_key[10]) begin
		if(ext) begin
			case(code)
				8'h75: `K(2,0);          // arriba
				8'h6B: `K(2,1);          // izquierda
				8'h72: `K(6,1);          // abajo
				8'h74: `K(6,0);          // derecha
				8'h5A: `K(0,5);          // Intro del teclado numérico
				8'h14: `K(0,2);          // Ctrl derecho
				8'h71: `K(2,1);          // Supr -> izquierda
				default:;
			endcase
		end
		else begin
			case(code)
				// Fila 0
				8'h54: `K(0,7);                                 // [
				8'h5B: begin `K(0,7); force_shift <= pressed; end // ]
				8'h52: `K(0,6);                                 // ' "
				8'h5A: `K(0,5);                                 // Intro
				8'h12, 8'h59: `K(0,4);                          // Shift
				8'h14: `K(0,2);                                 // Ctrl
				8'h0D: `K(0,1);                                 // Tab
				8'h76: `K(0,0);                                 // Esc

				// Fila 1
				8'h3E, 8'h75: `K(1,7);                          // 8
				8'h3D, 8'h6C: `K(1,6);                          // 7
				8'h36, 8'h74: `K(1,5);                          // 6
				8'h2E, 8'h73: `K(1,4);                          // 5
				8'h25, 8'h6B: `K(1,3);                          // 4
				8'h26, 8'h7A: `K(1,2);                          // 3
				8'h1E, 8'h72: `K(1,1);                          // 2
				8'h16, 8'h69: `K(1,0);                          // 1

				// Fila 2
				8'h46, 8'h7D: `K(2,7);                          // 9
				8'h44: `K(2,6);                                 // O
				8'h4D: `K(2,5);                                 // P
				8'h49, 8'h71: `K(2,4);                          // .
				8'h29: `K(2,3);                                 // espacio
				8'h45, 8'h70: `K(2,2);                          // 0
				8'h66: `K(2,1);                                 // retroceso -> izquierda

				// Fila 3
				8'h43: `K(3,7); 8'h3C: `K(3,6); 8'h35: `K(3,5); 8'h2C: `K(3,4); // I U Y T
				8'h2D: `K(3,3); 8'h24: `K(3,2); 8'h1D: `K(3,1); 8'h15: `K(3,0); // R E W Q

				// Fila 4
				8'h42: `K(4,7); 8'h3B: `K(4,6); 8'h33: `K(4,5); 8'h34: `K(4,4); // K J H G
				8'h2B: `K(4,3); 8'h23: `K(4,2); 8'h1B: `K(4,1); 8'h1C: `K(4,0); // F D S A

				// Fila 5
				8'h41: `K(5,7); 8'h3A: `K(5,6); 8'h31: `K(5,5); 8'h32: `K(5,4); // , M N B
				8'h2A: `K(5,3); 8'h21: `K(5,2); 8'h22: `K(5,1); 8'h1A: `K(5,0); // V C X Z

				// Fila 6
				8'h55, 8'h79: `K(6,7);                          // = +
				8'h4B: `K(6,6);                                 // L
				8'h5D, 8'h61: `K(6,5);                          // \ |
				8'h4C: `K(6,4);                                 // ; :
				8'h4A: `K(6,3);                                 // / ?
				8'h4E, 8'h7B: `K(6,2);                          // - _

				// Fila 7
				8'h58: if(pressed) alpha_lock <= ~alpha_lock;   // ALPHA LOCK

				8'h09: reset_key <= pressed;                    // F10 -> RESET
				default:;
			endcase
		end
	end
end

`undef K

endmodule
