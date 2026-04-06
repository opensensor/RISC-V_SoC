// Pipelined 64×64 → 128-bit multiplier for RISC-V MUL/MULH/MULHU/MULHSU
//
// Decomposes the multiply into four 32×32 unsigned partial products,
// accumulated over a 3-stage pipeline.  Maps to 4 DSP48E2 cascades
// on Xilinx UltraScale+.
//
// Pipeline: 4 cycles (IDLE → PP → CROSS → FINAL → DONE)
//   Stage 1 (PP):    Four 32×32 partial products in parallel
//   Stage 2 (CROSS): Cross-term addition with carry
//   Stage 3 (FINAL): Final accumulation + sign correction
//   Stage 4 (DONE):  Result ready, okay asserted

module mul (
    input                      clk,
    input                      rstn,
    input                      trig,
    input                      flush,
    input                      signed1,
    input        [  `XLEN-1:0] src1,
    input                      signed2,
    input        [  `XLEN-1:0] src2,
    output logic [2*`XLEN-1:0] out,
    output logic               okay
);

// ========================================================================
// FSM
// ========================================================================

logic [2:0] cur_state, nxt_state;

localparam [2:0] STATE_IDLE  = 3'd0,
                 STATE_PP    = 3'd1,  // partial products
                 STATE_CROSS = 3'd2,  // cross-term sum
                 STATE_FINAL = 3'd3,  // final accumulation
                 STATE_DONE  = 3'd4;

always_ff @(posedge clk or negedge rstn) begin
    if (~rstn) cur_state <= STATE_IDLE;
    else       cur_state <= nxt_state;
end

always_comb begin
    nxt_state = cur_state;
    case (cur_state)
        STATE_IDLE:  nxt_state = trig  ? STATE_PP    : STATE_IDLE;
        STATE_PP:    nxt_state = flush ? STATE_IDLE   : STATE_CROSS;
        STATE_CROSS: nxt_state = flush ? STATE_IDLE   : STATE_FINAL;
        STATE_FINAL: nxt_state = flush ? STATE_IDLE   : STATE_DONE;
        STATE_DONE:  nxt_state = STATE_IDLE;
        default:     nxt_state = STATE_IDLE;
    endcase
end

assign okay = (cur_state == STATE_DONE);

// ========================================================================
// Stage 0: Capture operands — compute absolute values and sign
// ========================================================================

logic [`XLEN-1:0] abs_src1, abs_src2;
logic             result_negate;

// For signed operands, take absolute value and track sign
wire src1_neg = signed1 & src1[`XLEN-1];
wire src2_neg = signed2 & src2[`XLEN-1];

always_comb begin
    abs_src1 = src1_neg ? (~src1 + `XLEN'd1) : src1;
    abs_src2 = src2_neg ? (~src2 + `XLEN'd1) : src2;
end

// Result is negative if exactly one operand is negative
logic s0_negate;

always_ff @(posedge clk or negedge rstn) begin
    if (~rstn) begin
        s0_negate <= 1'b0;
    end else if (trig) begin
        s0_negate <= src1_neg ^ src2_neg;
    end
end

// ========================================================================
// Stage 1 (PP): Four 32×32 unsigned partial products
// ========================================================================
// For 64-bit unsigned A, B:
//   A = {A_hi, A_lo}  where A_hi = A[63:32], A_lo = A[31:0]
//   B = {B_hi, B_lo}
//   A × B = (A_hi × B_hi) << 64
//         + (A_hi × B_lo + A_lo × B_hi) << 32
//         + (A_lo × B_lo)

logic [31:0] a_lo, a_hi, b_lo, b_hi;

always_ff @(posedge clk) begin
    if (trig) begin
        a_lo <= abs_src1[31:0];
        a_hi <= abs_src1[63:32];
        b_lo <= abs_src2[31:0];
        b_hi <= abs_src2[63:32];
    end
end

// Partial products (registered — each maps to ~2 DSP48E2s)
logic [63:0] pp_ll, pp_lh, pp_hl, pp_hh;

always_ff @(posedge clk) begin
    pp_ll <= a_lo * b_lo;   // A_lo × B_lo
    pp_lh <= a_lo * b_hi;   // A_lo × B_hi
    pp_hl <= a_hi * b_lo;   // A_hi × B_lo
    pp_hh <= a_hi * b_hi;   // A_hi × B_hi
end

// Pipeline the negate flag
logic s1_negate;
always_ff @(posedge clk) begin
    s1_negate <= s0_negate;
end

// ========================================================================
// Stage 2 (CROSS): Cross-term addition
// ========================================================================
// cross_sum = pp_lh + pp_hl (64-bit + 64-bit → 65-bit with carry)

logic [64:0] cross_sum;   // 65-bit to capture carry
logic [63:0] s2_pp_ll, s2_pp_hh;
logic        s2_negate;

always_ff @(posedge clk) begin
    cross_sum <= {1'b0, pp_lh} + {1'b0, pp_hl};
    s2_pp_ll  <= pp_ll;
    s2_pp_hh  <= pp_hh;
    s2_negate <= s1_negate;
end

// ========================================================================
// Stage 3 (FINAL): Combine partial products + sign correction
// ========================================================================
// result[127:0] = pp_hh << 64
//               + cross_sum << 32
//               + pp_ll
//
// Layout:
//   [127:64] = pp_hh + cross_sum[64:32] + carry_from_lower
//   [ 63:32] = cross_sum[31:0] + pp_ll[63:32] + carry
//   [ 31: 0] = pp_ll[31:0]

logic [127:0] unsigned_result;

always_comb begin
    // Accumulate with proper alignment
    unsigned_result = {64'b0, s2_pp_ll}
                    + {31'b0, cross_sum, 32'b0}
                    + {s2_pp_hh, 64'b0};
end

always_ff @(posedge clk) begin
    if (s2_negate)
        out <= ~unsigned_result + 128'd1;  // Two's complement negate
    else
        out <= unsigned_result;
end

endmodule
