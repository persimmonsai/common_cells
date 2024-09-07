//
// Author: Eugene Feinberg <uge@persimmons.ai>
//

module stream_fifo_segmented #(
    /// FIFO is in fall-through mode
    /// Applied to each segment
    parameter bit          FALL_THROUGH     = 1'b0,
    /// Default data width if the fifo is of type logic
    parameter int unsigned DATA_WIDTH       = 32,
    /// Depth can be arbitrary from 0 to 2**32
    parameter int unsigned DEPTH            = 8,
    parameter type         T                = logic [DATA_WIDTH-1:0],
    // Split FIFO into individual segments of at most MAX_SEGMENT_SIZE
    parameter int unsigned MAX_SEGMENT_SIZE = DEPTH,
    // Flag to balance size of FIFO segments rather than leave remainder
    // as last segment
    parameter int unsigned BALANCE_SEGMENTS = 0,
    // DO NOT OVERWRITE THIS PARAMETER
    parameter int unsigned ADDR_DEPTH  = (DEPTH > 1) ? $clog2(DEPTH) : 1
)  (
    input  logic                  clk_i,      // Clock
    input  logic                  rst_ni,     // Asynchronous reset active low
    input  logic                  flush_i,    // flush the fifo
    input  logic                  testmode_i, // test_mode to bypass clock gating
    output logic [ADDR_DEPTH-1:0] usage_o,    // fill pointer
    // input interface
    input  T                      data_i,     // data to push into the fifo
    input  logic                  valid_i,    // input data valid
    output logic                  ready_o,    // fifo is not full
    // output interface
    output T                      data_o,     // output data
    output logic                  valid_o,    // fifo is not empty
    input  logic                  ready_i     // pop head from fifo
);

    localparam int unsigned CMaxSegmentSize = MAX_SEGMENT_SIZE > DEPTH ? DEPTH : MAX_SEGMENT_SIZE;
    localparam int unsigned FifoSegments = (DEPTH + CMaxSegmentSize - 1)/CMaxSegmentSize;

    typedef struct {
        T data_i;
        T data_o;
        logic valid_i;
        logic valid_o;
        logic ready_i;
        logic ready_o;
        logic [$clog2(CMaxSegmentSize)-1:0] usage_o;
    } segment_if_t;

    segment_if_t segment_if[FifoSegments];

    for (genvar i=0; i<FifoSegments; i=i+1) begin : gen_segments

        // Head element external connectivity
        if (i==0) begin : gen_connect_head
            assign segment_if[0].data_i  = data_i;
            assign segment_if[0].valid_i = valid_i;
            assign ready_o               = segment_if[0].ready_o;
        end

        // Not first element
        if ((i!=0) && (FifoSegments > 1)) begin : gen_connect_middle_segment
            assign segment_if[i].valid_i   = segment_if[i-1].valid_o;
            assign segment_if[i].data_i    = segment_if[i-1].data_o;
            assign segment_if[i-1].ready_i = segment_if[i].ready_o;
        end

        // Tail element external connectivity
        if (i==FifoSegments-1) begin : gen_connect_tail
            assign data_o                = segment_if[i].data_o;
            assign valid_o               = segment_if[i].valid_o;
            assign segment_if[i].ready_i = ready_i;
        end

        localparam int unsigned SegmentDepth =
            (BALANCE_SEGMENTS == 1) ? (((i+1)*CMaxSegmentSize)<=DEPTH ?
                                                (DEPTH / FifoSegments) :
                                                DEPTH - (i*(DEPTH / FifoSegments))) :
                                      (((i+1)*CMaxSegmentSize)<=DEPTH ?
                                                CMaxSegmentSize :
                                                (DEPTH % CMaxSegmentSize));

        localparam int CSegmentDepth = SegmentDepth == 1 ? 2 : SegmentDepth;
        logic [$clog2(CSegmentDepth)-1:0] segment_usage;

        stream_fifo #(
            .FALL_THROUGH  ( FALL_THROUGH          ),
            .DATA_WIDTH    ( DATA_WIDTH            ),
            .DEPTH         ( SegmentDepth          ),
            .T             ( T                     )
        ) fifo_i (
            .clk_i         ( clk_i                 ),
            .rst_ni        ( rst_ni                ),

            .flush_i       ( flush_i               ),
            .testmode_i    ( testmode_i            ),
            .usage_o       ( segment_usage         ),

            .data_i        ( segment_if[i].data_i  ),
            .valid_i       ( segment_if[i].valid_i ),
            .ready_o       ( segment_if[i].ready_o ),

            .data_o        ( segment_if[i].data_o  ),
            .valid_o       ( segment_if[i].valid_o ),
            .ready_i       ( segment_if[i].ready_i )
        );

        assign segment_if[i].usage_o = segment_usage;

    end

    // Should be pruned if not used during logic synthesis
    // Anticipated use of the segmented fifo will distribute segments
    // spatially so a reduction sum may run counter to those
    // goals.
    always_comb begin
        automatic integer s;
        usage_o = 0;
        for (s=0; s<FifoSegments; s=s+1) begin
            usage_o = usage_o + {{$bits(usage_o)-$bits(segment_if[s].usage_o){1'b0}},
                                 {segment_if[s].usage_o}};
        end
    end

endmodule
