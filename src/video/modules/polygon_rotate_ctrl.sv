`include "types.sv"

// ====================================================================================================
// polygon_rotate_ctrl
// ----------------------------------------------------------------------------------------------------
// Controlador de TESTE: gira continuamente todos os polígonos ATIVOS do banco, devagar (parâmetros
// THETA_STEP/UPDATE_DIV controlam a velocidade), escrevendo cos_theta/sin_theta/p1/p2 atualizados de
// volta no polygon_register_bank a cada início de frame real (frame_start_pulse_via).
//
// Fica no domínio video_clock -- mesmo domínio do polygon_register_bank -- então NÃO precisa de CDC
// pra escrever em i_we/i_waddr/i_wdata. A porta de escrita do register bank é separada da porta de
// leitura contínua (i_raddr) usada pelo square_polygon_render, então não há disputa de porta.
//
// Vértice de referência fixo (min_x, max_y) e centro de rotação na origem (0,0) -- só pra teste
// visual de que a rotação via CORDIC está funcionando. Numa versão "de produção" isso viraria
// parâmetro por polígono.
// ====================================================================================================
module polygon_rotate_ctrl #(
    parameter int                 NUM_POLYGONS               = 2,
    parameter polygon_config_t    DEFAULT_CONFIGS [NUM_POLYGONS] = '{default: '0}, // MESMO array passado ao polygon_register_bank
    parameter cordic_theta_t      THETA_STEP                 = 256, // Q9.8 graus por atualização -- 256 = 1.000 grau
    parameter int                 UPDATE_DIV                 = 1    // atualiza a cada N frames (1 = todo frame).
                                                                     // Com THETA_STEP=1 grau e UPDATE_DIV=1 @60Hz,
                                                                     // uma volta completa leva 360 frames (~6s) -- "não muito rápido".
)(
    input  logic                  clk,                 // video_clock
    input  logic                  rst_n,               // já sincronizado (rst_n_sync)

    input  logic                  i_frame_start_pulse, // pulso de 1 ciclo por vsync real

    input  logic signed [11:0]    min_x,               // vértice de referência fixo (canto da tela,
    input  logic signed [11:0]    max_y,               // sistema de coordenadas já centralizado em 0,0)

    output logic                  o_we,
    output polygon_addr_t         o_waddr,
    output polygon_config_t       o_wdata
);

    // ------------------------------------------------------------------------------------------
    // Ângulo corrente de cada polígono (acumulador independente -- permite futuramente dar
    // velocidades/fases diferentes por polígono sem mudar a estrutura da FSM).
    // ------------------------------------------------------------------------------------------
    cordic_theta_t theta_q [NUM_POLYGONS];

    // ------------------------------------------------------------------------------------------
    // Prescaler: só gera update_tick a cada UPDATE_DIV pulsos de frame_start_pulse.
    // ------------------------------------------------------------------------------------------
    localparam int DIV_W = (UPDATE_DIV <= 1) ? 1 : $clog2(UPDATE_DIV);
    logic [DIV_W-1:0] frame_div_cnt;
    logic             update_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_div_cnt <= '0;
            update_tick   <= 1'b0;
        end else begin
            update_tick <= 1'b0; // pulso de 1 ciclo
            if (i_frame_start_pulse) begin
                if (UPDATE_DIV <= 1 || frame_div_cnt == UPDATE_DIV - 1) begin
                    frame_div_cnt <= '0;
                    update_tick   <= 1'b1;
                end else begin
                    frame_div_cnt <= frame_div_cnt + 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------------------------------
    // polygon_rotation (que por sua vez instancia o cordic_sincos por baixo).
    // rot_if é declarada e usada localmente -- sem restrição de modport, já que este módulo é o
    // "dono" da interface (não a recebeu como porta).
    // ------------------------------------------------------------------------------------------
    polygon_rotation_if rot_if();

    polygon_rotation rot_inst (
        .clk               ( clk         ),
        .rst_n             ( rst_n       ),
        .polygon_source_if ( rot_if      ),
        .o_busy            (             ) // não usado -- a FSM abaixo já sabe seu próprio estado
    );

    // ------------------------------------------------------------------------------------------
    // FSM: pra cada polígono ATIVO, dispara uma rotação e escreve o resultado de volta.
    // ------------------------------------------------------------------------------------------
    typedef enum logic [1:0] { S_IDLE, S_ISSUE, S_WAIT, S_WRITE } state_t;
    state_t        state;
    polygon_addr_t poly_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            poly_idx        <= '0;
            o_we            <= 1'b0;
            o_waddr         <= '0;
            o_wdata         <= '0;
            rot_if.valid_in <= 1'b0;
            for (int k = 0; k < NUM_POLYGONS; k++) theta_q[k] <= '0;
        end else begin
            o_we            <= 1'b0; // pulsos de 1 ciclo -- default "baixo"
            rot_if.valid_in <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (update_tick) begin
                        poly_idx <= '0;
                        state    <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    if (DEFAULT_CONFIGS[poly_idx].is_active) begin
                        theta_q[poly_idx] <= theta_q[poly_idx] + THETA_STEP;
                        rot_if.theta      <= theta_q[poly_idx] + THETA_STEP;
                        rot_if.center_x   <= '0; // centro de rotação = origem (0,0)
                        rot_if.center_y   <= '0;
                        rot_if.x0         <= min_x; // vértice de referência fixo (só teste)
                        rot_if.y0         <= max_y;
                        rot_if.valid_in   <= 1'b1;
                        state             <= S_WAIT;
                    end else if (poly_idx == NUM_POLYGONS - 1) begin
                        state <= S_IDLE; // nenhum polígono ativo restante -- espera o próximo update_tick
                    end else begin
                        poly_idx <= poly_idx + 1'b1; // pula polígono inativo, não gasta ciclos de CORDIC
                    end
                end

                S_WAIT: begin
                    if (rot_if.valid_out) state <= S_WRITE;
                end

                S_WRITE: begin
                    o_we    <= 1'b1;
                    o_waddr <= poly_idx;
                    o_wdata <= '{
                        bg_color:     DEFAULT_CONFIGS[poly_idx].bg_color,
                        border_color: DEFAULT_CONFIGS[poly_idx].border_color,
                        radius:       DEFAULT_CONFIGS[poly_idx].radius,
                        border_size:  DEFAULT_CONFIGS[poly_idx].border_size,
                        is_active:    DEFAULT_CONFIGS[poly_idx].is_active,
                        bg_mode:      DEFAULT_CONFIGS[poly_idx].bg_mode,
                        cos_theta:    rot_if.cos_theta,
                        sin_theta:    rot_if.sin_theta,
                        p1:           rot_if.p1,
                        p2:           rot_if.p2
                    };

                    if (poly_idx == NUM_POLYGONS - 1) state <= S_IDLE;
                    else begin
                        poly_idx <= poly_idx + 1'b1;
                        state    <= S_ISSUE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
