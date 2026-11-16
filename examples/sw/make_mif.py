import sys

src = sys.argv[1]
dst = sys.argv[2]

with open(src, "rb") as f:
    data = f.read()

if len(data) % 4:
    data += b"\x00" * (4 - len(data) % 4)

lines = []
for i in range(0, len(data), 4):
    word = int.from_bytes(data[i:i+4], "little")
    lines.append(f"{word:08x}")

with open(dst, "w", encoding="ascii") as f:
    f.write("\n".join(lines))