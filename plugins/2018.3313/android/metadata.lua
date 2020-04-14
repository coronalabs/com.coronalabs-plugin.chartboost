local metadata =
{
    plugin =
    {
        format = 'jar',
        manifest = 
        {
            permissions = {},
            usesPermissions =
            {
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE",
                {name="android.permission.WRITE_EXTERNAL_STORAGE", maxSdkVersion=18},
            },
            usesFeatures = 
            {
            },
            applicationChildElements =
            {
                -- Array of strings
                [[
                <activity android:name="com.chartboost.sdk.CBImpressionActivity"
               android:excludeFromRecents="true"
               android:hardwareAccelerated="true"
               android:theme="@android:style/Theme.Translucent.NoTitleBar.Fullscreen"
               android:configChanges="keyboardHidden|orientation|screenSize" />
                ]]
            }
        }
    },

    coronaManifest = {
        dependencies = {
            ["shared.google.play.services.ads.identifier"] = "com.coronalabs"
        }
    }
}

return metadata
