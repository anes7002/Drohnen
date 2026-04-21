import re
import os

with open('/home/oscar/Workplace/SYP/Drohnen/Frontend/drohnen_fronted/lib/main.dart', 'r') as f:
    lines = f.readlines()

content = "".join(lines)

# Create directories
os.makedirs('/home/oscar/Workplace/SYP/Drohnen/Frontend/drohnen_fronted/lib/models', exist_ok=True)
os.makedirs('/home/oscar/Workplace/SYP/Drohnen/Frontend/drohnen_fronted/lib/screens', exist_ok=True)
os.makedirs('/home/oscar/Workplace/SYP/Drohnen/Frontend/drohnen_fronted/lib/widgets', exist_ok=True)

print("Split script created")
