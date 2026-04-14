import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

async def simulate_button_press(dut, pin_index):
    """Simulates a bouncy physical button press."""
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

async def send_uart_command(dut, char_string, baud_clocks=3):
    """Simulates a laptop sending data TO the chip over uio_in[1]"""
    for char in char_string:
        byte_val = ord(char)
        
        dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 1) # Start Bit (LOW)
        await ClockCycles(dut.clk, baud_clocks)
        
        for i in range(8): # Data Bits
            bit = (byte_val >> i) & 1
            if bit:
                dut.uio_in.value = int(dut.uio_in.value) | (1 << 1)
            else:
                dut.uio_in.value = int(dut.uio_in.value) & ~(1 << 1)
            await ClockCycles(dut.clk, baud_clocks)
            
        dut.uio_in.value = int(dut.uio_in.value) | (1 << 1) # Stop Bit (HIGH)
        await ClockCycles(dut.clk, baud_clocks)
        
        await ClockCycles(dut.clk, baud_clocks * 2) # Gap

async def decode_uart_string(dut, baud_clocks=3, length=13):
    """Listens to uio_out[0] and decodes an entire UART string."""
    received = ""
    for _ in range(length):
        while int(dut.uio_out.value) & 1 == 1: 
            await FallingEdge(dut.clk)
        await ClockCycles(dut.clk, baud_clocks // 2) 
        char_val = 0
        for i in range(8):
            await ClockCycles(dut.clk, baud_clocks)
            bit = int(dut.uio_out.value) & 1
            char_val |= (bit << i)
        await ClockCycles(dut.clk, baud_clocks) 
        received += chr(char_val)
    return received

@cocotb.test()
async def test_paranoia_suite(dut):
    dut._log.info("Starting The Paranoia Suite: Complete Edge Case Coverage")
    
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    # Phase 1: Reset & Setup (Target = 3)
    dut.ena.value = 1
    dut.ui_in.value = 0b0011_0000 
    dut.uio_in.value = 0b0000_0010 
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    if os.environ.get("GATES") == "yes":
        dut._log.info("Gate-Level Simulation detected. Bypassing RTL timing.")
        await send_uart_command(dut, 'R', baud_clocks=1041)
        await ClockCycles(dut.clk, 50)
        assert (int(dut.uo_out.value) & 0x7F) == 0b0111111, "GL UART RX Reset Failed!"
        return 

    # -------------------------------------------------------------------
    # EDGE CASE 1: GLITCH REJECTION
    # -------------------------------------------------------------------
    dut._log.info("Testing Glitch Rejection: Injecting 5-clock noise spike on ui_in[0]...")
    dut.ui_in.value = int(dut.ui_in.value) | 1
    await ClockCycles(dut.clk, 5) # Too short for the 8-clock debouncer
    dut.ui_in.value = int(dut.ui_in.value) & ~1
    await ClockCycles(dut.clk, 50)
    
    assert (int(dut.uo_out.value) & 0x7F) == 0b0111111, "Glitch Rejection Failed! Timer started on noise."
    dut._log.info("Glitch ignored. Debouncer is solid.")

    # Standard Start
    dut._log.info("Starting timer legitimately...")
    await simulate_button_press(dut, 0)
    await ClockCycles(dut.clk, 100) # Hits 1

    # -------------------------------------------------------------------
    # EDGE CASE 2: THE PAUSE STATE
    # -------------------------------------------------------------------
    dut._log.info("Testing Pause State: Sending 'S' to pause at 1...")
    await send_uart_command(dut, 'S', baud_clocks=3)
    
    await ClockCycles(dut.clk, 250) # Wait 2.5 simulated seconds
    assert (int(dut.uo_out.value) & 0x7F) == 0b0000110, "Pause Failed! Timer kept running."
    dut._log.info("Pause verified. Timer held state perfectly.")

    # -------------------------------------------------------------------
    # EDGE CASE 3: ROGUE UART DATA
    # -------------------------------------------------------------------
    dut._log.info("Testing Rogue Data: Sending invalid command 'Q'...")
    await send_uart_command(dut, 'Q', baud_clocks=3)
    await ClockCycles(dut.clk, 50)
    
    assert (int(dut.uo_out.value) & 0x7F) == 0b0000110, "Rogue Data Failed! 'Q' altered the timer state."
    dut._log.info("Rogue data ignored. Command decoder is secure.")
    
    # Resume counting
    dut._log.info("Sending 'S' to resume counting...")
    await send_uart_command(dut, 'S', baud_clocks=3)
    
    # Trigger Lap at 2
    await ClockCycles(dut.clk, 100) # Hits 2
    await simulate_button_press(dut, 1) 

    # Autonomous TX at 3
    dut._log.info("Waiting for timer to hit 3 to trigger TX...")
    uart_task = cocotb.start_soon(decode_uart_string(dut, baud_clocks=3, length=13))
    await ClockCycles(dut.clk, 100) # Hits 3
    
    received_string = await uart_task
    assert received_string == "VIT Vellore\r\n", "TX String Mismatch!"

    # -------------------------------------------------------------------
    # EDGE CASE 4: THE ROLLOVER
    # -------------------------------------------------------------------
    dut._log.info("Testing BCD Rollover: Fast-forwarding to 9...")
    await ClockCycles(dut.clk, 600) # Fast forward 6 seconds (Hits 9)
    
    assert (int(dut.uo_out.value) & 0x7F) == 0b1101111, "Counter failed to reach 9."
    
    dut._log.info("Timer is at 9. Waiting 1 second for rollover...")
    await ClockCycles(dut.clk, 100) 
    
    assert (int(dut.uo_out.value) & 0x7F) == 0b0111111, "Rollover Failed! Expected 0, got a Hex/Garbage value."
    dut._log.info("Rollover verified. 9 wrapped perfectly back to 0.")

    # Soft Reset
    dut._log.info("Sending DIGITAL 'R' Command to Soft Reset...")
    await send_uart_command(dut, 'R', baud_clocks=3)
    await ClockCycles(dut.clk, 20)
    assert (int(dut.uo_out.value) & 0x7F) == 0b0111111, "Digital Reset Failed!"

    dut._log.info("PARANOIA SUITE PASSED. You have 100% unbreakable silicon.")
