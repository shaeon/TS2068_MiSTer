//-------------------------------------------------------------------------------------------------
// TS2068 para MiSTer - carga de cartuchos DCK (formato de Warajevo) desde hps_io.
// Shaeon (Carlos Palmero).
//
// Un DCK es una o varias entradas "cabecera de 9 bytes + datos":
//   byte 0      banco: 0 = DOCK, 254 = EXROM, 255 = HOME
//   bytes 1-8   un byte por cada trozo (chunk) de 8K del banco, 0-7:
//                 bit 0 = trozo de lectura/escritura (RAM)
//                 bit 1 = la imagen del trozo esta en el fichero
//   datos       8K por cada trozo con el bit 1 a 1, en orden de trozo
//
// En hps_io no llega el tamano del fichero, asi que (a diferencia de psd.v de Kyp, que decide por
// el tamano si hay cabecera) se interpreta la cabecera conforme llegan los bytes y cada byte de
// datos sale ya con su banco y su direccion: { trozo, desplazamiento de 13 bits }.
//
// Imagenes sin cabecera (volcado del banco DOCK tal cual, p. ej. Manic Miner de 64K): psd.v de Kyp
// y el port de Calypso las cargan desde la direccion 0 y dejan visibles los trozos 0 hasta el
// ultimo cargado. Aqui se reconocen porque los 9 primeros bytes no son una cabecera valida
// (banco 0, 254 o 255 y bytes de trozo de 0 a 3). Para no tener que retenerlos, los 9 primeros
// bytes del fichero se escriben siempre en el DOCK (direcciones 0-8) mientras se leen: si era una
// cabecera, esas 9 posiciones las pisa el trozo 0 si viene en el fichero y, si no viene, el trozo
// no se ve (lee FF) o es RAM sin contenido definido.
//
// Para el banco DOCK se devuelven ademas los trozos que existen (rd: ROM o RAM) y los que se
// pueden escribir (wr), que sustituyen al "docked/dckS" de Kyp: asi tambien funcionan los
// cartuchos AROS (trozos 4-7) y los de RAM (cabecera 0,1,1,1,1,1,1,1,1).
//-------------------------------------------------------------------------------------------------
module dck_loader
(
	input  wire       clock,

	input  wire       dl,           // descarga del DCK en curso
	input  wire       dlW,          // byte valido
	input  wire[ 7:0] dlD,

	input  wire       eject,        // quitar el cartucho

	output reg        w = 1'b0,     // escritura de un byte de datos (un ciclo)
	output reg [ 7:0] bank = 8'd0,  // banco del byte (0 DOCK, 254 EXROM, 255 HOME)
	output reg [15:0] a = 16'd0,    // direccion dentro del banco
	output reg [ 7:0] d = 8'd0,

	output reg [ 7:0] dockRd = 8'd0,// trozos del DOCK presentes
	output reg [ 7:0] dockWr = 8'd0 // trozos del DOCK de RAM
);
//-------------------------------------------------------------------------------------------------

	reg       dlP = 1'b0;
	reg       hdr = 1'b1;           // 1: leyendo cabecera, 0: leyendo datos
	reg [3:0] cnt = 4'd0;           // byte de la cabecera
	reg [7:0] bnk = 8'd0;
	reg [7:0] rdM = 8'd0;           // trozos con bit 0 o 1 (de la cabecera en curso)
	reg [7:0] wrM = 8'd0;           // trozos con bit 0
	reg [7:0] pending = 8'd0;       // trozos con imagen que faltan por llegar
	reg [2:0] chunk = 3'd0;
	reg[12:0] off = 13'd0;
	reg       firstE = 1'b1;        // primera entrada del fichero
	reg       ok = 1'b1;            // la cabecera en curso es valida
	reg       raw = 1'b0;           // imagen sin cabecera
	reg[15:0] rawA = 16'd0;

	// primer trozo pendiente
	function [3:0] first(input [7:0] m);   // { encontrado, indice }
		integer i;
		begin
			first = 4'd0;
			for(i = 7; i >= 0; i = i-1) if(m[i]) first = { 1'b1, i[2:0] };
		end
	endfunction

	wire[3:0] fHdr  = first({ dlD[1], pending[6:0] });
	wire[7:0] left  = pending & ~(8'd1 << chunk);
	wire[3:0] fNext = first(left);

	always @(posedge clock) begin
		dlP <= dl;
		w <= 1'b0;

		if(eject) begin
			dockRd <= 8'd0;
			dockWr <= 8'd0;
		end

		if(dl && !dlP) begin
			hdr <= 1'b1;
			cnt <= 4'd0;
			firstE <= 1'b1;
			ok <= 1'b1;
			raw <= 1'b0;
			dockRd <= 8'd0;     // un cartucho nuevo sustituye al anterior
			dockWr <= 8'd0;
		end
		else if(dl && dlW && raw) begin
			// imagen sin cabecera: todo seguido en el DOCK, de solo lectura (como psd.v)
			w <= 1'b1;
			bank <= 8'd0;
			a <= rawA;
			d <= dlD;
			dockRd[rawA[15:13]] <= 1'b1;
			rawA <= rawA+1'd1;
		end
		else if(dl && dlW) begin
			if(hdr) begin
				// primera entrada: el byte va tambien al DOCK por si no hay cabecera
				if(firstE) begin
					w <= 1'b1;
					bank <= 8'd0;
					a <= { 12'd0, cnt };
					d <= dlD;
				end

				// cabecera: byte 0 = banco, bytes 1-8 = trozos 0-7
				if(cnt == 4'd0) begin
					bnk <= dlD;
					ok <= dlD == 8'd0 || dlD == 8'd254 || dlD == 8'd255;
				end
				else begin
					rdM[cnt-1'd1] <= dlD[0] | dlD[1];
					wrM[cnt-1'd1] <= dlD[0];
					pending[cnt-1'd1] <= dlD[1];
					if(dlD[7:2] != 6'd0) ok <= 1'b0;
				end

				if(cnt == 4'd8 && firstE && (!ok || dlD[7:2] != 6'd0)) begin
					// no es una cabecera: imagen sin cabecera desde el byte 0
					raw <= 1'b1;
					rawA <= 16'd9;
					dockRd <= 8'd1;
					dockWr <= 8'd0;
				end
				else if(cnt == 4'd8) begin
					cnt <= 4'd0;
					firstE <= 1'b0;
					if(bnk == 8'd0) begin
						dockRd <= dockRd | { dlD[0] | dlD[1], rdM[6:0] };
						dockWr <= dockWr | { dlD[0], wrM[6:0] };
					end
					if(fHdr[3]) begin
						hdr <= 1'b0;
						chunk <= fHdr[2:0];
						off <= 13'd0;
					end
				end
				else cnt <= cnt+1'd1;
			end
			else begin
				// datos del trozo en curso
				w <= 1'b1;
				bank <= bnk;
				a <= { chunk, off };
				d <= dlD;

				off <= off+1'd1;
				if(&off) begin
					pending <= left;
					if(fNext[3]) chunk <= fNext[2:0];
					else begin hdr <= 1'b1; cnt <= 4'd0; end   // otra entrada (otro banco)
				end
			end
		end
	end

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
