module error_counter (
    input  wire        pattern1,
    input  wire        pattern2,
    input  wire        clock,
    input  wire        reset,
    input  wire        enable,
    output reg  [11:0] errors,
    output reg         error_flag
);

always @(posedge clock or posedge reset) begin
    if (reset) begin
        errors     <= 12'b0;
        error_flag <= 1'b0;
    end
    else if (enable) begin
        if (errors == 12'hFFF) begin
            // Counter saturated - stop counting, flag stays set
            error_flag <= 1'b1;
        end
        else if (pattern1 != pattern2) begin
            errors <= errors + 1'b1;
        end
    end
end

endmodule