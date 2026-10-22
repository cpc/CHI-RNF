import sys
import argparse

def convert(input_file, output_file, bit_width=32, pad_to=16):
    """
    input_file: Path to your hex file (41014081...)
    output_file: Path for the binary ascii output (01000001...)
    bit_width: The width of each word (default 32)
    pad_to: Cacheline boundary in words (default 16 for 512-bit lines)
    """
    try:
        with open(input_file, 'r') as f:
            # Filter out empty lines, comments, and address tags (@...)
            hex_lines = [
                line.strip() for line in f 
                if line.strip() and not line.strip().startswith(('@', '/', '#', '*'))
            ]

        # Calculate padding to prevent the "dropped last cacheline" bug
        if pad_to > 0:
            remainder = len(hex_lines) % pad_to
            if remainder != 0:
                padding_needed = pad_to - remainder
                print(f"[*] Padding: Adding {padding_needed} zero-words to align to {pad_to}-word boundary.")
                hex_lines.extend(["0" * (bit_width // 4)] * padding_needed)

        binary_ascii_lines = []
        for line_num, h_str in enumerate(hex_lines, 1):
            try:
                # Convert hex to integer, then to binary string padded to bit_width
                val = int(h_str, 16)
                bin_str = bin(val)[2:].zfill(bit_width)
                
                # If hex string was longer than bit_width, bin_str will be too long
                if len(bin_str) > bit_width:
                    bin_str = bin_str[-bit_width:]
                
                binary_ascii_lines.append(bin_str)
            except ValueError:
                print(f"[!] Error: Invalid hex on line {line_num}: '{h_str}'")
                sys.exit(1)

        with open(output_file, 'w') as f_out:
            f_out.write("\n".join(binary_ascii_lines) + "\n")

        print(f"[+] Success: {output_file} created with {len(binary_ascii_lines)} lines.")

    except FileNotFoundError:
        print(f"[!] Error: File '{input_file}' not found.")
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Hex ASCII to Binary ASCII for VHDL textio")
    parser.add_argument("input", help="Source .hex file")
    parser.add_argument("output", help="Target .hex or .bin file")
    parser.add_argument("-w", "--width", type=int, default=32, help="Bit width per line (default 32)")
    parser.add_argument("-p", "--pad", type=int, default=16, help="Word alignment for cachelines (default 16)")

    args = parser.parse_args()
    convert(args.input, args.output, args.width, args.pad)