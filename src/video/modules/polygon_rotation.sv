`include "types.sv"

// ====================================================================================================
// polygon_rotation
// ----------------------------------------------------------------------------------------------------
// FSM única (S_IDLE -> S_CORDIC -> S_SUM -> volta pra S_IDLE) que:
//   1) S_IDLE: captura theta/center/x0/y0 quando polygon_source_if.valid_in chega, já calculando
//      dx = x0-center_x e dy = y0-center_y (registrados), e dispara o cordic_sincos;
//   2) S_CORDIC: espera o pulso o_done e, nesse ciclo, registra os 4 produtos
//      (cos*dx, sin*dy, sin*dx, cos*dy);
//   3) S_SUM: p1 = cos*dx - sin*dy ; p2 = sin*dx + cos*dy, e sinaliza valid_out por 1 ciclo.
//
// MUDANÇA (timing): antes p1/p2 saíam de DOIS multiplicadores 20x12 + subtração no MESMO ciclo. A 148 MHz+
// isso não fecha timing na Gowin, e o resultado errado aparecia como o polígono "tremendo" de posição a
// cada quadro (p1/p2 aleatoriamente errados). Agora cada ciclo faz UMA operação. Como a rotação roda
// 1x por quadro, os 2 ciclos extras não custam nada.
//
// Todos os sinais têm exatamente UM always_ff como driver.
// ====================================================================================================
module polygon_rotation #(
)(
    input  logic                     clk,
    input  logic                     rst_n,

    polygon_rotation_if.sink         polygon_source_if,

    output logic                     o_busy
);

    cordic_theta_t                   theta;      // Ângulo de rotação em ponto fixo (Q9.8 graus)

    // diferenças inteiras (pixels) entre o ponto inicial e o centro de rotação
    logic signed [15:0]              dx;
    logic signed [15:0]              dy;

    // produtos (Q?.8 x inteiro = Q?.8), com folga de largura -- só os 20 bits baixos vão pra p1/p2
    logic signed [35:0]              prod_cos_dx;
    logic signed [35:0]              prod_sin_dy;
    logic signed [35:0]              prod_sin_dx;
    logic signed [35:0]              prod_cos_dy;

    logic cordic_start;
    logic cordic_busy;
    logic cordic_done;

    // cos_theta/sin_theta saem direto do cordic_sincos, já em Q?.8 (formato de polygon_param_t)
    cordic_sincos cordic_inst (
        .clk        ( clk                          ),
        .rst_n      ( rst_n                        ),
        .i_start    ( cordic_start                 ),
        .i_theta    ( theta                        ),
        .o_busy     ( cordic_busy                  ),
        .o_done     ( cordic_done                  ),
        .o_cos_theta( polygon_source_if.cos_theta   ), // só o cordic_inst escreve esses dois
        .o_sin_theta( polygon_source_if.sin_theta   )  // campos -- sem conflito de driver
    );

    typedef enum logic [1:0] { S_IDLE, S_CORDIC, S_SUM } state_t;
    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                       <= S_IDLE;
            cordic_start                <= 1'b0;
            theta                       <= '0;
            dx                          <= '0;
            dy                          <= '0;
            prod_cos_dx                 <= '0;
            prod_sin_dy                 <= '0;
            prod_sin_dx                 <= '0;
            prod_cos_dy                 <= '0;
            polygon_source_if.valid_out <= 1'b0;
            polygon_source_if.p1        <= '0;
            polygon_source_if.p2        <= '0;
        end else begin
            cordic_start                <= 1'b0; // pulsos de 1 ciclo -- default "baixo"
            polygon_source_if.valid_out <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (polygon_source_if.valid_in) begin
                        theta        <= polygon_source_if.theta;
                        dx           <= $signed(polygon_source_if.x0) - $signed(polygon_source_if.center_x);
                        dy           <= $signed(polygon_source_if.y0) - $signed(polygon_source_if.center_y);
                        cordic_start <= 1'b1;
                        state        <= S_CORDIC;
                    end
                end

                S_CORDIC: begin
                    if (cordic_done) begin
                        // cos_theta/sin_theta já estão estáveis neste ciclo (registrados no cordic_sincos)
                        prod_cos_dx <= $signed(polygon_source_if.cos_theta) * dx;
                        prod_sin_dy <= $signed(polygon_source_if.sin_theta) * dy;
                        prod_sin_dx <= $signed(polygon_source_if.sin_theta) * dx;
                        prod_cos_dy <= $signed(polygon_source_if.cos_theta) * dy;
                        state       <= S_SUM;
                    end
                end

                S_SUM: begin
                    polygon_source_if.p1        <= polygon_param_t'(prod_cos_dx - prod_sin_dy);
                    polygon_source_if.p2        <= polygon_param_t'(prod_sin_dx + prod_cos_dy);
                    polygon_source_if.valid_out <= 1'b1;
                    state                       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign o_busy = (state != S_IDLE);

endmodule