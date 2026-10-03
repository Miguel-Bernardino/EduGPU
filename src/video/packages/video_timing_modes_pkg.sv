package video_timing_modes_pkg;

    typedef enum logic [2:0] {
        MODE_480P_60HZ = 3'b000,   // 640x480    @ 60Hz
        MODE_720P_60HZ = 3'b001,   // 1280x720   @ 60Hz
        MODE_720P_30HZ = 3'b010,   // 1280x720   @ 30Hz
        MODE_1080P_60HZ = 3'b011,  // 1920x1080  @ 60Hz
        MODE_1080P_30HZ = 3'b100   // 1920x1080  @ 30Hz
    } video_mode_t;

    typedef struct packed {

        logic [31:0] pixel_clock; // Pixel clock frequency in Hz

        // Timing parameters for a video mode
        logic [11:0] h_sync;        // Horizontal sync pulse width
        logic [11:0] h_active;      // Active horizontal pixels
        logic [11:0] h_back_porch;  // Horizontal back porch
        logic [11:0] h_front_porch; // Horizontal front porch
        logic [11:0] h_total;       // Total horizontal pixels (active + blanking)
        logic        h_polarity;    // Horizontal sync polarity (0: negative, 1: positive)


        // Vertical timing parameters
        logic [11:0] v_sync;        // Vertical sync pulse width
        logic [11:0] v_active;      // Active vertical pixels
        logic [11:0] v_back_porch;  // Vertical back porch
        logic [11:0] v_front_porch; // Vertical front porch
        logic [11:0] v_total;       // Total vertical pixels (active + blanking)s
        logic        v_polarity;    // Vertical sync polarity (0: negative, 1: positive)

    } timing_params_t;

endpackage