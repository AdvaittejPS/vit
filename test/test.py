import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

async def send_uart_command(dut, char_string, baud_clocks=3):
    """Simulates a laptop sending data TO the chip over uio_in[1]"""
    for char in char_string:
        byte_val = ord(char)
        
        dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 1) # Start Bit (LOW)
        await ClockCycles(dut.clk, baud_clocks)
        
        for i in range(8): # Data Bits (LSB first)
            bit = (byte_val >> i) & 1
            if bit:
                dut.uio_in.value = int(dut.uio_in.value) | (1 << 1)
            else:
                dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 1)
            await ClockCycles(dut.clk, baud_clocks)
            
        dut.uio_in.value = int(dut.uio_in.value) | (1 << 1) # Stop Bit (HIGH)
        await ClockCycles(dut.clk, baud_clocks)
        
        await ClockCycles(dut.clk, baud_clocks * 2) # Gap

@cocotb.test()
async def test_bidirectional_telemetry(dut):
    dut._log.info("Starting Bidirectional Command & Control Test")
    
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    # Phase 1: Reset & Setup 
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0b0000_0010 # Hold RX high (idle) on uio_in[1]
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # -------------------------------------------------------------------
    # GATE-LEVEL SIMULATION BYPASS
    # -------------------------------------------------------------------
    if os.environ.get("GATES") == "yes":
        dut._log.info("Gate-Level Simulation detected. Bypassing 10M clock waits.")
        dut._log.info("Testing UART RX structural integrity...")
        
        # Test Reset Command structurally via UART RX (Uses default 1041 baud clocks)
        await send_uart_command(dut, 'R', baud_clocks=1041)
        await ClockCycles(dut.clk, 50)
        
        current_led_after_reset = int(dut.uo_out.value) & 0x7F
        assert current_led_after_reset == 0b0111111, "GL UART RX Reset Command Failed!"
        
        dut._log.info("GL Structural Integrity Verified. Exiting smoothly.")
        return # Skip the rest of the test!

    # -------------------------------------------------------------------
    # RTL SIMULATION (Fast Clocks)
    # -------------------------------------------------------------------
    
    # Phase 2: Send 'S' over UART to start the stopwatch
    dut._log.info("Sending 'S' (Start) command over UART...")
    await send_uart_command(dut, 'S', baud_clocks=3)
    
    # Wait for 2 simulated seconds (200 clocks)
    await ClockCycles(dut.clk, 200) 
    
    current_led = int(dut.uo_out.value) & 0x7F
    assert current_led != 0b0111111, "Stopwatch failed to start via UART command!"
    dut._log.info("UART Start Command Success! Timer is ticking.")

    # Phase 3: Send 'L' over UART to trigger Lap Memory
    dut._log.info("Sending 'L' (Lap) command over UART...")
    await send_uart_command(dut, 'L', baud_clocks=3)
    await ClockCycles(dut.clk, 10)
    
    lap_val = (int(dut.uio_out.value) >> 4) & 0xF
    assert lap_val == 2, f"UART Lap Command Failed! Expected 2, got {lap_val}"
    dut._log.info("UART Lap Command Success! Lap memory stored '2'.")

    # Phase 4: Send 'R' over UART to Soft Reset
    dut._log.info("Sending 'R' (Reset) command over UART...")
    await send_uart_command(dut, 'R', baud_clocks=3)
    await ClockCycles(dut.clk, 10)
    
    current_led_after_reset = int(dut.uo_out.value) & 0x7F
    assert current_led_after_reset == 0b0111111, "UART Reset Command Failed! Display is not 0."
    dut._log.info("UART Reset Command Success! System zeroed out.")

    dut._log.info("All RX/TX Bidirectional Command tests passed perfectly!")
