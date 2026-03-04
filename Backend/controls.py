import time

class Control:
    def __init__(self, connection):
        """
        Initializes the control with a DroneConnection object.
        Uses direct UDP commands for the Tello SDK.
        """
        self.connection = connection

    def takeoff(self):
        print("[INFO] Taking off...")
        self.connection.send_command("takeoff")

    def land(self):
        print("[INFO] Landing...")
        self.connection.send_command("land")

    def forward(self, distance=50):
        self.connection.send_command(f"forward {distance}")

    def backward(self, distance=50):
        self.connection.send_command(f"back {distance}")

    def left(self, distance=50):
        self.connection.send_command(f"left {distance}")

    def right(self, distance=50):
        self.connection.send_command(f"right {distance}")

    def up(self, distance=30):
        self.connection.send_command(f"up {distance}")

    def down(self, distance=30):
        self.connection.send_command(f"down {distance}")

    def rotate_left(self, angle=45):
        self.connection.send_command(f"ccw {angle}")

    def rotate_right(self, angle=45):
        self.connection.send_command(f"cw {angle}")

    def send_rc(self, a, b, c, d):
        """
        a: left/right (-100 to 100)
        b: forward/backward (-100 to 100)
        c: up/down (-100 to 100)
        d: yaw (-100 to 100)
        """
        self.connection.send_command(f"rc {a} {b} {c} {d}")

    def emergency_stop(self):
        print("[EMERGENCY STOP]")
        self.connection.send_command("emergency")
