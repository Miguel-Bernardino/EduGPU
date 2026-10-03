`ifndef types_sv
`define types_sv

// ====================================================================================================
// === HERE HAVE ALL OF THE TYPE DEFINITIONS USED IN THE PROJECT ======================================
// ====================================================================================================

typedef logic [2:0][4:0] rgb_color_t; // RGB color represented as an array of 3 bytes (R, G, B)

typedef enum logic  {
    NONE = 1'b0,
    FILL = 1'b1
} square_background_mode_t;


// ==============================================================================
// POLYGON TYPE DEFINITIONS
// ==============================================================================
typedef logic signed [19:0] polygon_param_t; // Define a type for polygon parameters (e.g., coordinates, radius) with a range of -2048 to 2047
typedef logic signed [11:0] polygon_param_integer_t; // Define a type for polygon coordinates with a range of -2048 to 2047
typedef logic signed [7:0]  polygon_param_fractional_t; // Define a type for polygon fractional parts with a range of 0 to 255

// [9:8] integer part, [7:0] fractional part
typedef logic signed [10:0] trig_coef_t;

typedef logic [0:0]         polygon_addr_t;  // Define a type for polygon address, if needed for indexing or addressing within the polygon generator

// ==============================================================================
// MULTI-VIA ADDRESSING (endereço usado pelo motor de rotação/CORDIC compartilhado)
// ==============================================================================
// O motor de rotação é UM SÓ, compartilhado entre todas as vias. Para saber em
// qual via e em qual polígono daquela via escrever o resultado (cos_theta,
// sin_theta, p1, p2), ele usa um endereço combinado:
//   bit mais significativo = polígono (mesmo espaço de polygon_addr_t, hoje 1 bit)
//   bits menos significativos = via
// Com NUM_VIAS = 4 (2 bits) e 1 bit de polígono, dá 3 bits no total.
localparam int NUM_VIAS      = 2;
localparam int VIA_ADDR_BITS = $clog2(NUM_VIAS); // 2 bits para 4 vias

typedef logic [VIA_ADDR_BITS-1:0] via_addr_t;

// Struct packed só para deixar explícito quem é quem; em bits crus equivale a
// {polygon, via} — polygon nos bits altos, via nos bits baixos, como pedido.
typedef struct packed {
    polygon_addr_t polygon; // bit(s) mais significativo(s): qual polígono dentro da via
    via_addr_t     via;     // bit(s) menos significativo(s): qual via
} polygon_via_addr_t;

// ==============================================================================
// CORDIC (via IP CORDIC_Top do Gowin) — formatos fixos ditados pela configuração
// da IP: Function=ROTATE, Implement Method=ITERATE, Angle Type=DEGREE,
// XY Bits=17 (1 sinal + 1 inteiro + 15 fração), Theta Bits=17 (1 sinal + 8
// inteiro + 8 fração), Iteration Accuracy=16.
// ==============================================================================
typedef logic signed [19:0] cordic_theta_t; // Q9.8 em graus (1 sinal + 8 inteiro + 8 fração)
typedef logic signed [19:0] cordic_xy_t;    // Q1.15 (1 sinal + 1 inteiro + 15 fração) — só serve para vetor unitário, não para offsets em pixels!

// 1/Kn em Q1.15, direto do painel da IP (Cordic Gain -> Fixed Point). Usado para
// pré-escalar o vetor de entrada (1,0) e sair já com cos/sin com o ganho do
// CORDIC compensado, sem precisar de um multiplicador extra depois.
localparam cordic_xy_t CORDIC_INV_GAIN_Q1_15 = 17'sd53961; // 1.646760 em Q1.15

// ==============================================================================
// Representa o estado do calculo da rotacao do poligono no CORDIC_SINCOS
typedef enum logic [1:0] { S_IDLE, S_WAIT, S_DONE } state_t;

// ==============================================================================
// POLYGON REGISTER BANK — uma entrada (uma "linha") do banco de registradores
// ==============================================================================
// Espelha 1:1 os campos de Polygon_Memory_Interface (modport source). p1 e p2 NÃO são calculados
// aqui dentro — eles chegam prontos (hoje como valor de reset/default, e futuramente escritos em
// tempo real por um pipeline de CORDIC + multiplicador) e o banco só guarda o que for escrito.
typedef struct packed {
    rgb_color_t               bg_color;
    rgb_color_t               border_color;
    polygon_param_t           radius;
    polygon_param_t           border_size;
    logic                     is_active;
    square_background_mode_t  bg_mode;
    polygon_param_t           cos_theta;
    polygon_param_t           sin_theta;
    polygon_param_t           p1;
    polygon_param_t           p2;
} polygon_config_t;

`endif // types_sv