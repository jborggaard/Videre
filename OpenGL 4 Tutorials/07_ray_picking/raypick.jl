include("glutils.jl")

@static if is_apple()
    const VERSION_MAJOR = 4
    const VERSION_MINOR = 1
end

# window init global variables
glfwWidth = 640
glfwHeight = 480
window = C_NULL

# start OpenGL
@assert startgl()

glEnable(GL_DEPTH_TEST)
glDepthFunc(GL_LESS)

# set camera
resetcamera()
set_camera_position(GLfloat[0.0, 0.0, 5.0])

# projective matrix
let
    near = 0.1            # clipping near plane
    far = 100.0           # clipping far plane
    fov = deg2rad(67)
    global function get_projective_matrix()
        aspectRatio = glfwWidth / glfwHeight
        range = tan(0.5*fov) * near
        Sx = 2.0*near / (range * aspectRatio + range * aspectRatio)
        Sy = near / range
        Sz = -(far + near) / (far - near)
        Pz = -(2.0*far*near) / (far - near)
        return GLfloat[ Sx   0.0  0.0  0.0;
                        0.0   Sy  0.0  0.0;
                        0.0  0.0   Sz   Pz;
                        0.0  0.0 -1.0  0.0]
    end
end

# ray casting
function screen2world(mouseX::Real, mouseY::Real)
    # screen space (window space)
    x = 2.0*mouseX/glfwWidth - 1.0
    y = 1.0 - (2.0*mouseY)/glfwHeight
    z = 1.0
    # normalised device space [-1:1, -1:1, -1:1]
    rayNDS = GLfloat[x, y, z]
    # clip space [-1:1, -1:1, -1:1, -1:1]
    rayClip = GLfloat[rayNDS[1], rayNDS[2], -1, 1]
    # eye space [-x:x, -y:y, -z:z, -w:w]
    rayEye = inv(get_projective_matrix()) * rayClip
    rayEye = GLfloat[rayEye[1], rayEye[2], -1, 0]
    # world space [-x:x, -y:y, -z:z, -w:w]
    rayWorldHomo = inv(get_view_matrix()) * rayEye
    rayWorld = rayWorldHomo[1:3]
    # normalize
    normalize!(rayWorld)
    return rayWorld
end

function raysphere(rayOriginWorld, rayDirectionWorld, sphereCenterWorld, shpereRadius)
    intersectionDistance = 0
    # quadratic parameters
    distance = rayOriginWorld - sphereCenterWorld
    b = rayDirectionWorld ⋅ distance
    c = distance ⋅ distance - shpereRadius * shpereRadius
    b²MinusC = b * b - c
    # no intersection
    b²MinusC < 0 && (flag = false)
    # one intersection (tangent ray)
    if b²MinusC == 0
        # if behind viewer, throw away
        t = -b + sqrt(b²MinusC)
        t < 0 && (flag = false)
        intersectionDistance = t
        flag = true
    end
    # two intersections (secant ray)
    if b²MinusC > 0
        t₁ = -b + sqrt(b²MinusC)
        t₂ = -b - sqrt(b²MinusC)
        intersectionDistance = t₂
        # if behind viewer, throw away
        t₁ < 0 && t₂ < 0 && (flag = false)
        t₁ ≥ 0 && t₂ < 0 && (intersectionDistance = t₁)
        flag = true
    end
    return flag, intersectionDistance
end

# spheres in world
const NUM_SPHERES = 4
sphereWorldPositions = GLfloat[-2.0 0.0  0.0;
                                2.0 0.0  0.0;
                               -2.0 0.0 -2.0;
                                1.5 1.0 -1.0]
modelMatrices = Array{Matrix,1}(4)
for i = 1:NUM_SPHERES
    modelMatrices[i] = GLfloat[ 1.0 0.0 0.0 sphereWorldPositions[i,1];
                                0.0 1.0 0.0 sphereWorldPositions[i,2];
                                0.0 0.0 1.0 sphereWorldPositions[i,3];
                                0.0 0.0 0.0                      1.0]
end

const SPHERE_RADIUS = 1
selectedSphere = -1
function mouse_click_callback(window::GLFW.Window, button::Cint, action::Cint, mods::Cint)
    if GLFW.PRESS == action
        xpos, ypos = GLFW.GetCursorPos(window)
        rayWorld = screen2world(xpos, ypos)
        # ray sphere
        closestSphereClicked = -1
        closestIntersection = 0
        for i = 1:NUM_SPHERES
            sp = collect(sphereWorldPositions[i,:])
            flag, distance = raysphere(get_camera_position(), rayWorld, sp, SPHERE_RADIUS)
            if flag
                if (closestSphereClicked == -1) || (distance < closestIntersection)
                    closestSphereClicked = i
                    closestIntersection = distance
                end
            end
        end
        global selectedSphere = closestSphereClicked
        println("sphere ", selectedSphere, " was clicked")
    end
    return nothing
end
# set mouse click callback
GLFW.SetMouseButtonCallback(window, mouse_click_callback)


# load glTF file
sphere = JSON.parsefile(joinpath(@__DIR__, "sphere.gltf"))
accessors = sphere["accessors"]
bufferViews = sphere["bufferViews"]
buffers = sphere["buffers"]
# load sphere position metadata
posAccessor = accessors["accessor_position"]
posBufferView = bufferViews[posAccessor["bufferView"]]
posBuffer = buffers[posBufferView["buffer"]]
# load sphere index metadata
idxAccessor = accessors["accessor_index_0"]
idxBufferView = bufferViews[idxAccessor["bufferView"]]
idxBuffer = buffers[idxBufferView["buffer"]]

# load buffer-blobs
readblob(uri, length, offset) = open(uri) do f
                                    skip(f, offset)
                                    posBlob = read(f, length)
                                end
posBlob = readblob(joinpath(@__DIR__, idxBuffer["uri"]), posBufferView["byteLength"], posBufferView["byteOffset"])
idxBlob = readblob(joinpath(@__DIR__, idxBuffer["uri"]), idxBufferView["byteLength"], idxBufferView["byteOffset"])
points = reinterpret(GLfloat, posBlob) # GLENUM(posAccessor["componentType"]).name => GLfloat
index = reinterpret(GLushort, idxBlob) # GLENUM(idxAccessor["componentType"]).name => GLushort

# create buffers located in the memory of graphic card
pointsVBO = Ref{GLuint}(0)
glGenBuffers(1, pointsVBO)
posTarget = posBufferView["target"]
glBindBuffer(posTarget, pointsVBO[])
glBufferData(posTarget, posBufferView["byteLength"], posBlob, GL_STATIC_DRAW)

indexEBO = Ref{GLuint}(0)
glGenBuffers(1, indexEBO)
idxTarget = idxBufferView["target"]
glBindBuffer(idxTarget, indexEBO[])
glBufferData(idxTarget, idxBufferView["byteLength"], idxBlob, GL_STATIC_DRAW)

# create VAO
vaoID = Ref{GLuint}(0)
glGenVertexArrays(1, vaoID)
glBindVertexArray(vaoID[])
glBindBuffer(posTarget, pointsVBO[])
posStride = posAccessor["byteStride"]
posOffset = posAccessor["byteOffset"] + posBufferView["byteOffset"]
glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, GLsizei(posStride), Ptr{Void}(posOffset))
glEnableVertexAttribArray(0)

# create shader program
vertexShaderPath = joinpath(@__DIR__, "raypick.vert")
fragmentShaderPath = joinpath(@__DIR__, "raypick.frag")
shaderProgramID = createprogram(vertexShaderPath, fragmentShaderPath)
modelMatrixLocation = glGetUniformLocation(shaderProgramID, "model")
viewMatrixLocation = glGetUniformLocation(shaderProgramID, "view")
projMatrixLocation = glGetUniformLocation(shaderProgramID, "proj")
blueLocation = glGetUniformLocation(shaderProgramID, "blue")
glUseProgram(shaderProgramID)
glUniformMatrix4fv(viewMatrixLocation, 1, GL_FALSE, get_view_matrix())
glUniformMatrix4fv(projMatrixLocation, 1, GL_FALSE, get_projective_matrix())

# enable cull face
glEnable(GL_CULL_FACE)
glCullFace(GL_BACK)
glFrontFace(GL_CCW)
# set background color to gray
glClearColor(0.2, 0.2, 0.2, 1.0)


# render
idxTarget = idxBufferView["target"]
idxCount = idxAccessor["count"]
idxComponentType = idxAccessor["componentType"]
idxByteOffset = idxAccessor["byteOffset"]
while !GLFW.WindowShouldClose(window)
    updatefps(window)
    # clear drawing surface
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
    glViewport(0, 0, glfwWidth, glfwHeight)
    # drawing
    glUseProgram(shaderProgramID)
    glBindBuffer(idxTarget, indexEBO[])
    for i = 1:NUM_SPHERES
        if i == selectedSphere
            glUniform1f(blueLocation, 1.0)
        else
            glUniform1f(blueLocation, 0.0)
        end
        glUniformMatrix4fv(modelMatrixLocation, 1, GL_FALSE, modelMatrices[i])
        glDrawElements(GL_TRIANGLES, idxCount, idxComponentType, Ptr{Void}(idxByteOffset))
    end
    # check and call events
    GLFW.PollEvents()
    yield()
    # move camera
    viewMatrix = updatecamera()
    glUniformMatrix4fv(viewMatrixLocation, 1, GL_FALSE, viewMatrix)
    # swap the buffers
    GLFW.SwapBuffers(window)
end

GLFW.DestroyWindow(window)