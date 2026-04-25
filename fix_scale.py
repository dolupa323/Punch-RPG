import sys

with open('src/ServerScriptService/Server/Services/EquipService.lua', 'rb') as f:
    content = f.read().decode('utf-8', errors='ignore')

content = content.replace(
    'if itemData.optimalTool == "SWORD" then\r\n\t\t\t\t\ttargetSize = 4.0\r\n\t\t\t\telse\r\n\t\t\t\t\ttargetSize = 4.0\r\n\t\t\t\tend',
    'if itemData.optimalTool == "SWORD" then\r\n\t\t\t\t\ttargetSize = 4.0\r\n\t\t\t\telseif itemData.optimalTool == "BOW" or itemData.optimalTool == "CROSSBOW" then\r\n\t\t\t\t\ttargetSize = 6.5\r\n\t\t\t\telse\r\n\t\t\t\t\ttargetSize = 4.0\r\n\t\t\t\tend'
)

with open('src/ServerScriptService/Server/Services/EquipService.lua', 'wb') as f:
    f.write(content.encode('utf-8'))
print('Done!')
