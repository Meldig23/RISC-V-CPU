\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
   
   // #################################################################
   // #                                                               #
   // #  Starting-Point Code for MEST Course Tiny Tapeout RISC-V CPU  #
   // #                                                               #
   // #################################################################
   
   // ========
   // Settings
   // ========
   
   //-------------------------------------------------------
   // Build Target Configuration
   //
   var(my_design, tt_um_example)   /// The name of your top-level TT module, to match your info.yml.
   var(target, ASIC)   /// Note, the FPGA CI flow will set this to FPGA.
   //-------------------------------------------------------
   
   var(in_fpga, 1)   /// 1 to include the demo board. (Note: Logic will be under /fpga_pins/fpga.)
   var(debounce_inputs, 0)         /// 1: Provide synchronization and debouncing on all input signals.
                                   /// 0: Don't provide synchronization and debouncing.
                                   /// m5_if_defined_as(MAKERCHIP, 1, 0, 1): Debounce unless in Makerchip.

   // CPU configs
   var(num_regs, 16)  /// 32 for full reg file.
   var(dmem_size, 8)  /// Size of DMem, a power of 2.
   
   
   // ======================
   // Computed From Settings
   // ======================
   
   // If debouncing, a user's module is within a wrapper, so it has a different name.
   var(user_module_name, m5_if(m5_debounce_inputs, my_design, m5_my_design))
   var(debounce_cnt, m5_if_defined_as(MAKERCHIP, 1, 8'h03, 8'hff))
   
   
   // ==================
   // Sum 1 to 9 Program
   // ==================
   
   TLV_fn(riscv_sum_prog, {
      ~assemble(['
         # Add 1,2,3,...,9 (in that order).
         #
         # Regs:
         #  x10 (a0): In: 0, Out: final sum
         #  x12 (a2): 10
         #  x13 (a3): 1..10
         #  x14 (a4): Sum
         #
         # External to function:
         reset:
            ADD x10, x0, x0             # Initialize r10 (a0) to 0.
         # Function:
            ADD x14, x10, x0            # Initialize sum register a4 with 0x0
            ADDI x12, x10, 10            # Store count of 10 in register a2.
            ADD x13, x10, x0            # Initialize intermediate sum register a3 with 0
         loop:
            ADD x14, x13, x14           # Incremental addition
            ADDI x13, x13, 1            # Increment count register by 1
            BLT x13,x12,loop          # If a3 is less than a2, branch to label named <loop>
         done:
            ADD x10, x14, x0            # Store final result to register a0 so that it can be read by main program
            SW x10, 4(x0)
            LW x15, 4(x0)
            JALR x11, 2(x2)           

      '])
   })
   
\SV
   // Include Tiny Tapeout Lab.
   m4_include_lib(['https:/']['/raw.githubusercontent.com/os-fpga/Virtual-FPGA-Lab/5744600215af09224b7235479be84c30c6e50cb7/tlv_lib/tiny_tapeout_lib.tlv'])  
   m4_include_lib(['https://raw.githubusercontent.com/efabless/chipcraft---mest-course/main/tlv_lib/risc-v_shell_lib.tlv'])


\TLV cpu()
   
   m5+riscv_gen()
   m5+riscv_sum_prog()
   m5_define_hier(IMEM, m5_NUM_INSTRS)
   |cpu
      
      
      // For program Counter
      @0
         $reset = *reset;
         $pc[31:0] = >>1$reset 
                        ? 32'd0 
                     :>>3$valid_taken_br || (>>3$valid_jal)
                        ?>>3$br_tgt_pc[31:0] 
                     : >>3$valid_jalr
                        ?>>3$jalr_tgt_pc
                     :>>3$valid_load 
                        ?>>3$inc_pc
                     //default
                        : >>1$inc_pc;
              
      @1
         $inc_pc[31:0] = $pc[31:0] + 32'd4;
         
      // For fetching from memory   
      @0
         $imem_rd_addr[m5_IMEM_INDEX_CNT-1:0] = $pc[m5_IMEM_INDEX_CNT+1:2];
         $imem_rd_en = !$reset;
      @1
         $instr[31:0] = $imem_rd_data[31:0];
         // Get type
         $is_i_instr = $instr[6:3] == 4'b0000 ||
                       $instr[6:2] == 5'b00100 ||
                       $instr[6:2] == 5'b00110 ||
                       $instr[6:2] == 5'b11001 ;
         $is_u_instr = ($instr[4:2] == 3'b101 && $instr[6] == 0) ;
                       
         $is_s_instr = $instr[6:3] == 4'b0100 ;
         
         $is_r_instr = $instr[6:2] == 5'b01011 ||
                       $instr[6:2] == 5'b01100 ||
                       $instr[6:2] == 5'b10110 ||
                       $instr[6:2] == 5'b10100 ;
         
         $is_b_instr = $instr[6:2] == 5'b11000 ;
         
         $is_j_instr = $instr[6:2] == 5'b11011 ;         
         
         
         // Get immediate value
         $imm[31:0] = $is_i_instr ? { {21{$instr[31]}}, $instr[30:20] } :
                      $is_s_instr ? { {21{$instr[31]}}, $instr[30:25], $instr[11:7] } :
                      $is_b_instr ? { {20{$instr[31]}}, $instr[7], $instr[30:25], $instr[11:8], 1'b0 } :
                      $is_u_instr ? { $instr[31:12], 12'b000  } :
                      $is_j_instr ? { {12{$instr[31]}}, $instr[19:12], $instr[20], $instr[30:21], 1'b0 } :
                      32'b0 ; 
         
         // Instruction Field decode rs1,rs2.. with validity
         $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
         $rs1_valid = $is_r_instr || $is_s_instr || $is_b_instr || $is_i_instr ;
         $rd_valid = $is_r_instr || $is_i_instr || $is_u_instr || $is_j_instr;
         $funct3_valid = $rs1_valid;
         
         
         ?$rs2_valid
            $rs2[4:0] = $instr[24:20];
         ?$rs1_valid   
            $rs1[4:0] = $instr[19:15];
         ?$rd_valid
            $rd[4:0] = $instr[11:7];
         ?$funct3_valid   
            $funct3[2:0] = $instr[14:12];
         $opcode[6:0] = $instr[6:0] ;
         
         
         // Decode
         $dec_bits[10:0] = {$instr[30], $funct3, $opcode};
         
         $is_lui = $dec_bits[6:0] == 7'b0110111 ;
         $is_auipc = $dec_bits[6:0] == 7'b0010111 ;
         
         $is_jal = $dec_bits[6:0] == 'b1101111 ;
         $is_jalr = $dec_bits[9:0] == 10'b000_1100111 ;         
         
         $is_beq = $dec_bits[9:0] == 10'b000_1100011;
         $is_bne = $dec_bits[9:0] == 10'b001_1100011;
         $is_blt = $dec_bits[9:0] == 10'b100_1100011;
         $is_bge = $dec_bits[9:0] == 10'b101_1100011;
         $is_bltu = $dec_bits[9:0] == 10'b110_1100011;
         $is_bgeu = $dec_bits[9:0] == 10'b111_1100011;
         
         $is_load = $dec_bits[6:0] == 7'b0000011 ;
         
         $is_addi = $dec_bits[9:0] == 10'b000_0010011;
         $is_slti = $dec_bits[9:0] == 10'b010_0010011;
         $is_sltiu = $dec_bits[9:0] == 10'b011_0010011;
         $is_xori = $dec_bits[9:0] == 10'b100_0010011;
         $is_ori = $dec_bits[9:0] == 10'b110_0010011;
         $is_andi = $dec_bits[9:0] == 10'b111_0010011;
         $is_slli = $dec_bits[10:0] == 11'b0001_0010011;
         $is_srli = $dec_bits[10:0] == 11'b0101_0010011;
         $is_srai = $dec_bits[10:0] == 11'b1101_0010011;
         
         
         $is_add = $dec_bits[10:0] == 11'b0000_0110011;
         $is_sub = $dec_bits[10:0] == 11'b1000_0110011;
         $is_sll = $dec_bits[10:0] == 11'b0001_0110011;
         $is_slt = $dec_bits[10:0] == 11'b0010_0110011;
         $is_sltu = $dec_bits[10:0] == 11'b0011_0110011;
         $is_xor = $dec_bits[10:0] == 11'b0100_0110011;
         $is_srl = $dec_bits[10:0] == 11'b0101_0110011;
         $is_sra = $dec_bits[10:0] == 11'b1101_0110011;
         $is_or = $dec_bits[10:0] == 11'b0110_0110011;
         $is_and = $dec_bits[10:0] == 11'b0111_0110011;
         
         
      // Register file(rf) read
      @2   
         
         $rf_rd_en1 = $rs1_valid;
         $rf_rd_index1[4:0] = $rs1[4:0];
         $rf_rd_en2 = $rs2_valid;
         $rf_rd_index2[4:0] = $rs2[4:0];
         
         $src1_value[31:0] = >>1$rd == $rs1 && >>1$rf_wr_en 
                             ? >>1$result[31:0] 
                             //default
                             : $rf_rd_data1[31:0];
         
         $src2_value[31:0] = >>1$rd == $rs2 && >>1$rf_wr_en 
                             ? >>1$result[31:0] 
                             //default
                             : $rf_rd_data2[31:0];
      // Branch 
      @2
         $br_tgt_pc[31:0] = $pc + $imm ; 
      @3   
         
         $taken_br = $is_beq ? $src1_value[31:0] == $src2_value[31:0] :
                     $is_bne ? $src1_value[31:0] != $src2_value[31:0] :
                     $is_blt ? ($src1_value[31:0] < $src2_value[31:0] ) ^ ($src1_value[31] != $src2_value[31]) :
                     $is_bge ? ($src1_value[31:0] >= $src2_value[31:0] ) ^ ($src1_value[31] != $src2_value[31]) :
                     $is_bltu ? $src1_value[31:0] < $src2_value[31:0] : 
                     $is_bgeu ? $src1_value[31:0] >= $src2_value[31:0]  
                     //default
                              : 1'b0 ;
         
         $valid_taken_br = $valid && $taken_br ;
         $valid_jal = $valid && $is_jal;
         $valid_jalr = $valid && $is_jalr;
         $valid_jump = $valid_jal || $valid_jalr ;
         
         $valid_load = $valid && $is_load;
         
         $jalr_tgt_pc[31:0] = $src1_value + $imm ;
         
      //Valid Set up
      @3
         $valid = !($reset || >>1$valid_taken_br || >>2$valid_taken_br || >>1$valid_load || >>2$valid_load || >>1$valid_jump || >>2$valid_jump) ;   
      
      //ALU
      @3
         /* verilator lint_off WIDTH */
         $result[31:0] = $is_sub ? $src1_value - $src2_value :
                         $is_add ? $src1_value + $src2_value :
                         ($is_addi || $is_load || $is_s_instr) ? $src1_value + $imm :
                         
                         $is_sll ? $src1_value << $src2_value[4:0] :
                         $is_slli ? $src1_value << $imm[5:0] :
                         $is_srl ? $src1_value >> $src2_value[4:0] :
                         $is_srli ? $src1_value >> $imm[5:0] :
                         
                         $is_and ? $src1_value & $src2_value :
                         $is_andi ? $src1_value & $imm :
                         $is_or ? $src1_value | $src2_value :
                         $is_ori ? $src1_value | $imm :
                         $is_xor ? $src1_value ^ $src2_value :
                         $is_xori ? $src1_value ^ $imm :
                         
                         $is_sltu ? $src1_value < $src2_value :
                         $is_sltiu ? $src1_value < $imm :
                         
                         $is_slt?  
                            (($src1_value[31] == $src2_value[31]) 
                               ? $src1_value < $src2_value  
                            //default
                               : {31'b0, $src1_value[31]} ) :
                         $is_slti? 
                            (($src1_value[31] == $imm[31])        
                               ? $src1_value < $imm 
                            //default
                               : {31'b0, $src1_value[31]}) :
                               
                         $is_sra ? 
                            {{32{$src1_value[31]}}, $src1_value} >> $src2_value[4:0] :
                         $is_srai ?  
                            {{32{$src1_value[31]}}, $src1_value} >> $imm[4:0] :
                           
                         $is_lui     ?  {$imm[31:12], 12'b0} :
                         $is_auipc   ?  $pc + $imm :
                         $is_jal     ?  $pc + 32'd4 :
                         $is_jalr    ?  $pc + 32'd4 
                         //default
                                  : 32'bx ;
                         
         /* verilator lint_on WIDTH */
      // Register File Write
      @3   
         $rf_wr_en = >>2$valid_load ? 1'b1 : $valid && $rd[4:0] != 5'b0 && $rd_valid && !$valid_load ;
         $rf_wr_index[4:0] = >>2$valid_load ? >>2$rd[4:0] : $rd[4:0];
         $rf_wr_data[31:0] = >>2$valid_load ? >>2$ld_data[31:0] : $result[31:0] ;
         
         
         
         // Getting value from memory (read) (Load)
         $dmem_rd_en = $valid_load ;
         $dmem_addr[2:0] = $result[4:2] ;
         
         // Writing to mem (store)
         $dmem_wr_en =  $valid && $is_s_instr;
         $dmem_wr_data[31:0] = $src2_value[31:0];
      @4
         $ld_data[31:0] = $dmem_rd_data[31:0] ;
         
         
         *passed = |cpu/xreg[15]>>10$value == (1+2+3+4+5+6+7+8+9);
         
      // Note that pipesignals assigned here can be found under /fpga_pins/fpga.
      
      
      
      
      
   
   // Assert these to end simulation (before Makerchip cycle limit).
   // Note, for Makerchip simulation these are passed in uo_out to top-level module's passed/failed signals.
   
   *failed = 1'b0;
   
   // Connect Tiny Tapeout outputs. Note that uio_ outputs are not available in the Tiny-Tapeout-3-based FPGA boards.
   *uo_out = {6'b0, *failed, *passed};
   m5_if_neq(m5_target, FPGA, ['*uio_out = 8'b0;'])
   m5_if_neq(m5_target, FPGA, ['*uio_oe = 8'b0;'])
   
   // Macro instantiations to be uncommented when instructed for:
   //  o instruction memory
   //  o register file
   //  o data memory
   //  o CPU visualization
   |cpu
      m5+imem(@1)    // Args: (read stage) Memory from which opcode is fetched
      m5+rf(@2, @3)  // Args: (read stage, write stage) - if equal, no register bypass is required
      m5+dmem(@4)    // Args: (read/write stage)

   m5+cpu_viz(@4)    // For visualization, argument should be at least equal to the last stage of CPU logic. @4 would work for all labs.

\SV

// ================================================
// A simple Makerchip Verilog test bench driving random stimulus.
// Modify the module contents to your needs.
// ================================================

module top(input logic clk, input logic reset, input logic [31:0] cyc_cnt, output logic passed, output logic failed);
   // Tiny tapeout I/O signals.
   logic [7:0] ui_in, uo_out;
   m5_if_neq(m5_target, FPGA, ['logic [7:0] uio_in, uio_out, uio_oe;'])
   assign ui_in = 8'b0;
   m5_if_neq(m5_target, FPGA, ['assign uio_in = 8'b0;'])
   logic ena = 1'b0;
   logic rst_n = ! reset;
   
   // Instantiate the Tiny Tapeout module.
   m5_user_module_name tt(.*);
   
   // Passed/failed to control Makerchip simulation, passed from Tiny Tapeout module's uo_out pins.
   assign passed = uo_out[0];
   assign failed = uo_out[1];
endmodule


// Provide a wrapper module to debounce input signals if requested.
m5_if(m5_debounce_inputs, ['m5_tt_top(m5_my_design)'])
\SV



// =======================
// The Tiny Tapeout module
// =======================

module m5_user_module_name (
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    m5_if_eq(m5_target, FPGA, ['/']['*'])   // The FPGA is based on TinyTapeout 3 which has no bidirectional I/Os (vs. TT6 for the ASIC).
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    m5_if_eq(m5_target, FPGA, ['*']['/'])
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
   logic passed, failed;  // Connected to uo_out[0] and uo_out[1] respectively, which connect to Makerchip passed/failed.

   wire reset = ! rst_n;
   
\TLV tt_lab()
   // Connect Tiny Tapeout I/Os to Virtual FPGA Lab.
   m5+tt_connections()
   // Instantiate the Virtual FPGA Lab.
   m5+board(/top, /fpga, 7, $, , cpu)
   // Label the switch inputs [0..7] (1..8 on the physical switch panel) (top-to-bottom).
   m5+tt_input_labels_viz(['"UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED"'])

\TLV
   /* verilator lint_off UNOPTFLAT */
   m5_if(m5_in_fpga, ['m5+tt_lab()'], ['m5+cpu()'])

\SV
endmodule
