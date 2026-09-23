import glob, os, re
pattern = re.compile(r'Instance\.new\(["\'](BodyVelocity|BodyGyro|BodyPosition|BodyAngularVelocity)["\']\)')
for path in glob.glob(r'C:\Users\User\.gemini\antigravity\scratch\*.lua'):
    filename = os.path.basename(path)
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        for i, line in enumerate(f, start=1):
            m = pattern.search(line)
            if m:
                print(f'{filename}:{i}: {line.strip()}')
