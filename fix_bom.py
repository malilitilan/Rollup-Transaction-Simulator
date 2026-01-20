import sys
content = open('contracts/rollup-transaction-simulator.clar', 'rb').read()
if content.startswith(b'\xef\xbb\xbf'):
    content = content[3:]
open('contracts/rollup-transaction-simulator.clar', 'wb').write(content)
