fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-shops'
description 'DPS shops: clerks who greet and react, then owned shops'
author 'DaemonAlex'
version '0.2.0'

shared_scripts { '@ox_lib/init.lua', 'config.lua', 'config_owned.lua', 'shared/shops.lua', 'shared/owned.lua' }
client_scripts { '@qbx_core/modules/playerdata.lua', 'client/clerk.lua', 'client/threat.lua', 'client/owned.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua', 'server/owned.lua' }

dependencies { 'ox_lib', 'qbx_core', 'wasabi_mdt', 'oxmysql', 'ox_inventory', 'ox_target' }
