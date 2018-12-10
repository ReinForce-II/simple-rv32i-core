`include "common.vh"
`include "alu.vh"

module core (
    clk,
    rstn,
    iaddr,
    idata,
    ivalid,
    daddr,
    drdata,
    drvalid,
    dwdata,
    dwe
);

input   wire    clk;
input   wire    rstn;
output  wire    [31:0]  iaddr;
input   wire    [31:0]  idata;
input   wire            ivalid;
output  reg     [31:0]  daddr;
input   wire    [31:0]  drdata;
input   wire            drvalid;
output  reg     [31:0]  dwdata;
output  reg     [3:0]   dwe;

reg     [31:0]  xreg    [0:31];

reg     [31:0]  inst;

reg     [31:0]  mcycle;

wire    [4:0]   i_rs1   =   inst[19:15];
wire    [4:0]   i_rs2   =   inst[24:20];
wire    [4:0]   i_rd    =   inst[11:7];
wire    [2:0]   i_fun3  =   inst[14:12];
wire    [6:0]   i_fun7  =   inst[31:25];
wire    [11:0]  i_iimm  =   inst[31:20];
wire    [11:0]  i_simm  =   {inst[31:25], inst[11:7]};
wire    [12:0]  i_bimm  =   {inst[31], inst[7], inst[30:25], inst[11:8], 1'h0};
wire    [31:0]  i_uimm  =   {inst[31:12], 12'h0};
wire    [20:0]  i_jimm  =   {inst[31], inst[19:12], inst[20], inst[30:21], 1'h0};

reg     [31:0]  pc;
reg     [3:0]   flush;
wire            halt;
reg             sub_stage;
assign halt = !ivalid || !drvalid;
assign iaddr = pc;

function [31:0] GET_XREG;
    input [4:0] REG;
    begin
        GET_XREG = REG ? xreg[REG] : 0;
        // GET_XREG = xreg[REG];
    end
endfunction

function [31:0] ALU;
    input   wire    [31:0]  a;
    input   wire    [31:0]  b;
    input   wire    [3:0]   op;
    begin
        case(op)
        `ALU_OP_ADD:    ALU = a + b;
        `ALU_OP_SUB:    ALU = a - b;
        `ALU_OP_SLL:    ALU = a << b[4:0];
        `ALU_OP_SLT:    ALU = $signed(a) < $signed(b);
        `ALU_OP_SLTU:   ALU = a < b;
        `ALU_OP_XOR:    ALU = a ^ b;
        `ALU_OP_SRL:    ALU = a >> b[4:0];
        `ALU_OP_SRA:    ALU = $signed(a) >>> b[4:0];
        `ALU_OP_OR:     ALU = a | b;
        `ALU_OP_AND:    ALU = a & b;
        // default:        ALU = 0;
        endcase
    end
endfunction

function [0:0] BALU;
    input   wire    [31:0]  a;
    input   wire    [31:0]  b;
    input   wire    [2:0]   op;
    begin
        case (op)
            `BALU_OP_EQ:    BALU = a == b ? 1 : 0;
            `BALU_OP_NE:    BALU = a != b ? 1 : 0;
            `BALU_OP_LT:    BALU = $signed(a) < $signed(b) ? 1 : 0;
            `BALU_OP_GE:    BALU = $signed(a) >= $signed(b) ? 1 : 0;
            `BALU_OP_LTU:   BALU = a < b ? 1 : 0;
            `BALU_OP_GEU:   BALU = a >= b ? 1 : 0;
            // default:        BALU = 0;
        endcase
    end
endfunction

always @ (posedge clk) begin
    if (!rstn) begin
        pc <= `RESET_VECTOR;
        inst <= 0;
        flush <= 0;
        sub_stage <= 0;

        daddr <= 0;
        dwdata <= 0;
        dwe <= 0;

        mcycle <= 0;
    end
    else begin
        mcycle <= mcycle + 1;

        flush <=    halt ? flush :
                    flush ? flush - 1 :
                    (
                        // inst ==? `INST_PATTERN_JAL ||
                        // inst ==? `INST_PATTERN_JALR ||
                        // inst ==? `INST_PATTERN_BRANCH
                        inst[6:0] == 'b1101111 ||
                        inst[6:0] == 'b1100111 ||
                        inst[6:0] == 'b1100011
                    ) ? 1 : 0;
        inst <=     halt ? inst :
                    flush ? 0 : (
                        // inst ==? `INST_PATTERN_LOAD
                        inst[6:0] == 'b0000011 ||
                        // inst ==? `INST_PATTERN_STORE
                        inst[6:0] == 'b0100011
                    ) ? inst : idata;
        if (!halt && !flush) begin
            if (
                // inst ==? `INST_PATTERN_JAL ||
                // inst ==? `INST_PATTERN_JALR ||
                // inst ==? `INST_PATTERN_BRANCH ||
                inst[6:0] == 'b1101111 ||
                inst[6:0] == 'b1100111 ||
                inst[6:0] == 'b1100011 ||
                // inst ==? `INST_PATTERN_LOAD
                inst[6:0] == 'b0000011 ||
                // inst ==? `INST_PATTERN_STORE
                inst[6:0] == 'b0100011
            ) begin
                // do nothing
            end
            else begin
                pc <= pc + 4;
            end
        end

        if (!halt && !flush && inst) begin
            casez (inst)
                `INST_PATTERN_LUI:      begin
                    xreg[i_rd] <= i_uimm;
                end
                `INST_PATTERN_AUIPC:    begin
                    xreg[i_rd] <= ALU(pc - 4, i_uimm, `ALU_OP_ADD);
                end
                `INST_PATTERN_JAL:      begin
                    xreg[i_rd] <= pc;
                    pc <= ALU(pc - 4, {{12{i_jimm[20]}}, i_jimm[19:0]}, `ALU_OP_ADD);
                end
                `INST_PATTERN_JALR:     begin
                    xreg[i_rd] <= pc;
                    pc <= ALU(GET_XREG(i_rs1), {{12{i_jimm[20]}}, i_jimm[19:0]}, `ALU_OP_ADD);
                end
                `INST_PATTERN_BRANCH:   begin
                    pc <= BALU(GET_XREG(i_rs1), GET_XREG(i_rs2), i_fun3) ? pc + {{20{i_bimm[12]}}, i_bimm[11:0]} - 4: pc;
                end
                `INST_PATTERN_LOAD:     begin
                    if (sub_stage == 0) begin
                        daddr <= ALU(GET_XREG(i_rs1), {{21{i_iimm[11]}}, i_iimm[10:0]}, `ALU_OP_ADD);
                        sub_stage <= 1;
                    end
                    else begin
                        xreg[i_rd] <= drdata;
                        pc <= pc + 4;
                        inst <= idata;
                        sub_stage <= 0;
                    end
                end
                `INST_PATTERN_STORE:    begin
                    if (sub_stage == 0) begin
                        daddr <= ALU(GET_XREG(i_rs1), {{21{i_simm[11]}}, i_simm[10:0]}, `ALU_OP_ADD);
                        dwdata <= GET_XREG(i_rs2);
                        dwe <= 15;
                        sub_stage <= 1;
                    end
                    else begin
                        dwe <= 0;
                        pc <= pc + 4;
                        inst <= idata;
                        sub_stage <= 0;
                    end
                end
                `INST_PATTERN_ALGI:     begin
                    if (i_fun3 == `ALU_OP_SLTU) begin
                        xreg[i_rd] <= ALU(GET_XREG(i_rs1), i_iimm, i_fun3);
                    end
                    else begin
                        xreg[i_rd] <= ALU(GET_XREG(i_rs1), {{21{i_iimm[11]}}, i_iimm[10:0]}, i_fun3);
                    end
                end
                `INST_PATTERN_ALG:      begin
                    xreg[i_rd] <= ALU(GET_XREG(i_rs1), GET_XREG(i_rs2), i_fun3);
                end
                `INST_PATTERN_SYSTEM:   begin
                    casez (inst)
                        `INST_PATTERN_CSRRW:
                            xreg[i_rd] <= mcycle;
                        `INST_PATTERN_CSRRS:
                            xreg[i_rd] <= mcycle;
                        `INST_PATTERN_CSRRC:
                            xreg[i_rd] <= mcycle;
                        `INST_PATTERN_CSRRWI:
                            xreg[i_rd] <= mcycle;
                        `INST_PATTERN_CSRRSI:
                            xreg[i_rd] <= mcycle;
                        `INST_PATTERN_CSRRCI:
                            xreg[i_rd] <= mcycle;
                        // default:
                    endcase
                end
                // default: ;
            endcase
        end
    end
end

endmodule
