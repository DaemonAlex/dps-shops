fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-shops'
description 'DPS shops: clerks who greet and react, then owned shops'
author 'DaemonAlex'
version '0.4.0'

shared_scripts { '@ox_lib/init.lua', 'config.lua', 'config_owned.lua', 'shared/shops.lua', 'shared/owned.lua', 'shared/ai.lua' }
client_scripts { '@qbx_core/modules/playerdata.lua', 'client/clerk.lua', 'client/threat.lua', 'client/owned.lua', 'client/ai.lua', 'client/runs.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua', 'server/owned.lua', 'server/ai.lua', 'server/runs.lua' }

dependencies { 'ox_lib', 'qbx_core', 'wasabi_mdt', 'oxmysql', 'ox_inventory', 'ox_target' }
