import socket,re,time,sys
SOCK="/tmp/ttyS0.sock"
_ESC=re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[@-Z\\-_]")
strip=lambda x:_ESC.sub("",x)
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
for _ in range(30):
    try: s.connect(SOCK); break
    except OSError: time.sleep(2)
s.setblocking(False)
buf=""
def pump(t):
    global buf; end=time.time()+t
    while time.time()<end:
        try:
            d=s.recv(4096)
            if d: buf+=d.decode("utf-8","replace")
            else: time.sleep(0.1)
        except OSError: time.sleep(0.1)
def send(x): s.sendall(x.encode())
def wait(pat,to):
    end=time.time()+to
    while time.time()<end:
        pump(1.0)
        if re.search(pat,strip(buf[-6000:])): return True
    return False
send("\x03")
end=time.time()+300; got=False
while time.time()<end:
    pump(2.0); send("\r")
    if re.search(r"login:",strip(buf[-3000:])): got=True; break
if not got: print("NO LOGIN"); sys.exit(2)
send("root\r"); wait("[Pp]assword:",30); send("rtdemo123\r")
wait(r"[#\$] ",60)
buf=""
# split marker so the shell-echo of the command (DONE\"\"MARK) differs from real output (DONEMARK)
send("cyclictest -D 20 -m -Sp99 -i 200 -q; echo DONE\"\"MARK\r")
ok=wait("DONEMARK",120)
print("=== cyclictest output (marker_seen=%s) ===" % ok)
# print the tail containing the T: lines
print(strip(buf)[-1500:])
