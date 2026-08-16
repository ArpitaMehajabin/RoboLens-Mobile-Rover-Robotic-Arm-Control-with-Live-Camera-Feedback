import asyncio
import websockets
import json
import serial
import threading
import time

# ===================== FIREBASE (FCM push notifications) =====================
# Push notifications are optional — if Firebase fails to init (no internet,
# missing key, etc.) the robot control (WebSocket + Serial) must still work.
FIREBASE_ENABLED = False
try:
    import firebase_admin
    from firebase_admin import credentials, messaging

    # Path to the service account key you downloaded from Firebase Console
    # (Project Settings -> Service accounts -> Generate new private key)
    SERVICE_ACCOUNT_PATH = "firebase-service-account.json"
    FCM_TOPIC = "robolens_alerts"

    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)
    FIREBASE_ENABLED = True
    print("[FIREBASE] Initialized successfully.")
except Exception as e:
    print(f"[FIREBASE] Disabled (init failed): {e}")


def send_push_alert(title: str, body: str):
    """Send an FCM push notification to the 'robolens_alerts' topic.
    Never raises — a failure here must not affect robot control."""
    if not FIREBASE_ENABLED:
        return
    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            topic=FCM_TOPIC,
        )
        messaging.send(message)
        print(f"[FIREBASE] Push sent: {title} - {body}")
    except Exception as e:
        print(f"[FIREBASE] Push failed: {e}")


# Human-friendly text for each alert code, used in the push notification body.
ALERT_MESSAGES = {
    "OBSTACLE FRONT": "Obstacle detected — robot stopped",
    "WATCHDOG STOP": "Connection lost — robot auto-stopped",
    "EMERGENCY STOPPED": "Emergency stop activated",
}

# ===================== SERIAL (Arduino) =====================
SERIAL_PORT = "/dev/ttyACM0"
BAUD_RATE = 115200

arduino = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)

connected_clients = set()
main_loop = None  # asyncio event loop, needed to broadcast from the serial thread


# ===================== COMMAND TRANSLATION (App JSON -> Arduino text) =====================
def translate_to_arduino(data: dict) -> str | None:
    t = data.get("type")

    if t == "arm":
        joint = data.get("joint")
        angle = data.get("angle")
        return f"{joint} {angle}\n"

    if t == "move":
        direction = data.get("direction", "stop").upper()
        if direction == "STOP":
            return "M STOP\n"
        return f"M {direction}\n"

    if t == "emergency_stop":
        return "ESTOP\n"

    if t == "settings" and data.get("target") == "speed":
        speed = data.get("value", "medium").upper()
        return f"SPD {speed}\n"

    if t == "settings" and data.get("target") == "armSpeed":
        speed = data.get("value", "medium").upper()
        return f"ASPD {speed}\n"

    return None  # unknown/test messages ignored


# ===================== SERIAL READER THREAD =====================
def serial_reader_thread():
    """Reads every line coming from the Arduino. Broadcasts sensor data (DIST)
    and alert events to all connected app clients over WebSocket, and also
    sends a push notification for alert events (if Firebase is enabled).
    On serial disconnect/error, retries with backoff to avoid a busy-loop."""
    global arduino
    consecutive_errors = 0

    while True:
        try:
            line = arduino.readline().decode(errors="ignore").strip()
            if not line:
                continue
            consecutive_errors = 0  # reset counter after a successful read
            print(f"[ARDUINO] {line}")

            if line.startswith("DIST "):
                parts = line.replace("DIST ", "").split(",")
                if len(parts) == 3:
                    payload = json.dumps({
                        "type": "sensor",
                        "front": int(parts[0]),
                        "left": int(parts[1]),
                        "right": int(parts[2]),
                    })
                    broadcast(payload)

            elif line in ("OBSTACLE FRONT", "WATCHDOG STOP", "EMERGENCY STOPPED"):
                payload = json.dumps({"type": "alert", "message": line})
                broadcast(payload)

                # Push notification — reaches the phone even if the app is
                # closed or in the background.
                send_push_alert("RoboLens Alert", ALERT_MESSAGES.get(line, line))

        except Exception as e:
            consecutive_errors += 1
            # Print every time for the first few errors, then throttle to avoid log spam
            if consecutive_errors <= 3 or consecutive_errors % 20 == 0:
                print(f"[SERIAL ERROR] ({consecutive_errors}) {e}")

            # Mandatory delay to avoid a CPU busy-loop
            time.sleep(1)

            # Try to reopen the port if failures keep happening
            if consecutive_errors % 5 == 0:
                try:
                    arduino.close()
                except Exception:
                    pass
                try:
                    print("[SERIAL] Reconnecting to Arduino...")
                    arduino = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
                    print("[SERIAL] Reconnected.")
                except Exception as reconnect_err:
                    print(f"[SERIAL] Reconnect failed: {reconnect_err}")


def broadcast(message: str):
    """Sends a message to all connected WebSocket clients from the serial thread."""
    if main_loop is None:
        return
    for client in list(connected_clients):
        asyncio.run_coroutine_threadsafe(safe_send(client, message), main_loop)


async def safe_send(client, message):
    try:
        await client.send(message)
    except Exception:
        pass


# ===================== WEBSOCKET HANDLER =====================
async def handler(websocket):
    client_ip = websocket.remote_address[0]
    print(f"[CONNECTED] {client_ip}")
    connected_clients.add(websocket)
    try:
        async for message in websocket:
            print(f"[RECEIVED] {client_ip}: {message}")
            try:
                data = json.loads(message)
            except json.JSONDecodeError:
                print("[WARNING] Invalid JSON")
                continue

            arduino_cmd = translate_to_arduino(data)
            if arduino_cmd:
                arduino.write(arduino_cmd.encode())
                print(f"[TO ARDUINO] {arduino_cmd.strip()}")

            await websocket.send(json.dumps({"status": "received", "echo": message}))
    except websockets.exceptions.ConnectionClosed:
        print(f"[DISCONNECTED] {client_ip}")
    finally:
        connected_clients.discard(websocket)


async def main():
    global main_loop
    main_loop = asyncio.get_running_loop()

    # Start the serial reading thread
    t = threading.Thread(target=serial_reader_thread, daemon=True)
    t.start()

    print("Starting WebSocket server on port 8765...")
    async with websockets.serve(handler, "0.0.0.0", 8765):
        print("Server is running. Waiting for connections...")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
