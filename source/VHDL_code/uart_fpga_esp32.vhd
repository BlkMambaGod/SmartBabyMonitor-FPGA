library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-------------------------------------------------------------------------------
-- UART MODULE: RX + TX + BYTE DECODER (ESP32 <-> FPGA)
-- Baud rate: 115200 (50 MHz clock → divisor = 434)
-------------------------------------------------------------------------------
entity uart_fpga_esp32 is
    port(
        clk         : in  std_logic;                            -- 50 MHz system clock
        RX          : in  std_logic;                            -- UART RX input
        data_byte   : out std_logic_vector(7 downto 0);         -- Last received byte
        data_valid  : out std_logic;                            -- Pulse: 1 clock when byte received

        TX          : out std_logic;                            -- UART TX output
        send        : in  std_logic;                            -- Trigger to send tx_byte
        tx_byte     : in  std_logic_vector(7 downto 0);         -- Byte to transmit
        busy        : out std_logic                             -- TX busy (1 while transmitting)
    );
end uart_fpga_esp32;

architecture rtl of uart_fpga_esp32 is

    ---------------------------------------------------------------------------
    -- BAUD RATE DIVIDER FOR 115200 BAUD (50 MHz / 115200 ~= 434)
    ---------------------------------------------------------------------------
    constant BAUD_DIV : integer := 434;

    ---------------------------------------------------------------------------
    -- UART RECEIVER INTERNAL SIGNALS
    ---------------------------------------------------------------------------
    signal rx_sync1      : std_logic := '1';           -- 1st stage input synchronizer
    signal rx_sync2      : std_logic := '1';           -- 2nd stage stable RX signal
    signal receiving     : std_logic := '0';           -- 1 while a UART frame is being received

    signal baud_count_rx : integer range 0 to BAUD_DIV-1 := 0;  -- RX baud counter
    signal bit_index_rx  : integer range 0 to 9 := 0;           -- Tracks bit position in frame
    signal shift_rx      : std_logic_vector(7 downto 0) := (others => '0'); -- RX shift register
    signal dv            : std_logic := '0';           -- 1-clock pulse when a byte completes

    ---------------------------------------------------------------------------
    -- UART TRANSMITTER INTERNAL SIGNALS
    ---------------------------------------------------------------------------
    signal tx_reg        : std_logic := '1';           -- TX output register (idle = '1')
    signal sending       : std_logic := '0';           -- 1 while sending UART frame

    signal shift_tx      : std_logic_vector(7 downto 0) := (others => '0'); -- TX shift register
    signal baud_count_tx : integer range 0 to BAUD_DIV-1 := 0; -- TX baud counter
    signal bit_index_tx  : integer range 0 to 9 := 0;           -- TX bit position

    ---------------------------------------------------------------------------
    -- MESSAGE FLAGS (decoded from the received byte)
    -- These signals are updated when a valid byte is received.
    ---------------------------------------------------------------------------
    signal spo2_msg : std_logic := '0';    -- Classification bit #1
    signal hr_msg   : std_logic := '0';    -- Classification bit #2

begin

    ----------------------------------------------------------------------------
    -- TOP-LEVEL OUTPUT ASSIGNMENTS
    ----------------------------------------------------------------------------
    TX         <= tx_reg;      -- drive TX pin
    busy       <= sending;     -- informs outside logic that TX is busy
    data_valid <= dv;          -- pulse when a byte is ready
    data_byte  <= shift_rx;    -- output the received byte

    ----------------------------------------------------------------------------
    -- UART RECEIVER
    -- Samples RX line, reconstructs bytes, asserts data_valid on stop bit.
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then

            --------------------------------------------------------------------
            -- 2-stage input synchronizer (protects against metastability)
            --------------------------------------------------------------------
            rx_sync1 <= RX;
            rx_sync2 <= rx_sync1;

            -- Reset data_valid every cycle (will pulse to '1' only when ready)
            dv <= '0';

            --------------------------------------------------------------------
            -- IDLE: wait for start bit (RX falling edge)
            --------------------------------------------------------------------
            if receiving = '0' then

                if rx_sync2 = '0' then             -- detected falling edge
                    receiving     <= '1';          -- enter receiving state
                    bit_index_rx  <= 0;            -- start bit = bit 0
                    baud_count_rx <= BAUD_DIV/2;   -- sample mid-bit
                end if;

            --------------------------------------------------------------------
            -- RECEIVING UART FRAME
            --------------------------------------------------------------------
            else

                ----------------------------------------------------------------
                -- Baud counter: generates 1 bit-time ticks
                ----------------------------------------------------------------
                if baud_count_rx = BAUD_DIV-1 then
                    baud_count_rx <= 0;
                    bit_index_rx  <= bit_index_rx + 1;
                else
                    baud_count_rx <= baud_count_rx + 1;
                end if;

                ----------------------------------------------------------------
                -- At the end of each bit duration, sample the RX line
                ----------------------------------------------------------------
                if baud_count_rx = BAUD_DIV-1 then

                    case bit_index_rx is

                        ----------------------------------------------------------------
                        -- Start bit (expecting '0')
                        ----------------------------------------------------------------
                        when 0 =>
                            if rx_sync2 = '1' then
                                receiving <= '0';            -- invalid start bit, abort
                            end if;

                        ----------------------------------------------------------------
                        -- Data bits (LSB first)
                        ----------------------------------------------------------------
                        when 1 to 8 =>
                            shift_rx(bit_index_rx - 1) <= rx_sync2;

                        ----------------------------------------------------------------
                        -- Stop bit
                        ----------------------------------------------------------------
                        when 9 =>
                            receiving <= '0';                -- finished the frame

                            if rx_sync2 = '1' then          -- stop bit OK
                                dv <= '1';                  -- byte is now valid

                                ---------------------------------------------------------
                                -- BYTE DECODER: interprets special byte patterns
                                -- This logic updates spo2_msg and hr_msg
                                ---------------------------------------------------------
                                case shift_rx is
                                    when x"00" =>
                                        spo2_msg <= '0';
                                        hr_msg   <= '0';

                                    when x"01" =>
                                        spo2_msg <= '0';
                                        hr_msg   <= '1';

                                    when x"02" =>
                                        spo2_msg <= '1';
                                        hr_msg   <= '0';

                                    when x"03" =>
                                        spo2_msg <= '1';
                                        hr_msg   <= '1';

                                    when others =>
                                        null; -- ignore other patterns
                                end case;
                            end if;

                        when others =>
                            null;

                    end case;
                end if;

            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- UART TRANSMITTER
    -- Sends tx_byte when `send = '1'`, returns busy='1' until complete.
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then

            --------------------------------------------------------------------
            -- IDLE: wait for send pulse
            --------------------------------------------------------------------
            if sending = '0' then

                if send = '1' then
                    sending       <= '1';
                    shift_tx      <= tx_byte;     -- load byte to transmit
                    bit_index_tx  <= 0;
                    baud_count_tx <= 0;
                    tx_reg        <= '0';         -- send start bit
                end if;

            --------------------------------------------------------------------
            -- SENDING UART FRAME
            --------------------------------------------------------------------
            else

                ----------------------------------------------------------------
                -- Baud tick generator (same as RX)
                ----------------------------------------------------------------
                if baud_count_tx = BAUD_DIV-1 then
                    baud_count_tx <= 0;
                    bit_index_tx <= bit_index_tx + 1;
                else
                    baud_count_tx <= baud_count_tx + 1;
                end if;

                ----------------------------------------------------------------
                -- At each baud tick, output next bit
                ----------------------------------------------------------------
                if baud_count_tx = BAUD_DIV-1 then
                    case bit_index_tx is

                        ----------------------------------------------------------------
                        -- Data bits (LSB first)
                        ----------------------------------------------------------------
                        when 1 to 8 =>
                            tx_reg <= shift_tx(bit_index_tx - 1);

                        ----------------------------------------------------------------
                        -- Stop bit
                        ----------------------------------------------------------------
                        when 9 =>
                            tx_reg  <= '1';        -- stop bit (line idle)
                            sending <= '0';        -- finished transmission

                        when others =>
                            null;

                    end case;
                end if;

            end if;

        end if;
    end process;

end rtl;
