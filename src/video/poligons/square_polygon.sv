// Gera um polígono quadrado com centro em (x_offset, y_offset)
module square_polygon_render (
    input logic                       clk,
    input logic                       rst_n,
    
    Polygon_Memory_Interface.source   polygon_params, // Interface to receive polygon parameters from memory
    video_interface.source            video_if, // Interface to receive video timing signals from the video timing generator

    logic [10:0]                      i_h_active,          // Horizontal active resolution (in pixels)
    logic [10:0]                      i_v_active,          // Vertical active resolution (in pixels)
    polygon_addr_t                    polygon_address, // Address signal to select the current polygon parameters from memory

    logic signed [11:0]               min_x, // Minimum X coordinate of the pixel grid (relative to the center of the square)
    logic signed [11:0]               max_x, // Maximum X coordinate of the pixel grid (relative to the center of the square)
    logic signed [11:0]               min_y, // Minimum Y coordinate of the pixel grid (relative to the center of the square)
    logic signed [11:0]               max_y, // Maximum Y coordinate of the pixel grid (relative to the center of the square)
   
    input logic                       i_frame_start_pulse, // Substitui a geração interna
    input logic                       i_frame_aligned,

    input rgb_color_t                 i_default_bg_color, // Default background color for blending when the current pixel is transparent
    
    input  logic                      i_AlmostEmpty, i_AlmostFull, // FIFO flow control signals
    
    output logic                      o_isTransparent, // Default background color for blending when the    
    output logic                      o_fifo_enable,   // Signal to indicate when the output pixel data is valid and can be written to the FIFO
    output rgb_color_t                o_render_data    // Output pixel color (used for blending and output to FIFO) and coordenates of the pixel (x,y) in the screen
);

parameter polygons_num = 2; // Number of polygons to be rendered in the polygon via

// Sinal único de habilitação usado por TODOS os estágios do pipeline (acumuladores,
// contador de endereço e todas as cadeias de signal_delay), garantindo que tudo
// pare e avance exatamente nos mesmos ciclos.
//
// ------------------------------------------------------------------------------------------------------------
// Alinhamento de início de quadro entre domínios de clock assíncronos (video_clock x pixel_clock)
// ------------------------------------------------------------------------------------------------------------
// video_if.vsync é gerado no domínio pixel_clock; 'clk' aqui é video_clock, vindo de um PLL
// independente (Video_rPLL). Sem alinhamento, o pipeline começa a contar pixels em uma fase
// arbitrária em relação ao início real do quadro de vídeo -- fase essa que muda a cada
// reset/energização, pois os dois PLLs não são sincronizados entre si. Isso aparece como um
// deslocamento horizontal pequeno e não determinístico.
//
// Solução: sincronizamos vsync para o domínio video_clock com um sincronizador de 2 flip-flops
// e só liberamos o pipeline (pipeline_enable) no primeiro início de quadro detectado após o
// reset. A partir daí a contagem de pixels fica alinhada ao quadro real de forma determinística,
// igual em todo reset.
// BUGFIX: sincronizador de reset. 'rst_n' é usado como reset assíncrono em vários
// always_ff espalhados pelo módulo (vsync_sync_ff, x_pos/y_pos, acumuladores, distance,
// o_pixel_color, e nos submódulos signal_delay). Se 'rst_n' vier direto de um botão físico
// (bounce) ou de qualquer fonte não perfeitamente síncrona, cada flip-flop pode sair do
// reset em um ciclo ligeiramente diferente dos outros (skew de remoção de reset),
// dependendo de como a metaestabilidade se resolve em cada célula. Isso desalinha a fase
// entre x_pos/y_pos, os acumuladores de rotação e os estágios de signal_delay -- o
// polígono continua sendo desenhado, mas a fase errada faz o cálculo de distância cruzar
// o limiar da borda o tempo todo, gerando o flicker constante.
// Solução: um único sincronizador de 2 flip-flops gera 'rst_n', que é distribuído
// para TODOS os registradores do módulo (inclusive os submódulos signal_delay abaixo).
// Assim, todo mundo sai do reset exatamente no mesmo ciclo de 'clk', sem skew.


wire pipeline_enable = !i_AlmostFull && i_frame_aligned;

// Stage 1: Calculate the relative position of the current pixel to the center of the square

polygon_param_t [polygons_num -1:0] coef_p1_cos_acc = '{default: '0};
polygon_param_t [polygons_num -1:0] coef_p1_sin_acc = '{default: '0};
polygon_param_t [polygons_num -1:0] coef_p2_cos_acc = '{default: '0};
polygon_param_t [polygons_num -1:0] coef_p2_sin_acc = '{default: '0};

//logic [polygons_num -1:0] i; // icrement value of coef_p1 and coef_p2 for each polygon

// Stage 1: Calculate the coefficient wich follow the p1(p1 = x0 -offset_x) and p2(p2 = y0 -offset_y) the for each polygon

logic signed [11:0]  min_x = -$signed(12'd1280 >> 1);
logic signed [11:0]  max_x =  $signed(12'd1280 >> 1) - 1'b1;
logic signed [11:0]  min_y = -$signed(12'd720  >> 1);
logic signed [11:0]  max_y =  $signed(12'd720  >> 1) - 1'b1;

logic signed [11:0] x_pos = min_x;
logic signed [11:0] y_pos = max_y;

// ============================================================================================================
// Pipeline (n = ciclo em que o endereço 'polygon_address' e os parâmetros do polígono estão na entrada):
//
//   n    : S1  lê os acumuladores ANTES do incremento e soma cos_acc+sin_acc (x) / sin_acc+cos_acc (y);
//               em paralelo, atualiza os acumuladores (stage 1 original)
//   n+1  : S2  x' = p1 + soma_x      ,  y' = p2 + soma_y
//   n+2  : S3  |x'| , |y'|
//   n+3  : S4  |x'| + |y'|
//   n+4  : S5  distance = radius - (|x'| + |y'|)
//   n+5  : S6  flags: dentro do polígono / dentro da borda
//   n+6  : S7  mistura de cor e escrita no FIFO
//
// ============================================================================================================

localparam int PIPE_FINAL = 6; // ciclos entre a entrada (S1) e o estágio final de cor (S7)

// ------------------------------------------------------------------------------------------------------------
// Stage 1: acumuladores (coeficientes de rotação por polígono)
// ------------------------------------------------------------------------------------------------------------
wire is_end_of_line  = (x_pos == max_x);
wire is_end_of_frame = (y_pos == min_y);
wire is_last_polygon = (polygon_address == polygons_num - 1);

always_ff@(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_pos <= min_x;
        y_pos <= max_y;

        for (int j = 0; j < polygons_num; j++) begin
            coef_p1_cos_acc[j] <= 0;
            coef_p1_sin_acc[j] <= 0;
            coef_p2_cos_acc[j] <= 0;
            coef_p2_sin_acc[j] <= 0;
        end

    end else if(i_frame_start_pulse) begin
        // resincroniza a varredura com o vsync real TODO quadro
        x_pos <= min_x;
        y_pos <= max_y;

        for (int j = 0; j < polygons_num; j++) begin
            coef_p1_cos_acc[j] <= 0;
            coef_p1_sin_acc[j] <= 0;
            coef_p2_cos_acc[j] <= 0;
            coef_p2_sin_acc[j] <= 0;
        end

    end else if(pipeline_enable) begin
        if(!is_end_of_line) begin
            if(is_last_polygon) begin
                x_pos <= x_pos + 1;
            end
            coef_p1_cos_acc[polygon_address] <= coef_p1_cos_acc[polygon_address] + polygon_params.cos_theta;
            coef_p2_sin_acc[polygon_address] <= coef_p2_sin_acc[polygon_address] + polygon_params.sin_theta;
        end else begin
            // fim da linha: zera a parte horizontal (cos_acc / sin_acc de p2)
            if(is_last_polygon) begin
                x_pos <= min_x;
            end
            coef_p1_cos_acc[polygon_address] <= 0;
            coef_p2_sin_acc[polygon_address] <= 0;

            if(!is_end_of_frame) begin
                if(is_last_polygon) begin
                    y_pos <= y_pos - 1;
                end
                coef_p1_sin_acc[polygon_address] <= coef_p1_sin_acc[polygon_address] + polygon_params.sin_theta;
                coef_p2_cos_acc[polygon_address] <= coef_p2_cos_acc[polygon_address] - polygon_params.cos_theta;
            end else begin
                // fim do quadro
                if(is_last_polygon) begin
                    y_pos <= max_y;
                end
                coef_p1_sin_acc[polygon_address] <= 0;
                coef_p2_cos_acc[polygon_address] <= 0;
            end
        end
    end
end

logic signed [11:0] x_pos_delayed, y_pos_delayed; // (sem uso hoje -- mantidos como estavam)

signal_delay #(
    .T(logic signed [11:0]),
    .DELAY_N(4)
) x_pos_delay (
    .clk(clk),
    .rst_n(rst_n),
    .enable(pipeline_enable),
    .signal_in(x_pos),
    .signal_out(x_pos_delayed)
);

signal_delay #(
    .T(logic signed [11:0]),
    .DELAY_N(4)
) y_pos_delay (
    .clk(clk),
    .rst_n(rst_n),
    .enable(pipeline_enable),
    .signal_in(y_pos),
    .signal_out(y_pos_delayed)
);

// ------------------------------------------------------------------------------------------------------------
// Parâmetros do polígono alinhados com o estágio em que cada um é consumido
// ------------------------------------------------------------------------------------------------------------
polygon_param_t p1_delayed, p2_delayed;    // consumidos em S2  (n+1)
polygon_param_t cached_radius;             // consumido em  S5  (n+4)
polygon_param_t border_size_delayed;       // consumido em  S6  (n+5)
logic           is_active_delayed;         // consumido em  S6  (n+5)

signal_delay #(.T(polygon_param_t), .DELAY_N(1)) p1_delay (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.p1), .signal_out(p1_delayed)
);

signal_delay #(.T(polygon_param_t), .DELAY_N(1)) p2_delay (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.p2), .signal_out(p2_delayed)
);

signal_delay #(.T(polygon_param_t), .DELAY_N(4)) radius_delayed_2 (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.radius), .signal_out(cached_radius)
);

signal_delay #(.T(polygon_param_t), .DELAY_N(5)) border_size_delay (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.border_size), .signal_out(border_size_delayed)
);

signal_delay #(.T(logic), .DELAY_N(5)) is_active_delay (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.is_active), .signal_out(is_active_delayed)
);

// ------------------------------------------------------------------------------------------------------------
// S1..S6: aritmética (22 bits com sinal é suficiente: |x'|,|y'| < ~1500 px * 256 = 3.8e5 < 2^21)
// ------------------------------------------------------------------------------------------------------------
// Cópia com sinal do acumulador do polígono corrente (evita depender de como o select de um array
// empacotado propaga o 'signed' do elemento).
polygon_param_t sel_p1_cos, sel_p1_sin, sel_p2_cos, sel_p2_sin;
assign sel_p1_cos = coef_p1_cos_acc[polygon_address];
assign sel_p1_sin = coef_p1_sin_acc[polygon_address];
assign sel_p2_cos = coef_p2_cos_acc[polygon_address];
assign sel_p2_sin = coef_p2_sin_acc[polygon_address];

logic signed [21:0] x_acc_sum, y_acc_sum; // S1
logic signed [21:0] x_prime,   y_prime;   // S2
logic signed [21:0] abs_x_calc, abs_y_calc; // S3
logic signed [21:0] abs_sum;              // S4
logic signed [21:0] distance;             // S5  (radius - |x'| - |y'|)
logic               inside_r, border_r;   // S6

always_ff@(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_acc_sum  <= 22'sd0;
        y_acc_sum  <= 22'sd0;
        x_prime    <= 22'sd0;
        y_prime    <= 22'sd0;
        abs_x_calc <= 22'sd0;
        abs_y_calc <= 22'sd0;
        abs_sum    <= 22'sd0;
        distance   <= 22'sd0;
        inside_r   <= 1'b0;
        border_r   <= 1'b0;
    end else if(pipeline_enable) begin
        // S1: x' parcial = cos*k + sin*r ; y' parcial = sin*k - cos*r  (valores ANTES do incremento)
        x_acc_sum <= $signed(sel_p1_cos) + $signed(sel_p1_sin);
        y_acc_sum <= $signed(sel_p2_sin) + $signed(sel_p2_cos);

        // S2: soma o termo constante do polígono (p1/p2 = rotação do canto superior esquerdo)
        x_prime <= $signed(p1_delayed) + x_acc_sum;
        y_prime <= $signed(p2_delayed) + y_acc_sum;

        // S3: valor absoluto (22 bits)
        abs_x_calc <= x_prime[21] ? -x_prime : x_prime;
        abs_y_calc <= y_prime[21] ? -y_prime : y_prime;

        // S4: norma L1
        abs_sum <= abs_x_calc + abs_y_calc;

        // S5: distância até a borda (>= 0 dentro do polígono)
        distance <= $signed(cached_radius) - abs_sum;

        // S6: flags
        inside_r <= (distance >= 0) && is_active_delayed;
        border_r <= (distance >= 0) && is_active_delayed
                    && (distance <= $signed(border_size_delayed))
                    && ($signed(border_size_delayed) > 0);
    end
end


// ------------------------------------------------------------------------------------------------------------
// Validade: cadeia de bits limpa no pulso de início de quadro (descarta o que estava em voo do quadro anterior)
// vld[k] fica visível em n+1+k  ->  no estágio final (n+6) usa-se vld[PIPE_FINAL-1]
// ------------------------------------------------------------------------------------------------------------
logic [PIPE_FINAL-1:0] vld;

always_ff@(posedge clk or negedge rst_n) begin
    if (!rst_n)                   vld <= '0;
    else if (i_frame_start_pulse) vld <= '0;
    else if (pipeline_enable)     vld <= {vld[PIPE_FINAL-2:0], 1'b1};
end

// Stage 7: Determine the color of the current pixel based on its position relative to the square and border,
// and handle transparency for blending with the background color

rgb_color_t last_color; // Register to hold the last color used for blending when the current pixel is transparent
logic is_transparent;   // Register to hold the transparency flag for the current pixel

assign o_isTransparent = is_transparent;

rgb_color_t border_color_delayed, bg_color_delayed;
square_background_mode_t bg_mode_delayed;
polygon_addr_t polygon_address_final; // endereço do polígono que está no estágio final

signal_delay #(.T(rgb_color_t), .DELAY_N(PIPE_FINAL)) border_color_delay (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.border_color), .signal_out(border_color_delayed)
);

signal_delay #(.T(rgb_color_t), .DELAY_N(PIPE_FINAL)) bg_color_delay (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.bg_color), .signal_out(bg_color_delayed)
);

signal_delay #(.T(square_background_mode_t), .DELAY_N(PIPE_FINAL)) bg_mode (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_params.bg_mode), .signal_out(bg_mode_delayed)
);

signal_delay #(.T(polygon_addr_t), .DELAY_N(PIPE_FINAL)) delay_polygon_address_final (
    .clk(clk), .rst_n(rst_n), .enable(pipeline_enable),
    .signal_in(polygon_address), .signal_out(polygon_address_final)
);

logic current_is_transparent;
assign current_is_transparent = (polygon_address_final == 0) ? 1'b1 : is_transparent;

rgb_color_t o_pixel_color;

always_ff@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        o_pixel_color   <= i_default_bg_color;
        is_transparent  <= 1'b1;
        o_fifo_enable   <= 1'b0;
    end else if(pipeline_enable) begin

        // Só escreve no FIFO no último polígono de cada pixel E se o pixel pertence ao quadro atual
        o_fifo_enable <= vld[PIPE_FINAL-1] && (polygon_address_final == polygons_num - 1);

        if (inside_r) begin
            if(border_r) begin
                o_pixel_color   <= border_color_delayed;
                last_color      <= border_color_delayed;
                is_transparent  <= 1'b0;

            end else if(bg_mode_delayed == FILL) begin
                o_pixel_color   <= bg_color_delayed;
                last_color      <= bg_color_delayed;
                is_transparent  <= 1'b0;

            end else begin
                if(!current_is_transparent) begin
                    o_pixel_color   <= last_color;
                    is_transparent  <= 1'b0;
                end else begin
                    o_pixel_color   <= i_default_bg_color;
                    is_transparent  <= 1'b1;
                end
            end

        end else begin
            if(!current_is_transparent) begin
                o_pixel_color   <= last_color;
                is_transparent  <= 1'b0;
            end else begin
                o_pixel_color   <= i_default_bg_color;
                is_transparent  <= 1'b1;
            end
        end
    end
end

assign o_render_data = {o_pixel_color[2], o_pixel_color[1], o_pixel_color[0]};

endmodule