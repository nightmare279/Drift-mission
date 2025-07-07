fx_version 'cerulean'
game 'gta5'

author 'Nightmare'
description 'Drift job'
lua54 'yes'

shared_scripts {
    'config.lua',
    '@ox_lib/init.lua'
}
client_script 'client.lua'
server_scripts {
    'unlocks.lua',
    'server.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html'
}