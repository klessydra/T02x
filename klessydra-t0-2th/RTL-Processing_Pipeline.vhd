library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.riscv_klessydra.all;
use work.thread_parameters_klessydra.all;

entity Pipeline is
  port (
    pc_IF                      : in  std_logic_vector(31 downto 0);
    harc_IF                    : in  harc_range;
    irq_pending                : in  replicated_bit;
    csr_instr_done             : in  std_logic;
    csr_access_denied_o        : in  std_logic;
    csr_rdata_o                : in  std_logic_vector (31 downto 0);
    dbg_req_o                  : in  std_logic;
    dbg_halted_o               : in  std_logic;
    MSTATUS                    : in  replicated_32b_reg;
	served_irq     			   : out replicated_bit;
	WFI_Instr				   : out std_logic;
    reset_state                : out std_logic;
    misaligned_err             : out std_logic;
    pc_IE                      : out std_logic_vector(31 downto 0);
    set_branch_condition       : out std_logic;
    taken_branch               : out std_logic;
    set_except_condition       : out std_logic;
    set_mret_condition         : out std_logic;
    set_wfi_condition          : out std_logic;
    csr_instr_req              : out std_logic;
    instr_rvalid_IE            : out std_logic;
    csr_addr_i                 : out std_logic_vector (11 downto 0);
    csr_wdata_i                : out std_logic_vector (31 downto 0);
    csr_op_i                   : out std_logic_vector (2 downto 0);
    jump_instr                 : out std_logic;
    jump_instr_lat             : out std_logic;
    branch_instr               : out std_logic;
    branch_instr_lat           : out std_logic;
    data_valid_waiting_counter : out std_logic;
    harc_ID                    : out harc_range;
    harc_IE                    : out harc_range;
    harc_to_csr                : out harc_range;
    instr_word_IE              : out std_logic_vector(31 downto 0);
    PC_offset                  : out replicated_32b_reg;
    pc_except_value            : out replicated_32b_reg;
    dbg_ack_i                  : out std_logic;
    ebreak_instr               : out std_logic;
    data_addr_internal         : out std_logic_vector(31 downto 0);
    absolute_jump              : out std_logic;
    regfile                    : out regfile_replicated_array;
    clk_i                      : in  std_logic;
    rst_ni                     : in  std_logic;
    instr_req_o                : out std_logic;
    instr_gnt_i                : in  std_logic;
    instr_rvalid_i             : in  std_logic;
    instr_addr_o               : out std_logic_vector(31 downto 0);
    instr_rdata_i              : in  std_logic_vector(31 downto 0);
    data_req_o_wire_top        : out std_logic;
    data_gnt_i                 : in  std_logic;
    data_rvalid_i              : in  std_logic;
    data_we_o_wire_top         : out std_logic;
    data_be_o                  : out std_logic_vector(3 downto 0);
    data_addr_o                : out std_logic_vector(31 downto 0);
    data_wdata_o               : out std_logic_vector(31 downto 0);
    data_rdata_i               : in  std_logic_vector(31 downto 0);
    data_err_i                 : in  std_logic;
	irq_i               	   : in  std_logic;
    debug_halted_o             : out std_logic;
    fetch_enable_i             : in  std_logic;
    core_busy_o                : out std_logic
    );
end entity;


architecture Pipe of Pipeline is

  type fsm_IF_states is (normal, waiting);
  type fsm_IE_states is (sleep, reset, normal, data_valid_waiting, data_grant_waiting,
                         csr_instr_wait_state, debug, first_boot);
  signal state_IF, nextstate_IF : fsm_IF_states;
  signal state_IE, nextstate_IE : fsm_IE_states;
  signal instr_rvalid_state     : std_logic;
  signal busy_ID                : std_logic;
  signal busy_IE                : std_logic;
  signal fix_harc_ID            : std_logic_vector(1 downto 0);
  
  signal load_err, store_err : std_logic;

  signal pass_BEQ_ID   : std_logic;
  signal pass_BNE_ID   : std_logic;
  signal pass_BLT_ID   : std_logic;
  signal pass_BLTU_ID  : std_logic;
  signal pass_BGE_ID   : std_logic;
  signal pass_BGEU_ID  : std_logic;
  signal pass_SLTI_ID  : std_logic;
  signal pass_SLTIU_ID : std_logic;
  signal pass_SLT_ID   : std_logic;
  signal pass_SLTU_ID  : std_logic;

  signal pc_ID     : std_logic_vector(31 downto 0);
  signal pc_ID_lat : std_logic_vector(31 downto 0);

  signal instr_word_ID_lat      : std_logic_vector(31 downto 0);
  signal instr_rvalid_ID        : std_logic;
  signal decoded_instruction_IE : std_logic_vector(INSTR_SET_SIZE-1 downto 0);

  signal data_we_o_lat : std_logic;


  signal clock_cycle         : std_logic_vector(63 downto 0);
  signal external_counter    : std_logic_vector(63 downto 0);
  signal instruction_counter : std_logic_vector(63 downto 0);
  signal flush_cycle_count  : replicated_positive_integer;

  signal amo_load_skip : std_logic;
  signal amo_load_lat  : std_logic;
  signal amo_load      : std_logic;
  signal amo_store_lat : std_logic;
  signal amo_store     : std_logic;
  signal sw_mip        : std_logic;

  signal data_addr_internal_ID  : std_logic_vector(31 downto 0);
  signal data_addr_internal_lat : std_logic_vector(31 downto 0);
  signal data_be_internal       : std_logic_vector(3 downto 0);

  signal harc_IF_lat        : harc_range;
  signal harc_ID_lat        : harc_range;
  signal S_Imm_IE           : std_logic_vector(11 downto 0);
  signal I_Imm_IE           : std_logic_vector(11 downto 0);
  signal SB_Imm_IE          : std_logic_vector(11 downto 0);
  signal CSR_ADDR_IE        : std_logic_vector(11 downto 0);
  signal RS1_Addr_IE        : std_logic_vector(4 downto 0);
  signal RS2_Addr_IE        : std_logic_vector(4 downto 0);
  signal RD_Addr_IE         : std_logic_vector(4 downto 0);
  signal RS1_Data_IE        : std_logic_vector(31 downto 0);
  signal RS2_Data_IE        : std_logic_vector(31 downto 0);
  signal RD_Data_IE         : std_logic_vector(31 downto 0);

  signal data_we_o_wire          : std_logic;
  signal data_addr_internal_wire : std_logic_vector(31 downto 0);
  signal pc_IE_wire              : std_logic_vector(31 downto 0);
  signal instr_word_IE_wire      : std_logic_vector(31 downto 0);
  signal harc_ID_wire            : harc_range;
  signal harc_IE_wire            : harc_range;
  signal regfile_wire            : regfile_replicated_array;

begin

  data_we_o_wire_top <= data_we_o_wire;
  data_addr_internal <= data_addr_internal_wire;
  harc_ID            <= harc_ID_wire;
  harc_IE            <= harc_IE_wire;
  regfile            <= regfile_wire;
  pc_IE              <= pc_IE_wire;
  instr_word_IE      <= instr_word_IE_wire;


  assert THREAD_POOL_SIZE < 2**THREAD_ID_SIZE
    report "threading configuration not supported"
    severity error;

  load_err  <= data_gnt_i and data_err_i and not(data_we_o_wire);
  store_err <= data_gnt_i and data_err_i and data_we_o_wire;

  data_addr_o <= data_addr_internal_wire(31 downto 2) & "00";
  data_be_o <= to_stdlogicvector(to_bitvector(data_be_internal) sll
                                 to_integer(unsigned(data_addr_internal_wire(1 downto 0))));

  instr_addr_o <= pc_IF;


  debug_halted_o <= dbg_halted_o;


  core_busy_o <= '1' when (instr_rvalid_i or instr_rvalid_ID or instr_rvalid_IE) = '1' and rst_ni = '1' else '0';


  fsm_IF_nextstate : process(all)
  begin
    if rst_ni = '0' then
      instr_req_o  <= '0';
      nextstate_IF <= normal;
    else
      case state_IF is
        when normal =>
          if busy_ID = '0' then
            instr_req_o <= '1';
            if instr_gnt_i = '1' then
              nextstate_IF <= normal;
            else
              nextstate_IF <= waiting;
            end if;
          else
            instr_req_o  <= '0';
            nextstate_IF <= normal;
          end if;
        when waiting =>
          if busy_ID = '0' then
            instr_req_o <= '1';
            if instr_gnt_i = '1' then
              nextstate_IF <= normal;
            else
              nextstate_IF <= waiting;
            end if;
          else
            instr_req_o  <= '0';
            nextstate_IF <= normal;
          end if;

        when others =>
          nextstate_IF <= normal;
          instr_req_o  <= '0';
      end case;
    end if;
  end process;

  fsm_IF_register_state : process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      state_IF <= normal;
    elsif rising_edge(clk_i) then
      state_IF <= nextstate_IF;
    end if;
  end process;


  process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      pc_ID        <= (others => '0');
      harc_ID_wire <= 0;
    elsif rising_edge(clk_i) then
      if instr_gnt_i = '1' then
        pc_ID        <= pc_IF;
        harc_ID_wire <= harc_IF;
      end if;
    end if;
  end process;

  process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      instr_rvalid_state <= '0';
    elsif rising_edge(clk_i) then
      instr_rvalid_state <= busy_ID and (instr_rvalid_i or instr_rvalid_state);
    end if;
  end process;
  instr_rvalid_ID <= (instr_rvalid_i or instr_rvalid_state);

  instr_word_ID_lat  <= instr_rdata_i when instr_rvalid_i = '1';
  pc_ID_lat          <= pc_ID         when instr_rvalid_ID = '1' else (others => '0') when rst_ni = '0';
  harc_ID_lat        <= harc_ID_wire  when instr_rvalid_ID = '1' else 0 when rst_ni = '0';







  fsm_ID_sync : process(clk_i, rst_ni)

    variable OPCODE_wires  : std_logic_vector (6 downto 0);
    variable FUNCT3_wires  : std_logic_vector (2 downto 0);
    variable FUNCT7_wires  : std_logic_vector (6 downto 0);
    variable FUNCT12_wires : std_logic_vector (11 downto 0);

  begin

    OPCODE_wires  := OPCODE(instr_word_ID_lat);
    FUNCT3_wires  := FUNCT3(instr_word_ID_lat);
    FUNCT7_wires  := FUNCT7(instr_word_ID_lat);
    FUNCT12_wires := FUNCT12(instr_word_ID_lat);

    if rst_ni = '0' then
      pc_IE_wire      <= (others => '0');
      harc_IE_wire    <= 0;
      instr_rvalid_IE <= '0';
    elsif rising_edge(clk_i) then
      if busy_IE = '1' then
        null;
      elsif instr_rvalid_ID = '0' then
        instr_rvalid_IE <= '0';
      else
        instr_rvalid_IE    <= '1';
        instr_word_IE_wire <= instr_word_ID_lat;
        pc_IE_wire         <= pc_ID_lat;
        harc_IE_wire       <= harc_ID_lat;
        RS1_Addr_IE        <= std_logic_vector(to_unsigned(rs1(instr_word_ID_lat), 5));
        RS2_Addr_IE        <= std_logic_vector(to_unsigned(rs2(instr_word_ID_lat), 5));
        RD_Addr_IE         <= std_logic_vector(to_unsigned(rd(instr_word_ID_lat), 5));

        RS1_Data_IE <= regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat));
        RS2_Data_IE <= regfile_wire(harc_ID_lat)(rs2(instr_word_ID_lat));
        RD_Data_IE  <= regfile_wire(harc_ID_lat)(rd(instr_word_ID_lat));
      end if;
      if busy_IE /= '1' and instr_rvalid_ID /= '0' then
        pass_BEQ_ID   <= '0';
        pass_BNE_ID   <= '0';
        pass_BLT_ID   <= '0';
        pass_BLTU_ID  <= '0';
        pass_BGE_ID   <= '0';
        pass_BGEU_ID  <= '0';
        amo_load_skip <= '0';
        amo_load      <= '0';
        sw_mip        <= '0';
        if data_addr_internal_ID(31 downto 4) = x"0000FF0" then
          sw_mip <= '1';
        end if;
        if (signed(regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat))(31 downto 0)) = signed(regfile_wire(harc_ID_lat)(rs2(instr_word_ID_lat))(31 downto 0))) then
          pass_BEQ_ID <= '1';
        end if;
        if (signed(regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat))(31 downto 0)) /= signed(regfile_wire(harc_ID_lat)(rs2(instr_word_ID_lat))(31 downto 0))) then
          pass_BNE_ID <= '1';
        end if;
        if (signed(regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat))(31 downto 0)) < signed(regfile_wire(harc_ID_lat)(rs2(instr_word_ID_lat))(31 downto 0))) then
          pass_BLT_ID <= '1';
        end if;
        if (unsigned(regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat))(31 downto 0)) < unsigned(regfile_wire(harc_ID_lat)(rs2(instr_word_ID_lat))(31 downto 0))) then
          pass_BLTU_ID <= '1';
        end if;
        if (signed(regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat))(31 downto 0)) >= signed(regfile_wire(harc_ID_lat)(rs2(instr_word_ID_lat))(31 downto 0))) then
          pass_BGE_ID <= '1';
        end if;
        if (unsigned(regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat))(31 downto 0)) >= unsigned(regfile_wire(harc_ID_lat)(rs2(instr_word_ID_lat))(31 downto 0))) then
          pass_BGEU_ID <= '1';
        end if;

        case OPCODE_wires is
          when OP_IMM =>
            if(rd(instr_word_ID_lat) /= 0) then
              case FUNCT3_wires is
                when ADDI =>
                  decoded_instruction_IE <= ADDI_pattern;
                when SLTI =>
                  decoded_instruction_IE <= SLTI_pattern;
                when SLTIU =>
                  decoded_instruction_IE <= SLTIU_pattern;
                when ANDI =>
                  decoded_instruction_IE <= ANDI_pattern;
                when ORI =>
                  decoded_instruction_IE <= ORI_pattern;
                when XORI =>
                  decoded_instruction_IE <= XORI_pattern;
                when SLLI =>
                  decoded_instruction_IE <= SLLI_pattern;
                when SRLI_SRAI =>
                  case FUNCT7_wires is
                    when SRLI7 =>
                      decoded_instruction_IE <= SRLI7_pattern;
                    when SRAI7 =>
                      decoded_instruction_IE <= SRAI7_pattern;
                    when others =>
                      decoded_instruction_IE <= ILL_pattern;
                  end case;
                when others =>
                  decoded_instruction_IE <= ILL_pattern;
              end case;
            else
              decoded_instruction_IE <= NOP_pattern;
            end if;
          when LUI =>
            if (rd(instr_word_ID_lat) /= 0) then
              decoded_instruction_IE <= LUI_pattern;
            else
              decoded_instruction_IE <= NOP_pattern;
            end if;
          when AUIPC =>
            if (rd(instr_word_ID_lat) /= 0) then
              decoded_instruction_IE <= AUIPC_pattern;
            else
              decoded_instruction_IE <= NOP_pattern;
            end if;
          when OP =>
            if (rd(instr_word_ID_lat) /= 0) then
              case FUNCT3_wires is
                when ADD_SUB =>
                  case FUNCT7_wires is
                    when ADD7 =>
                      decoded_instruction_IE <= ADD7_pattern;
                    when SUB7 =>
                      decoded_instruction_IE <= SUB7_pattern;
                    when others =>
                      decoded_instruction_IE <= ILL_pattern;
                  end case;
                when SLT =>
                  decoded_instruction_IE <= SLT_pattern;
                when SLTU =>
                  decoded_instruction_IE <= SLTU_pattern;
                when ANDD =>
                  decoded_instruction_IE <= ANDD_pattern;
                when ORR =>
                  decoded_instruction_IE <= ORR_pattern;
                when XORR =>
                  decoded_instruction_IE <= XORR_pattern;
                when SLLL =>
                  decoded_instruction_IE <= SLLL_pattern;
                when SRLL_SRAA =>
                  case FUNCT7_wires is
                    when SRLL7 =>
                      decoded_instruction_IE <= SRLL7_pattern;
                    when SRAA7 =>
                      decoded_instruction_IE <= SRAA7_pattern;
                    when others =>
                      decoded_instruction_IE <= ILL_pattern;
                  end case;
                when others =>
                  decoded_instruction_IE <= ILL_pattern;
              end case;
            else
              decoded_instruction_IE <= NOP_pattern;
            end if;

          when JAL =>
            decoded_instruction_IE <= JAL_pattern;

          when JALR =>
            decoded_instruction_IE <= JALR_pattern;

          when BRANCH =>
            case FUNCT3_wires is
              when BEQ =>
                decoded_instruction_IE <= BEQ_pattern;
              when BNE =>
                decoded_instruction_IE <= BNE_pattern;
              when BLT =>
                decoded_instruction_IE <= BLT_pattern;
              when BLTU =>
                decoded_instruction_IE <= BLTU_pattern;
              when BGE =>
                decoded_instruction_IE <= BGE_pattern;
              when BGEU =>
                decoded_instruction_IE <= BGEU_pattern;
              when others =>
                decoded_instruction_IE <= ILL_pattern;
            end case;

          when LOAD =>
            if (rd(instr_word_ID_lat) /= 0) then
              case FUNCT3_wires is
                when LW =>
                  decoded_instruction_IE <= LW_pattern;
                when LH =>
                  decoded_instruction_IE <= LH_pattern;
                when LHU =>
                  decoded_instruction_IE <= LHU_pattern;
                when LB =>
                  decoded_instruction_IE <= LB_pattern;
                when LBU =>
                  decoded_instruction_IE <= LBU_pattern;
                when others =>
                  decoded_instruction_IE <= ILL_pattern;
              end case;
            else
              decoded_instruction_IE <= NOP_pattern;
            end if;

          when STORE =>
            case FUNCT3_wires is
              when SW =>
                decoded_instruction_IE <= SW_pattern;
              when SH =>
                decoded_instruction_IE <= SH_pattern;
              when SB =>
                decoded_instruction_IE <= SB_pattern;
              when others =>
                decoded_instruction_IE <= ILL_pattern;
            end case;

          when MISC_MEM =>
            case FUNCT3_wires is
              when FENCE =>
                decoded_instruction_IE <= FENCE_pattern;
              when FENCEI =>
                decoded_instruction_IE <= FENCEI_pattern;
              when others =>
                decoded_instruction_IE <= ILL_pattern;
            end case;

          when SYSTEM =>
            case FUNCT3_wires is
              when PRIV =>
                if (rs1(instr_word_ID_lat) = 0 and rd(instr_word_ID_lat) = 0) then
                  case FUNCT12_wires is
                    when ECALL =>
                      decoded_instruction_IE <= ECALL_pattern;
                    when EBREAK =>
                      decoded_instruction_IE <= EBREAK_pattern;
                    when mret =>
                      decoded_instruction_IE <= MRET_pattern;
                    when WFI =>
                      decoded_instruction_IE <= WFI_pattern;
                    when others =>
                      decoded_instruction_IE <= ILL_pattern;
                  end case;
                else
                  decoded_instruction_IE <= ILL_pattern;
                end if;
              when CSRRW =>
                decoded_instruction_IE <= CSRRW_pattern;
              when CSRRS =>
                if(rd(instr_word_ID_lat) /= 0) then
                  decoded_instruction_IE <= CSRRS_pattern;
                else
                  decoded_instruction_IE <= NOP_pattern;
                end if;
              when CSRRC =>
                if(rd(instr_word_ID_lat) /= 0) then
                  decoded_instruction_IE <= CSRRC_pattern;
                else
                  decoded_instruction_IE <= NOP_pattern;
                end if;
              when CSRRWI =>
                decoded_instruction_IE <= CSRRWI_pattern;
              when CSRRSI =>
                if(rd(instr_word_ID_lat) /= 0) then
                  decoded_instruction_IE <= CSRRSI_pattern;
                else
                  decoded_instruction_IE <= NOP_pattern;
                end if;
              when CSRRCI =>
                if(rd(instr_word_ID_lat) /= 0) then
                  decoded_instruction_IE <= CSRRCI_pattern;
                else
                  decoded_instruction_IE <= NOP_pattern;
                end if;
              when others =>
                decoded_instruction_IE <= ILL_pattern;
            end case;

          when AMO =>
            case FUNCT3_wires is
              when SINGLE =>
                if(rd(instr_word_ID_lat) /= 0) then
                  amo_load_skip          <= '0';
                  decoded_instruction_IE <= AMOSWAP_pattern;
                  if amo_store = '1' then
                    amo_load <= '0';
                  elsif amo_store = '0' then
                    amo_load <= '1';
                  end if;
                elsif (rd(instr_word_ID_lat) = 0) then
                  decoded_instruction_IE <= AMOSWAP_pattern;
                  amo_load_skip          <= '1';
                end if;
              when others =>
                decoded_instruction_IE <= ILL_pattern;
            end case;
          when others =>
            decoded_instruction_IE <= ILL_pattern;
        end case;

      end if;
    end if;
  end process;

  fsm_ID_comb : process(all)
  begin
    if busy_IE = '1' then
      busy_ID <= '1';
    else 
      busy_ID <= '0';
    end if;  
  end process;

  data_addr_internal_ID <= std_logic_vector(signed(regfile_wire(harc_ID_lat)(rs1(instr_word_ID_lat))) + signed(S_immediate(instr_word_ID_lat)));







  fsm_IE_sync : process(clk_i, rst_ni)

    variable row : line;

  begin
    if rst_ni = '0' then
      for index in 0 to 31
      loop
        for h in harc_range loop
          regfile_wire(h)(index) <= std_logic_vector(to_unsigned(0, 32));
        end loop;
      end loop;
      instruction_counter <= std_logic_vector(to_unsigned(0, 64));
      csr_instr_req       <= '0';
      csr_op_i            <= (others => '0');
      csr_wdata_i         <= (others => '0');
      csr_addr_i          <= (others => '0');
    elsif rising_edge(clk_i) then
      case state_IE is
        when sleep =>
          null;
        when reset =>
          null;
        when first_boot =>
          null;
        when debug =>
          null;
        when normal =>
          if instr_rvalid_IE = '0' or flush_cycle_count(harc_IE) /=0 then
          elsif irq_pending(harc_IE) = '1' then
          else
            instruction_counter <= std_logic_vector(unsigned(instruction_counter)+1);
            misaligned_err      <= '0';
            -- pragma translate_off
            hwrite(row, pc_IE_wire);
            write(row, '_');
            hwrite(row, instr_word_IE_wire);
            write(row, "   " & to_string(now));
            writeline(file_handler, row);
            -- pragma translate_on


            if decoded_instruction_IE(ADDI_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(signed(RS1_Data_IE)+
                                                             signed(I_immediate(instr_word_IE_wire)));

            elsif decoded_instruction_IE(SLTI_bit_position) = '1' then
              if (signed(RS1_Data_IE) < signed (I_immediate(instr_word_IE))) then
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(1, 32));
              else
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(0, 32));
              end if;

            elsif decoded_instruction_IE(SLTIU_bit_position) = '1' then
              if (unsigned(RS1_Data_IE) < unsigned (I_immediate(instr_word_IE))) then
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(1, 32));
              else
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(0, 32));
              end if;

            elsif decoded_instruction_IE(ANDI_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= RS1_Data_IE and I_immediate(instr_word_IE_wire);

            elsif decoded_instruction_IE(ORI_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= RS1_Data_IE or I_immediate(instr_word_IE_wire);

            elsif decoded_instruction_IE(XORI_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= RS1_Data_IE xor I_immediate(instr_word_IE_wire);

            elsif decoded_instruction_IE(SLLI_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                to_stdlogicvector(to_bitvector(RS1_Data_IE)
                                  sll to_integer(unsigned(SHAMT(instr_word_IE_wire))));

            elsif decoded_instruction_IE(SRLI7_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                to_stdlogicvector(to_bitvector(RS1_Data_IE)
                                  srl to_integer(unsigned(SHAMT(instr_word_IE_wire))));

            elsif decoded_instruction_IE(SRAI7_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                to_stdlogicvector(to_bitvector(RS1_Data_IE)
                                  sra to_integer(unsigned(SHAMT(instr_word_IE_wire))));

            elsif decoded_instruction_IE(LUI_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= U_immediate(instr_word_IE_wire);

            elsif decoded_instruction_IE(AUIPC_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(signed(U_immediate(instr_word_IE_wire))
                                                             + signed(pc_IE_wire));

            elsif decoded_instruction_IE(ADD7_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(signed(RS1_Data_IE)
                                                             + signed(RS2_Data_IE));

            elsif decoded_instruction_IE(SUB7_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(signed(RS1_Data_IE)
                                                             - signed(RS2_Data_IE));

            elsif decoded_instruction_IE(SLT_bit_position) = '1' then
              if (signed(RS1_Data_IE) < signed (RS2_Data_IE)) then
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(1, 32));
              else
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(0, 32));
              end if;

            elsif decoded_instruction_IE(SLTU_bit_position) = '1' then
              if (unsigned(RS1_Data_IE) < unsigned (RS2_Data_IE)) then
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(1, 32));
              else
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(to_unsigned(0, 32));
              end if;

            elsif decoded_instruction_IE(ANDD_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= RS1_Data_IE and RS2_Data_IE;

            elsif decoded_instruction_IE(ORR_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= RS1_Data_IE or RS2_Data_IE;

            elsif decoded_instruction_IE(XORR_bit_position) = '1' then
              regfile_wire(harc_IE)(rd(instr_word_IE)) <= RS1_Data_IE xor RS2_Data_IE;

            elsif decoded_instruction_IE(SLLL_bit_position) = '1' then
              
              regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                to_stdlogicvector(to_bitvector(RS1_Data_IE)
                                  sll to_integer(unsigned(RS2_Data_IE
                                                          (4 downto 0))));

            elsif decoded_instruction_IE(SRLL7_bit_position) = '1' then
              
              regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                to_stdlogicvector(to_bitvector(RS1_Data_IE)
                                  srl to_integer(unsigned(RS2_Data_IE
                                                          (4 downto 0))));

            elsif decoded_instruction_IE(SRAA7_bit_position) = '1' then
              
              regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                to_stdlogicvector(to_bitvector(RS1_Data_IE)
                                  sra to_integer(unsigned(RS2_Data_IE
                                                          (4 downto 0))));

            elsif decoded_instruction_IE(JAL_bit_position) = '1' or decoded_instruction_IE(JALR_bit_position) = '1' then
              if (rd(instr_word_IE_wire) /= 0) then
                regfile_wire(harc_IE)(rd(instr_word_IE)) <= std_logic_vector(unsigned(pc_IE_wire) + "100");
              else
                
                null;
              end if;



            elsif decoded_instruction_IE(BEQ_bit_position) = '1' then
              null;

            elsif decoded_instruction_IE(BNE_bit_position) = '1' then
              null;

            elsif decoded_instruction_IE(BLT_bit_position) = '1' then
              null;

            elsif decoded_instruction_IE(BLTU_bit_position) = '1' then
              null;

            elsif decoded_instruction_IE(BGE_bit_position) = '1' then
              null;

            elsif decoded_instruction_IE(BGEU_bit_position) = '1' then
              null;

            elsif decoded_instruction_IE(LW_bit_position) = '1' or (decoded_instruction_IE(AMOSWAP_bit_position) = '1' and amo_load = '1' and amo_load_skip = '0') then
              
              if(data_addr_internal_wire(1 downto 0) = "00") then
                if (load_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
                elsif (store_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
                end if;
              else
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= LOAD_MISALIGNED_EXCEPT_CODE;
                misaligned_err                       <= '1';
              end if;

            elsif decoded_instruction_IE(LH_bit_position) = '1' or decoded_instruction_IE(LHU_bit_position) = '1' then
              
              if(data_addr_internal_wire(0) = '0') then
                if (load_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
                elsif (store_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
                end if;
              else
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= LOAD_MISALIGNED_EXCEPT_CODE;
                misaligned_err                       <= '1';
              end if;

            elsif decoded_instruction_IE(LB_bit_position) = '1' or decoded_instruction_IE(LBU_bit_position) = '1' then
              
              if (load_err = '1') then
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
              elsif (store_err = '1') then
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
              end if;


            elsif decoded_instruction_IE(SW_bit_position) = '1' or (decoded_instruction_IE(AMOSWAP_bit_position) = '1' and (amo_store_lat = '1' or amo_load_skip = '1')) then
              

              if sw_mip = '1' then
                csr_op_i      <= CSRRW;
                csr_instr_req <= '1';
                csr_wdata_i   <= RS2_Data_IE;
                csr_addr_i    <= MIP_ADDR;

				for i in harc_range loop
                	if data_addr_internal_wire(3 downto 0) = std_logic_vector(to_unsigned((4*i),4)) then
                  	harc_to_csr <= i;
                	end if;
				end loop;
						
              elsif(data_addr_internal_wire(1 downto 0) = "00") then
                if (load_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
                elsif (store_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
                end if;
              else
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= STORE_MISALIGNED_EXCEPT_CODE;
                misaligned_err                       <= '1';
              end if;

            elsif decoded_instruction_IE(SH_bit_position) = '1' then
              
              if(data_addr_internal_wire(0) = '0') then
                if (load_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
                elsif (store_err = '1') then
                  pc_except_value(harc_IE_wire) <= pc_IE_wire;
                  csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
                end if;
              else
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= STORE_MISALIGNED_EXCEPT_CODE;
                misaligned_err                       <= '1';
              end if;

            elsif decoded_instruction_IE(SB_bit_position) = '1' then
              
              if (load_err = '1') then
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
              elsif (store_err = '1') then
                pc_except_value(harc_IE_wire) <= pc_IE_wire;
                csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
              end if;

            elsif decoded_instruction_IE(FENCE_bit_position) = '1' then
              
              null;

            elsif decoded_instruction_IE(FENCEI_bit_position) = '1' then
              
              null;

            elsif decoded_instruction_IE(ECALL_bit_position) = '1' then

              csr_wdata_i                          <= ECALL_EXCEPT_CODE;
              pc_except_value(harc_IE_wire) <= pc_IE_wire;

            elsif decoded_instruction_IE(EBREAK_bit_position) = '1' then
              
              null;

            elsif decoded_instruction_IE(MRET_bit_position) = '1' then
              
              null;

            elsif decoded_instruction_IE(WFI_bit_position) = '1' then
              
              null;

            elsif decoded_instruction_IE(CSRRW_bit_position) = '1' then

              csr_op_i      <= FUNCT3(instr_word_IE_wire);
              csr_instr_req <= '1';
              csr_wdata_i   <= RS1_Data_IE;
              csr_addr_i    <= std_logic_vector(to_unsigned(to_integer(unsigned(CSR_ADDR(instr_word_IE_wire))), 12));
              harc_to_csr   <= harc_IE_wire;

            elsif decoded_instruction_IE(CSRRC_bit_position) = '1' or decoded_instruction_IE(CSRRS_bit_position) = '1' then

              csr_op_i      <= FUNCT3(instr_word_IE_wire);
              csr_instr_req <= '1';
              csr_wdata_i   <= RS1_Data_IE;
              csr_addr_i    <= std_logic_vector(to_unsigned(to_integer(unsigned(CSR_ADDR(instr_word_IE_wire))), 12));
              harc_to_csr   <= harc_IE_wire;

            elsif decoded_instruction_IE(CSRRWI_bit_position) = '1' then
              csr_op_i      <= FUNCT3(instr_word_IE_wire);
              csr_instr_req <= '1';
              csr_wdata_i   <= std_logic_vector(resize(to_unsigned(rs1(instr_word_IE_wire), 5), 32));
              csr_addr_i    <= std_logic_vector(to_unsigned(to_integer(unsigned(CSR_ADDR(instr_word_IE_wire))), 12));
              harc_to_csr   <= harc_IE_wire;

            elsif decoded_instruction_IE(CSRRSI_bit_position) = '1'or decoded_instruction_IE(CSRRCI_bit_position) = '1' then

              csr_op_i      <= FUNCT3(instr_word_IE_wire);
              csr_instr_req <= '1';
              csr_wdata_i   <= std_logic_vector(resize(to_unsigned(rs1(instr_word_IE_wire), 5), 32));
              csr_addr_i    <= std_logic_vector(to_unsigned(to_integer(unsigned(CSR_ADDR(instr_word_IE_wire))), 12));
              harc_to_csr   <= harc_IE_wire;

            elsif decoded_instruction_IE(ILL_bit_position) = '1' then

              csr_wdata_i                          <= ILLEGAL_INSN_EXCEPT_CODE;
              pc_except_value(harc_IE_wire) <= pc_IE_wire;

            elsif decoded_instruction_IE(NOP_bit_position) = '1' then
              
              null;
            end if;

          end if;

        when data_valid_waiting =>
          if instr_rvalid_IE = '0' then
            null;
          else
            if (load_err = '1') then
              pc_except_value(harc_IE_wire) <= pc_IE_wire;
              csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
            elsif (store_err = '1') then
              pc_except_value(harc_IE_wire) <= pc_IE_wire;
              csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
            elsif (data_rvalid_i = '1' and (OPCODE(instr_word_IE_wire) = LOAD or OPCODE(instr_word_IE_wire) = AMO) and rd(instr_word_IE_wire) /= 0) then
              if decoded_instruction_IE(LW_bit_position) = '1' or (decoded_instruction_IE(AMOSWAP_bit_position) = '1' and amo_load = '1') then
                if(data_addr_internal_wire(1 downto 0) = "00") then
                  regfile_wire(harc_IE)(rd(instr_word_IE)) <= data_rdata_i;
                end if;
              elsif decoded_instruction_IE(LH_bit_position) = '1' then
                case data_addr_internal_wire(1 downto 0) is
                  when "00" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(signed(data_rdata_i(15 downto 0)), 32));
                  when "01" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(signed(data_rdata_i(23 downto 8)), 32));
                  when "10" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(signed(data_rdata_i(31 downto 16)), 32));
                  when others =>
                    null;
                end case;
              elsif decoded_instruction_IE(LHU_bit_position) = '1' then
                case data_addr_internal_wire(1 downto 0) is
                  when "00" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(unsigned(data_rdata_i(15 downto 0)), 32));
                  when "01" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(unsigned(data_rdata_i(23 downto 8)), 32));
                  when "10" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(unsigned(data_rdata_i(31 downto 16)), 32));
                  when others =>
                    null;
                end case;
              elsif decoded_instruction_IE(LB_bit_position) = '1' then
                case data_addr_internal_wire(1 downto 0) is
                  when "00" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(signed(data_rdata_i(7 downto 0)), 32));
                  when "01" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(signed(data_rdata_i(15 downto 8)), 32));
                  when "10" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(signed(data_rdata_i(23 downto 16)), 32));
                  when "11" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(signed(data_rdata_i(31 downto 24)), 32));
                  when others =>
                    null;
                end case;
              elsif decoded_instruction_IE(LBU_bit_position) = '1' then
                case data_addr_internal_wire(1 downto 0) is
                  when "00" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(unsigned(data_rdata_i(7 downto 0)), 32));
                  when "01" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(unsigned(data_rdata_i(15 downto 8)), 32));
                  when "10" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(unsigned(data_rdata_i(23 downto 16)), 32));
                  when "11" =>
                    
                    regfile_wire(harc_IE)(rd(instr_word_IE)) <=
                      std_logic_vector(resize(unsigned(data_rdata_i(31 downto 24)), 32));
                  when others =>
                    
                    null;
                end case;
              end if;
            end if;
          end if;
          
        when data_grant_waiting =>
          if instr_rvalid_IE = '0' then
            null;
          else
            if (load_err = '1') then

              pc_except_value(harc_IE_wire) <= pc_IE_wire;
              csr_wdata_i                          <= LOAD_ERROR_EXCEPT_CODE;
            elsif (store_err = '1') then

              pc_except_value(harc_IE_wire) <= pc_IE_wire;
              csr_wdata_i                          <= STORE_ERROR_EXCEPT_CODE;
            end if;
          end if;
          
        when csr_instr_wait_state =>
          csr_instr_req <= '0';
          if (csr_instr_done = '1' and csr_access_denied_o = '0') then
            if (rd(instr_word_IE_wire) /= 0) then

              regfile_wire(harc_IE)(rd(instr_word_IE)) <= csr_rdata_o;
            else
              
              null;
            end if;
          elsif (csr_instr_done = '1' and csr_access_denied_o = '1') then

            csr_wdata_i                          <= ILLEGAL_INSN_EXCEPT_CODE;
            pc_except_value(harc_IE_wire) <= pc_IE_wire;
          else
          end if;

      end case;
    end if;
  end process;

  fsm_IE_comb : process(all)

    variable PC_offset_wires                  : replicated_32b_reg;
    variable data_addr_internal_wires         : std_logic_vector (31 downto 0);
    variable data_wdata_o_wires               : std_logic_vector (31 downto 0);
    variable data_be_internal_wires           : std_logic_vector (3 downto 0);
    variable data_we_o_wires                  : std_logic;
    variable absolute_jump_wires              : std_logic;
    variable busy_IE_wires                    : std_logic;
    variable set_except_condition_wires       : std_logic;
    variable set_branch_condition_wires       : std_logic;
    variable taken_branch_wires               : std_logic;
    variable set_mret_condition_wires         : std_logic;
    variable set_wfi_condition_wires          : std_logic;
    variable jump_instr_wires                 : std_logic;
    variable branch_instr_wires               : std_logic;
    variable ebreak_instr_wires               : std_logic;
    variable dbg_ack_i_wires                  : std_logic;
    variable data_valid_waiting_counter_wires : std_logic;
	variable WFI_Instr_wires				  : std_logic;
    variable data_req_o_wires                 : std_logic;
    variable served_irq_wires                 : replicated_bit;
    variable nextstate_IE_wires               : fsm_IE_states;

  begin

    data_addr_internal_wires         := (others => '0');
    data_wdata_o_wires               := (others => '0');
    data_be_internal_wires           := (others => '0');
	served_irq_wires				 := (others => '0');
    data_we_o_wires                  := '0';
    absolute_jump_wires              := '0';
    busy_IE_wires                    := '0';
    set_except_condition_wires       := '0';
    set_branch_condition_wires       := '0';
    set_wfi_condition_wires          := '0';    
    taken_branch_wires               := '0';
    set_mret_condition_wires         := '0';
    jump_instr_wires                 := '0';
    branch_instr_wires               := '0';
    ebreak_instr_wires               := '0';
    dbg_ack_i_wires                  := '0';
    data_valid_waiting_counter_wires := '0';
	WFI_Instr_wires                  := '0';
    data_req_o_wires                 := '0';
    amo_store                        <= '0';
    amo_load_lat                     <= '0';
    nextstate_IE_wires               := sleep;
    reset_state                      <= '0';

    if rst_ni = '0' then
      if fetch_enable_i = '1' then
        null;
      else
        busy_IE_wires := '1';
      end if;
      nextstate_IE_wires := normal;
    else
      case state_IE is
        when sleep =>
          if dbg_req_o = '1' then
            dbg_ack_i_wires    := '1';
            busy_IE_wires      := '1';
            nextstate_IE_wires := sleep;
          elsif irq_i = '1' or fetch_enable_i = '1' then
            nextstate_IE_wires := normal;
          else
            busy_IE_wires      := '1';
            nextstate_IE_wires := sleep;
          end if;

        when reset =>
          reset_state <= '1';
          if dbg_req_o = '1' then
            dbg_ack_i_wires    := '1';
            busy_IE_wires      := '1';
            nextstate_IE_wires := reset;
          elsif fetch_enable_i = '0' then
            nextstate_IE_wires := reset;
            busy_IE_wires      := '1';
          else
            nextstate_IE_wires := normal;
          end if;

        when first_boot =>
          nextstate_IE_wires := normal;

        when debug =>
          dbg_ack_i_wires := '1';
          if dbg_req_o = '0' then
            nextstate_IE_wires := normal;
          else
            nextstate_IE_wires := debug;
            busy_IE_wires      := '1';
          end if;

        when normal =>
          if instr_rvalid_IE = '0' or flush_cycle_count(harc_IE) /=0  then
            nextstate_IE_wires := normal;
          elsif irq_pending(harc_IE)= '1' then
              nextstate_IE_wires         := normal;
              served_irq_wires(harc_IE) := '1';
              taken_branch_wires         := '1';
              if decoded_instruction_IE(WFI_bit_position) = '1' then
				WFI_Instr_wires		 := '1';
			  end if;
          else
 
 
            if decoded_instruction_IE(ADDI_bit_position) = '1' or decoded_instruction_IE(SLTI_bit_position) = '1'
              or decoded_instruction_IE(SLTIU_bit_position) = '1' or decoded_instruction_IE(ANDI_bit_position) = '1'
              or decoded_instruction_IE(ORI_bit_position) = '1' or decoded_instruction_IE(XORI_bit_position) = '1'
              or decoded_instruction_IE(SLLI_bit_position) = '1' or decoded_instruction_IE(SRLI7_bit_position) = '1'
              or decoded_instruction_IE(SRAI7_bit_position) = '1' then
              nextstate_IE_wires := normal;

            elsif decoded_instruction_IE(LUI_bit_position) = '1' or decoded_instruction_IE(AUIPC_bit_position) = '1' then
              nextstate_IE_wires := normal;

            elsif decoded_instruction_IE(ADD7_bit_position) = '1' or decoded_instruction_IE(SUB7_bit_position) = '1'
              or decoded_instruction_IE(SLT_bit_position) = '1' or decoded_instruction_IE(SLTU_bit_position) = '1'
              or decoded_instruction_IE(ANDD_bit_position) = '1' or decoded_instruction_IE(ORR_bit_position) = '1'
              or decoded_instruction_IE(XORR_bit_position) = '1' or decoded_instruction_IE(SLLL_bit_position) = '1'
              or decoded_instruction_IE(SRLL7_bit_position) = '1' or decoded_instruction_IE(SRAA7_bit_position) = '1' then
              nextstate_IE_wires := normal;

            elsif decoded_instruction_IE(FENCE_bit_position) = '1' or decoded_instruction_IE(FENCEI_bit_position) = '1' then
              nextstate_IE_wires := normal;

            elsif decoded_instruction_IE(JAL_bit_position) = '1' then
              nextstate_IE_wires                   := normal;
              jump_instr_wires                     := '1';
              set_branch_condition_wires           := '1';
              taken_branch_wires                   := '1';
              PC_offset_wires(harc_IE_wire) := UJ_immediate(instr_word_IE_wire);

            elsif decoded_instruction_IE(JALR_bit_position) = '1' then
              nextstate_IE_wires         := normal;
              set_branch_condition_wires := '1';
              taken_branch_wires         := '1';
              PC_offset_wires(harc_IE_wire) := std_logic_vector(signed(RS1_Data_IE)
                                                                       + signed(I_immediate(instr_word_IE_wire)))
                                                      and X"FFFFFFFE";
              jump_instr_wires    := '1';
              absolute_jump_wires := '1';

            elsif decoded_instruction_IE(BEQ_bit_position) = '1' then
              nextstate_IE_wires                   := normal;
              branch_instr_wires                   := '1';
              PC_offset_wires(harc_IE_wire) := SB_immediate(instr_word_IE_wire);
              if pass_BEQ_ID = '1' then
                set_branch_condition_wires := '1';
                taken_branch_wires         := '1';
              end if;

            elsif decoded_instruction_IE(BNE_bit_position) = '1' then
              nextstate_IE_wires                   := normal;
              branch_instr_wires                   := '1';
              PC_offset_wires(harc_IE_wire) := SB_immediate(instr_word_IE_wire);
              if pass_BNE_ID = '1' then
                set_branch_condition_wires := '1';
                taken_branch_wires         := '1';
              end if;

            elsif decoded_instruction_IE(BLT_bit_position) = '1' then
              nextstate_IE_wires                   := normal;
              branch_instr_wires                   := '1';
              PC_offset_wires(harc_IE_wire) := SB_immediate(instr_word_IE_wire);
              if pass_BLT_ID = '1' then
                set_branch_condition_wires := '1';
                taken_branch_wires         := '1';
              end if;

            elsif decoded_instruction_IE(BLTU_bit_position) = '1' then
              nextstate_IE_wires                   := normal;
              branch_instr_wires                   := '1';
              PC_offset_wires(harc_IE_wire) := SB_immediate(instr_word_IE_wire);
              if pass_BLTU_ID = '1' then
                set_branch_condition_wires := '1';
                taken_branch_wires         := '1';
              end if;

            elsif decoded_instruction_IE(BGE_bit_position) = '1' then
              nextstate_IE_wires                   := normal;
              branch_instr_wires                   := '1';
              PC_offset_wires(harc_IE_wire) := SB_immediate(instr_word_IE_wire);
              if pass_BGE_ID = '1' then
                set_branch_condition_wires := '1';
                taken_branch_wires         := '1';
              end if;

            elsif decoded_instruction_IE(BGEU_bit_position) = '1' then
              nextstate_IE_wires                   := normal;
              branch_instr_wires                   := '1';
              PC_offset_wires(harc_IE_wire) := SB_immediate(instr_word_IE_wire);
              if pass_BGEU_ID = '1' then
                set_branch_condition_wires := '1';
                taken_branch_wires         := '1';
              end if;

            elsif decoded_instruction_IE(LW_bit_position) = '1' or (decoded_instruction_IE(AMOSWAP_bit_position) = '1' and amo_store_lat = '0' and amo_load_skip = '0') then
              if amo_load = '0' then
                data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE) + signed(I_immediate(instr_word_IE_wire)));
              elsif amo_load = '1' then
                data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE));
                amo_load_lat             <= '1';
              end if;
              data_be_internal_wires := "1111";
              data_req_o_wires       := '1';
              data_we_o_wires        := '0';
              if(data_addr_internal_wires(1 downto 0) = "00") then
                if (load_err = '1') then
                  nextstate_IE_wires         := normal;
                  set_except_condition_wires := '1';
                  taken_branch_wires         := '1';
                elsif data_gnt_i = '1' then
                  nextstate_IE_wires := data_valid_waiting;
                  busy_IE_wires      := '1';
                else
                  nextstate_IE_wires := data_grant_waiting;
                  busy_IE_wires      := '1';
                end if;
              else
                set_except_condition_wires := '1';
                taken_branch_wires         := '1';
                busy_IE_wires              := '1';
              end if;

            elsif decoded_instruction_IE(LH_bit_position) = '1' or decoded_instruction_IE(LHU_bit_position) = '1' then  -- LH instruction
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE) + signed(I_immediate(instr_word_IE_wire)));
              data_req_o_wires         := '1';
              data_we_o_wires          := '0';
              data_be_internal_wires   := "0011";
              if(data_addr_internal_wires(0) = '0') then
                if (load_err = '1') then
                  nextstate_IE_wires         := normal;
                  set_except_condition_wires := '1';
                  taken_branch_wires         := '1';
                elsif data_gnt_i = '1' then
                  nextstate_IE_wires := data_valid_waiting;
                  busy_IE_wires      := '1';
                else
                  nextstate_IE_wires := data_grant_waiting;
                  busy_IE_wires      := '1';
                end if;
              else
                set_except_condition_wires := '1';
                taken_branch_wires         := '1';
                busy_IE_wires              := '1';
              end if;

            elsif decoded_instruction_IE(LB_bit_position) = '1' or decoded_instruction_IE(LBU_bit_position) = '1' then  -- LB instruction
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE) + signed(I_immediate(instr_word_IE_wire)));
              data_req_o_wires         := '1';
              data_we_o_wires          := '0';
              data_be_internal_wires   := "0001";
              if (load_err = '1') then
                nextstate_IE_wires         := normal;
                set_except_condition_wires := '1';
                taken_branch_wires         := '1';
              elsif data_gnt_i = '1' then
                nextstate_IE_wires := data_valid_waiting;
                busy_IE_wires      := '1';
              else
                nextstate_IE_wires := data_grant_waiting;
                busy_IE_wires      := '1';
              end if;

            elsif decoded_instruction_IE(SW_bit_position) = '1' or (decoded_instruction_IE(AMOSWAP_bit_position) = '1' and (amo_store_lat = '1' or amo_load_skip = '1')) then
              if amo_store_lat = '0' and amo_load_skip = '0'  then
                data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE) + signed(S_immediate(instr_word_IE_wire)));
              elsif amo_store_lat = '1' or amo_load_skip = '1' then
                data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE));
                amo_load_lat             <= '0';
                amo_store                <= '1';
              end if;
              data_we_o_wires        := '1';
              data_be_internal_wires := "1111";
              if(data_addr_internal_wires(1 downto 0) = "00") then
                data_wdata_o_wires := RS2_Data_IE(31 downto 0);
                data_req_o_wires   := '1';
                if sw_mip = '1' then
                  busy_IE_wires      := '1';
                  nextstate_IE_wires := csr_instr_wait_state;
                elsif (store_err = '1') then
                  nextstate_IE_wires         := normal;
                  set_except_condition_wires := '1';
                  taken_branch_wires         := '1';
                elsif data_gnt_i = '1' then
                  nextstate_IE_wires := data_valid_waiting;
                  busy_IE_wires      := '1';
                else
                  nextstate_IE_wires := data_grant_waiting;
                  busy_IE_wires      := '1';
                end if;
              else
                set_except_condition_wires := '1';
                taken_branch_wires         := '1';
                busy_IE_wires              := '1';
              end if;

            elsif decoded_instruction_IE(SH_bit_position) = '1' then
              data_we_o_wires := '1';
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE)
                                                           + signed(S_immediate(instr_word_IE_wire)));
              case data_addr_internal_wires(1 downto 0) is
                when "00" =>
                  data_wdata_o_wires := RS2_Data_IE(31 downto 0);
                when "10" =>
                  data_wdata_o_wires := RS2_Data_IE(15 downto 0) & std_logic_vector(to_unsigned(0, 16));
                when others =>
                  null;
              end case;
              data_be_internal_wires := "0011";
              if(data_addr_internal_wires(0) = '0') then
                data_req_o_wires := '1';
                if (store_err = '1') then
                  nextstate_IE_wires         := normal;
                  set_except_condition_wires := '1';
                  taken_branch_wires         := '1';
                elsif data_gnt_i = '1' then
                  nextstate_IE_wires := data_valid_waiting;
                  busy_IE_wires      := '1';
                else
                  nextstate_IE_wires := data_grant_waiting;
                  busy_IE_wires      := '1';
                end if;
              else
                set_except_condition_wires := '1';
                taken_branch_wires         := '1';
                busy_IE_wires              := '1';
              end if;

            elsif decoded_instruction_IE(SB_bit_position) = '1' then
              data_we_o_wires := '1';
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE)
                                                           + signed(S_immediate(instr_word_IE_wire)));
              case data_addr_internal_wires(1 downto 0) is
                when "00" =>
                  data_wdata_o_wires := RS2_Data_IE(31 downto 0);
                when "01" =>
                  data_wdata_o_wires := RS2_Data_IE(23 downto 0) & std_logic_vector(to_unsigned(0, 8));
                when "10" =>
                  data_wdata_o_wires := RS2_Data_IE(15 downto 0) & std_logic_vector(to_unsigned(0, 16));
                when "11" =>
                  data_wdata_o_wires := RS2_Data_IE(7 downto 0) & std_logic_vector(to_unsigned(0, 24));
                when others =>
                  null;
              end case;
              data_req_o_wires       := '1';
              data_be_internal_wires := "0001";
              if (store_err = '1') then
                nextstate_IE_wires         := normal;
                set_except_condition_wires := '1';
                taken_branch_wires         := '1';
              elsif data_gnt_i = '1' then
                nextstate_IE_wires := data_valid_waiting;
                busy_IE_wires      := '1';
              else
                nextstate_IE_wires := data_grant_waiting;
                busy_IE_wires      := '1';
              end if;

            elsif decoded_instruction_IE(CSRRW_bit_position) = '1' or decoded_instruction_IE(CSRRWI_bit_position) = '1' then
              nextstate_IE_wires := csr_instr_wait_state;
              busy_IE_wires      := '1';

            elsif decoded_instruction_IE(CSRRC_bit_position) = '1' or decoded_instruction_IE(CSRRCI_bit_position) = '1'
              or decoded_instruction_IE(CSRRS_bit_position) = '1' or decoded_instruction_IE(CSRRSI_bit_position) = '1' then
              nextstate_IE_wires := csr_instr_wait_state;
              busy_IE_wires      := '1';

            elsif decoded_instruction_IE(ECALL_bit_position) = '1' then
              nextstate_IE_wires         := normal;
              set_except_condition_wires := '1';
              taken_branch_wires         := '1';

            elsif decoded_instruction_IE(EBREAK_bit_position) = '1' then
              ebreak_instr_wires := '1';
              nextstate_IE_wires := normal;

            elsif decoded_instruction_IE(MRET_bit_position) = '1' then
			  set_mret_condition_wires := '1';
              taken_branch_wires       := '1';
              if fetch_enable_i = '0' then
                nextstate_IE_wires := sleep;
				busy_IE_wires      := '1';
              else
                nextstate_IE_wires := normal;
              end if;

            elsif decoded_instruction_IE(WFI_bit_position) = '1' then
              if MSTATUS(harc_IE)(3) = '1' then
                set_wfi_condition_wires  := '1';
                taken_branch_wires       := '1';
              end if;
              nextstate_IE_wires := normal;

            elsif decoded_instruction_IE(ILL_bit_position) = '1' then
              nextstate_IE_wires         := normal;
              set_except_condition_wires := '1';
              taken_branch_wires         := '1';

            elsif decoded_instruction_IE(NOP_bit_position) = '1' then
              nextstate_IE_wires := normal;
            end if;

            if dbg_req_o = '1' then
              nextstate_IE_wires := debug;
              dbg_ack_i_wires    := '1';
              busy_IE_wires      := '1';
            end if;

          end if;

        when data_grant_waiting =>
          data_req_o_wires := '1';
          if data_we_o_lat = '1' then
            if amo_store_lat = '0' then
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE)
                                                           + signed(S_immediate(instr_word_IE_wire)));
              data_wdata_o_wires := RD_Data_IE(31 downto 0);
            else
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE));
              data_wdata_o_wires       := RS2_Data_IE(31 downto 0);
            end if;
          else
            if amo_load = '0' then
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE) + signed(I_immediate(instr_word_IE_wire)));
            else
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE));
              amo_store                <= '1';
            end if;
          end if;

          if (load_err = '1') then
            nextstate_IE_wires         := normal;
            set_except_condition_wires := '1';
            taken_branch_wires         := '1';
          elsif (store_err = '1') then
            nextstate_IE_wires         := normal;
            set_except_condition_wires := '1';
            taken_branch_wires         := '1';
          elsif data_gnt_i = '1' then
            nextstate_IE_wires := data_valid_waiting;
            busy_IE_wires      := '1';
          else
            nextstate_IE_wires := data_grant_waiting;
            busy_IE_wires      := '1';
          end if;

        when data_valid_waiting =>

          if data_we_o_lat = '1' then
            if amo_store_lat = '0' then
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE)
                                                           + signed(S_immediate(instr_word_IE_wire)));
              data_wdata_o_wires := RD_Data_IE(31 downto 0);
            else
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE));
              data_wdata_o_wires       := RS2_Data_IE(31 downto 0);
            end if;
          else
            if amo_load = '0' then
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE) + signed(I_immediate(instr_word_IE_wire)));
            else
              data_addr_internal_wires := std_logic_vector(signed(RS1_Data_IE));
              amo_store                <= '1';
              amo_load_lat             <= '1';
            end if;
          end if;

          if (load_err = '1') then
            nextstate_IE_wires         := normal;
            set_except_condition_wires := '1';
            taken_branch_wires         := '1';
          elsif (store_err = '1') then
            nextstate_IE_wires         := normal;
            set_except_condition_wires := '1';
            taken_branch_wires         := '1';
          elsif data_rvalid_i = '1' then
            if dbg_req_o = '1' then
              nextstate_IE_wires := debug;
              dbg_ack_i_wires    := '1';
              busy_IE_wires      := '1';
            else
              nextstate_IE_wires := normal;
              if amo_load_lat = '1' then
                busy_IE_wires := '1';
              end if;
            end if;
          else
            nextstate_IE_wires := data_valid_waiting;
            busy_IE_wires      := '1';
          end if;

        when csr_instr_wait_state =>
          if (csr_instr_done = '0') then
            nextstate_IE_wires := csr_instr_wait_state;
            busy_IE_wires      := '1';
          elsif (csr_instr_done = '1' and csr_access_denied_o = '1') then
            nextstate_IE_wires         := normal;
            set_except_condition_wires := '1';
            taken_branch_wires         := '1';
          else
            nextstate_IE_wires := normal;
          end if;

      end case;
    end if;

    PC_offset                  <= PC_offset_wires;
    data_addr_internal_wire    <= data_addr_internal_wires;
    data_wdata_o               <= data_wdata_o_wires;
    data_be_internal           <= data_be_internal_wires;
    data_we_o_wire             <= data_we_o_wires;
    absolute_jump              <= absolute_jump_wires;
    busy_IE                    <= busy_IE_wires;
    set_except_condition       <= set_except_condition_wires;
    set_branch_condition       <= set_branch_condition_wires;
    served_irq                 <= served_irq_wires;
    taken_branch               <= taken_branch_wires;
    set_mret_condition         <= set_mret_condition_wires;    
    set_wfi_condition          <= set_wfi_condition_wires;
    jump_instr                 <= jump_instr_wires;
    branch_instr               <= branch_instr_wires;
    ebreak_instr               <= ebreak_instr_wires;
    dbg_ack_i                  <= dbg_ack_i_wires;
    nextstate_IE               <= nextstate_IE_wires;
    data_valid_waiting_counter <= data_valid_waiting_counter_wires;
	WFI_Instr				   <= WFI_Instr_wires;
    data_req_o_wire_top        <= data_req_o_wires;
  end process;

  fsm_IE_state : process(clk_i, rst_ni)
  begin
    
    if rst_ni = '0' then
      branch_instr_lat <= '0'; 
      jump_instr_lat   <= '0';
      data_we_o_lat    <= '0';
      amo_store_lat    <= '0';
      for h in harc_range loop
        flush_cycle_count(h) <= 0;
      end loop;
      state_IE         <= reset;
      
    elsif rising_edge(clk_i) then
      branch_instr_lat       <= branch_instr;
      jump_instr_lat         <= jump_instr;
      data_we_o_lat          <= data_we_o_wire;
      amo_store_lat          <= amo_store;
      data_addr_internal_lat <= data_addr_internal_wire;
      for h in harc_range loop
        if taken_branch = '1' and harc_IE = h then 
        flush_cycle_count(h) <= NOP_POOL_SIZE;
        elsif flush_cycle_count(h) /= 0 and busy_IE = '0' then
          flush_cycle_count(h) <= flush_cycle_count(h) - 1;
        end if;
      end loop;
      state_IE               <= nextstate_IE;

    end if;
  end process;


end Pipe;
