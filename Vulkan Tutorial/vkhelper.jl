using GLFW
using VulkanCore

# helper functions
"""
    strings2pp(names) -> ppNames
Dump a pointer that is of type `Ptr{String}` from a Julia `String` array.
"""
strings2pp(names::Vector{String}) = (ptr = Base.cconvert(Ptr{Cstring}, names); GC.@preserve ptr Base.unsafe_convert(Ptr{Cstring}, ptr))

vktuple2string(x) = x |> collect |> String |> s->strip(s, '\0')

# helper types
struct ExtensionProperties
    extensionName::String
    specVersion::Int
end
ExtensionProperties(extension::vk.VkExtensionProperties) = ExtensionProperties(vktuple2string(extension.extensionName), Int(extension.specVersion))

struct LayerProperties
    layerName::String
    specVersion::Int
    implementationVersion::Int
    description::String
end
LayerProperties(layer::vk.VkLayerProperties) = LayerProperties(vktuple2string(layer.layerName), Int(layer.specVersion), Int(layer.implementationVersion), vktuple2string(layer.description))


function get_supported_extensions()
    extensionCountRef = Ref{Cuint}(0)
    vk.vkEnumerateInstanceExtensionProperties(C_NULL, extensionCountRef, C_NULL)
    extensionCount = extensionCountRef[]
    supportedExtensions = Vector{vk.VkExtensionProperties}(undef, extensionCount)
    vk.vkEnumerateInstanceExtensionProperties(C_NULL, extensionCountRef, supportedExtensions)
    return [ExtensionProperties(ext) for ext in supportedExtensions]
end

function checkextensions(requiredExtensions::Vector{T}) where {T<:AbstractString}
    supportedExtensions = get_supported_extensions()
    println("available extensions:")
    for ext in supportedExtensions
        println("  ", ext.extensionName, ": ", ext.specVersion)
    end
    supportedExtensionNames = [ext.extensionName for ext in supportedExtensions]
    setdiff(requiredExtensions, supportedExtensionNames) |> isempty || error("not all required extensions are supported.")
end

function get_supported_layers()
    layerCountRef = Ref{Cuint}(0)
    vk.vkEnumerateInstanceLayerProperties(layerCountRef, C_NULL)
    layerCount = layerCountRef[]
    availableLayers = Vector{vk.VkLayerProperties}(undef, layerCount)
    vk.vkEnumerateInstanceLayerProperties(layerCountRef, availableLayers)
    return [LayerProperties(layer) for layer in availableLayers]
end

function checklayers(requiredLayers::Vector{T}) where {T<:AbstractString}
    supportedLayers = get_supported_layers()
    println("available layers:")
    for layer in supportedLayers
        println("  ", layer.layerName, ": ", layer.description, ": ", layer.specVersion, " -- ", layer.implementationVersion)
    end
    supportedLayerNames = [layer.layerName for layer in supportedLayers]
    setdiff(requiredLayers, supportedLayerNames) |> isempty || error("not all required layers are supported.")
end


# helper constructors
function VkApplicationInfo(applicationName::AbstractString, applicationVersion::VersionNumber, engineName::AbstractString, engineVersion::VersionNumber, apiVersion::Integer)
    sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO
    pNext = C_NULL    # reserved for extension-specific structure
    pApplicationName = pointer(transcode(Cuchar, applicationName))    # TODO: use codeunits(applicationName) in julia-v0.7+
    vkApplicationVersion = vk.VK_MAKE_VERSION(applicationVersion.major, applicationVersion.minor, applicationVersion.patch)
    pEngineName = pointer(transcode(Cuchar, applicationName))    # TODO: use codeunits(engineName) in julia-v0.7+
    vkEngineVersion = vk.VK_MAKE_VERSION(engineVersion.major, engineVersion.minor, engineVersion.patch)
    return vk.VkApplicationInfo(sType, pNext, pApplicationName, vkApplicationVersion, pEngineName, vkEngineVersion, Cuint(apiVersion))
end

function VkInstanceCreateInfo(applicationInfoRef::Ref{vk.VkApplicationInfo}, enabledLayerCount::Integer, ppEnabledLayerNames::Ref, enabledExtensionCount::Integer, ppEnabledExtensionNames::Ref)
    sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
    pNext = C_NULL    # reserved for extension-specific structure
    flags = UInt32(0)    # reserved for future use
    pApplicationInfo = Base.unsafe_convert(Ptr{vk.VkApplicationInfo}, applicationInfoRef)
    return vk.VkInstanceCreateInfo(sType, pNext, flags, pApplicationInfo, Cuint(enabledLayerCount), ppEnabledLayerNames, Cuint(enabledExtensionCount), ppEnabledExtensionNames)
end

function VkInstanceCreateInfo(applicationInfoRef, layerNames::Vector{String}, extensionNames::Vector{String})
    enabledLayerCount = length(layerNames)
    ppEnabledLayerNames = strings2pp(layerNames)
    enabledExtensionCount = length(extensionNames)
    ppEnabledExtensionNames = strings2pp(extensionNames)
    return VkInstanceCreateInfo(applicationInfoRef, enabledLayerCount, ppEnabledLayerNames, enabledExtensionCount, ppEnabledExtensionNames)
end

function VkDebugReportCallbackCreateInfoEXT(debugcallback, flags::vk.VkDebugReportFlagsEXT=vk.VK_DEBUG_REPORT_ERROR_BIT_EXT, pUserData=C_NULL)
    sType = vk.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT
    pNext = C_NULL    # reserved for extension-specific structure
    pfnCallback = @cfunction($debugcallback, vk.VkBool32, (vk.VkDebugReportFlagsEXT, vk.VkDebugReportObjectTypeEXT, Culonglong, Csize_t, Cint, Ptr{Cchar}, Ptr{Cchar}, Ptr{Cvoid}))
    GC.@preserve pfnCallback begin
        ptr = Base.unsafe_convert(Ptr{Cvoid}, pfnCallback)
        ret = vk.VkDebugReportCallbackCreateInfoEXT(sType, pNext, flags, ptr, pUserData)
    end
    return ret
end

function VkCreateDebugReportCallbackEXT(instance, callbackInfoRef, allocatorRef, callbackRef)
    fnptr = vk.vkGetInstanceProcAddr(instance, "vkCreateDebugReportCallbackEXT") |> vk.PFN_vkCreateDebugReportCallbackEXT
    ccall(fnptr, vk.VkResult, (vk.VkInstance, Ptr{vk.VkDebugReportCallbackCreateInfoEXT}, Ptr{vk.VkAllocationCallbacks},
                               Ptr{vk.VkDebugReportCallbackEXT}), instance, callbackInfoRef, allocatorRef, callbackRef)
end
VkCreateDebugReportCallbackEXT(instance, callbackInfoRef, callbackRef) = VkCreateDebugReportCallbackEXT(instance, callbackInfoRef, C_NULL, callbackRef)

function VkDestroyDebugReportCallbackEXT(instance, callback, allocatorRef=C_NULL)
    fnptr = vk.vkGetInstanceProcAddr(instance, "vkDestroyDebugReportCallbackEXT") |> vk.PFN_vkCreateDebugReportCallbackEXT
    ccall(fnptr, vk.VkResult, (vk.VkInstance, vk.VkDebugReportCallbackEXT, Ptr{vk.VkAllocationCallbacks}), instance, callback, allocatorRef)
end
