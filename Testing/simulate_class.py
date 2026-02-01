import requests
import hashlib
import hmac
import time
import random

# --- CONFIGURATION ---
BASE_URL = "http://localhost:5000/api"
SECRET_SALT = "64650144b7d4b235198e6b1ca6d3352a921022d311f14e06d45dc4667314155a" # From your .env
SESSION_ID = "YOUR_ACTIVE_SESSION_UUID" # Get this from your Supabase sessions table
CLASS_ID = "CS101"
CURRENT_MINOR = 101 # Match your ESP32/Backend minor

def get_signature(device_id):
    """Mocks the security.js HMAC logic"""
    return hmac.new(SECRET_SALT.encode(), device_id.encode(), hashlib.sha256).hexdigest()

def simulate_student(i):
    student_id = f"STU_{1000 + i}"
    device_id = f"DEV_UUID_{i}"
    sig = get_signature(device_id)
    
    # 1. Step: Check-in
    checkin_payload = {
        "studentId": student_id,
        "classId": CLASS_ID,
        "sessionId": SESSION_ID,
        "deviceId": device_id,
        "deviceSignature": sig,
        "reportedMinor": CURRENT_MINOR,
        "rssi": random.randint(-80, -60)
    }
    
    print(f"🚀 Student {student_id} attempting check-in...")
    res = requests.post(f"{BASE_URL}/attendance/check-in", json=checkin_payload)
    print(f"   Response: {res.status_code} - {res.json().get('message' or 'success')}")

    # 2. Step: Stream RSSI (Simulate 5 data points)
    if res.status_code in [201, 200]:
        stream_payload = {
            "studentId": student_id,
            "classId": CLASS_ID,
            "rssiData": [{"rssi": random.randint(-85, -55), "ts": time.time()} for _ in range(5)]
        }
        requests.post(f"{BASE_URL}/attendance/stream-rssi", json=stream_payload)
        print(f"   📡 RSSI Stream uploaded for {student_id}")

# --- RUN SIMULATION ---
if __name__ == "__main__":
    print(f"🏁 Starting Stress Test for {SESSION_ID}...")
    for i in range(50): # Simulating 50 students
        simulate_student(i)
        time.sleep(0.1) # Small delay to avoid OS socket exhaustion
    print("\n✅ Simulation Complete. Check your Supabase 'attendance' table!")