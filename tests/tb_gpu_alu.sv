`timescale 1ns/1ps
module tb_gpu_alu;
    reg [3:0] operation;
    reg [31:0] lhs,rhs;
    wire [31:0] result;
    wire [3:0] flags;
    reg [31:0] boundary [0:7];
    reg [31:0] seed=32'h7102F35A;
    integer checks=0, a,b,n,op;
    gpu_alu dut (.*);

    task automatic exact(input reg [3:0] code,input reg [31:0] x,y,wanted,
                         input reg [3:0] wanted_flags);
        begin
            operation=code; lhs=x; rhs=y; #1;
            if(result !== wanted || flags !== wanted_flags)
                $fatal(1,"ULA op=%x x=%08x y=%08x got=%08x flags=%x expected=%08x/%x",
                       code,x,y,result,flags,wanted,wanted_flags);
            checks=checks+1;
        end
    endtask

    // Reference uses full-width integer mathematics, independent from RTL
    // overflow bit equations; shifts count individual bits leaving the word.
    task automatic reference(input reg [3:0] code,input reg [31:0] x,y);
        reg [31:0] wanted,shifted;
        reg z,nflag,c,v;
        longint signed sx,sy,full;
        longint unsigned ux,uy,total;
        integer amount,k;
        begin
            sx=$signed(x); sy=$signed(y); ux=x; uy=y;
            wanted=0; c=0; v=0;
            case(code)
                1,10: begin
                    full=sx+sy; total=ux+uy; wanted=total[31:0];
                    c=(total>64'hFFFFFFFF);
                    v=(full>64'sd2147483647 || full< -64'sd2147483648);
                end
                2,8: begin
                    full=sx-sy; wanted=full[31:0]; c=(ux>=uy);
                    v=(full>64'sd2147483647 || full< -64'sd2147483648);
                end
                3: wanted=x&y;
                4,15: wanted=x|y;
                5: wanted=x^y;
                6,7: begin
                    amount=y%32; shifted=x;
                    for(k=0;k<amount;k=k+1) begin
                        if(code==6) begin c=shifted[31]; shifted={shifted[30:0],1'b0}; end
                        else begin c=shifted[0]; shifted={1'b0,shifted[31:1]}; end
                    end
                    wanted=shifted;
                end
                default: $fatal(1,"Reference operation unsupported");
            endcase
            z=(wanted==0); nflag=wanted[31];
            exact(code,x,y,wanted,{v,c,nflag,z});
            if(code==8 && ((flags[1]^flags[3]) !== (sx<sy)))
                $fatal(1,"Signed CMP condition disagrees with integer comparison");
        end
    endtask

    initial begin
        exact(1,32'hFFFFFFFF,1,0,4'h5);
        exact(1,32'h7FFFFFFF,1,32'h80000000,4'hA);
        exact(1,32'h80000000,32'h80000000,0,4'hD);
        exact(2,0,1,32'hFFFFFFFF,4'h2);
        exact(2,32'h80000000,1,32'h7FFFFFFF,4'hC);
        exact(2,32'h7FFFFFFF,32'hFFFFFFFF,32'h80000000,4'hA);
        exact(8,42,42,0,4'h5);
        exact(6,32'h80000001,0,32'h80000001,4'h2);
        exact(6,32'h80000001,1,2,4'h4);
        exact(6,3,31,32'h80000000,4'h6);
        exact(6,32'h80000001,32,32'h80000001,4'h2);
        exact(7,32'h80000001,0,32'h80000001,4'h2);
        exact(7,32'h80000001,1,32'h40000000,4'h4);
        exact(7,32'h40000000,31,0,4'h5);
        exact(7,32'h80000001,63,1,4'h0);
        boundary[0]=0; boundary[1]=1; boundary[2]=32'hFFFFFFFF;
        boundary[3]=32'h80000000; boundary[4]=32'h7FFFFFFF;
        boundary[5]=32'h80000001; boundary[6]=32'h7FFFFFFE; boundary[7]=32'hFFFF0000;
        for(a=0;a<8;a=a+1) for(b=0;b<8;b=b+1) begin
            reference(1,boundary[a],boundary[b]);
            reference(2,boundary[a],boundary[b]);
            reference(8,boundary[a],boundary[b]);
        end
        for(n=0;n<512;n=n+1) begin
            seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]}; lhs=seed;
            seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]}; rhs=seed;
            for(op=1;op<=8;op=op+1) reference(op,lhs,rhs);
            reference(10,lhs,rhs); reference(15,lhs,rhs);
        end
        $display("PASS tb_gpu_alu: %0d arithmetic/logic/shift cases; signed comparison, carry and overflow",checks);
        $finish;
    end
    initial begin #20000; $fatal(1,"ULA timeout"); end
endmodule
