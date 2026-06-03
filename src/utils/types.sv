// ====================================================================================================
// === HERE HAVE ALL OF THE TYPE DEFINITIONS USED IN THE PROJECT ======================================
// ====================================================================================================

typedef logic [7:0] rgb_color_t [2:0]; // RGB color represented as an array of 3 bytes (R, G, B)
typedef logic signed [20:0] float_21b; // Define um tipo para números de ponto fixo, se necessário
typedef logic signed [41:0] float_42b; // Define um tipo para números de ponto fixo, se necessário

typedef enum logic  {
    NONE = 1'b0,
    FILL = 1'b1
} square_background_mode_t;