package video_timing_modes_pkg;

    typedef enum logic [1:0] {
        MODE_480P = 2'b00,   // 640x480   @ 60Hz
        MODE_720P = 2'b01,   // 1280x720  @ 60Hz
        MODE_1080P = 2'b10,  // 1920x1080 @ 60Hz
    } video_mode_t;

    typedef struct packed {

        logic [31:0] pixel_clock; // Pixel clock frequency in Hz

        // Timing parameters for a video mode
        logic [11:0] h_sync;     // Horizontal sync pulse width
        logic [11:0] h_active;   // Active horizontal pixels
        logic [11:0] h_bporch;   // Horizontal back porch
        logic [11:0] h_fporch;   // Horizontal front porch
        logic        h_polarity;  // Horizontal sync polarity (0: negative, 1: positive)


        // Vertical timing parameters
        logic [11:0] v_sync;     // Vertical sync pulse width
        logic [11:0] v_active;   // Active vertical pixels
        logic [11:0] v_bporch;   // Vertical back porch
        logic [11:0] v_fporch;   // Vertical front porch
        logic        v_polarity;  // Vertical sync polarity (0: negative, 1: positive)

    } timing_params_t;

endpackage