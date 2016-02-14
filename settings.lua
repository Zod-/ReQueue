local ReQueue = Apollo.GetAddon("ReQueue")

function ReQueue:BuildConfig(ui)
  ui:category("Basic")
  :header("Basic Configuration")
  :pagedivider()
  :check({
    label = "Ignore solo-queue warnings in this group",
    map = "ignoreWarning"
  })
  :check({
    label = "Automatically confirm your roles when you are not the leader of the group",
    map = "autoRoleSelect"
  })

  -- Credits
  :navdivider()
  :category("Credits")
	:header("Developer Credits")
  :note("This addon is developed by Zod Bain@Luminai \
  \nSpecial thanks to the developers of _uiMapper and GeminiHook which made it a lot easier to create this addon.")
end
