// ====================================================================================================================
// reset_sync
// ----------------------------------------------------------------------------------------------------------------
// Sincronizador de reset "assert assíncrono / deassert síncrono".
//
// Por que isso é necessário:
//   Quando o mesmo rst_n é usado como reset assíncrono em vários domínios de clock não
//   relacionados (ex.: clk, video_clock, pixel_clock, cada um vindo de um PLL/gerador
//   diferente), o instante em que rst_n sobe (deassert) cai em uma fase aleatória em
//   relação a cada clock. Isso faz com que contadores/pipelines em domínios diferentes
//   saiam do reset com uma relação de fase distinta a cada reset, gerando deslocamentos
//   não determinísticos entre o pipeline de geração de pixel e o timing de vídeo.
//
//   A solução padrão é: manter o assert do reset assíncrono (imediato, robusto), mas
//   sincronizar o deassert (subida de rst_n) ao clock de cada domínio usando uma cadeia
//   de 2 flip-flops. Assim, cada domínio sai do reset de forma alinhada ao seu próprio
//   clock, eliminando a variação de fase entre domínios.
//
// Uso: instanciar UMA vez por domínio de clock que consome reset assíncrono.
// ====================================================================================================================

module reset_sync (
    input  logic clk,          // Clock do domínio de destino
    input  logic rst_n_async,  // Reset assíncrono ativo em baixo (fonte, ex.: ~rst_p)
    output logic rst_n_sync    // Reset sincronizado ativo em baixo para uso em 'clk'
);

    // Cadeia de 2 flip-flops para sincronizar o deassert do reset.
    // O assert continua assíncrono via 'negedge rst_n_async'.
    logic meta_ff;

    always_ff @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async) begin
            meta_ff    <= 1'b0;
            rst_n_sync <= 1'b0;
        end else begin
            meta_ff    <= 1'b1;   // 1o estágio (pode ser metaestável)
            rst_n_sync <= meta_ff; // 2o estágio (já estabilizado)
        end
    end

endmodule