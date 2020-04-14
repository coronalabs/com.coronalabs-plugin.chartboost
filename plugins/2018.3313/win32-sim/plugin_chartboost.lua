-- Chartboost plugin

local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name='plugin.chartboost', publisherId='com.coronalabs', version=2 }

-------------------------------------------------------------------------------
-- BEGIN
-------------------------------------------------------------------------------

-- This sample implements the following Lua:
-- 
--    local PLUGIN_NAME = require "plugin_PLUGIN_NAME"
--    PLUGIN_NAME:showPopup()
--    

local function showWarning(functionName)
    print( functionName .. " WARNING: The Chartboost plugin is only supported on Android & iOS devices. Please build for device")
end

function lib.init()
    showWarning("chartboost.init")
end

function lib.load()
    showWarning("chartboost.load")
end

function lib.isLoaded()
    showWarning("chartboost.isLoaded")
    return false
end

function lib.isAdVisible()
    showWarning("chartboost.isAdVisible")
    return false
end

function lib.show()
    showWarning("chartboost.show")
end

function lib.hide()
    showWarning("chartboost.hide")
end

function lib.onBackPressed()
    showWarning("chartboost.onBackPressed")
    return false
end

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return an instance
return lib
