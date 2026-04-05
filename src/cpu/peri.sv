`include "soc_define.h"

module peri (
    input             clk,
    input             rstn,
    apb_intf.slave    s_apb_intf,

    // UART interface
    input             uart_rx,
    output            uart_tx,

    // SPI interface
    // inout             sclk,
    // inout             nss,
    // inout             mosi,
    // inout             miso
    output            sclk,
    output            nss,
    output            mosi,
    input             miso,

    // SPI DMA interface
    axi_intf.master   m_dma_axi_intf,

    // RMII interface
    input             rmii_refclk,
    input             rmii_crsdv,
    input    [ 1: 0]  rmii_rxd,
    output            rmii_txen,
    output   [ 1: 0]  rmii_txd,

    // IRQ
    output            uart_irq,
    output            spi_irq,
    output            mac_irq,

    // OVIS external APB (PLIC, CSI, VENC, Crypto, VDMA)
    output            ovis_psel,
    output            ovis_penable,
    output   [ 31: 0] ovis_paddr,
    output            ovis_pwrite,
    output   [  3: 0] ovis_pstrb,
    output   [  2: 0] ovis_pprot,
    output   [ 31: 0] ovis_pwdata,
    input    [ 31: 0] ovis_prdata,
    input             ovis_pslverr,
    input             ovis_pready
);

apb_intf uart_apb();
apb_intf spi_apb();
apb_intf mac_apb();
apb_intf nna_apb();
apb_intf ovis_apb_intf();

peri_apb_conn u_peri_apb_conn (
    .peri_apb ( s_apb_intf           ),
    .uart_apb ( uart_apb.master      ),
    .spi_apb  ( spi_apb.master       ),
    .mac_apb  ( mac_apb.master       ),
    .nna_apb  ( nna_apb.master       ),
    .ovis_apb ( ovis_apb_intf.master )
);

// Bridge ovis_apb interface to flat ports
assign ovis_psel    = ovis_apb_intf.psel;
assign ovis_penable = ovis_apb_intf.penable;
assign ovis_paddr   = ovis_apb_intf.paddr;
assign ovis_pwrite  = ovis_apb_intf.pwrite;
assign ovis_pstrb   = ovis_apb_intf.pstrb;
assign ovis_pprot   = ovis_apb_intf.pprot;
assign ovis_pwdata  = ovis_apb_intf.pwdata;
assign ovis_apb_intf.prdata  = ovis_prdata;
assign ovis_apb_intf.pslverr = ovis_pslverr;
assign ovis_apb_intf.pready  = ovis_pready;

uart u_uart(
    .clk        ( clk            ),
    .rstn       ( rstn           ),
    .s_apb_intf ( uart_apb.slave ),

    .irq_out    ( uart_irq       ),
    .uart_rx    ( uart_rx        ),
    .uart_tx    ( uart_tx        )
);


spi_core u_spi_core (
    .clk        ( clk            ),
    .rstn       ( rstn           ),
    .s_apb_intf ( spi_apb.slave  ),

    // SPI interface
    .sclk       ( sclk           ),
    .nss        ( nss            ),
    .mosi       ( mosi           ),
    .miso       ( miso           ),

    // DMA
    .m_axi_intf ( m_dma_axi_intf ),

    // Interrupt
    .irq_out    ( spi_irq        )
);

mac u_mac (
    .clk         ( clk           ),
    .rstn        ( rstn          ),
    .s_apb_intf  ( mac_apb.slave ),

    // RMII interface
    .rmii_refclk ( rmii_refclk   ),
    .rmii_crsdv  ( rmii_crsdv    ),
    .rmii_rxd    ( rmii_rxd      ),
    .rmii_txen   ( rmii_txen     ),
    .rmii_txd    ( rmii_txd      ),

    // Interrupt
    .irq_out     ( mac_irq       )
);

// OVIS-1: Neural Network Accelerator
`include "ovis_config.svh"
nna_unit u_nna (
    .clk     ( clk                      ),
    .rstn    ( rstn                     ),
    .psel    ( nna_apb.slave.psel       ),
    .penable ( nna_apb.slave.penable    ),
    .paddr   ( nna_apb.slave.paddr      ),
    .pwrite  ( nna_apb.slave.pwrite     ),
    .pstrb   ( nna_apb.slave.pstrb      ),
    .pwdata  ( nna_apb.slave.pwdata     ),
    .prdata  ( nna_apb.slave.prdata     ),
    .pready  ( nna_apb.slave.pready     ),
    .pslverr ( nna_apb.slave.pslverr    ),
    .irq     (                          )   // TODO: connect to interrupt controller
);

endmodule
