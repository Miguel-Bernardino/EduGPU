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
    input logic [10:0]             i_center_x,          // Center X position of the square (in pixels)
    input logic [10:0]             i_center_y,          // Center Y position of the square (in pixels)
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
float_21b c = i_cos_theta;
float_21b d = i_sin_theta;

logic signed [11:0] minus_center_x;
logic signed [11:0] minus_center_y;

assign minus_center_x = -$signed({1'b0, i_center_x});
assign minus_center_y = -$signed({1'b0, i_center_y});

// Agora a multiplicação de ponto fixo (a * -X_c) funcionará perfeitamente no silício:
float_42b p1_at_zero = (a * minus_center_x) + (b * minus_center_y);
float_42b p2_at_zero = (c * minus_center_x) + (d * minus_center_y);

// Variáveis de acumulação para os pontos transformados
float_42b   p1_acc;
float_42b   p2_acc;

//float_42b distance = {1'b0, i_radius, 10'b0} - ( abs_42b(p1_at_zero) + abs_42b(p2_at_zero) ); // Calculate the Manhattan distance

logic [11:0] distance =  i_radius - ( abs_12b(in_vif.x_pos) + abs_12b(in_vif.y_pos) );

logic     is_inside_square = (distance >= 0); // Check if the pixel is inside the square
//logic     is_inside_border = (distance <= (float_42b'(i_border_size) << 10) && i_border_size > 0) && is_inside_square; // Check if the pixel is within the border area
logic     is_inside_border = (distance <= i_border_size) && i_border_size > 0 && is_inside_square; // Check if the pixel is within the border area

logic isTransparent; // Internal transparency flag for blending
rgb_color_t computed_next_color;


always_ff @(posedge clk or negedge rst_n) begin     
    if (!rst_n) begin
        out_vif.x_pos <= '0;
        out_vif.y_pos <= '0;
        out_vif.de    <= 1'b0;
        out_vif.hsync <= 1'b0;
        out_vif.vsync <= 1'b0;
        out_vif.color <= {8'h00, 8'h00, 8'h00}; // Default background color on reset
        o_isTransparent <= 1'b1;
    end else begin
        // Pipeline: Copia o status da entrada para a saída
        out_vif.de    <= in_vif.de;
        out_vif.hsync <= in_vif.hsync;
        out_vif.vsync <= in_vif.vsync;

        if (in_vif.de) begin
            
            out_vif.color <= {8'hFF, 8'hFF, 8'h00}; // Default background color when not in active video

            if(distance <= 0) begin 
                if(i_border_size != 0) begin
                    out_vif.color <= blend_half(i_border_color, {8'h00, 8'h00, 8'h00}); // Pixel is within the border area
                    o_isTransparent <= 1'b0; // Not transparent, use border color
                end else begin
                    out_vif.color <= blend_half(i_bg_color, {8'h00, 8'h00, 8'h00}); // Pixel is inside the square (filled)
                    o_isTransparent <= 1'b0; // Not transparent, use background color
                end
            end else if(distance > 0) begin
                if( distance <= i_border_size) begin
                    out_vif.color <= i_border_color; // Pixel is within the border area
                    o_isTransparent <= 1'b0; // Not transparent, use border color
                end else if(i_bg_mode == FILL &&  distance <= i_radius) begin
                    out_vif.color <= i_bg_color; // Pixel is inside the square (filled)
                    o_isTransparent <= 1'b0; // Not transparent, use background color
                end else begin
                    out_vif.color <= i_default_bg_color; // Use the default background color
                    o_isTransparent <= 1'b1;
                end
            end 
            
        end else begin
            out_vif.color   <= {8'hFF, 8'h00, 8'hFF}; // Use default background color when not in active video
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