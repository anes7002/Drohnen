import json
import asyncio
import websockets
import sys

async def view():
    uri = "ws://localhost:8000/rc"
    print("\n" + "="*45)
    print("   DRONE TELEMETRY MONITOR (Live)")
    print("="*45)
    print("Connecting to drone...")
    try:
        async with websockets.connect(uri) as ws:
            print("Connected. Receiving status updates...\n")
            async for message in ws:
                data = json.loads(message)
                if data.get("type") == "telemetry":
                    tele = data.get("data", {})
                    
                    # Get raw values
                    bat = str(tele.get('battery', '---'))
                    h = str(tele.get('height', '---'))
                    t = str(tele.get('temp', '---'))
                    spd = str(tele.get('speed', '--'))
                    ftime = str(tele.get('flight_time', '--s'))
                    
                    # Log cleanup if data is weird
                    if "pitch" in bat or "pitch" in h or "pitch" in t:
                        continue # Skip corrupted frames

                    # Layout: Fixed width formatting to prevent shifting
                    sys.stdout.write(f"\rBattery: {bat:<5} | Height: {h:<9} | Temp: {t:<7} | Speed: {spd:<10} | Time: {ftime:<4}")
                    sys.stdout.flush()
    except Exception as e:
        print(f"\nError: {e}")

if __name__ == "__main__":
    asyncio.run(view())
