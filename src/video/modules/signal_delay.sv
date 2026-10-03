module signal_delay #(
    parameter type T = logic,
    parameter int DELAY_N = 1
)(
    input  logic clk,
    input  logic rst_n,
    input  logic enable = 1'b1,          // <-- novo
    input  T     signal_in,
    output T     signal_out
);

    generate
        if (DELAY_N == 0) begin : gen_no_delay
            assign signal_out = signal_in;
        end else begin : gen_delay
            T delay_pipe [DELAY_N-1:0];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < DELAY_N; i++) begin
                        delay_pipe[i] <= T'('0);
                    end
                end else if (enable) begin        // <-- só desloca quando habilitado
                    delay_pipe[0] <= signal_in;
                    for (int i = 1; i < DELAY_N; i++) begin
                        delay_pipe[i] <= delay_pipe[i-1];
                    end
                end
            end

            assign signal_out = delay_pipe[DELAY_N-1];
        end
    endgenerate

endmodule