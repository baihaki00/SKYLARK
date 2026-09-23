import re

with open(r'C:\Users\User\.gemini\antigravity\scratch\AnimationLabController.lua', 'r', encoding='utf-8') as f:
    text = f.read()

# Let's inspect where createPrecisionSlider is defined
# We want createPrecisionSlider to be defined BEFORE Sub-tab 1 do block, or pre-declared
# Let's check lines 960 to 1090
m = re.search(r'(local function createPrecisionSlider\(parent, yPos, labelText.*?\nend\n)', text, re.DOTALL)
assert m, 'createPrecisionSlider not found'
slider_func_code = m.group(1)

# Remove createPrecisionSlider from its original position
text = text.replace(slider_func_code, '')

# Declare forward locals before Sub-tab 1
old_sub1_header = '''--------------------------------------------------------------------------------
-- 4A. SUB-TAB 1: ANIMATION STUDIO (BROWSER, PRECISION KNOBS, COMBO)
--------------------------------------------------------------------------------'''

new_sub1_header = f'''{slider_func_code}
local savePermBtn, statusToast, selectAnimation

--------------------------------------------------------------------------------
-- 4A. SUB-TAB 1: ANIMATION STUDIO (BROWSER, PRECISION KNOBS, COMBO)
--------------------------------------------------------------------------------
do'''

assert old_sub1_header in text, 'old_sub1_header not found'
text = text.replace(old_sub1_header, new_sub1_header)

text = text.replace('local savePermBtn = Instance.new("TextButton")', 'savePermBtn = Instance.new("TextButton")')
text = text.replace('local statusToast = Instance.new("TextLabel")', 'statusToast = Instance.new("TextLabel")')
text = text.replace('local function selectAnimation(item)', 'selectAnimation = function(item)')

# Close Sub-tab 1 do block before the forward declarations for 4B
old_4b_pre = '''-- Forward declarations for controls referenced across tabs & Section 9 event listeners'''
new_4b_pre = '''end

-- Forward declarations for controls referenced across tabs & Section 9 event listeners'''

assert old_4b_pre in text, 'old_4b_pre not found'
text = text.replace(old_4b_pre, new_4b_pre)

with open(r'C:\Users\User\.gemini\antigravity\scratch\AnimationLabController.lua', 'w', encoding='utf-8') as f:
    f.write(text)

lines = text.splitlines()
root_locals = [l.strip() for l in lines if l.startswith('local ')]
print(f'Total root-level locals now: {len(root_locals)}')
