import video_timing_modes_pkg::*;

interface video_interface;

    // Current pixel position
    // Per while i define the video mode to 0, cause of that i use [9:0] for x and [8:0] for y
    logic signed [10:0] x_pos; // Current horizontal pixel position
    logic signed [9:0] y_pos; // Current vertical pixel position

    video_mode_t mode; // Current video mode (e.g., 480p, 720p, 1080p)

    // Video signal definitions
    logic [7:0] red;
    logic [7:0] green;
    logic [7:0] blue;

    logic de; // Data enable signal
    logic vsync; // Vertical sync signal
    logic hsync; // Horizontal sync signal

    modport source (
        output red, green, blue,
        input x_pos, y_pos,     // Current pixel position
        input de, vsync, hsync
    );

    /*
        the video_generator will recieve the colors and return the positions and the frame_just_finished signal means that the frame is just finished.
      
        the video_test will define the logic using the cords to set the colors, moreover will use if the frame is just finished informing to generate the next frame.
    */
    modport sink (
        input  red, green, blue,
        output x_pos, y_pos,    // Current pixel position
        output de, vsync, hsync
    );

endinterface