import video_timing_modes_pkg::*;

interface video_timing_interface;

    // Current pixel position
    // Per while i define the video mode to 0, cause of that i use [9:0] for x and [8:0] for y
    logic signed [10:0] x_pos; // Current horizontal pixel position
    logic signed [10:0] y_pos; // Current vertical pixel position

    video_mode_t mode; // Current video mode (e.g., 480p, 720p, 1080p)

    // Video signal definitions
    rgb_color_t color;   // Red color component (8 bits)

    logic de; // Data enable signal
    logic vsync; // Vertical sync signal
    logic hsync; // Horizontal sync signal
    
    // FIFO control signals
    //In the FIFO is current empty.
    logic fifo_AlmostEmpty = 1'b1; // Signal to indicate if the FIFO is empty (used for flow control)
    logic fifo_AlmostFull  = 1'b0;  // Signal to indicate if the FIFO is almost full 

    modport source (
        output x_pos, y_pos,     // Current pixel position
        output fifo_AlmostEmpty,          // Signal to indicate if the FIFO is empty (used for flow control)
        output fifo_AlmostFull,
        output de, vsync, hsync
    );

    /*
        the video_generator will recieve the colors and return the positions and the frame_just_finished signal means that the frame is just finished.
      
        the video_test will define the logic using the cords to set the colors, moreover will use if the frame is just finished informing to generate the next frame.
    */
    modport sink (
        input x_pos, y_pos,    // Current pixel position
        input fifo_AlmostEmpty,          // Signal to indicate if the FIFO is empty (used for flow control)
        input fifo_AlmostFull,
        input de, vsync, hsync
    );

endinterface