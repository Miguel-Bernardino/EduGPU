// ====================================================================================================================
// pulse_sync
// ====================================================================================================================
// Safely crosses a single-cycle pulse from one clock domain (clk_src) into another (clk_dst).
// Uses the classic "toggle + double-flop synchronizer + edge detect" technique instead of
// synchronizing the pulse itself, so it works correctly even when clk_src and clk_dst are
// asynchronous / have no fixed phase relationship to each other (e.g. two independent PLLs).
//
// Latency: 2-3 clk_dst cycles. The pulse on pulse_in must be exactly 1 clk_src cycle wide and
// pulses must be spaced at least 2 clk_src cycles apart (true here: frame_start happens once
// per frame).
// ====================================================================================================================
module pulse_sync (
    input  logic clk_src,
    input  logic rst_n,
    input  logic pulse_in,   // 1-cycle pulse in the clk_src domain

    input  logic clk_dst,
    output logic pulse_out   // 1-cycle pulse in the clk_dst domain
);

    // ---- Source domain: toggle a flip-flop every time pulse_in fires ----
    logic toggle_src;

    always_ff @(posedge clk_src or negedge rst_n) begin
        if (!rst_n) toggle_src <= 1'b0;
        else if (pulse_in) toggle_src <= ~toggle_src;
    end

    // ---- Destination domain: double-flop synchronizer on the toggle bit ----
    (* ASYNC_REG = "TRUE" *) logic sync_ff1, sync_ff2, sync_ff3;

    always_ff @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
            sync_ff3 <= 1'b0;
        end else begin
            sync_ff1 <= toggle_src;
            sync_ff2 <= sync_ff1;
            sync_ff3 <= sync_ff2;
        end
    end

    // Edge on the synchronized toggle bit = the original pulse, now safely in clk_dst domain
    assign pulse_out = sync_ff2 ^ sync_ff3;

endmodule