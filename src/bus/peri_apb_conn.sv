module peri_apb_conn (
    apb_intf.slave  peri_apb,
    apb_intf.master uart_apb,
    apb_intf.master spi_apb,
    apb_intf.master mac_apb,
    apb_intf.master nna_apb,     // OVIS-1: NNA at offset 0x3000 (regs + ORAM)
    apb_intf.master ovis_apb     // OVIS-1: external peripheral bus (PLIC, CSI, VENC, Crypto, VDMA)
);

// Address decode — top-level region select:
// OVIS external peripherals: addr >= 0x0C00_0000 (PLIC) or addr >= 0x2000_0000 (ISP/VENC/Crypto/CSI/VDMA)
// Legacy peripherals: addr in [0x1000_0000, 0x1008_0000)
wire ovis_sel = (peri_apb.paddr[31:26] == 6'b000011)         // 0x0C00_0000 - 0x0FFF_FFFF (PLIC)
              | (peri_apb.paddr[31:24] == 8'h20);             // 0x2000_0000 - 0x20FF_FFFF (OVIS peri)

// Legacy decode (unchanged for NNA + UART/SPI/MAC at 0x1000_xxxx):
// NNA occupies 0x3000+ (regs at 0x3000-0x3FFF, ORAM at 0x4000+)
// NNA selected when paddr[13:12]==11 OR paddr[14]==1
// Otherwise decode [13:12] for legacy peripherals:
//   00 = UART  (0x10000000)
//   01 = SPI   (0x10001000) + DMA (0x10001800)
//   10 = MAC   (0x10002000)
wire nna_sel = !ovis_sel && ((peri_apb.paddr[13:12] == 2'b11) || peri_apb.paddr[14]);
wire [1:0] peri_sel = peri_apb.paddr[13:12];
wire legacy_sel = !ovis_sel && !nna_sel;

assign uart_apb.psel    = legacy_sel && (peri_sel == 2'b00) && peri_apb.psel;
assign uart_apb.penable = legacy_sel && (peri_sel == 2'b00) && peri_apb.penable;
assign uart_apb.paddr   =  peri_apb.paddr;
assign uart_apb.pwrite  =  peri_apb.pwrite;
assign uart_apb.pstrb   =  peri_apb.pstrb;
assign uart_apb.pprot   =  peri_apb.pprot;
assign uart_apb.pwdata  =  peri_apb.pwdata;

assign spi_apb.psel     = legacy_sel && (peri_sel == 2'b01) && peri_apb.psel;
assign spi_apb.penable  = legacy_sel && (peri_sel == 2'b01) && peri_apb.penable;
assign spi_apb.paddr    =  peri_apb.paddr;
assign spi_apb.pwrite   =  peri_apb.pwrite;
assign spi_apb.pstrb    =  peri_apb.pstrb;
assign spi_apb.pprot    =  peri_apb.pprot;
assign spi_apb.pwdata   =  peri_apb.pwdata;

assign mac_apb.psel     = legacy_sel && (peri_sel == 2'b10) && peri_apb.psel;
assign mac_apb.penable  = legacy_sel && (peri_sel == 2'b10) && peri_apb.penable;
assign mac_apb.paddr    =  peri_apb.paddr;
assign mac_apb.pwrite   =  peri_apb.pwrite;
assign mac_apb.pstrb    =  peri_apb.pstrb;
assign mac_apb.pprot    =  peri_apb.pprot;
assign mac_apb.pwdata   =  peri_apb.pwdata;

// NNA receives local offset from 0x10003000 (subtract 0x3000 from lower bits)
assign nna_apb.psel     = nna_sel && peri_apb.psel;
assign nna_apb.penable  = nna_sel && peri_apb.penable;
assign nna_apb.paddr    = peri_apb.paddr - 32'h10003000;
assign nna_apb.pwrite   =  peri_apb.pwrite;
assign nna_apb.pstrb    =  peri_apb.pstrb;
assign nna_apb.pprot    =  peri_apb.pprot;
assign nna_apb.pwdata   =  peri_apb.pwdata;

// OVIS external APB — pass through full address (bridge handles decode)
assign ovis_apb.psel    = ovis_sel && peri_apb.psel;
assign ovis_apb.penable = ovis_sel && peri_apb.penable;
assign ovis_apb.paddr   =  peri_apb.paddr;
assign ovis_apb.pwrite  =  peri_apb.pwrite;
assign ovis_apb.pstrb   =  peri_apb.pstrb;
assign ovis_apb.pprot   =  peri_apb.pprot;
assign ovis_apb.pwdata  =  peri_apb.pwdata;

always_comb begin
    if (ovis_sel) begin
        peri_apb.prdata  = ovis_apb.prdata;
        peri_apb.pslverr = ovis_apb.pslverr;
        peri_apb.pready  = ovis_apb.pready;
    end else if (nna_sel) begin
        peri_apb.prdata  = nna_apb.prdata;
        peri_apb.pslverr = nna_apb.pslverr;
        peri_apb.pready  = nna_apb.pready;
    end else begin
        case (peri_sel)
            2'b01:   begin peri_apb.prdata = spi_apb.prdata;  peri_apb.pslverr = spi_apb.pslverr;  peri_apb.pready = spi_apb.pready;  end
            2'b10:   begin peri_apb.prdata = mac_apb.prdata;  peri_apb.pslverr = mac_apb.pslverr;  peri_apb.pready = mac_apb.pready;  end
            default: begin peri_apb.prdata = uart_apb.prdata; peri_apb.pslverr = uart_apb.pslverr; peri_apb.pready = uart_apb.pready; end
        endcase
    end
end

endmodule
