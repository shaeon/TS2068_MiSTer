//-------------------------------------------------------------------------------------------------
// Timex Sinclair 2068 / Timex Computer 2068 para MiSTer
//
// Core: Kyp (https://github.com/Kyp069/ts2068), submodulo rtl/ts2068 sin cambios.
// Port MiSTer: Shaeon (Carlos Palmero), a partir de psd.v (version para Poseidon) del mismo repo.
//
// Memoria (toda en BRAM, no hace falta SDRAM):
//   home  64K  ROM (0000-3FFF, inicializada con tc2068-0) + RAM 48K, doble puerto para el video
//   extd   8K  EXROM (tc2068-1)
//   dock  64K  banco DOCK del cartucho (DCK)
//   dram 128K  RAM de la DivMMC, drom 8K esxDOS
// La cinta va a la DDR3 (rtl/tape_ddr.sv).
//
// ROM (opcional, la de Kyp va dentro del core): games/TS2068/boot.rom o "Load ROM": los primeros
// 16K van a HOME y, si el fichero tiene 24K (ts2068.rom), los 8K siguientes a la EXROM.
//
// This program is free software; you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation; either version 3 of
// the License, or (at your option) any later version.
//-------------------------------------------------------------------------------------------------
module emu
(
	`include "sys/emu_ports.vh"
);
//--- defaults ------------------------------------------------------------------------------------

	assign USER_OUT = '1;
	assign {UART_RTS, UART_TXD, UART_DTR} = 0;
	assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
	assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

	assign VGA_F1 = 0;
	assign VGA_SCALER = 0;
	assign VGA_DISABLE = 0;
	assign HDMI_FREEZE = 0;
	assign HDMI_BLACKOUT = 0;
	assign HDMI_BOB_DEINT = 0;

	assign BUTTONS = 0;
	assign LED_POWER = 0;

//--- forward declarations ------------------------------------------------------------------------

	wire[127:0] status;
	wire        model = status[3];        // 0: PAL (TC2068), 1: NTSC (TS2068)

//--- config string -------------------------------------------------------------------------------
//
//  bits usados: 0-4, 6-7, 9-19
//  0         1         2         3
//  01234567890123456789012345678901
//  XXXXX XX XXXXXXXXXXX
//
	`include "build_id.v"
	localparam CONF_STR =
	{
		"TS2068;;",
		"-;",
		"F1,DCK,Load cartridge;",
		"F2,TZXTAPPZX,Load tape;",
		"S0,VHD,Mount SD (DivMMC);",
		"F3,ROM,Load ROM;",
		"-;",
		"O[3],Model,TC2068 (PAL),TS2068 (NTSC);",
		"O[4],DivMMC,Off,On;",
		"-;",
		"P1,Video;",
		"P1-;",
		"P1O[10:9],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
		"P1O[13:11],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
		"P1O[15:14],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
		"P2,Audio & Input;",
		"P2-;",
		"P2O[6],Tape sound,Off,On;",
		"P2O[17:16],Stereo mix,None,25%,50%,100%;",
		"P2O[7],Swap joysticks,Off,On;",
		"-;",
		"T[18],Tape play;",
		"T[19],Tape stop;",
		"T[2],Remove cartridge;",
		"-;",
		"R[0],Reset;",
		"T[1],NMI;",
		"J1,Fire;",
		"jn,A;",
		"V,v",`BUILD_DATE
	};

//--- clock ---------------------------------------------------------------------------------------

	wire clock;
	wire power;

	wire[63:0] reconfig_to_pll;
	wire[63:0] reconfig_from_pll;

	pll pll
	(
		.refclk           (CLK_50M          ),
		.rst              (1'b0             ),
		.outclk_0         (clock            ), // 56.000 MHz (PAL) / 56.488 MHz (NTSC)
		.locked           (power            ),
		.reconfig_to_pll  (reconfig_to_pll  ),
		.reconfig_from_pll(reconfig_from_pll)
	);

	// psd.v de Kyp usa dos PLL (56.000 y 56.488 MHz) y elige con el modelo; aqui se reconfigura
	// la misma PLL al cambiar el modelo (como el core C64 con PAL/NTSC).

	wire       cfgWait;
	wire       cfgW;
	wire[ 5:0] cfgA;
	wire[31:0] cfgD;

	pll_cfg pll_cfg
	(
		.mgmt_clk         (CLK_50M          ),
		.mgmt_reset       (1'b0             ),
		.mgmt_waitrequest (cfgWait          ),
		.mgmt_read        (1'b0             ),
		.mgmt_readdata    (                 ),
		.mgmt_write       (cfgW             ),
		.mgmt_address     (cfgA             ),
		.mgmt_writedata   (cfgD             ),
		.reconfig_to_pll  (reconfig_to_pll  ),
		.reconfig_from_pll(reconfig_from_pll)
	);

	wire cfgBusy;

	pll_timing pll_timing
	(
		.clk    (CLK_50M  ),
		.timing (model    ),
		.busy   (cfgBusy  ),
		.cfgWait(cfgWait  ),
		.cfgW   (cfgW     ),
		.cfgA   (cfgA     ),
		.cfgD   (cfgD     )
	);

	reg cfgBusyS1 = 1'b0, cfgBusyS = 1'b0;
	always @(posedge clock) begin cfgBusyS1 <= cfgBusy; cfgBusyS <= cfgBusyS1; end

	// habilitaciones de reloj: las mismas que psd.v
	reg[3:0] ce;
	always @(negedge clock, negedge power) if(!power) ce <= 1'd0; else ce <= ce+1'd1;

	wire ne14M = ce[1:0] == 3;
	wire ne7M0 = ce[2:0] == 7;
	wire pe7M0 = ce[2:0] == 3;
	wire ne3M5 = ce[3:0] == 15;
	wire pe3M5 = ce[3:0] == 7;

//--- hps io --------------------------------------------------------------------------------------

	wire [  1:0] buttons;
	wire         forced_scandoubler;
	wire [ 21:0] gamma_bus;

	wire         ps2kCk;
	wire         ps2kD;

	wire [ 31:0] joystick_0;
	wire [ 31:0] joystick_1;

	wire         ioctl_download;
	wire [ 15:0] ioctl_index;
	wire         ioctl_wr;
	wire [ 26:0] ioctl_addr;
	wire [  7:0] ioctl_dout;
	wire         ioctl_wait;

	wire [  0:0] img_mounted;
	wire         img_readonly;
	wire [ 63:0] img_size;

	wire [ 31:0] sd_lba[1];
	wire [  0:0] sd_rd;
	wire [  0:0] sd_wr;
	wire [  0:0] sd_ack;
	wire [ 13:0] sd_buff_addr;
	wire [  7:0] sd_buff_dout;
	wire [  7:0] sd_buff_din[1];
	wire         sd_buff_wr;

	hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2000), .VDNUM(1)) hps_io
	(
		.clk_sys           (clock             ),
		.HPS_BUS           (HPS_BUS           ),
		.EXT_BUS           (                  ),
		.gamma_bus         (gamma_bus         ),

		.forced_scandoubler(forced_scandoubler),
		.buttons           (buttons           ),
		.status            (status            ),
		.status_menumask   (16'd0             ),

		.ps2_kbd_clk_out   (ps2kCk            ),
		.ps2_kbd_data_out  (ps2kD             ),

		.joystick_0        (joystick_0        ),
		.joystick_1        (joystick_1        ),

		.ioctl_download    (ioctl_download    ),
		.ioctl_index       (ioctl_index       ),
		.ioctl_wr          (ioctl_wr          ),
		.ioctl_addr        (ioctl_addr        ),
		.ioctl_dout        (ioctl_dout        ),
		.ioctl_wait        (ioctl_wait        ),

		.img_mounted       (img_mounted       ),
		.img_readonly      (img_readonly      ),
		.img_size          (img_size          ),

		.sd_lba            (sd_lba            ),
		.sd_blk_cnt        ('{6'd0}           ),
		.sd_rd             (sd_rd             ),
		.sd_wr             (sd_wr             ),
		.sd_ack            (sd_ack            ),
		.sd_buff_addr      (sd_buff_addr      ),
		.sd_buff_dout      (sd_buff_dout      ),
		.sd_buff_din       (sd_buff_din       ),
		.sd_buff_wr        (sd_buff_wr        )
	);

	// boot.rom (indice 0) y "Load ROM" (F3) cargan la ROM; F1 el cartucho y F2 la cinta
	wire romIo = ioctl_download && (ioctl_index[5:0] == 0 || ioctl_index[5:0] == 3);
	wire dckIo = ioctl_download && ioctl_index[5:0] == 1;
	wire tzxIo = ioctl_download && ioctl_index[5:0] == 2;

	wire romW  = romIo && ioctl_wr;

//--- joysticks -----------------------------------------------------------------------------------

	// formato de MiSTer = el de Kyp: { -, -, -, fuego, arriba, abajo, izquierda, derecha }
	wire[7:0] joy1 = status[7] ? joystick_1[7:0] : joystick_0[7:0]; // Kempston y mando 1 del AY
	wire[7:0] joy2 = status[7] ? joystick_0[7:0] : joystick_1[7:0]; // mando 2 del AY

//--- keyboard ------------------------------------------------------------------------------------

	wire      strb;
	wire[7:0] code;

	ps2k ps2k(clock, ps2kCk, ps2kD, strb, code);

	wire[4:0] col;
	wire[7:0] row;
	wire play;
	wire stop;
	wire F5;
	wire F9;

	matrix matrix(clock, strb, code, row, col, play, stop, F5, F9);

//--- sd card (DivMMC sobre VHD) ------------------------------------------------------------------

	wire sdcCs;
	wire sdcCk;
	wire sdcMosi;
	wire sdcMiso;

	sd_card sd_card
	(
		.clk_sys     (clock          ),
		.reset       (~power         ),
		.sdhc        (1'b1           ),
		.img_mounted (img_mounted[0] ),
		.img_size    (img_size       ),
		.sd_lba      (sd_lba[0]      ),
		.sd_rd       (sd_rd[0]       ),
		.sd_wr       (sd_wr[0]       ),
		.sd_ack      (sd_ack[0]      ),
		.sd_buff_addr(sd_buff_addr[8:0]),
		.sd_buff_dout(sd_buff_dout   ),
		.sd_buff_din (sd_buff_din[0] ),
		.sd_buff_wr  (sd_buff_wr     ),
		.clk_spi     (clock          ),
		.ss          (sdcCs          ),
		.sck         (sdcCk          ),
		.mosi        (sdcMosi        ),
		.miso        (sdcMiso        )
	);

//--- tape ----------------------------------------------------------------------------------------

	// tzxplayer espera 56000 ciclos de ce por ms: en NTSC el reloj es 56.488 MHz, asi que se quitan
	// los ciclos sobrantes para que la cinta vaya a su velocidad (psd.v usa 56000 en los dos).
	reg [16:0] tapeAcc = 1'd0;
	reg        tapeCe = 1'b0;
	always @(posedge clock)
		if(!model) begin tapeCe <= 1'b1; tapeAcc <= 1'd0; end
		else if(tapeAcc+17'd488 >= 17'd56488) begin tapeCe <= 1'b0; tapeAcc <= tapeAcc+17'd488-17'd56488; end
		else begin tapeCe <= 1'b1; tapeAcc <= tapeAcc+17'd488; end

	wire tzxBusy;
	wire tapeWait;
	wire tzxTape;

	// Zona de la DDR3 para la cinta: 0x30000000 en la DE10-Nano (1 GB). En placas con menos memoria
	// (Chameleon96, 512 MB) hay que darla con macros en el .qsf, por ejemplo:
	//   set_global_assignment -name VERILOG_MACRO "TAPE_DDR_BASE=32'h1F000000"
	//   set_global_assignment -name VERILOG_MACRO "TAPE_DDR_SIZE=32'h00800000"
`ifdef TAPE_DDR_BASE
	localparam [31:0] TAPE_BASE = `TAPE_DDR_BASE;
`else
	localparam [31:0] TAPE_BASE = 32'h30000000;
`endif
`ifdef TAPE_DDR_SIZE
	localparam [31:0] TAPE_SIZE = `TAPE_DDR_SIZE;
`else
	localparam [31:0] TAPE_SIZE = 32'h08000000;
`endif

	tape_ddr #(.MS(56000), .BASE(TAPE_BASE), .SIZE(TAPE_SIZE)) tape_ddr
	(
		.clock           (clock           ),
		.ce              (tapeCe          ),
		.dl              (tzxIo           ),
		.dlA             (ioctl_addr      ),
		.dlD             (ioctl_dout      ),
		.dlW             (ioctl_wr && tzxIo),
		.dlWait          (tapeWait        ),
		.play            (!play || status[18]),
		.stop            (!stop || status[19]),
		.stop48          (1'b1            ),   // como tzx.v de Kyp: el bloque 0x2A para la cinta
		.busy            (tzxBusy         ),
		.tape            (tzxTape         ),
		.DDRAM_CLK       (DDRAM_CLK       ),
		.DDRAM_BUSY      (DDRAM_BUSY      ),
		.DDRAM_BURSTCNT  (DDRAM_BURSTCNT  ),
		.DDRAM_ADDR      (DDRAM_ADDR      ),
		.DDRAM_DOUT      (DDRAM_DOUT      ),
		.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
		.DDRAM_RD        (DDRAM_RD        ),
		.DDRAM_DIN       (DDRAM_DIN       ),
		.DDRAM_BE        (DDRAM_BE        ),
		.DDRAM_WE        (DDRAM_WE        )
	);

	assign ioctl_wait = tapeWait;

	// entrada de audio analogica (ADC de la placa I/O)
	wire tapeAdc;
	wire tapeAdcAct;

	ltc2308_tape ltc2308_tape
	(
		.reset   (1'b0      ),
		.clk     (CLK_50M   ),
		.ADC_BUS (ADC_BUS   ),
		.dout    (tapeAdc   ),
		.active  (tapeAdcAct),
		.adc_sync(          ),
		.adc_data(          )
	);

	reg tapeAdcS1 = 1'b0, tapeAdcS = 1'b0, tapeAdcActS1 = 1'b0, tapeAdcActS = 1'b0;
	always @(posedge clock) begin
		tapeAdcS1 <= tapeAdc;       tapeAdcS <= tapeAdcS1;
		tapeAdcActS1 <= tapeAdcAct; tapeAdcActS <= tapeAdcActS1;
	end

	wire ear = tzxBusy ? tzxTape : tapeAdcActS && !tapeAdcS;

//--- cartridge (DCK) -----------------------------------------------------------------------------

	wire       dckW;
	wire[ 7:0] dckBank;
	wire[15:0] dckA;
	wire[ 7:0] dckD;
	wire[ 7:0] dockRd;
	wire[ 7:0] dockWr;

	dck_loader dck_loader
	(
		.clock (clock    ),
		.dl    (dckIo    ),
		.dlW   (ioctl_wr ),
		.dlD   (ioctl_dout),
		.eject (status[2]),
		.w     (dckW     ),
		.bank  (dckBank  ),
		.a     (dckA     ),
		.d     (dckD     ),
		.dockRd(dockRd   ),
		.dockWr(dockWr   )
	);

	wire dckBusy = dckIo || dckW;           // la ultima escritura llega un ciclo despues

//--- memory --------------------------------------------------------------------------------------

	wire[13:0] va;
	wire[ 7:0] vd;

	wire[15:0] memA;
	wire[ 7:0] memD;
	wire[ 7:0] memQ;
	wire       memB;
	wire[ 7:0] memM;
	wire       memR;
	wire       memW;

	wire       mapped;
	wire       ramcs;
	wire[ 3:0] page;

	wire[2:0] chunk = memA[15:13];

	// HOME: ROM (con la imagen de Kyp) + RAM; el segundo puerto es el del video
	wire[15:0] homeA = romIo ? { 2'b00, ioctl_addr[13:0] } : dckBusy ? dckA : memA;
	wire[ 7:0] homeD = romIo ? ioctl_dout : dckBusy ? dckD : memD;
	wire       homeW = romIo ? romW && ioctl_addr[26:14] == 0
	                 : dckBusy ? dckW && dckBank == 8'd255
	                 : memW && chunk >= 2 && !memM[chunk];

	wire[7:0] homeQ;
	dprfm #(64, "rtl/ts2068/rom/tc2068-0.mif") home(clock, { 2'b01, va }, vd, clock, homeA, homeD, homeQ, homeW);

	// EXROM: tc2068-1, o los 8K que siguen a los 16K de HOME en un fichero de ROM de 24K
	wire[12:0] extdA = romIo ? ioctl_addr[12:0] : dckBusy ? dckA[12:0] : memA[12:0];
	wire[ 7:0] extdD = romIo ? ioctl_dout : dckD;
	wire       extdW = romIo ? romW && ioctl_addr[26:13] == 2 : dckW && dckBank == 8'd254 && dckA[15:13] == 0;

	wire[7:0] extdQ;
	ramm #(8, "rtl/ts2068/rom/tc2068-1.mif") extd(clock, extdA, extdD, extdQ, extdW);

	// DOCK: cartucho; los trozos de RAM del cartucho los puede escribir la CPU
	wire[15:0] dockA = dckBusy ? dckA : memA;
	wire[ 7:0] dockD = dckBusy ? dckD : memD;
	wire       dockW = dckBusy ? dckW && dckBank == 8'd0 : memW && memM[chunk] && !memB && dockWr[chunk];

	wire[7:0] dockQ;
	ram #(64) dock(clock, dockA, dockD, dockQ, dockW);

	// DivMMC
	wire[7:0] dromQ;
	romm #(8, "rtl/ts2068/rom/esxdos.mif") drom(clock, memA[12:0], dromQ);

	wire[7:0] dramQ;
	ram #(128) dram(clock, { page, memA[12:0] }, memD, dramQ, memW && memA[15:13] == 1 && mapped);

	// como psd.v, salvo que el DOCK usa los trozos que dice la cabecera del DCK
	wire[7:0] memB0 = dockRd[chunk] ? dockQ : 8'hFF;
	wire[7:0] memB1 = chunk == 0 ? extdQ : 8'hFF;

	assign memQ
		= memA[15:14] == 0 && mapped ? (ramcs ? dramQ : dromQ)
		: memM[chunk] ? (memB ? memB1 : memB0)
		: homeQ;

//--- ts ------------------------------------------------------------------------------------------

	wire divmmc = status[4];

	wire reset = power && F9 && !romIo && !dckBusy && !status[0] && !status[2] && !buttons[1] && !RESET && !cfgBusyS;
	wire rfsh;
	wire nmi = (F5 && !status[1]) || mapped;

	wire hsync;
	wire vsync;
	wire r;
	wire g;
	wire b;
	wire i;

	wire[14:0] left;
	wire[14:0] right;

	ts ts
	(
		.model  (model  ),
		.divmmc (divmmc ),
		.clock  (clock  ),
		.ne14M  (ne14M  ),
		.ne7M0  (ne7M0  ),
		.pe7M0  (pe7M0  ),
		.ne3M5  (ne3M5  ),
		.pe3M5  (pe3M5  ),
		.reset  (reset  ),
		.rfsh   (rfsh   ),
		.nmi    (nmi    ),
		.va     (va     ),
		.vd     (vd     ),
		.memA   (memA   ),
		.memD   (memD   ),
		.memQ   (memQ   ),
		.memB   (memB   ),
		.memM   (memM   ),
		.memR   (memR   ),
		.memW   (memW   ),
		.mapped (mapped ),
		.ramcs  (ramcs  ),
		.page   (page   ),
		.hsync  (hsync  ),
		.vsync  (vsync  ),
		.r      (r      ),
		.g      (g      ),
		.b      (b      ),
		.i      (i      ),
		.ear    (ear    ),
		.left   (left   ),
		.right  (right  ),
		.col    (col    ),
		.row    (row    ),
		.joy1   (joy1   ),
		.joy2   (joy2   ),
		.sdcCs  (sdcCs  ),
		.sdcCk  (sdcCk  ),
		.sdcMosi(sdcMosi),
		.sdcMiso(sdcMiso)
	);

//--- audio ---------------------------------------------------------------------------------------

	wire tapeSnd = status[6] && ear;

	assign AUDIO_S = 1'b0;
	assign AUDIO_L = { 1'b0,  left }+{ 4'd0, {12{ tapeSnd }} };
	assign AUDIO_R = { 1'b0, right }+{ 4'd0, {12{ tapeSnd }} };
	assign AUDIO_MIX = status[17:16];

//--- video ---------------------------------------------------------------------------------------

	// vdu.v no exporta el blanking (pone el color a 0), asi que se reconstruyen sus contadores a
	// 14 MHz (896 por linea, para el modo de 512 pixeles) a partir de los syncs:
	//   hsync empieza en hCount=335 (670 a 14 MHz) y hblank va de 320 a 416 (640-832)
	//   vsync empieza en la linea 248 (PAL) o 216 (NTSC) y vblank dura 8 lineas desde ahi
	wire[8:0] vEnd = model ? 9'd262 : 9'd312;
	wire[8:0] vBeg = model ? 9'd216 : 9'd248;

	reg [9:0] hc = 1'd0;
	reg [8:0] vc = 1'd0;
	reg       hsP = 1'b0;
	reg       vsP = 1'b0;

	always @(posedge clock) if(ne14M) begin
		hsP <= hsync;
		vsP <= vsync;

		if(hsync && !hsP) hc <= 10'd671;
		else if(hc >= 10'd895) hc <= 1'd0;
		else hc <= hc+1'd1;

		if(vsync && !vsP) vc <= vBeg;
		else if(hc >= 10'd895) begin
			if(vc >= vEnd-1'd1) vc <= 1'd0; else vc <= vc+1'd1;
		end
	end

	wire hblank = hc >= 640 && hc < 832;
	wire vblank = vc >= vBeg && vc < vBeg+4'd8;

	reg ce_pix = 1'b0;
	always @(posedge clock) ce_pix <= ne14M;

	reg [7:0] R, G, B;
	reg       hs, vs, hbl, vbl;

	always @(posedge clock) if(ne14M) begin
		hs  <= hsync;
		if(!hs && hsync) vs <= vsync;
		hbl <= hblank;
		vbl <= vblank;
		R   <= {4{ r, r&i }};
		G   <= {4{ g, g&i }};
		B   <= {4{ b, b&i }};
	end

	wire[2:0] scale = status[13:11];
	wire[1:0] ar = status[10:9];
	wire      vga_de;

	assign CLK_VIDEO = clock;
	assign VGA_SL = scale >= 2 ? scale[1:0]-1'd1 : 2'd0;

	video_freak video_freak
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.VGA_VS     (VGA_VS     ),
		.HDMI_WIDTH (HDMI_WIDTH ),
		.HDMI_HEIGHT(HDMI_HEIGHT),
		.VGA_DE     (VGA_DE     ),
		.VIDEO_ARX  (VIDEO_ARX  ),
		.VIDEO_ARY  (VIDEO_ARY  ),
		.VGA_DE_IN  (vga_de     ),
		.ARX        ((!ar) ? 12'd4 : (ar - 1'd1)),
		.ARY        ((!ar) ? 12'd3 : 12'd0),
		.CROP_SIZE  (12'd0      ),
		.CROP_OFF   (5'd0       ),
		.SCALE      ({ 1'b0, status[15:14] })
	);

	video_mixer #(.LINE_LENGTH(1024), .GAMMA(1)) video_mixer
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.ce_pix     (ce_pix     ),
		.scandoubler(scale || forced_scandoubler),
		.hq2x       (scale == 1 ),
		.gamma_bus  (gamma_bus  ),
		.R          (R          ),
		.G          (G          ),
		.B          (B          ),
		.HSync      (hs         ),
		.VSync      (vs         ),
		.HBlank     (hbl        ),
		.VBlank     (vbl        ),
		.HDMI_FREEZE(HDMI_FREEZE),
		.freeze_sync(           ),
		.VGA_R      (VGA_R      ),
		.VGA_G      (VGA_G      ),
		.VGA_B      (VGA_B      ),
		.VGA_VS     (VGA_VS     ),
		.VGA_HS     (VGA_HS     ),
		.VGA_DE     (vga_de     )
	);

//--- leds ----------------------------------------------------------------------------------------

	assign LED_USER = ioctl_download || tzxBusy;
	assign LED_DISK = { 1'b0, !sdcCs };

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
