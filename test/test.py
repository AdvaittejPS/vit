import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

async def simulate_button_press(dut, pin_index):
    """Simulates a bouncy physical button press."""
    # Add int() to cast the LogicArray to a standard integer
    dut.ui_in.value = int(dut.ui_in.value) | (1 << pin_index)
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << pin_index)
    await ClockCycles(dut.clk, 1)
    
    # Solid press (hold > 8 clocks to pass the debouncer)
    dut.ui_in.value = int(dut.ui_in.value) | (1 << pin_index)
    await ClockCycles(dut.clk, 15)
    
    # Release
    dut.ui_in.value = int(dut.ui_in.value) & ~(1 << pin_index)
    await ClockCycles(dut.clk, 15)

async def decode_uart_string(dut, baud_clocks=3, length=13):
    """Listens to uio_out[0] and decodes an entire UART string."""
    received = ""
    for _ in range(length):
        # Wait for Start Bit
        while int(dut.uio_out.value) & 1 == 1:
            await FallingEdge(dut.clk)
            
        await ClockCycles(dut.clk, baud_clocks // 2) # Center of Start Bit
        
        char_val = 0
        for i in range(8):
            await ClockCycles(dut.clk, baud_clocks)
            bit = int(dut.uio_out.value) & 1
            char_val |= (bit << i)
            
        await ClockCycles(dut.clk, baud_clocks) # Stop Bit
        received += chr(char_val)
    return received

@cocotb.test()
async def test_telemetry_stopwatch(dut):
    dut._log.info("Starting Telemetry Stopwatch Full System Test")
    
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    # Phase 1: Reset & Setup (Set Alarm Target to 3)
    dut.ena.value = 1
    dut.ui_in.value = 0b0011_0000 # Target = 3 (ui_in[7:4])
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # Phase 2: Start Stopwatch
    dut._log.info("Pressing Start Button...")
    # Wrap in int() here as well!
    dut.ui_in.value = int(dut.ui_in.value) | 0b0000_0001
    await ClockCycles(dut.clk, 20) # Pass debouncer

    # Phase 3: Wait for 1, then hit Lap
    await ClockCycles(dut.clk, 10) # 1 sec passes
    dut._log.info("Timer hit 1. Pressing Lap Button!")
    await simulate_button_press(dut, 1) # Hit Lap (ui_in[1])
    
    lap_val = (int(dut.uio_out.value) >> 4) & 0xF
    assert lap_val == 1, f"Lap Memory Failed! Expected 1, got {lap_val}"
    dut._log.info("Lap memory correctly stored '1' in uio_out[7:4].")

    # Phase 4: Wait for the Alarm (Target = 3) and intercept UART
    dut._log.info("Waiting for timer to hit target (3) to trigger UART...")
    
    # Start a background task to listen to the UART line
    uart_task = cocotb.start_soon(decode_uart_string(dut, baud_clocks=3, length=13))
    
    # Wait for the timer to count 2, then 3. 
    await ClockCycles(dut.clk, 20) 
    
    # Check if the decimal point (Alarm LED) turned on
    dp_led = (int(dut.uo_out.value) >> 7) & 1
    assert dp_led == 1, "Alarm LED (uo_out[7]) did not turn on!"
    
    # Await the UART string decoding
    received_string = await uart_task
    dut._log.info(f"UART Transmitted: {repr(received_string)}")
    
    expected_string = "VIT Vellore\r\n"
    assert received_string == expected_string, "UART string mismatch!"
    
    dut._log.info("All Telemetry, Lap Memory, and Alarm tests passed perfectly!")
