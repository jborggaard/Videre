using GLFW
using VulkanCore

include(joinpath(@__DIR__, "..", "vkhelper.jl"))

const WIDTH = 800
const HEIGHT = 600

## init GLFW window
GLFW.WindowHint(GLFW.CLIENT_API, GLFW.NO_API)    # not to create an OpenGL context
GLFW.WindowHint(GLFW.RESIZABLE, 0)
window = GLFW.CreateWindow(WIDTH, HEIGHT, "Vulkan")

## init Vulkan
# create instance
apiVersion = vk.VK_MAKE_VERSION(1, 1, 0)
appInfoRef = VkApplicationInfo("Application Name: Create Instance", v"1.0.0", "No Engine Name", v"1.0.0", apiVersion) |> Ref
requiredExtensions = GLFW.GetRequiredInstanceExtensions()
# check extension
checkextensions(requiredExtensions)
enabledExtensionCount = length(requiredExtensions)
ppEnabledExtensionNames = strings2pp(requiredExtensions)
createInfoRef = VkInstanceCreateInfo(appInfoRef, 0, C_NULL, enabledExtensionCount, ppEnabledExtensionNames) |> Ref

# create instance
instanceRef = Ref{vk.VkInstance}(C_NULL)
result = vk.vkCreateInstance(createInfoRef, C_NULL, instanceRef)
result != vk.VK_SUCCESS && error("failed to create instance!")
instance = instanceRef[]

## main loop
while !GLFW.WindowShouldClose(window)
    GLFW.PollEvents()
end

## clean up
vk.vkDestroyInstance(instance, C_NULL)
GLFW.DestroyWindow(window)
