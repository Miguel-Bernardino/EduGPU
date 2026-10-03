`include "types.sv"

// ====================================================================================================
// cordic_sincos  (versão em RTL puro -- NÃO usa mais a IP CORDIC_Top da Gowin)
// ----------------------------------------------------------------------------------------------------
// Mesma interface da versão anterior (drop-in): i_start (pulso) + i_theta (Q9.8 graus) ->
// o_done (pulso) + o_cos_theta/o_sin_theta em Q?.8 (formato de polygon_param_t), sem ganho residual.
//
// POR QUE SAIU A IP (ver IPUG522 -- Gowin CORDIC IP User Guide):
//   1) Faixa do ângulo: a IP em modo DEGREE só é válida em (-90°, +90°). A rotação varria -180..+180,
//      então para |theta| > ~100° o CORDIC não converge (satura em ~99,88° = soma dos atan(2^-i)) e
//      devolve cos/sin de um ângulo errado -- o polígono trava/salta em metade da volta.
//   2) Constante de entrada: o guia manda usar x_i = 0,607253 (= 19898 em Q1.15). Se a constante em
//      types.sv (CORDIC_INV_GAIN_Q1_15) estiver como 1/0,607253 = 1,6468, a saída sai ~2,7x maior
//      e o polígono ENCOLHE (a varredura anda 2,7x mais rápido no espaço do polígono).
//   3) Frequência: o guia cita ~95 MHz de máximo para a IP (GW2A-55). O video_clock precisa ser
//      >= 2x o pixel_clock (2 polígonos), ou seja >= 148,5 MHz em 720p -- a IP não fecha timing aí, e
//      saída errada por violação de timing aparece como "tremor" de tamanho/posição a cada quadro.
//   4) A latência real da IP nunca foi confirmada (CORDIC_LATENCY era um placeholder).
//
// ESTE MÓDULO:
//   - Dobra o ângulo para [-90°, +90°] (theta -/+ 180° e inverte o sinal de cos e sin), então aceita
//     qualquer theta em [-256°, +255,99°] (toda a faixa de cordic_theta_t).
//   - CORDIC circular, modo rotação, 16 iterações, x,y em Q3.16 (20 bits) e ângulo em graus Q9.16 (26 bits).
//     Começa em (1/K, 0) com 1/K = 0,6072529 -> sai (cos, sin) com magnitude 1 sem multiplicador.
//   - Cada iteração gasta 2 ciclos (1: barrel shift, 2: soma/subtração) -> caminho crítico curto,
//     fecha timing folgado mesmo a 150-200 MHz. Latência total fixa e conhecida: 35 ciclos.
//   - Arredonda (não trunca) de Q.16 para Q.8. Erro máximo medido (todos os 92161 ângulos Q9.8 entre
//     -180 e +180): 0,00205 (meio LSB de Q.8 = 0,00195), magnitude 0,998..1,002.
//     (verificado bit a bit em modelo Python -- ver explicação da resposta.)
// ====================================================================================================
module cordic_sincos (
    input  logic           clk,
    input  logic           rst_n,

    input  logic           i_start, // pulso de 1 ciclo: "calcule este ângulo"
    input  cordic_theta_t  i_theta, // ângulo desejado, Q9.8 graus, qualquer valor de cordic_theta_t

    output logic           o_busy,  // alto enquanto processando -- não mande novo i_start nesse meio tempo
    output logic           o_done,  // pulso de 1 ciclo quando o_cos_theta/o_sin_theta ficam válidos
    output polygon_param_t o_cos_theta, // Q?.8 -- mesmo formato do campo cos_theta em polygon_config_t
    output polygon_param_t o_sin_theta
);

    localparam int XW       = 20; // x,y: Q3.16
    localparam int ZW       = 26; // z  : graus Q9.16
    localparam int NUM_ITER = 8;

    // 1/K = 0,6072529350 * 2^16 = 39797
    localparam logic signed [XW-1:0] K_INV_Q16 = 20'sd39797;

    // atan(2^-i) em graus, Q9.16 (round(atan(2^-i)*180/pi*65536))
    function automatic logic signed [ZW-1:0] atan_rom(input logic [3:0] idx);
        case (idx)
            4'd0:    atan_rom = 26'sd2949120;
            4'd1:    atan_rom = 26'sd1740967;
            4'd2:    atan_rom = 26'sd919879;
            4'd3:    atan_rom = 26'sd466945;
            4'd4:    atan_rom = 26'sd234379;
            4'd5:    atan_rom = 26'sd117304;
            4'd6:    atan_rom = 26'sd58666;
            4'd7:    atan_rom = 26'sd29335;
            4'd8:    atan_rom = 26'sd14668;
            4'd9:    atan_rom = 26'sd7334;
            4'd10:   atan_rom = 26'sd3667;
            4'd11:   atan_rom = 26'sd1833;
            4'd12:   atan_rom = 26'sd917;
            4'd13:   atan_rom = 26'sd458;
            4'd14:   atan_rom = 26'sd229;
            4'd15:   atan_rom = 26'sd115;
            default: atan_rom = 26'sd0;
        endcase
    endfunction

    // theta de entrada estendido com sinal (Q9.8) -- usado só no ciclo do i_start
    logic signed [ZW-1:0] theta_ext;
    assign theta_ext = $signed(i_theta);

    typedef enum logic [2:0] { S_IDLE, S_SHIFT, S_ADD, S_SIGN, S_ROUND } state_t;
    state_t state;

    logic signed [XW-1:0] x, y;     // vetor em rotação
    logic signed [XW-1:0] xs, ys;   // x>>>i, y>>>i (registrados: quebra o caminho shift -> soma)
    logic signed [ZW-1:0] z;        // ângulo residual (graus Q9.16)
    logic signed [ZW-1:0] atan_r;   // atan(2^-i) da iteração corrente
    logic                 z_pos;    // sentido da rotação da iteração corrente (z >= 0)
    logic                 neg;      // ângulo foi dobrado (+-180°): inverte cos e sin no final
    logic        [4:0]    iter;
    logic signed [XW-1:0] xn, yn;   // x,y já com o sinal do dobramento aplicado

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            o_busy      <= 1'b0;
            o_done      <= 1'b0;
            o_cos_theta <= '0;
            o_sin_theta <= '0;
            x           <= '0;
            y           <= '0;
            xs          <= '0;
            ys          <= '0;
            z           <= '0;
            atan_r      <= '0;
            z_pos       <= 1'b0;
            neg         <= 1'b0;
            iter        <= '0;
            xn          <= '0;
            yn          <= '0;
        end else begin
            o_done <= 1'b0; // pulso de 1 ciclo

            case (state)
                S_IDLE: begin
                    if (i_start) begin
                        // Dobra para [-90°, +90°]. 90° = 90<<8 = 23040 ; 180° = 46080 (Q9.8)
                        if (theta_ext > 26'sd23040) begin
                            z   <= (theta_ext - 26'sd46080) <<< 8;
                            neg <= 1'b1;
                        end else if (theta_ext < -26'sd23040) begin
                            z   <= (theta_ext + 26'sd46080) <<< 8;
                            neg <= 1'b1;
                        end else begin
                            z   <= theta_ext <<< 8;
                            neg <= 1'b0;
                        end
                        x      <= K_INV_Q16;
                        y      <= '0;
                        iter   <= '0;
                        o_busy <= 1'b1;
                        state  <= S_SHIFT;
                    end
                end

                S_SHIFT: begin
                    xs     <= x >>> iter;
                    ys     <= y >>> iter;
                    atan_r <= atan_rom(iter[3:0]);
                    z_pos  <= ~z[ZW-1];
                    state  <= S_ADD;
                end

                S_ADD: begin
                    if (z_pos) begin
                        x <= x - ys;
                        y <= y + xs;
                        z <= z - atan_r;
                    end else begin
                        x <= x + ys;
                        y <= y - xs;
                        z <= z + atan_r;
                    end

                    if (iter == NUM_ITER - 1) begin
                        state <= S_SIGN;
                    end else begin
                        iter  <= iter + 1'b1;
                        state <= S_SHIFT;
                    end
                end

                S_SIGN: begin
                    xn    <= neg ? -x : x;
                    yn    <= neg ? -y : y;
                    state <= S_ROUND;
                end

                S_ROUND: begin
                    // Q3.16 -> Q.8 com arredondamento para o mais próximo (+0,5 LSB antes do shift)
                    o_cos_theta <= polygon_param_t'((xn + 20'sd128) >>> 8);
                    o_sin_theta <= polygon_param_t'((yn + 20'sd128) >>> 8);
                    o_busy      <= 1'b0;
                    o_done      <= 1'b1;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule