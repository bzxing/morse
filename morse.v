module morse_multiple(
	clk,
	resetn,
	letter,
	start,
	light
);
	parameter num_instances = 1;
	input clk, resetn;
    input [2:0] letter;
    input start;
    output light;
    
	wire [num_instances-1:0] start_internal;
	wire [num_instances:0] light_internal;

    assign light_internal[num_instances] = start;
    assign light = light_internal[0];
	genvar i;
	generate
		for (i=0; i<num_instances; i=i+1) begin:gen_loop
			assign start_internal[i] = light_internal[i+1];
            morse morse_inst (
				.clk(clk),
				.resetn(resetn),
				.letter(letter[2:0]),
				.start(start_internal[i]),
				.light(light_internal[i])
			);
		end
	endgenerate
endmodule

module morse(
	clk,
	resetn,
	letter,
	start,
	light
   // , current_state
);
	input clk, resetn;
	input [2:0] letter;
	input start;
	output light;
	// output[2:0]current_state;
	
	wire time_is_up, end_of_sequence;
	wire sequence_load, sequence_shift, length_enable, timer_clear, symbol_counter_clear, symbol_counter_enable, pausing;
	
	
	control control_inst (
		.clk(clk), 
		.resetn(resetn),
		.start(start),
		.time_is_up(time_is_up),
		.end_of_sequence(end_of_sequence),
		.light(light),
		.sequence_load(sequence_load), 
		.sequence_shift(sequence_shift),
		.length_enable(length_enable),
		.timer_clear(timer_clear),
		.symbol_counter_clear(symbol_counter_clear),
		.symbol_counter_enable(symbol_counter_enable),
		.pausing(pausing)
		// , .current_state(current_state)
	);
	
	datapath datapath_inst (
		.clk(clk), 
		.resetn(resetn),
		.letter(letter),
		.sequence_load(sequence_load), 
		.sequence_shift(sequence_shift),
		.length_enable(length_enable),
		.timer_clear(timer_clear),
		.symbol_counter_clear(symbol_counter_clear),
		.symbol_counter_enable(symbol_counter_enable),
		.pausing(pausing),
		.time_is_up(time_is_up),
		.end_of_sequence(end_of_sequence)
	);	
endmodule

module control(
	clk, 
	resetn,
	start,
	time_is_up,
	end_of_sequence,
	light,
	sequence_load, 
	sequence_shift,
	length_enable,
	timer_clear,
	symbol_counter_clear,
	symbol_counter_enable,
	pausing
	//, current_state
);
	parameter s0=3'd0, s1=3'd1, s2=3'd2, s3=3'd3, s4=3'd4, s5=3'd5;
	
	input clk, resetn;
	input start;
	input time_is_up, end_of_sequence;
	output light;
	output sequence_load, sequence_shift;
	output length_enable;
	output timer_clear;
	output symbol_counter_clear;
	output symbol_counter_enable;
	output pausing;
	// output [2:0]current_state;
		
	reg [2:0] current_state, next_state;
	
	always@(*) begin
		case (current_state)
		s0:	if (start) next_state = s1; 
			else next_state = s0;
		s1:	if (time_is_up) next_state = s4; 
			else next_state = s1;
		s2:	if (end_of_sequence) next_state = s3;
			else next_state = s1;
		s3:	if (start) next_state = s3;
			else next_state = s0;
		s4: next_state = s5;
		s5:	if (time_is_up) next_state = s2; 
			else next_state = s5;
		default: next_state = 3'bx;
		endcase
	end
	
	always@(posedge clk or negedge resetn) begin
		if (!resetn) current_state <= s3;
		else current_state <= next_state;
	end
	
	assign light = (current_state == s1);
	assign sequence_load = (current_state == s0);
	assign sequence_shift = (current_state == s2);
	assign length_enable = (current_state == s0);
	assign timer_clear = (current_state == s0 || current_state == s2 || current_state == s4);
	assign symbol_counter_clear = (current_state == s0);
	assign symbol_counter_enable = (current_state == s2);
	assign pausing = (current_state == s5);
	
endmodule

module datapath(
	clk, 
	resetn,
	letter,
	sequence_load, 
	sequence_shift,
	length_enable,
	timer_clear,
	symbol_counter_clear,
	symbol_counter_enable,
	pausing,
	time_is_up,
	end_of_sequence
);
	parameter count_500ms = 27'd25000000;
	parameter count_1500ms = 27'd75000000;
	
	input clk, resetn;
	input [2:0] letter;
	input sequence_load, sequence_shift;
	input length_enable;
	input timer_clear;
	input symbol_counter_clear;
	input symbol_counter_enable;
	input pausing;
	output time_is_up;
	output end_of_sequence;
	
	wire [3:0] sequence_decoded;
	wire [1:0] length_decoded, length_q;
	wire current_symbol_is_dash;
	wire [1:0] symbol_counter_q;
	wire [26:0] timer_q;
	
	assign time_is_up = (pausing ? (count_500ms == timer_q) : (timer_q == (current_symbol_is_dash ? count_1500ms : count_500ms) ));
	assign end_of_sequence = (symbol_counter_q == length_q);
	
	letter_decoder letter_decoder_inst(
		.letter(letter),
		.my_sequence(sequence_decoded),
		.length(length_decoded)
	);
	
	shift_reg #(
		.width(4)
	) sequence_shift_reg (
		.clk(clk),
		.resetn(resetn),
		.shift(sequence_shift),
		.load(sequence_load),
		.load_data(sequence_decoded),
		.q(current_symbol_is_dash)
	);
	
	register #(
		.width(2)
	) length_reg (
		.clk(clk),
		.resetn(resetn),
		.enable(length_enable),
		.d(length_decoded),
		.q(length_q)
	);
	
	counter #(
		.width(27)
	) timer (
		.clk(clk),
		.resetn(resetn),
		.clear(timer_clear),
		.enable(~time_is_up),
		.q(timer_q)
	);
	
	counter #(
		.width(2)
	) symbol_counter (
		.clk(clk),
		.resetn(resetn),
		.clear(symbol_counter_clear),
		.enable(symbol_counter_enable),
		.q(symbol_counter_q)
	);
	
endmodule

module letter_decoder(
	letter,
	my_sequence,
	length
);
	input [2:0] letter;
	output reg [3:0] my_sequence;
	output reg [1:0] length;
	
	always@(*) begin
		case(letter)
		3'd0:	begin
				my_sequence = 4'bxx10;
				length = 2'd1;
				end
		3'd1:	begin
				my_sequence = 4'b0001;
				length = 2'd3;
				end
		3'd2:	begin
				my_sequence = 4'b0101;
				length = 2'd3;
				end
		3'd3:	begin
				my_sequence = 4'bx001;
				length = 2'd2;
				end
		3'd4:	begin
				my_sequence = 4'bxxx0;
				length = 2'd0;
				end
		3'd5:	begin
				my_sequence = 4'b0100;
				length = 2'd3;
				end
		3'd6:	begin
				my_sequence = 4'bx111;
				length = 2'd2;
				end
		3'd7:	begin
				my_sequence = 4'b1111;
				length = 2'd3;
				end
		endcase
	end
endmodule

module register(
	clk,
	resetn,
	enable,
	d,
	q
);
	parameter width = 4;
	
	input clk, resetn;
	input enable;
	input [width-1:0] d;
	output reg [width-1:0] q;
	
	always@(posedge clk or negedge resetn) begin
		if (!resetn) q <= 0;
		else if (enable) q <= d;
		else q <= q;
	end
endmodule

module shift_reg(
	clk,
	resetn,
	shift,
	load,
	load_data,
	q
);
	parameter width = 4;
	
	input clk, resetn;
	input shift, load;
	input [width-1:0] load_data;
	output q;
	
	reg [width-1:0] q_parallel;
	
	assign q = q_parallel[0];
	
	always@(posedge clk or negedge resetn) begin
		if (!resetn) q_parallel <= 0;
		else if (load) q_parallel <= load_data;
		else if (shift) q_parallel <= {1'b0, q_parallel[width-1:1]};
		else q_parallel <= q_parallel;
	end
endmodule


module counter(
	clk,
	resetn,
	clear,
	enable,
	q
);
	parameter width = 4;
	
	input clk, resetn;
	input clear, enable;
	output reg [width-1:0] q;
	
	always@(posedge clk or negedge resetn) begin
		if (!resetn) q <= 0;
		else if (clear) q <= 0;
		else if (enable) q <= q + 1'b1;
		else q <= q;
	end
endmodule
