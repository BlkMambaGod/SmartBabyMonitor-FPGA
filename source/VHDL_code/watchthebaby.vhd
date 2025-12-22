

library IEEE;
use IEEE.std_logic_1164.all;

ENTITY watchthebaby IS
    PORT(
        sound_sensor     : IN  std_logic;
        gas_sensor       : IN  std_logic; 
        
        sound_light   : OUT std_logic; 
        gas_light     : OUT std_logic;
        alarm         : OUT std_logic;
        fan           : OUT std_logic
    );
END watchthebaby;

ARCHITECTURE Behaviour OF watchthebaby IS 
    
    COMPONENT SoundSensor
        PORT(
            sound_sensor : IN  std_logic;
            sound_light  : OUT std_logic
        );
    END COMPONENT;

    COMPONENT GasSensor
        PORT(
            gas_sensor : IN  std_logic;
            gas_light  : OUT std_logic;
            alarm      : OUT std_logic;
            fan        : OUT std_logic
        );
    END COMPONENT;

BEGIN

    sound_sensor_inst : SoundSensor
        PORT MAP (
            sound_sensor => sound_sensor,    
            sound_light  => sound_light  
        );

    gas_sensor_inst : GasSensor
        PORT MAP (
            gas_sensor => gas_sensor,       
            gas_light  => gas_light,     
            alarm      => alarm,        
            fan        => fan  
        );

END Behaviour;
