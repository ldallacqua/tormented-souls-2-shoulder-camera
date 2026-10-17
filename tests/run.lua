SOURCE='src/TormentedShoulderCamera/Scripts'
for _,name in ipairs({'main','camera','config','input','collision','aim','crosshair','motion','aimwalk'}) do
    assert(loadfile(SOURCE..'/'..name..'.lua'))
end
print('PASS: syntax')
dofile('tests/test_collision.lua')
dofile('tests/test_input.lua')
dofile('tests/test_zone_camera.lua')
dofile('tests/test_character_hide.lua')
dofile('tests/test_hold_camera.lua')
dofile('tests/test_aim.lua')
dofile('tests/test_controls.lua')
dofile('tests/test_motion.lua')
dofile('tests/test_aimwalk.lua')
