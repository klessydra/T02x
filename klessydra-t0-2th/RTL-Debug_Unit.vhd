library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.riscv_klessydra.all;
use work.thread_parameters_klessydra.all;

entity Debug_UNIT is
  port (
    set_branch_condition     : in  std_logic;
    set_except_condition     : in  std_logic;
    set_mret_condition       : in  std_logic;
    branch_condition_pending : in  replicated_bit;
    except_condition_pending : in  replicated_bit;
    mret_condition_pending   : in  replicated_bit;
    served_irq               : in  replicated_bit;
    irq_pending              : in  replicated_bit;
    taken_branch_pc_lat      : in  replicated_32b_reg;
    incremented_pc           : in  replicated_32b_reg;
    MTVEC                    : in  replicated_32b_reg;
    MIP                      : in  replicated_32b_reg;
    MSTATUS                  : in  replicated_32b_reg;
    MCAUSE                   : in  replicated_32b_reg;
    mepc_incremented_pc      : in  replicated_32b_reg;
    mepc_interrupt_pc        : in  replicated_32b_reg;
    regfile                  : in  regfile_replicated_array;
    pc_IE                    : in  std_logic_vector (31 downto 0);
    harc_IE                  : in  harc_range;
    ebreak_instr             : in  std_logic;
    dbg_ack_i                : in  std_logic;
	taken_branch			 : in std_logic;
	taken_branch_pending     : in replicated_bit;
    dbg_req_o                : out std_logic;
    dbg_halted_o             : out std_logic;
    clk_i                    : in  std_logic;
    rst_ni                   : in  std_logic;
    debug_req_i              : in  std_logic;
    debug_gnt_o              : out std_logic;
    debug_rvalid_o           : out std_logic;
    debug_addr_i             : in  std_logic_vector(14 downto 0);
    debug_we_i               : in  std_logic;
    debug_wdata_i            : in  std_logic_vector(31 downto 0);
    debug_rdata_o            : out std_logic_vector(31 downto 0);
    debug_halted_o           : out std_logic;
    debug_halt_i             : in  std_logic;
    debug_resume_i           : in  std_logic
    );
end entity;

architecture DBG of Debug_Unit is



  type fsm_DBU_states is (RUNNING, HALT_REQ, HALT, SINGLE_STEP_REQ, SINGLE_STEP);
  signal state_DBU       : fsm_DBU_states;
  signal nextstate_DBU   : fsm_DBU_states;
  signal dbg_halt_req    : std_logic;
  signal dbg_resume_core : std_logic;
  signal dbg_ssh         : std_logic;
  signal dbg_sse         : std_logic;

  signal dbg_halted_o_wire : std_logic;

begin

  dbg_halted_o <= dbg_halted_o_wire;


  DBU_interface_handler : process(clk_i, rst_ni)
  begin
    if(rst_ni = '0') then
      debug_rvalid_o  <= '0';
      debug_rdata_o   <= (others => 'Z');
      dbg_halt_req    <= '0';
      dbg_sse         <= '0';
      dbg_ssh         <= '1';
      dbg_resume_core <= '0';
    elsif rising_edge(clk_i) then
      dbg_ssh <= '1';
      if(debug_req_i = '1') then
        debug_rvalid_o <= '1';
        if(debug_we_i = '0') then
          case debug_addr_i(13 downto 8) is
            when "000000" =>
              case debug_addr_i(6 downto 2) is
                when "00000" =>
                  debug_rdata_o <= (0      => dbg_halted_o_wire,
                                    16     => dbg_sse,
                                    others => '0');
                when "00001" =>
                  debug_rdata_o <= (0 => dbg_ssh, others => '0');
                when others =>
                  null;
              end case;
            when "100000" =>
              if dbg_halted_o_wire = '1' then
                case debug_addr_i(2) is
                  when '0' =>
                    debug_rdata_o <= pc_ie;
                  when '1' =>
                    if served_irq(harc_IE) = '1' then
                      debug_rdata_o <= MTVEC(harc_IE);
                    elsif (not taken_branch = '1' and not taken_branch_pending(harc_IE) = '1')
                    then
                      debug_rdata_o <= incremented_pc(harc_IE);
                    elsif set_branch_condition = '1' or branch_condition_pending(harc_IE) = '1' then
                      debug_rdata_o <= taken_branch_pc_lat(harc_IE);
                    elsif irq_pending(harc_IE) = '1' then
                      debug_rdata_o <= MTVEC(harc_IE);
                    elsif (set_except_condition or except_condition_pending(harc_IE)) = '1' then
                      debug_rdata_o <= MTVEC(harc_IE);
                    elsif (set_mret_condition or mret_condition_pending(harc_IE)) = '1' and MCAUSE(harc_IE)(31) = '0' then
                      debug_rdata_o <= mepc_incremented_pc(harc_IE);
                    elsif (set_mret_condition or mret_condition_pending(harc_IE)) = '1' and MCAUSE(harc_IE)(31) = '1' then
                      debug_rdata_o <= mepc_interrupt_pc(harc_IE);
                    end if;
                  when others =>
                    null;
                end case;
              end if;
            when "000100" =>
              debug_rdata_o <= regfile(harc_IE)(to_integer(unsigned(debug_addr_i(6 downto 2))));
            when others =>
              null;
          end case;
        else
          debug_rvalid_o <= '0';
          case debug_addr_i(13 downto 8) is
            when "000000" =>
              case debug_addr_i(6 downto 2) is
                when "00000" =>
                  if (debug_wdata_i(16) = '1') then
                    if dbg_halted_o_wire = '0' then
                      dbg_halt_req <= '1';
                    else
                      dbg_halt_req <= '0';
                    end if;
                  else
                    if dbg_halted_o_wire = '1' then
                      dbg_resume_core <= '1';
                      dbg_halt_req    <= '0';
                    end if;
                  end if;
                  if(debug_wdata_i(0) = '1') then
                    dbg_sse <= '1';
                  else
                    dbg_sse <= '0';
                  end if;
                when "00001" =>
                  if (debug_wdata_i(0) = '0') then
                    if dbg_sse = '1' and dbg_halted_o_wire = '1' then
                      dbg_ssh <= '0';
                    end if;
                  end if;
                when others =>
                  null;
              end case;
            when others =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process;

  DBU_combinatory_access : process (all)
  begin
    if (debug_req_i = '1') then
      debug_gnt_o <= '1';
    else
      debug_gnt_o <= '0';
    end if;
  end process;

  fsm_Debug_Unit_nextstate : process(all)

  begin
    if rst_ni = '0' then
      nextstate_DBU     <= RUNNING;
      dbg_req_o         <= '0';
      dbg_halted_o_wire <= '0';
    else
      case state_DBU is
        when RUNNING =>
          dbg_halted_o_wire <= '0';
          if ebreak_instr = '1' then
            dbg_req_o <= '0';
            if dbg_sse = '1' then
              nextstate_DBU <= SINGLE_STEP;
            else
              nextstate_DBU <= HALT;
            end if;
          elsif dbg_halt_req = '1' then
            dbg_req_o <= '1';
            if dbg_sse = '0' then
              nextstate_DBU <= HALT_REQ;
            else
              nextstate_DBU <= SINGLE_STEP_REQ;
            end if;
          else
            dbg_req_o     <= '0';
            nextstate_DBU <= RUNNING;
          end if;
        when HALT_REQ =>
          dbg_halted_o_wire <= '0';
          dbg_req_o         <= '1';
          if dbg_ack_i = '1' then
            nextstate_DBU <= HALT;
          else
            if dbg_resume_core = '1' then
              nextstate_DBU <= RUNNING;
            else
              if dbg_sse = '1' then
                nextstate_DBU <= SINGLE_STEP_REQ;
              else
                nextstate_DBU <= HALT_REQ;
              end if;
            end if;
          end if;
        when HALT =>
          dbg_req_o         <= '1';
          dbg_halted_o_wire <= '1';
          if dbg_resume_core = '1' then
            nextstate_DBU <= RUNNING;
          else
            if dbg_sse = '1' then
              nextstate_DBU <= SINGLE_STEP;
            else
              nextstate_DBU <= HALT;
            end if;
          end if;
        when SINGLE_STEP_REQ =>
          dbg_req_o         <= '1';
          dbg_halted_o_wire <= '0';
          if dbg_ack_i = '1' then
            nextstate_DBU <= SINGLE_STEP;
          else
            if dbg_sse = '0' then
              nextstate_DBU <= HALT_REQ;
            else
              nextstate_DBU <= SINGLE_STEP_REQ;
            end if;
          end if;
        when SINGLE_STEP =>
          if dbg_sse = '0' then
            if dbg_resume_core = '1' then
              nextstate_DBU     <= RUNNING;
              dbg_req_o         <= '0';
              dbg_halted_o_wire <= '0';
            else
              dbg_req_o         <= '1';
              dbg_halted_o_wire <= '1';
              nextstate_DBU     <= HALT;
            end if;
          elsif dbg_ssh = '0' then
            dbg_req_o         <= '0';
            dbg_halted_o_wire <= '0';
            nextstate_DBU     <= SINGLE_STEP_REQ;
          else
            dbg_req_o         <= '1';
            dbg_halted_o_wire <= '1';
            nextstate_DBU     <= SINGLE_STEP;
          end if;
        when others =>
          nextstate_DBU     <= RUNNING;
          dbg_req_o         <= '0';
          dbg_halted_o_wire <= '0';
      end case;
    end if;
  end process;


  fsm_DBU_register_state : process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      state_DBU <= RUNNING;
    elsif rising_edge(clk_i) then
      state_DBU <= nextstate_DBU;
    end if;
  end process;

end DBG;
