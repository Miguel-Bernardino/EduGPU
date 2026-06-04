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
    video_interface.sink           i_v_if,                // Video interface for receiving pixel positions and sending colors
    video_interface.source         o_v_if,         // Output color for the current pixel

    // SQUARE PARAMETERS
    input logic        [10:0]      i_h_active,          // Horizontal active resolution (in pixels)
    input logic        [10:0]      i_v_active,          // Vertical active resolution
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
    
    input  logic                   i_AlmostEmpty, i_AlmostFull, // FIFO flow control signals

    input  logic                   i_isTransparent,        // Flag to indicate if the pixel is transparent (used for blending)
    
    output logic                   o_isTransparent,     // Flag to indicate if the pixel is transparent (used for blending)
    output logic                   o_fifo_enable     // Signal to indicate when the output pixel data is valid and can be written to the FIFO
);

// Stage 1: Calculate the relative position of the current pixel to the center of the square


logic signed [11:0] x_min, x_max, y_min, y_max; // Boundaries of the active video area centered around (0,0)

assign x_min = -$signed({1'b0, i_h_active} >> 1);        // Ex: -640 para 720p
assign x_max =  $signed({1'b0, i_h_active} >> 1) - 1'b1; // Ex: 639 para 720p

assign y_min = -$signed({1'b0, i_v_active} >> 1);        // Ex: -360 para 720p
assign y_max =  $signed({1'b0, i_v_active} >> 1) - 1'b1; // Ex: 359 para 720p

logic signed [11:0] rel_x = x_min  -i_center_x;
logic signed [11:0] rel_y = y_max  -i_center_y;

logic signed [12:0] distance; 
assign distance = $signed({1'b0, i_radius}) - $signed(abs_12b(rel_x)) - $signed(abs_12b(rel_y));

logic is_inside_square;
assign is_inside_square = distance[12] == 0; // Flag to indicate if the current pixel is inside the square

logic is_inside_border;
assign is_inside_border = is_inside_square && distance < i_border_size && i_border_size > 0; // Flag to indicate if the current pixel is within the border area

logic signed [11:0] x_pos = x_min;
logic signed [11:0] y_pos = y_max;

// Stage 2: Increment the pixel position and update the relative coordinates accordingly
always_ff@(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Reset logic
        x_pos <= x_min;
        y_pos <= y_max;
        rel_x <= x_min - i_center_x;
        rel_y <= y_max - i_center_y;
    end else if(!i_AlmostFull) begin
        // Normal operation logic
        if(x_pos < x_max) begin
            x_pos <= x_pos + 1;
            rel_x <= rel_x + 1; // Update relative X position as we move horizontally

        end else begin
            x_pos <= x_min;
            rel_x <= x_min - i_center_x; // Reset relative X position when we wrap around horizontally

            if(y_pos > y_min) begin
                y_pos <= y_pos - 1;
                rel_y <= rel_y - 1; // Update relative Y position as we move vertically
            end else begin
                y_pos <= y_max;
                rel_y <= y_max - i_center_y; // Reset relative Y position when we wrap around vertically
            end
        end
    end
end

// Stage 3: Determine the color of the current pixel based on its position relative to the square and border, and handle transparency for blending with the background color
always_ff@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        o_v_if.color <= i_default_bg_color; // Default to background color on reset
        o_v_if.video_transparence <= 1'b1; // Default to transparent on reset
        o_v_if.de <= 1'b0;

    end else if(!i_AlmostFull) begin
        o_v_if.de <= 1'b1;

        if (is_inside_square) begin

            if(is_inside_border) begin
                o_v_if.color <= i_border_color; // Pixel is within the border area
                o_v_if.video_transparence <= 1'b0; // Not transparent, use border color

            end else if(i_bg_mode == FILL) begin
                o_v_if.color <= i_bg_color; // Pixel is inside the square (filled)
                o_v_if.video_transparence <= 1'b0; // Not transparent, use background color

            end else begin
                if(!i_v_if.video_transparence) begin
                    o_v_if.color <= i_v_if.color; // Blend with the default background color
                    o_v_if.video_transparence <= 1'b0; // Not transparent, use blended color
                end else begin
                    o_v_if.color <= i_default_bg_color; // Use the default background color
                    o_v_if.video_transparence <= 1'b1; // Transparent, use default background color
                end
            end

        end else begin

            if(!i_v_if.video_transparence) begin

                o_v_if.color <= i_v_if.color; // Blend with the default background color
                o_v_if.video_transparence <= 1'b0; // Not transparent, use blended color
            end else begin
                
                o_v_if.color <= i_default_bg_color; // Use the default background color
                o_v_if.video_transparence <= 1'b1; // Transparent, use default background color
            end
        end

    end
end
    

endmodule