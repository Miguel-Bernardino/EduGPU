module signal_delay #(
    parameter int DELAY_N = 1  // Number of clock cycles to delay the signal
)(
    input  logic clk,
    input  logic rst_n,
    input  logic signal_in,
    output logic signal_out
);

    // Registradores para o pipeline de atraso
    logic [DELAY_N-1:0] delay_pipe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delay_pipe <= '0;
        end else begin
            // Shift the input signal through the pipeline
            delay_pipe <= {delay_pipe[DELAY_N-2:0], signal_in};
        end
    end

    // The output is the last bit of the pipeline
    assign signal_out = delay_pipe[DELAY_N-1];

endmodule