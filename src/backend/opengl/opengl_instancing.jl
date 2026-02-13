# OpenGL instanced rendering — instance buffer management

"""
    InstanceBuffer

GPU buffer for per-instance transform data.
Stores model matrices (mat4, locations 5-8) and normal matrices (mat3, locations 9-11).
"""
mutable struct InstanceBuffer
    vbo::GLuint
    capacity::Int    # Max instances currently allocated

    InstanceBuffer() = new(GLuint(0), 0)
end

"""
    upload_instance_data!(buf::InstanceBuffer, gpu_mesh::GPUMesh,
                          models::Vector{Mat4f},
                          normals::Vector{SMatrix{3,3,Float32,9}})

Upload per-instance transform data to GPU. Reallocates if capacity is exceeded.
Binds instance attributes to the mesh's VAO.
"""
function upload_instance_data!(buf::InstanceBuffer, gpu_mesh::GPUMesh,
                               models::Vector{Mat4f},
                               normals::Vector{SMatrix{3,3,Float32,9}})
    count = length(models)
    @assert count == length(normals)

    # Pack data: mat4 (16 floats) + mat3 (9 floats) = 25 floats per instance
    floats_per_instance = 16 + 9
    data = Vector{Float32}(undef, count * floats_per_instance)

    for i in 1:count
        base = (i - 1) * floats_per_instance
        m = models[i]
        # mat4 column-major
        for col in 1:4, row in 1:4
            data[base + (col-1)*4 + row] = m[row, col]
        end
        n = normals[i]
        # mat3 column-major
        for col in 1:3, row in 1:3
            data[base + 16 + (col-1)*3 + row] = n[row, col]
        end
    end

    # Create or resize buffer
    if buf.vbo == GLuint(0)
        vbo_ref = Ref(GLuint(0))
        glGenBuffers(1, vbo_ref)
        buf.vbo = vbo_ref[]
    end

    glBindBuffer(GL_ARRAY_BUFFER, buf.vbo)

    if count > buf.capacity
        # Allocate with some headroom
        buf.capacity = max(count, buf.capacity * 2, 16)
        glBufferData(GL_ARRAY_BUFFER, buf.capacity * floats_per_instance * sizeof(Float32), C_NULL, GL_DYNAMIC_DRAW)
    end

    glBufferSubData(GL_ARRAY_BUFFER, 0, count * floats_per_instance * sizeof(Float32), data)

    # Bind to VAO with vertex attribute divisor
    glBindVertexArray(gpu_mesh.vao)
    glBindBuffer(GL_ARRAY_BUFFER, buf.vbo)

    stride = floats_per_instance * sizeof(Float32)

    # Model matrix: 4 vec4 columns at locations 5, 6, 7, 8
    for col in 0:3
        loc = GLuint(5 + col)
        offset = Ptr{Cvoid}(col * 4 * sizeof(Float32))
        glEnableVertexAttribArray(loc)
        glVertexAttribPointer(loc, 4, GL_FLOAT, GL_FALSE, stride, offset)
        glVertexAttribDivisor(loc, 1)
    end

    # Normal matrix: 3 vec3 columns at locations 9, 10, 11
    for col in 0:2
        loc = GLuint(9 + col)
        offset = Ptr{Cvoid}((16 + col * 3) * sizeof(Float32))
        glEnableVertexAttribArray(loc)
        glVertexAttribPointer(loc, 3, GL_FLOAT, GL_FALSE, stride, offset)
        glVertexAttribDivisor(loc, 1)
    end

    glBindVertexArray(GLuint(0))
    glBindBuffer(GL_ARRAY_BUFFER, GLuint(0))

    return nothing
end

"""
    draw_instanced!(gpu_mesh::GPUMesh, instance_count::Int)

Issue a glDrawElementsInstanced call.
"""
function draw_instanced!(gpu_mesh::GPUMesh, instance_count::Int)
    glBindVertexArray(gpu_mesh.vao)
    glDrawElementsInstanced(GL_TRIANGLES, gpu_mesh.index_count, GL_UNSIGNED_INT, C_NULL, instance_count)
    glBindVertexArray(GLuint(0))
    return nothing
end

"""
    destroy_instance_buffer!(buf::InstanceBuffer)

Release GPU resources for the instance buffer.
"""
function destroy_instance_buffer!(buf::InstanceBuffer)
    if buf.vbo != GLuint(0)
        glDeleteBuffers(1, Ref(buf.vbo))
        buf.vbo = GLuint(0)
    end
    buf.capacity = 0
    return nothing
end

# Global instance buffer (reused across frames)
const _INSTANCE_BUFFER = Ref{Union{InstanceBuffer, Nothing}}(nothing)

"""
    get_instance_buffer!() -> InstanceBuffer

Get or create the global instance buffer.
"""
function get_instance_buffer!()
    if _INSTANCE_BUFFER[] === nothing
        _INSTANCE_BUFFER[] = InstanceBuffer()
    end
    return _INSTANCE_BUFFER[]
end

"""
    reset_instance_buffer!()

Destroy the global instance buffer.
"""
function reset_instance_buffer!()
    if _INSTANCE_BUFFER[] !== nothing
        destroy_instance_buffer!(_INSTANCE_BUFFER[])
        _INSTANCE_BUFFER[] = nothing
    end
    return nothing
end
