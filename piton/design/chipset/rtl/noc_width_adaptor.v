module noc_width_adaptor #(
    parameter INPUT_WIDTH = 64,
    parameter OUTPUT_WIDTH =64
)(
    input                                  flit_val_i,
    input  [INPUT_WIDTH-1:0]               flit_data_i,
    output                                 flit_rdy_o,

    output                                 flit_val_o,
    output  [OUTPUT_WIDTH-1:0]             flit_data_o,
    input                                  flit_rdy_i,
    input                                  rst_n,
    input                                  clk
);

genvar i;
generate
if ( INPUT_WIDTH == OUTPUT_WIDTH) begin : bypass
    assign flit_val_o  = flit_val_i;
    assign flit_data_o = flit_data_i;
    assign flit_rdy_o  = flit_rdy_i;
end else if(INPUT_WIDTH > OUTPUT_WIDTH) begin : serialer

    wire is_tail_out;

    tail_hdr_detect #(
        .FLIT_WIDTH(OUTPUT_WIDTH)
    ) detect_out (
        .reset      (~rst_n),
        .clk        (clk ),
        .flit_in    (flit_data_o),
        .valid      (flit_val_o ),
        .ready      (flit_rdy_i ),
        .is_tail    (is_tail_out),
        .is_header  ( )
    );

    localparam
        CHANEL_WORLD_NUM = INPUT_WIDTH/64,
        BUFF_NUM = INPUT_WIDTH / OUTPUT_WIDTH, //should be power of 2
        CNT_W    = $clog2(BUFF_NUM);

    wire [OUTPUT_WIDTH-1:0] in_array [BUFF_NUM-1 : 0];
    reg [CNT_W-1 : 0] counter;


    for (i=0;i<BUFF_NUM;i=i+1) begin :sep
        assign in_array [i] = flit_data_i [(i+1)*OUTPUT_WIDTH-1 : i*OUTPUT_WIDTH];
    end

    always @(posedge clk)begin
        if(!rst_n) begin
            counter <= {CNT_W{1'b0}};
        end else begin
            if (flit_val_o & flit_rdy_i) begin
                if(is_tail_out)counter<={CNT_W{1'b0}};
                else counter<=counter+1'b1;
            end
        end
    end

    assign flit_data_o = in_array [counter];
    assign flit_val_o  = flit_val_i;
    assign flit_rdy_o  = (counter==BUFF_NUM-1 || is_tail_out==1'b1)?  flit_rdy_i : 1'b0;

end else begin : parallelr

    wire is_tail_in;
    tail_hdr_detect #(
        .FLIT_WIDTH(INPUT_WIDTH)
    ) detect_in (
        .reset      (~rst_n),
        .clk        (clk ),
        .flit_in    (flit_data_i),
        .valid      (flit_val_i ),
        .ready      (flit_rdy_o ),
        .is_tail    (is_tail_in),
        .is_header  ( )
    );

    localparam
        CHANEL_WORLD_NUM = INPUT_WIDTH/64,
        BUFF_NUM = OUTPUT_WIDTH/INPUT_WIDTH, //should be power of 2
        CNT_W    = $clog2(BUFF_NUM);

    reg [CNT_W-1 : 0] counter;
    reg [INPUT_WIDTH-1:0] buff_array [BUFF_NUM-2 : 0];

    for (i=0;i<BUFF_NUM-1;i=i+1) begin : buff
        always @(posedge clk) begin
            if(!rst_n) begin
                buff_array [i] <= {INPUT_WIDTH{1'b0}};
            end else
            if( flit_val_i & flit_rdy_o) begin 
                if(counter == i) buff_array [i] <= flit_data_i;
                else if (counter < i) buff_array [i] <=  {INPUT_WIDTH{1'b0}}; //reset the rest of flit 
            end           
        end
        assign flit_data_o [(i+1)*INPUT_WIDTH-1 : i*INPUT_WIDTH] =(counter == i)? flit_data_i : buff_array [i];
    end
    assign flit_data_o [OUTPUT_WIDTH-1 : OUTPUT_WIDTH-INPUT_WIDTH] = flit_data_i;

    always @(posedge clk)begin
        if(!rst_n) begin
            counter <= {CNT_W{1'b0}};
        end else begin
            if (flit_val_i & flit_rdy_o) begin
                if(is_tail_in)counter<={CNT_W{1'b0}};
                else counter<=counter+1'b1;
            end
        end
    end

   assign flit_val_o = flit_val_i && (counter==BUFF_NUM-1 || is_tail_in==1'b1 );
   assign flit_rdy_o  = (counter!=BUFF_NUM-1)?  1'b1 : flit_rdy_i;
end
endgenerate

endmodule


module tail_hdr_detect #(
    parameter FLIT_WIDTH=64
)(
    reset,
    clk,
    flit_in,
    valid,
    ready,
    is_tail,
    is_header
);
    input reset,clk;
    input valid,ready;
    input [FLIT_WIDTH-1 : 0] flit_in;
    output is_tail, is_header;

    localparam
        CHANEL_WORLD_NUM = FLIT_WIDTH/64;

    localparam  [1:0]
        HEADER = 1,
        BODY   = 2;
    reg [2:0] flit_type,flit_type_next;
    wire [`MSG_LENGTH_WIDTH-1       :0] length_in      =  flit_in [ `MSG_LENGTH ];
    reg  [`MSG_LENGTH_WIDTH-1       :0] remain, remain_next;

    always @ (*) begin
        remain_next = remain;
        flit_type_next = flit_type;
        if(valid & ready) begin
            case(flit_type)
            HEADER: begin
                if (length_in >= CHANEL_WORLD_NUM ) begin
                        flit_type_next = BODY;
                        remain_next = length_in  - CHANEL_WORLD_NUM;                  
                end
            end //HEADER
            BODY: begin
                if(remain < CHANEL_WORLD_NUM) begin
                        flit_type_next = HEADER;   
                end else if (remain >= CHANEL_WORLD_NUM ) begin
                        remain_next = remain  - CHANEL_WORLD_NUM;  
                end
            end //BODY
            endcase
        end
    end//always

    always @ (posedge clk) begin
        if (reset)  begin
            remain <= {`MSG_LENGTH_WIDTH{1'b0}};
            flit_type <=HEADER;
        end else begin
            remain <= remain_next;
            flit_type <= flit_type_next;
        end
    end

    assign is_tail = (flit_type == HEADER)? (length_in < CHANEL_WORLD_NUM) : (remain < CHANEL_WORLD_NUM);
    assign is_header = (flit_type == HEADER);

endmodule


module piton_pck_monitor #(
    parameter MAX_PCK_SIZ =100,
    parameter INPUT_WIDTH = 64,
    parameter DIR = "IN",
    parameter NAME= ""
)(
    input  [7:0]                           id,
    input                                  valid,
    input  [INPUT_WIDTH-1:0]               flit_in,
    input                                  ready,
    input reset,clk
);

    localparam  WORLD_NUM = INPUT_WIDTH/64;
    reg [INPUT_WIDTH-1:0]  data [MAX_PCK_SIZ : 0];

    wire tail,header;
    tail_hdr_detect #(
        .FLIT_WIDTH(INPUT_WIDTH)
    ) detect_in (
        .reset      (reset),
        .clk        (clk ),
        .flit_in    (flit_in),
        .valid      (valid ),
        .ready      (ready ),
        .is_tail    (tail),
        .is_header  (header)
    );



 localparam
        CHANEL_WORLD_NUM = INPUT_WIDTH/64;


    wire [`MSG_LENGTH_WIDTH-1       :0] length_in      =  flit_in [ `MSG_LENGTH ];
    reg  [`MSG_LENGTH_WIDTH-1       :0] len_reg;
    wire [`MSG_LENGTH_WIDTH-1       :0] pck_size;
    integer flit_cnt, pck_cnt;
    reg print_en;
    wire  [`MSG_TYPE_WIDTH-1:0] type_in = flit_in [`MSG_TYPE];
    reg   [`MSG_TYPE_WIDTH-1:0] type_reg;

    always @ (posedge clk) begin
        if (reset)  begin
            flit_cnt <=0;
            pck_cnt<=0;
            print_en<=1'b0;
        end else begin
            if(valid & ready & header) len_reg <=   length_in+1;
            if(valid & ready & header) type_reg <=   type_in;
            if(valid & ready) flit_cnt <= (tail)? 0 : flit_cnt+1;
            if(print_en)  print_the_pck();
            if(valid & ready & tail) begin
                pck_cnt<=pck_cnt+1;
                print_en<=1'b1;
            end else begin
                print_en<=1'b0;
            end
        end
    end


    always @(posedge clk) begin
        if(valid & ready) data[flit_cnt] <=   flit_in ;
    end

    assign pck_size =  len_reg;
/*
    wire [15*8-1:0] msg_type_string;
    l2_msg_type_parse parse(
        .msg_type(type_reg),
        .msg_type_string(msg_type_string)
    );
*/

    task automatic print_the_pck;
        integer i,j;
        reg [63 : 0] temp;
        begin
            $display("------------------------------------");
            if(DIR == "IN") $display("[->] %s in  id:%h",  NAME,id);
            else            $display("[<-] %s out id:%h",  NAME,id);
    //      $display("      #Hdr Time:    %d", hdr_time);
            $display("      #Pck:         %d", pck_cnt);
            $display("      #pck size:    %d", pck_size);
    //        $display("      #type:        %s", msg_type_string);
    //     $display("      #total Flit:  %d", flit_cnt);

            for(i=0; i<pck_size; i=i+1)begin
                    j=i % WORLD_NUM;
                    temp =  data[i/WORLD_NUM] >> (j*64);
                    $display("      Data%d:  %x",i, temp);
            end
    //      $display("      #Tail time:  %d",$time);
    $display("------------------------------------");
        end
    endtask


endmodule
