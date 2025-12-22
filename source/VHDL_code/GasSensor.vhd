library IEEE;
use IEEE.std_logic_1164.all;

ENTITY GasSensor IS
    PORT(
        gas_sensor : IN  std_logic;
        gas_light    : OUT std_logic;
		  alarm    : OUT std_logic;
		  fan    : OUT std_logic
		  
    );
END GasSensor;

ARCHITECTURE Behaviour OF GasSensor IS
BEGIN
	PROCESS(gas_sensor)
BEGIN
    gas_light <= NOT gas_sensor;
	 alarm <= NOT gas_sensor;
	 fan <= NOT gas_sensor;
	 END PROCESS;
END Behaviour;