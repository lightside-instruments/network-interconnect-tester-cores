module pma_1000basex_rx #(
    parameter integer OVERSAMPLE = 4
)(
    input wire sample_clk,
    input wire rst,
    input wire serial_rx,
    input wire signal_detect,
    output wire nrz_bit,
    output wire bit_valid,
    output wire cdr_locked
);
    cdr_oversample_1000basex #(.OVERSAMPLE(OVERSAMPLE)) cdr (
        .sample_clk(sample_clk),.rst(rst),.serial_rx(serial_rx),
        .signal_detect(signal_detect),.nrz_bit(nrz_bit),
        .bit_valid(bit_valid),.locked(cdr_locked)
    );
endmodule
