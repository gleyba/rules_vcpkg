load("@aspect_bazel_lib//lib/private:base64.bzl", "BASE64_CHARS")

_HEX_TO_BIN = {
    "0": "0000",
    "1": "0001",
    "2": "0010",
    "3": "0011",
    "4": "0100",
    "5": "0101",
    "6": "0110",
    "7": "0111",
    "8": "1000",
    "9": "1001",
    "a": "1010",
    "b": "1011",
    "c": "1100",
    "d": "1101",
    "e": "1110",
    "f": "1111",
}

def _chunk(data, length):
    return [data[i:i + length] for i in range(0, len(data), length)]

def _hex_to_binary_string(hexstr):
    result = []
    for i in range(len(hexstr)):
        s = hexstr[i]
        if s not in _HEX_TO_BIN:
            fail("Unexpected char in hex string: %s" % s)

        result.append(_HEX_TO_BIN[s])

    return "".join(result)

def base64_encode_hexstr(hexstr):
    """Encode HEX characters string to base64

    Args:
        hexstr: HEX string in format: "5f87ffdb83"

    Returns:
        base64 encoded representation in format: "X4f/24M="
    """
    padding = 0
    if len(hexstr) % 6 != 0:
        padding = ((len(hexstr) + 6 - len(hexstr) % 6) - len(hexstr)) // 2

    hexstr = hexstr.lower() + "00" * padding
    binstr = _hex_to_binary_string(hexstr.lower())

    outstring = ""
    for element in _chunk(binstr, 6):
        outstring += BASE64_CHARS[int(element, 2)]

    return outstring if padding == 0 else outstring[:-padding] + "=" * padding
