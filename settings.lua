local ReQueue = Apollo.GetAddon("ReQueue")

function ReQueue:BuildConfig(ui)
  ui:category("Basic")
  :header("Basic Configuration")
  :pagedivider()
  :check({
    label = "Ignore solo-queue warnings in this group",
    map = "ignoreWarning"
  })

  -- Credits
  :navdivider()
  :category("Credits")
	:header("Developer Credits")
  :note("This addon is developed by Zod Bain@Luminai \
  \nSpecial thanks to the developers of _uiMapper and GeminiHook which made it a lot easier to create this addon.")
end
