import video_timing_modes_pkg::*;

interface video_interface;

    logic de;    // Data enable signal
    logic vsync; // Vertical sync signal
    logic hsync; // Horizontal sync signal

    modport source (
        output de, vsync, hsync
    );

    modport sink (
        input de, vsync, hsync
    );

endinterface