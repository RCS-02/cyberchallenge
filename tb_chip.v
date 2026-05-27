`timescale 1ns/1ps

module tb_chip;
    reg clk;
    reg rst_n;
    reg cs_n;
    reg mosi;
    reg start;
    reg enc_dec;
    
    wire miso;
    wire busy;
    wire led;
    wire secondary_out;

    reg [31:0] captured_output;
    reg [31:0] dummy;

    // Connect to the top-level chip module
    chip uut (
        .io_9_31_1(clk),           // SCK Clock
        .io_19_31_1(mosi),         // MOSI Data
        .io_17_31_0(rst_n),        // RST_N Reset
        .io_18_31_1(cs_n),         // NORM_CS_N Chip Select
        .io_16_31_0(start),        // START Control
        .io_13_31_1(enc_dec),      // ENC_DEC Control
        .io_8_31_1(miso),          // MISO Data
        .io_19_31_0(secondary_out),
        .io_16_31_1(led)
    );

    // Free-running background clock (1 MHz)
    always #500 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 1;
        cs_n = 1;
        mosi = 0;
        start = 0;
        enc_dec = 0;

        // Synchronous hardware reset (toggling clock while reset is low)
        #1000;
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ====================================================================
        // PHASE 0: MICROPYTHON SPI LOOPBACK PROOF
        // Proves the SPI interface and testbench timing are flawless.
        // ====================================================================
        $display("\n=======================================================");
        $display(" PHASE 0: SPI LOOPBACK HARDWARE TEST");
        $display("=======================================================");
        
        // Shift data in
        spi_transfer(32'h59C359C3, dummy);
        
        // Read data back out (while shifting in zeros)
        spi_transfer(32'h00000000, captured_output);
        
        $display(" [EXPECTED LOOPBACK]: 0x59c359c3");
        $display(" [ACTUAL LOOPBACK]:   0x%h", captured_output);
        if (captured_output == 32'h59c359c3)
            $display(" [STATUS]: SPI FUNCTIONAL TEST PASS (TIMING IS PERFECT)");
        else
            $display(" [STATUS]: SPI ERROR");
        $display("-------------------------------------------------------");

        // ====================================================================
        // PHASE 1: AES CORE PROCESSING (TROJAN ASLEEP)
        // ====================================================================
        $display("\n=======================================================");
        $display(" PHASE 1: RUNNING AES CORE (TROJAN ASLEEP)");
        $display("=======================================================");
        
        spi_transfer(32'h59C359C3, dummy);
        
        // Strictly edge-aligned START pulse (exactly 1 cycle, like Python)
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        
        // Exactly 7 cycles of computation time
        repeat (7) @(posedge clk);
        
        spi_transfer(32'h00000000, captured_output);
        $display(" [RESULT] Plaintext Sent:  0x59c359c3");
        $display(" [RESULT] AES Cipher Out:  0x%h", captured_output);
        $display("-------------------------------------------------------");

        // ====================================================================
        // PHASE 2: TROJAN DETONATION
        // ====================================================================
        $display("\n=======================================================");
        $display(" PHASE 2: TRANSMITTING SECRET TROJAN TRIGGER");
        $display("=======================================================");
        
        spi_transfer(32'hAABBCCDD, dummy);
        
        if (uut.main_trojan.trojan_active) 
            $display(" STATUS: uut.main_trojan.trojan_active = 1 (TRAP SPRUNG!)");
        $display("-------------------------------------------------------");

        // ====================================================================
        // PHASE 3: VERIFY INTERCEPTION
        // ====================================================================
        $display("\n=======================================================");
        $display(" PHASE 3: RUNNING CORE AGAIN (TROJAN INTERCEPTING)");
        $display("=======================================================");
        
        spi_transfer(32'h59C359C3, dummy);
        
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        
        repeat (7) @(posedge clk);
        
        spi_transfer(32'h00000000, captured_output);
        $display(" [RESULT] Plaintext Sent:      0x59c359c3");
        $display(" [RESULT] Malicious Cipher Out: 0x%h", captured_output);
        $display("=======================================================");
        
        #2000;
        $finish;
    end

    // ====================================================================
    // BULLETPROOF SPI MODE 0 DRIVER
    // Data transitions on falling edge, sampled on rising edge.
    // ====================================================================
    task spi_transfer(input [31:0] tx_data, output [31:0] rx_data);
        integer i;
        begin
            @(negedge clk);
            cs_n = 0;
            for (i = 31; i >= 0; i = i - 1) begin
                mosi = tx_data[i];
                @(posedge clk);
                rx_data[i] = miso; // Core outputs data on posedge, we capture it
                @(negedge clk);
            end
            cs_n = 1;
        end
    endtask

endmodule
