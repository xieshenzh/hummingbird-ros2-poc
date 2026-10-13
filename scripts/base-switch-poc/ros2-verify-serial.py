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
        if re.search(pat,strip(buf[-8000:])): return True
    return False
send("\x03")
end=time.time()+300; got=False
while time.time()<end:
    pump(2.0); send("\r")
    if re.search(r"login:",strip(buf[-3000:])): got=True; break
if not got: print("NO LOGIN"); sys.exit(2)
send("root\r"); wait("[Pp]assword:",30); send("rtdemo123\r")
wait(r"[#\$] ",60); buf=""
cmd=("source /usr/lib64/ros-jazzy/setup.bash; export HOME=/root; mkdir -p /root/.ros/log; "
     "echo RMW=$RMW_IMPLEMENTATION; echo PKGS=$(ros2 pkg list 2>/dev/null | wc -l); "
     "ros2 topic echo --once /pocver std_msgs/msg/String >/tmp/e.out 2>/tmp/e.err & "
     "sleep 5; for i in $(seq 1 12); do ros2 topic pub -1 /pocver std_msgs/msg/String {data: ROS2_ON_RT_OK} >/dev/null 2>&1; sleep 0.5; done; "
     "sleep 1; echo ECHOSTART; cat /tmp/e.out; echo ECHOEND; "
     "echo TOPICS=$(ros2 topic list 2>/dev/null | wc -l); "
     "echo LOGFILE=$(ls /root/.ros/log/*.log 2>/dev/null | head -1); "
     "echo FIN\"\"MARK\r")
send(cmd)
ok=wait("FINMARK",150)
print("=== ROS2 functional test on booted RT VM (marker=%s) ===" % ok)
print(strip(buf)[-2000:])
