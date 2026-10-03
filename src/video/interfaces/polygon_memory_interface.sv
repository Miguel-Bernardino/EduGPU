import video_timing_modes_pkg::*;

interface Polygon_Memory_Interface;


    // =================================================================================================================
    // Polygon patch parameters
    // =================================================================================================================

    rgb_color_t              bg_color;     // Background color for the square
    rgb_color_t              border_color; // Border color for the square
    
    polygon_param_t          radius;       // Radius of the square (in pixels)
    polygon_param_t          border_size;  // Border size in pixels (if 0, the square will be filled)
    
    polygon_param_t          p1;           // Define the first part of the multiplication,  |ax0| => ax0 = p1
    polygon_param_t          p2;           // Define the second part of the multiplication, |by0| => by0 = p2

    logic                    is_active;    // Flag to indicate if the current polygon patch is active and should be rendered
    square_background_mode_t bg_mode;      // Mode to determine if the square is filled or just a border
    
    polygon_param_t          cos_theta;    // Cosine of the rotation angle for the square (in fixed-point representation)
    polygon_param_t          sin_theta;    // Sine of the rotation angle for the square (in fixed-point representation)


    // =================================================================================================================
    // Modports for the polygon patch interface
    // =================================================================================================================

    modport source (
        output bg_mode,

        output bg_color, border_color,
        
        output radius, border_size, 

        output is_active,

        output cos_theta, sin_theta,
        
        output p1, p2
    );


    modport sink (
        input bg_mode,

        input bg_color, border_color,
        
        input radius, border_size,
 
        input is_active,

        input cos_theta, sin_theta,

        input p1, p2
    );

endinterface