library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity uart_fpga_esp32 is
port(
    clk          : in std_logic;
    RX           : in std_logic;
    data_byte    : buffer std_logic_vector(7 downto 0);
    data_valid   : out std_logic;
    sound_sensor : in std_logic;
    gas_sensor   : in std_logic;
    sound_light  : out std_logic;
    gas_light    : out std_logic;
    alarm        : out std_logic;
    fan          : out std_logic
);
end uart_fpga_esp32;

architecture cmd of uart_fpga_esp32 is

    -- Constantes
    constant BAUD_DIV : integer := 434;
    constant DEBOUNCE_COUNT : integer := 10000;  -- Anti-rebonds
    
    -- Signaux UART
    signal baud_count : integer range 0 to BAUD_DIV-1 := 0;
    signal bit_index : integer range 0 to 9 := 0;
    signal receiving : std_logic := '0';
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_sync1 : std_logic := '1';
    signal rx_sync2 : std_logic := '1';
    signal dv : std_logic := '0';
    signal spo2_msg : std_logic := '0';
    signal hr_msg   : std_logic := '0';
    
    -- Signaux capteurs avec anti-rebonds
    signal gas_sensor_debounced   : std_logic;
    signal sound_sensor_debounced : std_logic;
    signal gas_counter   : integer range 0 to DEBOUNCE_COUNT := 0;
    signal sound_counter : integer range 0 to DEBOUNCE_COUNT := 0;
    
    -- Signaux détection
    signal gas_detected   : std_logic;
    signal sound_detected : std_logic;
    
    -- Configuration (ajuster selon tes capteurs)
    constant GAS_ACTIVE_LOW   : std_logic := '1';  -- '1' si capteur actif bas
    constant SOUND_ACTIVE_LOW : std_logic := '1';  -- '1' si capteur actif haut

begin

    data_valid <= dv;
    data_byte <= shift_reg;
    
    -- ========== ANTI-REBONDS DES CAPTEURS ==========
    
    process(clk)
    begin
        if rising_edge(clk) then
            -- Anti-rebonds pour capteur GAZ
            if gas_sensor = '0' then  -- Détection = '0' (actif bas)
                if gas_counter < DEBOUNCE_COUNT then
                    gas_counter <= gas_counter + 1;
                end if;
            else
                if gas_counter > 0 then
                    gas_counter <= gas_counter - 1;
                end if;
            end if;
            
            -- Seuil de détection (70% du temps)
            if gas_counter > (DEBOUNCE_COUNT * 7/10) then
                gas_sensor_debounced <= '0';  -- Gaz détecté
            else
                gas_sensor_debounced <= '1';  -- Pas de gaz
            end if;
            
            -- Anti-rebonds pour capteur SON (identique)
            if sound_sensor = '1' then  -- Détection = '1' (actif haut)
                if sound_counter < DEBOUNCE_COUNT then
                    sound_counter <= sound_counter + 1;
                end if;
            else
                if sound_counter > 0 then
                    sound_counter <= sound_counter - 1;
                end if;
            end if;
            
            if sound_counter > (DEBOUNCE_COUNT * 7/10) then
                sound_sensor_debounced <= '1';  -- Son détecté
            else
                sound_sensor_debounced <= '0';  -- Pas de son
            end if;
        end if;
    end process;
    
    -- ========== INTERPRÉTATION AVEC CONFIGURATION ==========
    
    -- Gaz : généralement actif bas (GAS_ACTIVE_LOW = '1')
    gas_detected <= NOT gas_sensor_debounced when GAS_ACTIVE_LOW = '1' 
                    else gas_sensor_debounced;
    
    -- Son : généralement actif haut (SOUND_ACTIVE_LOW = '0')
    sound_detected <= NOT sound_sensor_debounced when SOUND_ACTIVE_LOW = '1' 
                      else sound_sensor_debounced;
    
    -- ========== COMMANDES SORTIES ==========
    
    sound_light <= sound_detected;  -- Lumière sur détection son
    gas_light   <= gas_detected;    -- Lumière sur détection gaz
    fan         <= gas_detected;    -- Ventilateur sur détection gaz
    
    -- ========== RÉCEPTION UART (inchangé) ==========
    
    process(clk)
    begin
        if rising_edge(clk) then
            rx_sync1 <= RX;
            rx_sync2 <= rx_sync1;
            dv <= '0';
            
            if receiving = '0' then
                if rx_sync2 = '0' then
                    receiving <= '1';
                    bit_index <= 0;
                    baud_count <= BAUD_DIV/2;
                end if;
            else
                if baud_count = BAUD_DIV-1 then
                    baud_count <= 0;
                    bit_index <= bit_index + 1;
                else
                    baud_count <= baud_count + 1;
                end if;
                
                if baud_count = BAUD_DIV-1 then
                    case bit_index is
                        when 0 =>
                            if rx_sync2 = '1' then
                                receiving <= '0';
                            end if;
                        when 1 to 8 =>
                            shift_reg(bit_index-1) <= rx_sync2;
                        when 9 =>
                            receiving <= '0';
                            if rx_sync2 = '1' then
                                dv <= '1';
                            end if;
                        when others => null;
                    end case;
                end if;
            end if;
            
            if dv = '1' then
                case shift_reg is
                    when x"00" =>
                        spo2_msg <= '0';
                        hr_msg   <= '0';
                    when x"02" =>
                        spo2_msg <= '0';
                        hr_msg   <= '1';
                    when x"01" =>
                        spo2_msg <= '1';
                        hr_msg   <= '0';
                    when x"03" =>
                        spo2_msg <= '1';
                        hr_msg   <= '1';
                    when others =>
                        spo2_msg <= '0';
                        hr_msg   <= '0';
                end case;
            end if;
        end if;
    end process;
    
    -- ========== ALARME CORRIGÉE ==========
    -- MAINTENANT : Son active aussi l'alarme (buzzer)
    
    alarm <= '1' when (hr_msg = '1' or spo2_msg = '1) else '0';

end cmd;