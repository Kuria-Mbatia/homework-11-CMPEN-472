import matplotlib.pyplot as plt
import numpy as np
import re  # Import regex module

def parse_adc_data(filename):
    """Parse ADC data from the output file."""
    adc_data = []
    collecting = False

    with open(filename, 'r') as f:
        lines = f.readlines()

    for line in lines:
        line = line.strip()
        
        # Start collecting after seeing "analog signal acquisition" line
        if "analog signal acquisition" in line:
            collecting = True
            continue
        
        # Stop if we see a new HW11> prompt that's not followed by a number
        if collecting and line.startswith("HW11>") and not re.search(r'HW11>\s+\d+', line):
            if not line.strip() == "HW11>":  # Skip if it's just a prompt with nothing after it
                collecting = False
                continue
        
        # Extract number from lines with HW11> prefix
        if collecting and line.startswith("HW11>"):
            match = re.search(r'HW11>\s+(\d+)', line)
            if match:
                adc_data.append(int(match.group(1)))
                continue
        
        # Regular data lines
        if collecting:
            try:
                value = int(line)
                adc_data.append(value)
            except ValueError:
                # Skip lines that aren't numbers
                pass
    
    return adc_data

def plot_adc_analysis(adc_data):
    """Analyze and plot the ADC data."""
    if not adc_data:
        print("No ADC data found.")
        return
    
    n_points = len(adc_data)
    # Create time axis in milliseconds (8kHz sampling rate mentioned in file)
    time_axis = np.arange(0, n_points) * (1000/8000)  # ms
    
    # 1. Plot Full Waveform
    plt.figure(figsize=(10, 5))
    plt.plot(time_axis, adc_data)
    plt.title(f'ADC Signal (Full) - {n_points} points')
    plt.xlabel('Time (ms)')
    plt.ylabel('Value (0-255)')
    plt.grid(True)
    plt.show()
    
    # 2. Plot Zoomed View (first 200 samples)
    zoom_end = min(200, n_points)
    plt.figure(figsize=(10, 5))
    plt.plot(time_axis[:zoom_end], adc_data[:zoom_end])
    plt.title(f'ADC Signal (Zoomed) - {zoom_end} points')
    plt.xlabel('Time (ms)')
    plt.ylabel('Value (0-255)')
    plt.grid(True)
    plt.show()
    
    # 3. Plot FFT
    plot_fft(adc_data, "ADC Signal", 8000)  # 8kHz sampling rate

def plot_fft(wave_data, title, sample_rate=8000):
    """Plot FFT of the waveform data in its own figure."""
    n = len(wave_data)
    if n == 0:
        print(f"Skipping FFT for {title}: No data.")
        return
    
    yf = np.fft.fft(wave_data)
    xf = np.fft.fftfreq(n, 1/sample_rate)[:n//2]  # Frequency axis in Hz
    
    plt.figure(figsize=(10, 5))
    plt.plot(xf, 2.0/n * np.abs(yf[0:n//2]))
    plt.title(f'FFT of {title} - {n} points')
    plt.xlabel('Frequency (Hz)')
    plt.ylabel('Magnitude')
    plt.xlim(0, sample_rate/2)  # Nyquist frequency
    plt.grid(True)
    plt.show()

# Main execution
if __name__ == "__main__":
    try:
        # Parse ADC data
        adc_data = parse_adc_data('RxData3Sim.txt')
        print(f"Found {len(adc_data)} ADC data points")
        
        # Plot analysis
        plot_adc_analysis(adc_data)
        
    except FileNotFoundError:
        print("Error: RxData3Sim.txt not found.")
    except Exception as e:
        print(f"An error occurred: {e}")