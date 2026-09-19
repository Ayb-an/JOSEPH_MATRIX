/*
 * Copyright (c) 2024-2025 James Ross
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_glyph_mode(
	input  wire [7:0] ui_in,    // Dedicated inputs
	output wire [7:0] uo_out,   // Dedicated outputs
	input  wire [7:0] uio_in,   // IOs: Input path
	output wire [7:0] uio_out,  // IOs: Output path
	output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
	input  wire       ena,      // always 1 when the design is powered, so you can ignore it
	input  wire       clk,      // clock
	input  wire       rst_n     // reset_n - low to reset
);

	// VGA signals
	wire hsync, vsync, display_on;
	wire [10:0] hpos;
	wire [9:0] vpos;

	// TinyVGA PMOD
	assign uo_out = {hsync, RGB[0], RGB[2], RGB[4], vsync, RGB[1], RGB[3], RGB[5]};

	// Unused outputs assigned to 0.
	assign uio_out = 0;
	assign uio_oe  = 0;

	wire [7:0] xb = hpos[10:3];
	wire [6:0] x_mix = {xb[7] ^ xb[3], xb[1], xb[4], xb[1], xb[6], xb[0], xb[2]};
	wire [2:0] g_x = hpos[2:0];
	wire [5:0] yb;
	wire [3:0] _unused;
	assign {_unused, yb} = vpos / 10'd12;
	wire [5:0] g_unused;
	wire [3:0] g_y;
	assign {g_unused, g_y} = vpos - {yb, 3'b000} - {1'b0, yb, 2'b00};
	wire hl;

	// Suppress unused signals warning
	wire _unused_ok = &{ena, ui_in[5:2], uio_in};

	reg [9:0] frame;
	reg rst_drop;

	// VGA output
	hvsync_generator hvsync_gen(
		.clk(clk),
		.reset(~rst_n),
		.mode(ui_in[7:6]),
		.hsync(hsync),
		.vsync(vsync),
		.display_on(display_on),
		.hpos(hpos),
		.vpos(vpos)
	);

	// message: "SI DANE JOSEPH DIAZ AY BADING!!" (31 chars)
	// glyph ids from glyphs_rom: A=0 B=1 D=3 E=4 G=6 H=7 I=8 J=9 N=13 O=14 P=15
	//                            S=18 Y=24 Z=25 space=26 !=37
	function [5:0] msg_char(input [4:0] i);
		case (i)
			5'd0:  msg_char = 6'd18; // S
			5'd1:  msg_char = 6'd8;  // I
			5'd2:  msg_char = 6'd26; // _
			5'd3:  msg_char = 6'd3;  // D
			5'd4:  msg_char = 6'd0;  // A
			5'd5:  msg_char = 6'd13; // N
			5'd6:  msg_char = 6'd4;  // E
			5'd7:  msg_char = 6'd26; // _
			5'd8:  msg_char = 6'd9;  // J
			5'd9:  msg_char = 6'd14; // O
			5'd10: msg_char = 6'd18; // S
			5'd11: msg_char = 6'd4;  // E
			5'd12: msg_char = 6'd15; // P
			5'd13: msg_char = 6'd7;  // H
			5'd14: msg_char = 6'd26; // _
			5'd15: msg_char = 6'd3;  // D
			5'd16: msg_char = 6'd8;  // I
			5'd17: msg_char = 6'd0;  // A
			5'd18: msg_char = 6'd25; // Z
			5'd19: msg_char = 6'd26; // _
			5'd20: msg_char = 6'd0;  // A
			5'd21: msg_char = 6'd24; // Y
			5'd22: msg_char = 6'd26; // _
			5'd23: msg_char = 6'd1;  // B
			5'd24: msg_char = 6'd0;  // A
			5'd25: msg_char = 6'd3;  // D
			5'd26: msg_char = 6'd8;  // I
			5'd27: msg_char = 6'd13; // N
			5'd28: msg_char = 6'd6;  // G
			5'd29: msg_char = 6'd37; // !
			5'd30: msg_char = 6'd37; // !
			default: msg_char = 6'd26;
		endcase
	endfunction

	wire [7:0] msg_pos = xb % 8'd31;
	wire [5:0] glyph_index = msg_char(msg_pos[4:0]);

	// glyphs
	glyphs_rom glyphs(
		.c(glyph_index),
		.y(g_y),
		.x(g_x),
		.pixel(hl)
	);

	// palette
	wire [5:0] color;
	palette_rom palettes(
		.cid(y),
		.pid(ui_in[1:0]),
		.color(color)
	);

	wire [1:0] a = xb[1:0];
	wire [3:0] b = xb[5:2];
	wire [2:0] d = xb[3:2] + 2'd3;

	wire t = &{xb[0] ^ yb[2] ^ frame[7], xb[1] ^ yb[1] ^ frame[8], xb[2] ^ yb[3] ^ frame[9], xb[3] ^ yb[0]}; // toggle glyph

	// column features
	wire s = ^xb[6:0]; // speed of rain
	wire n = xb[1] ^ xb[3] ^ xb[5]; // lit on or off

	wire [6:0] v = (s ? frame[8:2] : frame[9:3]) - yb - x_mix;
	wire [3:0] c = {1'b0, a} + d;
	wire [6:0] e = {3'b000, b} << c;
	wire [6:0] f = v & e;
	wire [6:0] x = v >> a;
	wire [2:0] y = ~x[2:0];
	wire [9:0] drop = {1'b0, yb, 3'd0} >> s;
	wire drop_bit = ({3'd0, x_mix} + drop > frame) & ~rst_drop;
	wire [5:0] glyph_color = {6{drop_bit}} ^ color;

	wire [5:0] z = (&(~v[2:0]) & &(y)) ? 6'd63 : glyph_color;

	wire [5:0] RGB = (display_on & hl & ~(|f | n | drop_bit)) ? z : 6'd0;

		always @(posedge vsync, negedge rst_n) begin
		if (~rst_n) begin
			rst_drop <= 0;
			frame <= 0;
		end else begin
			if (&frame[9:1]) begin
				rst_drop <= 1;
			end
			frame <= frame + 10;
		end
	end

endmodule