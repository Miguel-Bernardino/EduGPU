import video_timing_modes_pkg::*;

interface video_interface;

    // Current pixel position
    // Per while i define the video mode to 0, cause of that i use [9:0] for x and [8:0] for y

    video_mode_t mode; // Current video mode (e.g., 480p, 720p, 1080p)

    // Video signal definitionss
    rgb_color_t color;   // Red color component (8 bits)

    logic de; // Data enable signal
    logic vsync; // Vertical sync signal
    logic hsync; // Horizontal sync signal
    
    // FIFO control signals
    //In the FIFO is current empty.
    logic video_transparence;

    modport source (
        output color,
        output de, vsync, hsync,
        output video_transparence
    );

    /*
        the video_generator will recieve the colors and return the positions and the frame_just_finished signal means that the frame is just finished.
      
        the video_test will define the logic using the cords to set the colors, moreover will use if the frame is just finished informing to generate the next frame.
    */
    modport sink (
        input color,
        input de, vsync, hsync,
        input video_transparence
    );

endinterface