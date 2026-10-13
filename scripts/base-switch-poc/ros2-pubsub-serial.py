import socket,re,time,sys
SOCK="/tmp/ttyS0.sock"
_ESC=re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[@-Z\\-_]")
strip=lambda x:_ESC.sub("",x)
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
for _ in range(30):
    try: s.connect(SOCK); break
    except OSError: time.sleep(2)
s.setblocking(False); buf=""
def pump(t):
    global buf; end=time.time()+t
    while time.time()<end:
        try:
            d=s.recv(4096)
            if d: buf+=d.decode("utf-8","replace")
            else: time.sleep(0.1)
        except OSError: time.sleep(0.1)
def slow(x):
    for c in x: s.sendall(c.encode()); time.sleep(0.012)
def send(x): s.sendall(x.encode())
def wait(pat,to):
    end=time.time()+to
    while time.time()<end:
        pump(1.0)
        if re.search(pat,strip(buf[-8000:])): return True
    return False
send("\x03")
end=time.time()+300; ok=False
while time.time()<end:
    pump(2.0); send("\r")
    if re.search(r"login:",strip(buf[-3000:])): ok=True; break
if not ok: print("NO LOGIN"); sys.exit(2)
slow("root\n"); wait("[Pp]assword:",30); slow("rtdemo123\n")
wait(r"[#\$] ",60); buf=""
slow("cat > /root/t.sh <<\"EOS\"\n")
for line in [
 "source /usr/lib64/ros-jazzy/setup.bash",
 "export HOME=/root; mkdir -p /root/.ros/log",
 "ros2 topic echo --once /pocver std_msgs/msg/String > /root/e.out 2>/root/e.err &",
 "ros2 topic pub /pocver std_msgs/msg/String \"{data: ROS2_ON_RT_OK}\" -r 3 >/dev/null 2>&1 &",
 "PP=$!",
 "for i in $(seq 1 50); do [ -s /root/e.out ] && break; sleep 1; done",
 "kill $PP 2>/dev/null",
 "echo RESULT_LINE:; cat /root/e.out",
 "EOS",
]:
    slow(line+"\n")
wait(r"[#\$] ",20); buf=""
slow("bash /root/t.sh\n")
got=wait("ROS2_ON_RT_OK",90)     # token only in script OUTPUT, not the typed line
print("=== pub/sub on booted RT VM: ROUND-TRIP %s ===" % ("PASS" if got else "NOT SEEN"))
print(strip(buf)[-1000:])
