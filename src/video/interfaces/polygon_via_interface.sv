import video_timing_modes_pkg::*;

interface Polygon_Via_Interface();


    // =================================================================================================================
    // Polygon patch parameters
    // =================================================================================================================
    square_background_mode_t bg_mode;
    
    rgb_color_t              bg_color;
    rgb_color_t              border_color;
    
    polygon_param_t          radius;
    polygon_param_t          border_size;

    polygon_param_t          p1; // Define the first part of the multiplication,  |ax0| => ax0 = p1 
    polygon_param_t          p2; // Define the second part of the multiplication, |by0| => by0 = p2
    
    polygon_param_t          cos_theta;
    polygon_param_t          sin_theta;

    rgb_color_t              default_bg_color = '{8'hFF, 8'hFF, 8'hFF}; // Default background color (black), can be overridden by parameters from the video timing generator

    logic                    is_active;

    polygon_addr_t           addr;         // Address for indexing or addressing within the polygon generator 

    // =================================================================================================================
    // Modports for the polygon patch interface
    // =================================================================================================================

    modport source (
        output bg_mode, bg_color, border_color, radius, border_size, 
        cos_theta, sin_theta, is_active, addr, default_bg_color, p1, p2

    );


    modport sink (
        input bg_mode, bg_color, border_color, radius, border_size, 
        cos_theta, sin_theta, is_active, addr, default_bg_color, p1, p2
    );

endinterface