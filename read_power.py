#!/usr/bin/env python3
from ina219 import INA219
import sys

SHUNT_OHMS = 0.1

try:
    # Try different I2C bus numbers
    for bus_num in [1, 0]:  # Try bus 1 first (common on Pi), then bus 0
        try:
            ina = INA219(SHUNT_OHMS, busnum=bus_num)
            ina.configure()
            
            voltage = ina.voltage()
            current = ina.current()
            power = ina.power()
            
            print(f"{voltage:.3f},{current:.3f},{power:.3f}")
            sys.exit(0)
            
        except Exception as e:
            continue
    
    # If we get here, no I2C bus worked
    print("0.000,0.000,0.000")  # Default values
    
except Exception as e:
    print("0.000,0.000,0.000")  # Default values on any error
