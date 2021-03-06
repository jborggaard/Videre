using CSyntax

@static if Sys.isapple()
    const VERSION_MAJOR = 4
    const VERSION_MINOR = 1
end

include(joinpath(@__DIR__, "glutils.jl"))

# init window
width, height = fb_width, fb_height = 640, 480
window = startgl(width, height)

glEnable(GL_DEPTH_TEST)
glDepthFunc(GL_LESS)

# vertex data
points = GLfloat[ 0.0,  0.5, 0.0,
                  0.5, -0.5, 0.0,
                 -0.5, -0.5, 0.0]

colors = GLfloat[ 1.0, 0.0, 0.0,
                  0.0, 1.0, 0.0,
                  0.0, 0.0, 1.0]

# create buffers located in the memory of graphic card
points_vbo = GLuint(0)
@c glGenBuffers(1, &points_vbo)
glBindBuffer(GL_ARRAY_BUFFER, points_vbo)
glBufferData(GL_ARRAY_BUFFER, sizeof(points), points, GL_STATIC_DRAW)

colors_vbo = GLuint(0)
@c glGenBuffers(1, &colors_vbo)
glBindBuffer(GL_ARRAY_BUFFER, colors_vbo)
glBufferData(GL_ARRAY_BUFFER, sizeof(colors), colors, GL_STATIC_DRAW)

# create VAO
vao = GLuint(0)
@c glGenVertexArrays(1, &vao)
glBindVertexArray(vao)
glBindBuffer(GL_ARRAY_BUFFER, points_vbo)
glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, C_NULL)
glBindBuffer(GL_ARRAY_BUFFER, colors_vbo)
glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, C_NULL)
glEnableVertexAttribArray(0)
glEnableVertexAttribArray(1)

# load and compile shaders from file
vert_shader = createshader(joinpath(@__DIR__, "camera.vert"), GL_VERTEX_SHADER)
frag_shader = createshader(joinpath(@__DIR__, "camera.frag"), GL_FRAGMENT_SHADER)

# link program
shader_prog = createprogram(vert_shader, frag_shader)

# enable cull face
glEnable(GL_CULL_FACE)
glCullFace(GL_BACK)
glFrontFace(GL_CW)
# set background color to gray
glClearColor(0.2, 0.2, 0.2, 1.0)

# camera
near = 0.1            # clipping near plane
far = 100.0           # clipping far plane
fov = deg2rad(67)
aspect_ratio = width / height
# perspective matrix
range = tan(0.5*fov) * near
Sx = 2.0*near / (range * aspect_ratio + range * aspect_ratio)
Sy = near / range
Sz = -(far + near) / (far - near)
Pz = -(2.0*far*near) / (far - near)
proj_matrix = GLfloat[ Sx  0.0  0.0  0.0;
                      0.0   Sy  0.0  0.0;
                      0.0  0.0   Sz   Pz;
                      0.0  0.0 -1.0  0.0]
# view matrix
camera_speed = GLfloat(1.0)
camera_yaw_speed = GLfloat(10.0)
camera_pos = GLfloat[0.0, 0.0, 2.0]   # don't start at zero, or we will be too close
camera_yaw = GLfloat(0.0)             # y-rotation in degrees
trans_matrix = GLfloat[1.0 0.0 0.0 -camera_pos[1];
                       0.0 1.0 0.0 -camera_pos[2];
                       0.0 0.0 1.0 -camera_pos[3];
                       0.0 0.0 0.0            1.0]
rotation_y = GLfloat[cosd(-camera_yaw)  0.0  sind(-camera_yaw)  0.0;
                                   0.0  1.0                0.0  0.0;
                    -sind(-camera_yaw)  0.0  cosd(-camera_yaw)  0.0;
                                   0.0  0.0                0.0  1.0]
view_matrix = rotation_y * trans_matrix    # only rotate around the Y axis

view_matrix_loc = glGetUniformLocation(shader_prog, "view")
proj_matrix_loc = glGetUniformLocation(shader_prog, "proj")
glUseProgram(shader_prog)
glUniformMatrix4fv(view_matrix_loc, 1, GL_FALSE, view_matrix)
glUniformMatrix4fv(proj_matrix_loc, 1, GL_FALSE, proj_matrix)

let
updatefps = FPSCounter()
# render
previous = time()
while !GLFW.WindowShouldClose(window)
    updatefps(window)
    # clear drawing surface
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
    glViewport(0, 0, GLFW.GetFramebufferSize(window)...)
    # drawing
    glUseProgram(shader_prog)
    glBindVertexArray(vao)
    glDrawArrays(GL_TRIANGLES, 0, 3)
    # check and call events
    GLFW.PollEvents()
    # move camera
    global camera_pos; global camera_speed; global camera_yaw
    current = time()
    elapsed = current - previous
    previous = current
    GLFW.GetKey(window, GLFW.KEY_A) && (camera_pos[1] -= camera_speed * elapsed)
    GLFW.GetKey(window, GLFW.KEY_D) && (camera_pos[1] += camera_speed * elapsed)
    GLFW.GetKey(window, GLFW.KEY_PAGE_UP) && (camera_pos[2] += camera_speed * elapsed)
    GLFW.GetKey(window, GLFW.KEY_PAGE_DOWN) && (camera_pos[2] -= camera_speed * elapsed)
    GLFW.GetKey(window, GLFW.KEY_W) && (camera_pos[3] -= camera_speed * elapsed)
    GLFW.GetKey(window, GLFW.KEY_S) && (camera_pos[3] += camera_speed * elapsed)
    GLFW.GetKey(window, GLFW.KEY_LEFT) && (camera_yaw += camera_yaw_speed * elapsed)
    GLFW.GetKey(window, GLFW.KEY_RIGHT) && (camera_yaw -= camera_yaw_speed * elapsed)
    # update view matrix
    trans_matrix .= GLfloat[1.0 0.0 0.0 -camera_pos[1];
                            0.0 1.0 0.0 -camera_pos[2];
                            0.0 0.0 1.0 -camera_pos[3];
                            0.0 0.0 0.0            1.0]
    rotation_y .= GLfloat[cosd(-camera_yaw)  0.0  sind(-camera_yaw) 0.0;
                                       0.0   1.0               0.0  0.0;
                         -sind(-camera_yaw)  0.0  cosd(-camera_yaw) 0.0;
                                       0.0   0.0               0.0  1.0]
    view_matrix .= rotation_y * trans_matrix
    glUniformMatrix4fv(view_matrix_loc, 1, GL_FALSE, view_matrix)
    # swap the buffers
    GLFW.SwapBuffers(window)
end
end # let

GLFW.DestroyWindow(window)
