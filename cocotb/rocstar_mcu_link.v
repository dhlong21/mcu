/*
 * rocstar_mcu_link.v
 * 
 * Logic to be run inside a rocstar board, to interface it with MCU;
 * to simplify simulation, Xilinx-specific details are omitted from
 * this module.
 * 
 * begun 2020-07-16 by wja and sz
 */

`timescale 1ns / 1ps
`default_nettype none

module rocstar_mcu_link
  (
   input  wire        clk,       // 100 MHz system-wide clock
   input  wire        rst,       // synchronous reset
   input  wire [3:0]  from_mcu,  // 4-bit datain (from MCU to ROCSTAR)
   output reg  [7:0]  to_mcu,    // 8-bit dataout (from ROCSTAR to MCU)
   input  wire [15:0] clk_ctr,   // low 16 bits of clock counter
   input  wire        single,    // single photon detected locally
   output reg  [15:0] spword,    // most recent "special word" from MCU
   output reg         runmode,   // are we in data-taking mode?
   output reg         sync_clk,  // pulse: reset clock counters to zero
   output reg         save_clk,  // pulse: save current clk ctr to register
   output reg         pcoinc,    // prompt coincidence confirmed by MCU
   output reg         dcoinc,    // delayed coincidence confirmed by MCU
   output reg         ncoinc     // no coincidence found by MCU
   );
    // Initialize registered outputs to avoid 'X' values in simulation at t=0
    initial begin
        spword <= 16'b0;
        runmode <= 1'b0;
        sync_clk <= 1'b0;
        save_clk <= 1'b0;
        pcoinc <= 1'b0;
        dcoinc <= 1'b0;
        ncoinc <= 1'b0;
    end
    // Mnemonic names for values sent by mcu (move to include file)
    localparam K_IDLE0 = 4'b0111;  // cycle through 4 IDLE words
    localparam K_IDLE1 = 4'b1011;
    localparam K_IDLE2 = 4'b1101;
    localparam K_IDLE3 = 4'b1110;
    localparam K_NCOIN = 4'b1001;  // no coincidence
    localparam K_PCOIN = 4'b0011;  // prompt coincidence
    localparam K_DCOIN = 4'b0110;  // delayed coincidence
    localparam K_SPECL = 4'b1100;  // begin "special word" sequence
    localparam SPWORD_SYNCH = 16'h1111;  // synchronize clock counters to 0
    localparam SPWORD_START = 16'h2222;  // start data taking
    localparam SPWORD_END   = 16'h3333;  // end data taking
    localparam SPWORD_SVCLK = 16'h4444;  // save current clk ctr to register
    // Observe incoming data words and report messages from MCU
    reg [15:0] spword_temp = 16'b0;
    reg [4:0] do_sp_shift = 5'b0;
    always @ (posedge clk) begin
        ncoinc <= runmode && (from_mcu == K_NCOIN);
        pcoinc <= runmode && (from_mcu == K_PCOIN);
        dcoinc <= runmode && (from_mcu == K_DCOIN);
        // If a K_SPECL word is seen, then a shift register
        // coordinates collecting next 4 words from MCU, to form the
        // 16-bit 'spword' payload.
        if (rst) begin
            do_sp_shift <= 5'b0;
            runmode <= 1'b0;
        end else if (from_mcu == K_SPECL && !do_sp_shift) begin
            do_sp_shift <= 5'b10000;
        end else begin
            do_sp_shift <= (do_sp_shift >> 1);
        end
        if (do_sp_shift[4]) spword_temp[15:12] <= from_mcu;
        if (do_sp_shift[3]) spword_temp[11:8]  <= from_mcu;
        if (do_sp_shift[2]) spword_temp[7:4]   <= from_mcu;
        if (do_sp_shift[1]) spword_temp[3:0]   <= from_mcu;
        if (do_sp_shift[0]) begin
            // We just finished receiving the full 'spword' contents
            spword <= spword_temp;  // capture spword payload
            if (spword_temp == SPWORD_START) runmode <= 1'b1;
            if (spword_temp == SPWORD_END)   runmode <= 1'b0;
            sync_clk <= (spword_temp == SPWORD_SYNCH);
            save_clk <= (spword_temp == SPWORD_SVCLK);
        end else begin
            sync_clk <= 1'b0;
            save_clk <= 1'b0;
        end
    end
    // Mnemonic names for Finite State Machine states
    localparam 
      START=0, IDLE1=1, IDLE2=2, IDLE3=3, SINGL=4;
    reg [3:0] fsm = START;  // flip-flop
    reg [3:0] fsm_prev = START;  // flip-flop: keep track of previous state
    reg [3:0] fsm_d = START;  // combinational logic
    reg [7:0] out_d;  // combinational logic
    reg [31:0] ticks = 0;  // useful to display time in units of 'clk'
    always @ (posedge clk) begin
        // Update 'fsm' FF from 'fsm_d' next-state value, except on reset
        if (rst) begin
            fsm <= START;
        end else begin
            fsm <= fsm_d;
        end
        // Update 'to_mcu' FF from 'out_d' next value
        to_mcu <= out_d;
        // Previous state on next clock is what 'fsm' is now
        fsm_prev <= fsm;
        // Increment 'ticks' counter
        ticks <= ticks + 1'd1;
    end
    // This COMBINATIONAL always block contains the next-state logic
    // and other state-dependent combinational logic.
    always @ (*) begin
        // Assign default values to avoid risk of implicit latches
        fsm_d = START;
        out_d = 4'b0000;
        if (0) $strobe("fsm_d=%1d fsm=%1d fsm_prev=%1d @%1d",
                       fsm_d, fsm, fsm_prev, ticks);
        case (fsm)
            START:
              begin
                  out_d = 8'b01000000;
                  out_d[5:4] = clk_ctr[3:2];
                  out_d[1:0] = clk_ctr[1:0];
                  fsm_d = IDLE1;
                  if (single) fsm_d = SINGL;
              end
            IDLE1:
              begin
                  out_d = 8'b01000100;
                  out_d[5:4] = clk_ctr[7:6];
                  out_d[1:0] = clk_ctr[5:4];
                  fsm_d = IDLE2;
                  if (single) fsm_d = SINGL;
              end
            IDLE2:
              begin
                  out_d = 8'b01001000;
                  out_d[5:4] = clk_ctr[11:10];
                  out_d[1:0] = clk_ctr[9:8];
                  fsm_d = IDLE3;
                  if (single) fsm_d = SINGL;
              end
            IDLE3:
              begin
                  out_d = 8'b01001100;
                  out_d[5:4] = clk_ctr[15:14];
                  out_d[1:0] = clk_ctr[13:12];
                  fsm_d = START;
                  if (single) fsm_d = SINGL;
              end
            SINGL:
              begin
                  out_d = 8'b10000000;  // bits 6:0 will be offset wrt clk
                  fsm_d = START;
                  if (single) fsm_d = SINGL;  // probably will never happen
              end
            default:
              begin
                  $strobe("INVALID STATE: fsm=%d fsm_prev=%d @%1d", 
                          fsm, fsm_prev, ticks);
                  fsm_d = START;
              end
        endcase
    end
endmodule  // rocstar_mcu_link

`default_nettype wire