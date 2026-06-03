
// Absolute value function for 13-bit signed integers
function automatic logic signed [12:0] abs_13b (input logic signed [12:0] val);
    abs_13b = (val[12]) ? (~val +1'b1) : val;
endfunction

function automatic logic signed [11:0] abs_12b (input logic signed [11:0] val);
    abs_12b = (val[11]) ? (~val +1'b1) : val;
endfunction

function automatic logic signed [10:0] abs_11b (input logic signed [10:0] val);
    abs_11b = (val[10]) ? (~val +1'b1) : val;
endfunction

function automatic logic signed [20:0] abs_21b (input logic signed [20:0] val);
    abs_21b = (val[20]) ? (~val +1'b1) : val;
endfunction

function automatic logic signed [41:0] abs_42b (input logic signed [41:0] val);
    abs_42b = (val[41]) ? (~val +1'b1) : val;
endfunction