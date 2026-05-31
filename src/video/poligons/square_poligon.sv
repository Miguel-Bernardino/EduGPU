
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
    
    input rgb_color_t           background_color,
    
    input logic signed [10:0]   border_size,
    input rgb_color_t           border_color,

    input rgb_color_t           default_color,
    
    input rgb_color_t           past_color,

    input [11:0]                radius,

    inout logic                 isTransparent


);

logic [11:0] sum = abs_12b(x_pos - x_offset) + abs_12b(y_pos - y_offset);
logic [11:0] distance = radius - abs_12b(x_pos - x_offset) - abs_12b(y_pos - y_offset);   

if( distance <= border_size && border_size != 0) begin
    isTransparent = 1'b0;
    return border_color;
end else if (background_mode == FILL &&  distance <= radius  ) begin
    isTransparent = 1'b0;
    return background_color;
end else begin 
    if(!isTransparent) begin
        return past_color;
    end else begin
        isTransparent = 1'b1;
        return default_color;
    end
end
    



endfunction