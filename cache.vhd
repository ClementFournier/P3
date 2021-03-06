library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768
);
port(
	clock : in std_logic;
	reset : in std_logic;
	
	-- Avalon interface --
	s_addr : in std_logic_vector (31 downto 0);
	s_read : in std_logic;
	s_readdata : out std_logic_vector (31 downto 0);
	s_write : in std_logic;
	s_writedata : in std_logic_vector (31 downto 0);
	s_waitrequest : out std_logic; 
    
	m_addr : out integer range 0 to ram_size-1;
	m_read : out std_logic;
	m_readdata : in std_logic_vector (7 downto 0);
	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0);
	m_waitrequest : in std_logic
);
end cache;

architecture arch of cache is

  --data is 127 downto 0, tag is 133 downto 128, flag is 135 downto 134
  type cache_array is array (31 downto 0) of std_logic_vector(137 downto 0); 
  
  --Temporary signals	
  signal cache: cache_array;
   
  
  --Address tag, index, offset --only use lower 15 bits
              --log15 = 4 bits offset
              --log(4096/128) = 5 bits index
              --15 - 9 = 6 bits tag 
  signal addr_word_offset: std_logic_vector(1 downto 0); -- 2 bits word offset
  signal addr_byte_offset: std_logic_vector (1 downto 0); -- 2 bits byte offset
  signal addr_index: std_logic_vector(4 downto 0); -- 5 bits index
  signal addr_tag: std_logic_vector(5 downto 0); -- 6 bits tag

  --Cache signals
  signal block_tag: std_logic_vector(5 downto 0);
  signal tag: std_logic_vector(5 downto 0);
  --integer 
  signal index: integer range 0 to 31;
  signal offset: integer range 0 to 3;

  --flags
  signal valid: std_logic := '0';
  signal dirty: std_logic := '0';

  --byte counters
  signal ref_counter : integer := 0;
  signal b_counter : integer := 0;

  --wait signals
  signal s_write_waitreq_reg: std_logic := '1';
  signal s_read_waitreq_reg: std_logic := '1';
  signal m_write_waitreq_reg: std_logic := '1';
  signal m_read_waitreq_reg: std_logic := '1';        

  --memory signals
  signal m_address: integer range 0 to ram_size-1;

  TYPE State_type IS (A, B, C, D, E, F, G);  -- Define the states
  SIGNAL state : State_Type;    -- Create a signal

	--LIST OF STATES
	--STATE A : Idle state : waiting for a read or write command from processor
	--STATE B : Compare tags set to determine if it is a hit or a miss
	--STATE C : Read memory state
    --STATE D : Waiting for memory read
	--STATE E : write back state
	--STATE F : Waiting for memory write
    --STATE F : signal CPU that operation is complete

 
  begin

    addr_word_offset <= s_addr(3 downto 2); -- word offset of address
    addr_byte_offset <= s_addr (1 downto 0); -- byte offset 
    addr_index <= s_addr(8 downto 4); -- index of address
    addr_tag <= s_addr(14 downto 9); -- tag of address
    
    index <= to_integer(unsigned(addr_index)); --index
    offset <= to_integer(unsigned(addr_word_offset)); --offset
   
    valid <= cache(index)(135); -- valid bit of block
    dirty <= cache(index)(134); -- dirty bit of block       
    block_tag <= cache(index)(133 downto 128); -- tag bits of block  

    
    process(clock,m_waitrequest,reset)
      begin
        if (reset'event and reset = '1') then
          state<=A;
    
        elsif (rising_edge(clock) ) then
          s_waitrequest<='1';
          m_read<='0';
          m_write<='0';
          
          case state is
          ----------------------------------------------------------
          --CPU request state
          when A =>
			--report "A";
            if(s_read='1' or s_write='1') then
              state <= B;
            end if;
          ----------------------------------------------------------
          --hit or miss state
          --for hit: either write_back or read
          --for miss: go to state C or D depending on dirty bit
          when B =>
		  --report "B";
            if(addr_tag = block_tag and valid='1') then
              if(s_read= '1') then
                s_readdata <=  cache(index)(32*(to_integer(unsigned(addr_word_offset)))+31 downto 32*(to_integer(unsigned(addr_word_offset))));
                state <= G;  --signal CPU
              elsif(s_write= '1') then
                cache(index)(32*(to_integer(unsigned(addr_word_offset)))+31 downto 32*(to_integer(unsigned(addr_word_offset)))) <= s_writedata;
                cache(index)(134)<= '1';
                state <= G;  --signal CPU
              end if;
            else
              if( dirty ='1') then
                state <= E;
              else
                state <= C;
              end if;
            end if;
          ------------------------------------------------------------
          --memory read state  
          when C =>
		  --report "C";
            if(ref_counter = 4) then
              ref_counter <= 0;
              cache(index)(135)<='1';  --set valid
              cache(index)(134)<='0';  --set not dirty
              cache(index)(133 downto 128)<=addr_tag;
              State <= B;
            else
              m_read<='1';
              m_address <=((to_integer(unsigned(addr_tag))*512)+(to_integer(unsigned(addr_index))*16)+ref_counter*4+b_counter);		
              state <= D;
            end if;
          --------------------------------------------------------------
          --Waiting for memory read
          when D =>
		  --report "D";
            --nothing
          --------------------------------------------------------------
          --write back state
          when E =>
		  --report "E";
            if(ref_counter = 4) then
              ref_counter <= 0;
              state <= C;
            else
              m_write <= '1';
              m_address <= ((to_integer(unsigned(block_tag))*512)+(to_integer(unsigned(addr_index))*16)+ref_counter*4+b_counter);
              m_writedata <= cache(index) ((ref_counter*32 + b_counter*8 + 7) downto (ref_counter*32 + b_counter*8));
              state <= F;
            end if;     
          --------------------------------------------------------------
          --Waiting for memory write
          when F =>
		  --report "F";
            --nothing
          --------------------------------------------------------------
          when others =>
            state <= A; --default state
          
          end case;

        elsif(falling_edge(clock)) then
	  if (state = G) then
            s_waitrequest<= '0';
            state<=A;
          end if;
        end if;
        
        --the process waiting for a memory read finish, if done, then add the offset and pass to memory_read 
        if (m_waitrequest'event and m_waitrequest = '0' and state=D) then 
          state <= C;

          cache(index)(ref_counter*32+b_counter*8+7 downto ref_counter*32+b_counter*8)<= m_readdata;

          if(b_counter = 3 ) then 
             b_counter <=0;
             ref_counter <= ref_counter+1;
          else
             b_counter <= b_counter+1;
          end if;

        --the process waiting for a write back finish, if done, then add the offset and pass to memory_write
        elsif (m_waitrequest'event and m_waitrequest = '0' and state=F)then
          state <= E;
          if(b_counter = 3 ) then 
            b_counter <=0;
            ref_counter <= ref_counter+1;
          else
            b_counter <= b_counter+1;
          end if;
        end if;
      end process;
    
    m_addr<= m_address;
  
  end arch;