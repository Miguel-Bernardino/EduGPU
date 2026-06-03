// Função de mistura corrigida para não perder precisão no Bit Menos Significativo (LSB)
function automatic rgb_color_t blend_half(rgb_color_t c_fg, rgb_color_t c_bg);
    rgb_color_t blended;
    logic [8:0] sum_r, sum_g, sum_b; // 9 bits para evitar overflow antes da divisão
    
    sum_r = c_fg[0] + c_bg[0];
    sum_g = c_fg[1] + c_bg[1];
    sum_b = c_fg[2] + c_bg[2];
    
    blended[0] = sum_r[8:1]; // Deslocamento seguro mantendo o LSB correto
    blended[1] = sum_g[8:1];
    blended[2] = sum_b[8:1];
    
    return blended;
endfunction

// Gera um polígono quadrado com centro em (x_offset, y_offset)
module square_poligon_render (
    input logic                    clk,
    input logic                    rst_n,
    
    // Video interface 
    video_timing_interface         in_vif,                // Video interface for receiving pixel positions and sending colors
    video_interface                out_vif,         // Output color for the current pixel

    // SQUARE PARAMETERS
    input logic signed [11:0]      i_h_active,          // Horizontal active resolution (in pixels)
    input logic signed [11:0]      i_v_active,          // Vertical active resolution
    input logic signed [11:0]      i_center_x,          // Center X position of the square (in pixels)
    input logic signed [11:0]      i_center_y,          // Center Y position of the square (in pixels)
    input logic [10:0]             i_radius,            // radius of the square (in pixels)
    input rgb_color_t              i_past_rgb,          // Cor do pixel anterior (usada para mistura)
    input logic signed [10:0]      i_border_size,       // Border size in pixels (if 0, the square will be filled)

    input float_21b                i_cos_theta,         //  angle of rotation for the square (if needed, otherwise set to 1 for no rotation)
    input float_21b                i_sin_theta,         //  angle of rotation for the square (if needed, otherwise set to 0 for no rotation)

    // BACKGORUND PARAMETERS
    input square_background_mode_t i_bg_mode,           // Mode to determine if the square is filled or just a border
    input rgb_color_t              i_default_bg_color,  // Default background color (used when the pixel is outside the square)
    input rgb_color_t              i_bg_color,          // Background color for the square (used when the pixel is inside the square)
    // BORDER PARAMETERS
    input rgb_color_t              i_border_color,      // Border color for the square (used when the pixel is within the border area)

    input logic                    i_enabled,            // Enable signal for the module
    
    input  logic                   i_isTransparent,        // Flag to indicate if the pixel is transparent (used for blending)
    output logic                   o_isTransparent     // Flag to indicate if the pixel is transparent (used for blending)

);

float_21b a = i_cos_theta;
float_21b b = (~i_sin_theta + 1'b1); // Negação de i_sin_theta para multiplicação de rotação
float_21b c = i_sin_theta;
float_21b d = i_cos_theta;


logic signed [11:0] x_start_cord = -12'(i_h_active / 2); 
logic signed [11:0] y_start_cord =  12'(i_v_active / 2);

wire signed [20:0] x_start_fixed = x_start_cord << 9;
wire signed [20:0] y_start_fixed = y_start_cord << 9;

wire signed [20:0] center_x_fixed = 21'($signed(i_center_x)) << 9;
wire signed [20:0] center_y_fixed = 21'($signed(i_center_y)) << 9;

// Agora a multiplicação de ponto fixo (a * -X_c) funcionará perfeitamente no silício:
wire float_42b p1_at_zero = ($signed(a) * $signed(x_start_fixed - center_x_fixed)) + ($signed(b) * $signed(y_start_fixed - center_y_fixed));
wire float_42b p2_at_zero = ($signed(c) * $signed(x_start_fixed - center_x_fixed)) + ($signed(d) * $signed(y_start_fixed - center_y_fixed));

// Variáveis de acumulação para os pontos transformados
float_42b p1_current = p1_at_zero; // Inicializa com a posição do centro transformada
float_42b p2_current = p2_at_zero; // Inicializa com a posição do centro transformada

float_42b p1_line_start = p1_at_zero; // Posição do pixel atual no espaço transformado
float_42b p2_line_start = p2_at_zero; // Posição do pixel atual no espaço transformado

//float_42b distance = {1'b0, i_radius, 10'b0} - ( abs_42b(p1_at_zero) + abs_42b(p2_at_zero) ); // Calculate the Manhattan distance

float_42b distance;
assign distance = $signed(float_42b'(i_radius) << 18) - $signed(abs_42b(p1_current)) - $signed(abs_42b(p2_current)); // Calculate the Manhattan distance
//assign distance = $signed({1'b0, i_radius}) - $signed(abs_12b(in_vif.x_pos)) - $signed(abs_12b(in_vif.y_pos));

logic     is_inside_square; 
assign    is_inside_square = (distance[41] == 1'b0); // Check if the pixel is inside the square
logic     is_inside_border; 
assign    is_inside_border = ($signed(distance) <= $signed(float_42b'(i_border_size) << 18) && i_border_size > 0) && is_inside_square; // Check if the pixel is within the border area

logic isTransparent; // Internal transparency flag for blending
rgb_color_t computed_next_color;

logic vsync_past;
logic hsync_past;

// Flags to manage the line and frame timing
wire vsync_strobe = (in_vif.vsync && !vsync_past);
wire hsync_strobe = (in_vif.hsync && !hsync_past);

always_ff @(posedge clk or negedge rst_n) begin     
    if (!rst_n) begin
        out_vif.x_pos   <= '0;
        out_vif.y_pos   <= '0;
        out_vif.de      <= '0;
        out_vif.hsync   <= '0;
        out_vif.vsync   <= '0;
        out_vif.color   <= {8'h00, 8'h00, 8'h00}; // Default background color on reset
        o_isTransparent <= 1'b1;
        vsync_past      <= '0;
        hsync_past      <= '0;
    end else begin
        // Pipeline: Copia o status da entrada para a saída
        out_vif.de    <= in_vif.de;
        out_vif.hsync <= in_vif.hsync;
        out_vif.vsync <= in_vif.vsync;

        vsync_past    <= in_vif.vsync;
        hsync_past    <= in_vif.hsync;

        if(vsync_strobe) begin
            p1_current <= p1_at_zero; // Reset the accumulated positions at the start of each frame
            p2_current <= p2_at_zero;
            p1_line_start <= p1_at_zero; // Reset the line start positions for the new frame
            p2_line_start <= p2_at_zero;
            
        end else if(hsync_strobe) begin
            // says that we are at the end of the line
            // increment more 1 pixel in the y axis
            // the line variables dont have a x increment
            p1_line_start <= p1_line_start + ($signed(b) << 9);
            p2_line_start <= p2_line_start + ($signed(d) << 9);
            
            
            // when we are at the end of the line, we need to reset the x position
            // i.e. we need to move y axis and start at 0 x axis again
            p1_current <= p1_line_start + ($signed(b) << 9); // Move right by one pixel in the rotated space
            p2_current <= p2_line_start + ($signed(d) << 9); // Move right by one pixel in the rotated space

        end

        if (in_vif.de) begin
            
            p1_current <= p1_current + ($signed(a) << 9); // Move right by one pixel in the rotated space
            p2_current <= p2_current + ($signed(c) << 9); // Move right by one pixel in the rotated space

            if(is_inside_square) begin 
                if(is_inside_border) begin
                    out_vif.color <= i_border_color; // Pixel is within the border area
                    o_isTransparent <= 1'b0; // Not transparent, use border color

                end else if(i_bg_mode == FILL) begin
                    out_vif.color <= i_bg_color; // Pixel is inside the square (filled)
                    o_isTransparent <= 1'b0; // Not transparent, use background color
                end else begin
                    if(!i_isTransparent) begin
                        out_vif.color <= i_past_rgb; // Blend with the default background color
                        o_isTransparent <= 1'b0; // Not transparent, use blended color
                    end else begin
                        out_vif.color <= i_default_bg_color; // Use the default background color
                        o_isTransparent <= 1'b1; // Transparent, use default background color
                    end
                end
            end else begin
                if(!i_isTransparent) begin
                    out_vif.color <= i_past_rgb; // Blend with the default background color
                    o_isTransparent <= 1'b0; // Not transparent, use blended color
                end else begin
                    out_vif.color <= i_default_bg_color; // Use the default background color
                    o_isTransparent <= 1'b1; // Transparent, use default background color
                end
            end
            
        end else begin
            out_vif.color   <= i_default_bg_color; // Use default background color when not in active video
            o_isTransparent <= 1'b1;
        end
    end
end


/*
always_comb begin 
    if (is_inside_square) begin
        if(is_inside_border) begin
            o_pixel_color = i_border_color; // Pixel is within the border area
            io_isTransparent = 1'b0; // Not transparent, use border color

        end else if(i_bg_mode == FILL) begin
            o_pixel_color = i_bg_color; // Pixel is inside the square (filled)
            io_isTransparent = 1'b0; // Not transparent, use background color
        end

    end else begin
        if(!io_isTransparent) begin
            o_pixel_color = i_past_rgb; // Blend with the default background color
        end else begin
            o_pixel_color = i_default_bg_color; // Use the default background color
            io_isTransparent = 1'b1;
        end
    end
end
*/
    

endmodule