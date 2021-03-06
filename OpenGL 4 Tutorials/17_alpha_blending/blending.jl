include(joinpath(@__DIR__, "glutils.jl"))

@static if Sys.isapple()
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
set_camera_position(GLfloat[0.0, 0.0, 2.0])

# vertex data
points = GLfloat[-0.5, -0.5, 0.0,
                  0.5, -0.5, 0.0,
                  0.5,  0.5, 0.0,
                  0.5,  0.5, 0.0,
                 -0.5,  0.5, 0.0,
                 -0.5, -0.5, 0.0]

texcoords = GLfloat[0.0, 0.0,
                    1.0, 0.0,
                    1.0, 1.0,
                    1.0, 1.0,
                    0.0, 1.0,
                    0.0, 0.0]

# create buffers located in the memory of graphic card
pointsVBO = Ref{GLuint}(0)
glGenBuffers(1, pointsVBO)
glBindBuffer(GL_ARRAY_BUFFER, pointsVBO[])
glBufferData(GL_ARRAY_BUFFER, sizeof(points), points, GL_STATIC_DRAW)

texcoordsVBO = Ref{GLuint}(0)
glGenBuffers(1, texcoordsVBO)
glBindBuffer(GL_ARRAY_BUFFER, texcoordsVBO[])
glBufferData(GL_ARRAY_BUFFER, sizeof(texcoords), texcoords, GL_STATIC_DRAW)

# create VAO
vaoID = Ref{GLuint}(0)
glGenVertexArrays(1, vaoID)
glBindVertexArray(vaoID[])
glBindBuffer(GL_ARRAY_BUFFER, pointsVBO[])
glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, C_NULL)
glBindBuffer(GL_ARRAY_BUFFER, texcoordsVBO[])
glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, C_NULL)
glEnableVertexAttribArray(0)
glEnableVertexAttribArray(1)

# create shader program
vertexShaderPath = joinpath(@__DIR__, "blending.vert")
fragmentShaderPath = joinpath(@__DIR__, "blending.frag")
shaderProgramID = createprogram(vertexShaderPath, fragmentShaderPath)
modelMatrixLocation = glGetUniformLocation(shaderProgramID, "model")
viewMatrixLocation = glGetUniformLocation(shaderProgramID, "view")
projMatrixLocation = glGetUniformLocation(shaderProgramID, "proj")
glUseProgram(shaderProgramID)
glUniformMatrix4fv(viewMatrixLocation, 1, GL_FALSE, get_view_matrix())
glUniformMatrix4fv(projMatrixLocation, 1, GL_FALSE, get_projective_matrix())

# load texture
glActiveTexture(GL_TEXTURE0)
texa = loadtexture(joinpath(@__DIR__, "blob.png"))
texb = loadtexture(joinpath(@__DIR__, "blob2.png"))

glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
glEnable(GL_BLEND)
# glDisable(GL_DEPTH_TEST)

# enable cull face
glEnable(GL_CULL_FACE)
glCullFace(GL_BACK)
glFrontFace(GL_CCW)
# set background color to gray
glClearColor(0.2, 0.2, 0.2, 1.0)

# render
while !GLFW.WindowShouldClose(window)
    updatefps(window)
    # clear drawing surface
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
    glViewport(0, 0, glfwWidth, glfwHeight)
    # drawing
    glUseProgram(shaderProgramID)
    glBindVertexArray(vaoID[])

    glDepthMask(GL_FALSE)

    glBindTexture(GL_TEXTURE_2D, texa[])
    modelMatrix = eye(GLfloat, 4, 4)
    glUniformMatrix4fv(modelMatrixLocation, 1, GL_FALSE, modelMatrix)
    glDrawArrays(GL_TRIANGLES, 0, 6)

    glBindTexture(GL_TEXTURE_2D, texb[])
    modelMatrix[1,4] = 0.5
    modelMatrix[3,4] = 0.1
    glUniformMatrix4fv(modelMatrixLocation, 1, GL_FALSE, modelMatrix)
    glDrawArrays(GL_TRIANGLES, 0, 6)

    glDepthMask(GL_TRUE)

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
