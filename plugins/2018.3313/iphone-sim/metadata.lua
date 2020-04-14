local metadata =
{
	plugin =
	{
		format = "staticLibrary",

		-- This is the name without the 'lib' prefix.
		-- In this case, the static library is called: libSTATIC_LIB_NAME.a
		staticLibs = { "ChartboostPlugin", "Chartboost" },

		frameworks = { "AdSupport", "StoreKit", "Foundation", "CoreGraphics", "UIKit", "WebKit" },
		frameworksOptional = {},
	}
}

return metadata
