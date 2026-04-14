# Phase 3: Wait for 1, then hit Lap
    await ClockCycles(dut.clk, 100) # 100 clocks = 1 sec passes
    dut._log.info("Timer hit 1. Pressing Lap Button!")
    await simulate_button_press(dut, 1) # Hit Lap (ui_in[1])
    
    lap_val = (int(dut.uio_out.value) >> 4) & 0xF
    assert lap_val == 1, f"Lap Memory Failed! Expected 1, got {lap_val}"
    dut._log.info("Lap memory correctly stored '1' in uio_out[7:4].")

    # Phase 4: Wait for the Alarm (Target = 3) and intercept UART
    dut._log.info("Waiting for timer to hit target (3) to trigger UART...")
    
    # Start a background task to listen to the UART line
    uart_task = cocotb.start_soon(decode_uart_string(dut, baud_clocks=3, length=13))
    
    # Wait for the timer to count 2, then 3. (2 seconds = 200 clocks)
    await ClockCycles(dut.clk, 200) 
    
    # Check if the decimal point (Alarm LED) turned on
    dp_led = (int(dut.uo_out.value) >> 7) & 1
    assert dp_led == 1, "Alarm LED (uo_out[7]) did not turn on!"
    
    # Await the UART string decoding
    received_string = await uart_task
    dut._log.info(f"UART Transmitted: {repr(received_string)}")
    
    expected_string = "VIT Vellore\r\n"
    assert received_string == expected_string, "UART string mismatch!"
    
    dut._log.info("All Telemetry, Lap Memory, and Alarm tests passed perfectly!")
