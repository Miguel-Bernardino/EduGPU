
// Absolute value function for 12-bit signed integers
function automatic logic signed [11:0] abs_12b (input logic signed [11:0] val);
    abs_12b = (val[11]) ? ~val : val;
endfunction

function automatic logic signed [10:0] abs_11b (input logic signed [10:0] val);
    abs_11b = (val[10]) ? ~val : val;
endfunction