`include "types.sv"

interface polygon_rotation_if #(
    // Parâmetros genéricos podem ser adicionados aqui se necessário

);

    // =========================================================================
    // Sinais de Entrada (Source -> Sink)
    // =========================================================================
    cordic_theta_t          theta;      // Ângulo de rotação em ponto fixo
    polygon_param_integer_t center_x;   // Coordenada X do centro de rotação
    polygon_param_integer_t center_y;   // Coordenada Y do centro de rotação
    polygon_param_integer_t x0;         // Coordenada X do ponto inicial
    polygon_param_integer_t y0;         // Coordenada Y do ponto inicial
    logic                   valid_in;   // Indica que os dados de entrada são válidos

    // =========================================================================
    // Sinais de Saída (Sink -> Source)
    // =========================================================================
    polygon_param_t         p1;         // Termo de multiplicação 1 (ex: a * x0)
    polygon_param_t         p2;         // Termo de multiplicação 2 (ex: b * y0)
    polygon_param_t         cos_theta;  // Cosseno calculado via CORDIC
    polygon_param_t         sin_theta;  // Seno calculado via CORDIC
    logic                   valid_out;  // Indica que os resultados de saída são válidos

    // =========================================================================
    // Modports
    // =========================================================================
    
    // Módulo gerador/emissor de dados (ex: Processador ou FSM de controle)
    modport source (
        input  p1, p2, cos_theta, sin_theta, valid_out,
        output theta, center_x, center_y, x0, y0, valid_in
    );

    // Módulo receptor/processador (ex: Bloco CORDIC / Datapath)
    modport sink (
        input  theta, center_x, center_y, x0, y0, valid_in,
        output p1, p2, cos_theta, sin_theta, valid_out
    );

endinterface : polygon_rotation_if