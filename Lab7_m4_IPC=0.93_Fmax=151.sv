module cpu
(
	input 	clk,
	input 	reset,
	
	output 	[15:0] 	o_pc_addr,
	output 		o_pc_rd,
	input 	[15:0] 	i_pc_rddata,
	
	output 	[15:0] 	o_ldst_addr,
	output 		o_ldst_rd,
	output 		o_ldst_wr,
	input 	[15:0] 	i_ldst_rddata,
	output 	[15:0] 	o_ldst_wrdata,
	
	
	// reg
	output  	[7:0][15:0] o_tb_regs
);

	// reg list
	reg 	[15:0] 	pc;
	reg 	[15:0] 	lpc;				// reg to store last pc value for branch

	reg		N;
	reg		Z;
	
	reg		[15:0]	IR;
	
	reg 		[15:0]	rf[7:0];
	
	reg		delayed; 			// used to record a delay on branch/mem instr 
	reg		dummy_instr;		// used to ignore dummy instr preloaded after daleyed branch

	reg		pc_rdvalid;			// reg 1 cyc after o_pc_rd to show i_pc_rddata is valid\
	reg		[15:0]	st_addr;


	// wire list
	wire 	[15:0]	rf_Ox;
	wire 	[15:0]	rf_Oy;
	wire 	[15:0]	rf_wrdata;
	wire 	[2:0]	rf_selwr;
	wire 		rf_wr_en;
	
	
	wire 	[15:0]	IR_s_ext;
	wire	[2:0]	IR_Rx;
	wire	[2:0]	IR_Ry;
	wire	[7:0]	IR_imm8;
	wire	[10:0]	IR_imm11;
	wire		IR_wr_en;
	
	wire 		pc_wr_en;
	
	wire		mem_pc_rd;

	wire		NZ_wr_en;

	// ALUs
	wire 	[15:0]	ALUout;
	wire 	[15:0]	pc_ALUout;
	wire	[15:0]	br_ALUout;
	
	// branch
	wire 	[15:0]	pc_mem_s_ext;		// These wires are used 
	wire	[2:0]	pc_mem_Rx;			// to analyze i_pc_rddata
	wire	[10:0]	pc_mem_imm11;		// directly.	
	
	wire	[15:0]	br_Ox;
	wire	[15:0]	br_imm;
	
	// mem instr
	wire	[2:0]	pc_mem_Ry;			
	wire	[15:0]	pld_Oy;				// preload Ry
	wire		ldst_rd_en;
	
	// logics
	logic [15:0]	ALU_in1;
	logic [15:0]	ALU_in2;
	logic		ALU_op;
	
	logic 		pld_valid;
	logic		pld_br;
	logic		exe_br;
	


	always_ff @ (posedge clk) begin
		if (reset)begin
			pc 	<= 0;
			lpc   <= 0;
			rf[0]	<= 0;
			rf[1]	<= 0;
			rf[2]	<= 0;
			rf[3]	<= 0;
			rf[4]	<= 0;
			rf[5]	<= 0;
			rf[6]	<= 0;
			rf[7]	<= 0;
			N	<= 0;
			Z	<= 0;
			IR 	<= 0;
			
			delayed <= 0;
			pc_rdvalid <= 0;
			dummy_instr <= 0;
			st_addr <= 0;
		end
		else begin
			if (rf_wr_en) begin
				rf[rf_selwr] <= rf_wrdata;
			end
			
			if (mem_pc_rd) pc_rdvalid <= 1;
			
			if (rf_wr_en) rf[rf_selwr] <= rf_wrdata;
			
			if (pc_wr_en) begin
				pc <= pc_ALUout;
				lpc <= pc;
			end
			
			if (NZ_wr_en) begin
				N <= ALUout[15];
				Z <= ALUout == 0;
			end
			
			if (IR_wr_en) IR <= i_pc_rddata;
			
			if (i_pc_rddata[3] && (!pld_valid)) delayed <= 1'b1;
			else delayed <= 0;
			
			if (delayed && (exe_br || pld_br)) dummy_instr <= 1'b1;
			else dummy_instr <= 0;
			
			if (ldst_rd_en) st_addr <= pld_Oy; 
			
		end
		
	end
	
	always_comb begin
	
		// Execution ALU control
		ALU_in2 = rf_Oy;
		ALU_in1 = rf_Ox;
		ALU_op = 1'b1;
		
		case (IR[3:0])
		
			4'b0000 : begin
				ALU_in1 = 15'b0;
				ALU_op = 1'b0;
			end
			
			4'b0110 : begin
				ALU_in1 = {8'b0,rf_Ox[7:0]};
				ALU_op = 1'b0;
			end
			
			4'b0001 : ALU_op = 1'b0;
			
		endcase
		
		if (IR[3:0] == 4'b0110) ALU_in2 = {IR_imm8,8'b0};
		else if (IR[4] == 1'b1) ALU_in2 = IR_s_ext;
		
		
		// preload valid
		pld_valid = 1'b0;
		
		if (dummy_instr) pld_valid = 1'b1;
		else if (pc_rdvalid && i_pc_rddata[3]) pld_valid =  !((rf_wr_en && pc_mem_Rx == IR_Rx && (!i_pc_rddata[4])) || 
															(NZ_wr_en && (i_pc_rddata[0] || i_pc_rddata[1]))); 	// i_pc_rddata opcode = 1001/1010
																			
		
		// do branch
		exe_br = 1'b0;			// branch in execution stage
		pld_br = 1'b0;			// branch in fetch stage
	
		if (delayed) exe_br = 	(IR[3:0] == 4'b1001 && Z == 1'b1) ||  			// jz
					(IR[3:0] == 4'b1010 && N == 1'b1) ||  			// jn
					(IR[3:0] == 4'b1000) || 				// j
					(IR[3:0] == 4'b1100);
												
	   if (pld_valid) pld_br = 	(pc_rdvalid) && (i_pc_rddata[3:0] == 4'b1001 && Z == 1'b1) ||  	// jz
					(i_pc_rddata[3:0] == 4'b1010 && N == 1'b1) ||  			// jn
					(i_pc_rddata[3:0] == 4'b1000) || 				// j
					(i_pc_rddata[3:0] == 4'b1100);
										

		
	end


	// *****************************************	
	// 		ALU blocks
	// *****************************************	
	
	// Execution ALU
	assign ALUout = (ALU_op) ? ALU_in1 - ALU_in2 : ALU_in1 + ALU_in2;

	// PC ALU
	assign pc_ALUout = (exe_br || pld_br) ? br_ALUout + 2 : pc + 2;
	
	// BR ALU
	assign br_ALUout = (exe_br && IR[4]) ? br_imm : (pld_br && i_pc_rddata[4] && !exe_br) ? br_imm : br_Ox;

	
	// *****************************************
	// 		Wire Assignment
	// *****************************************
	
	// mem wires
	assign mem_pc_rd = !reset;
	
	// IR wires
	assign IR_Rx = IR[7:5];
	assign IR_Ry = IR[10:8];
																	
	assign IR_s_ext = (IR[3]) ? {{5{IR_imm11[10]}},IR_imm11} : {{8{IR_imm8[7]}},IR_imm8};
	assign IR_imm8 = IR[15:8];
	assign IR_imm11 = IR[15:5];
	
	assign IR_wr_en = pc_rdvalid;


	// rf wires
	assign rf_Ox = rf[IR_Rx];
	assign rf_Oy = rf[IR_Ry];
	assign rf_selwr = (IR[3:2] == 2'b11) ? 3'b111 : IR_Rx;
	assign rf_wrdata = (IR[3:2] == 2'b11) ? lpc :		// lpc = rlpc + 2.
							 (IR[2:1] == 2'b10) ? i_ldst_rddata :
														 ALUout; 		
	assign rf_wr_en = ((!IR[3]) || (IR[3:0] == 4'b1100)) && (!(IR[3:0] == 4'b0101 || IR[3:0] == 4'b0011)) && (!dummy_instr);
	
	// pc wires
	assign pc_wr_en = mem_pc_rd;
	
	// NZ wires
	assign NZ_wr_en = (IR[3:2] == 2'b00 && (IR[0] || IR[1]) && (!dummy_instr)); // (IR[3:0] == 4'b0010 || IR[3:0] == 4'b0001 || IR[3:0] == 4'b0011);

	
	// *****************************************	
	// 		Branch Blocks
	// *****************************************	
	
	// branch
	assign pc_mem_s_ext = {{5{pc_mem_imm11[10]}},pc_mem_imm11};
	assign pc_mem_Rx = i_pc_rddata[7:5];
	assign pc_mem_imm11 = i_pc_rddata[15:5];
	
	assign br_Ox = (exe_br) ? rf_Ox : rf[pc_mem_Rx];	
	assign br_imm = (exe_br) ? lpc + IR_s_ext + IR_s_ext : pc + pc_mem_s_ext + pc_mem_s_ext;
	
	
	// *****************************************	
	// 		mem instr blocks
	// *****************************************	
	assign pc_mem_Ry = i_pc_rddata[10:8];
	assign pld_Oy = (rf_wr_en && (pc_mem_Ry == IR_Rx || pc_mem_Ry == IR_Ry)) ? rf_wrdata : rf[pc_mem_Ry];	// if rf_wr_en and Rx is same, we need to read directly from rf_wrdata
	assign ldst_rd_en = (i_pc_rddata[3:0] == 4'b0100) || (i_pc_rddata[3:0] == 4'b0101);
	
	
	
	// *****************************************	
	// 		I/O wires
	// *****************************************	
	assign o_tb_regs[0] = rf[0];
	assign o_tb_regs[1] = rf[1];
	assign o_tb_regs[2] = rf[2];
	assign o_tb_regs[3] = rf[3];
	assign o_tb_regs[4] = rf[4];
	assign o_tb_regs[5] = rf[5];
	assign o_tb_regs[6] = rf[6];
	assign o_tb_regs[7] = rf[7];
	
	assign o_pc_addr = (exe_br || pld_br) ? br_ALUout : pc;
	assign o_pc_rd = mem_pc_rd;
	
	assign o_ldst_addr = (IR[3:0] == 4'b0101) ? st_addr : pld_Oy; 	
	assign o_ldst_rd = ldst_rd_en;		
	assign o_ldst_wr = IR[3:0] == 4'b0101;	
	assign o_ldst_wrdata = rf_Ox;	

endmodule

