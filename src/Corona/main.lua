--
--  main.lua
--  Chartboost Sample App
--
--  Copyright (c) 2016 Corona Labs Inc. All rights reserved.
--

local chartboost = require( "plugin.chartboost" )
local widget = require( "widget" )
local json = require("json")

--------------------------------------------------------------------------
-- set up UI
--------------------------------------------------------------------------

display.setStatusBar( display.HiddenStatusBar )
widget.setTheme( "widget_theme_ios" )

-- forward declarations
local sdkReady = false
local appId = "62472ac1ddd544255d577b64"
local appSig = "51ead858631ad979ce72a1e15beb422b2ca8560b"
local platformName = system.getInfo("platformName")

local chartboostLogo = display.newImage("chartboostlogo.png")
chartboostLogo.anchorY = 0
chartboostLogo.x, chartboostLogo.y = display.contentCenterX, 0

local subTitle = display.newText {
    text = "plugin for Corona SDK",
    x = display.contentCenterX,
    y = chartboostLogo.contentHeight + 15,
    font =display.systemFont,
    fontSize = 20
}

local statusText = display.newText {
    text = "Please load an ad",
    x = display.contentCenterX,
    y = display.contentHeight,
    font = display.systemFont,
    fontSize = 10,
    width = 280,
    align = "center"
}
statusText.anchorY = 1

processEventTable = function(event)
    local logString = json.prettify(event):gsub("\\","")
    logString = "\nPHASE: "..event.phase.." - - - - - - - - - - - - - - - - - - - - -\n" .. logString
    print(logString)
end

statusText.text = "Initializing..."

--------------------------------------------------------------------------
-- plugin implementation
--------------------------------------------------------------------------

if platformName == "Android" then
    if system.getInfo("targetAppStore") == "amazon" then
        appId="56da6b030d60257460d00fe2"
        appSig="8b48c5667b2d193c0254c75336c83798ef1a0116"
    else -- Google Play
        appId="56da6aac346b521990910ad1"
        appSig="6d70467d87898ad9e84e7700ca41bdf285e4cd04"
    end
elseif platformName == "iPhone OS" then
    appId="56da6a7643150f0166c4a722"
    appSig="5d37922b50cf04a865e68586c18cd918b763f78a"
else
    print "Unsupported platform"
end

print("AppId: "..appId)
print("SIG: "..appSig)

-- The ChartBoost listener function
local function chartBoostListener( event )
    processEventTable(event)

    local data = (event .data ~= nil) and json.decode(event.data) or {}

    if event.phase == "init" then
        sdkReady = true
        statusText.text = "SDK is ready"

    elseif event.phase == "loaded" then
        statusText.text = "A new "..event.type.." is loaded"

    elseif event.phase == "failed" then
        statusText.text = data.errorMsg
    end
end

-- Initialise ChartBoost
chartboost.init( chartBoostListener, {
    appId = appId,
    appSig = appSig,
    hasUserConsent = true
})

-- Load Interstitial Ad
local loadInterstitialButton = widget.newButton {
    label = "Load Interstitial",
    width = 250,
    fontSize = 15,
    emboss = false,
    labelColor = { default={1,1,1,0.75}, over={0,0,0,0.5} },
    shape = "roundedRect",
    width = 200,
    height = 35,
    cornerRadius = 4,
    fillColor = { default={116/255,150/255,67/255,1}, over={129/255,204/255,20/255,1} },
    strokeColor = { default={255/255,178/255,25/255,1}, over={255/255,178/255,25/255,1} },
    strokeWidth = 2,
    onRelease = function( event )
        if (sdkReady) then
            statusText.text = "Loading interstitial..."
            chartboost.load( "interstitial" )
        end
    end,
}
loadInterstitialButton.x = display.contentCenterX
loadInterstitialButton.y = 175

-- Load Rewarded Video
local loadRewardedVideoButton = widget.newButton
{
    label = "Load Rewarded Video",
    width = 200,
    fontSize = 15,
    emboss = false,
    labelColor = { default={1,1,1,0.75}, over={0,0,0,0.5} },
    shape = "roundedRect",
    width = 200,
    height = 35,
    cornerRadius = 4,
    fillColor = { default={116/255,150/255,67/255,1}, over={129/255,204/255,20/255,1} },
    strokeColor = { default={255/255,178/255,25/255,1}, over={255/255,178/255,25/255,1} },
    strokeWidth = 2,
    onRelease = function( event )
        if (sdkReady) then
            statusText.text = "Loading rewarded video..."
            chartboost.load( "rewardedVideo" )
        end
    end
}
loadRewardedVideoButton.x = display.contentCenterX
loadRewardedVideoButton.y = loadInterstitialButton.y + loadInterstitialButton.contentHeight + loadRewardedVideoButton.contentHeight * 0.25


-- Show Interstitial button
local showInterstitialButton = widget.newButton {
    label = "Show Interstitial",
    width = 200,
    fontSize = 15,
    emboss = false,
    labelColor = { default={0,0,0,0.75}, over={0,0,0,0.5} },
    shape = "roundedRect",
    width = 200,
    height = 35,
    cornerRadius = 4,
    fillColor = { default={175/255,226/255,101/255,1}, over={129/255,204/255,20/255,1} },
    strokeColor = { default={226/255,116/255,90/255,1}, over={255/255,178/255,25/255,1} },
    strokeWidth = 2,
    onRelease = function( event )
        if (sdkReady) then
            if not chartboost.isLoaded( "interstitial" ) then
                native.showAlert( "No ad available", "Please load Interstitial.", { "OK" })
            else
                statusText.text = ""
                chartboost.show( "interstitial" )
            end
        end
    end
}
showInterstitialButton.x = display.contentCenterX
showInterstitialButton.y = 325

-- Show Rewarded Video button
local showRewardedVideoButton = widget.newButton
{
    label = "Show Rewarded Video",
    width = 200,
    fontSize = 15,
    emboss = false,
    labelColor = { default={0,0,0,0.75}, over={0,0,0,0.5} },
    shape = "roundedRect",
    width = 200,
    height = 35,
    cornerRadius = 4,
    fillColor = { default={175/255,226/255,101/255,1}, over={129/255,204/255,20/255,1} },
    strokeColor = { default={226/255,116/255,90/255,1}, over={255/255,178/255,25/255,1} },
    strokeWidth = 2,
    onRelease = function( event )
        if (sdkReady) then
            if not chartboost.isLoaded( "rewardedVideo" ) then
                native.showAlert( "Not available", "Please load Rewarded Video.", { "OK" })
            else
                statusText.text = ""
                chartboost.show( "rewardedVideo" )
            end
        end
    end
}
showRewardedVideoButton.x = display.contentCenterX
showRewardedVideoButton.y = showInterstitialButton.y + showInterstitialButton.contentHeight + showRewardedVideoButton.contentHeight * 0.25

--------------------------------------------------------------------------------------
-- To enable Chartboost to handle the back button on Android (close ads), you need to
-- implement chartboost.onBackPressed() as follows
--------------------------------------------------------------------------------------
local function onKeyEvent( event )
    local phase = event.phase
    local keyName = event.keyName

    if keyName == "back" and phase == "up" then
        if chartboost.onBackPressed() then
            -- chartboost closed an active ad
            print ( "back key handled by chartboost")
            return true -- don't pass the event down the responder chain
        else
            -- handle the back key yourself
            print ("Back key handled by Corona")
        end
    end

    return false
end

Runtime:addEventListener( "key", onKeyEvent )
