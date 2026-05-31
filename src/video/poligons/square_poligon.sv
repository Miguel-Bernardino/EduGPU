
typedef enum logic  {
    NONE = 1'b0,
    FILL = 1'b1

} square_background_mode_t;

typedef logic [7:0] rgb_color_t [2:0]; // RGB color represented as an array of 3 bytes (R, G, B)

//generate a square poligon with the center in (x_offset, y_offset) and the size of border_size, the color of the border is border_color and the color of the background is background_color, if background_mode is FILL the background will be filled with background_color otherwise it will be NONE
function automatic rgb_color_t square_poligon (

    input square_background_mode_t background_mode,
    
    input logic signed [10:0]   x_pos,
    input logic signed [9:0]    y_pos,
    
    input logic signed [10:0]   x_offset,
    input logic signed [9:0]    y_offset,
    
    input logic [7:0]           background_color [2:0],
    
    input logic signed [10:0]   border_size,
    input logic [7:0]           border_color [2:0],

    input [11:0] size

);

logic [11:0] distance = size - ((abs_12b(x_pos - x_offset) + abs_12b(y_pos - y_offset) )); 

if (distance < border_size) begin
    return border_color;

end else if (background_mode == FILL && distance <= size) begin
    return background_color;

end else begin
    return '{8'h00, 8'h00, 8'h00}; // Return black color when not in the active area

end
    



endfunction