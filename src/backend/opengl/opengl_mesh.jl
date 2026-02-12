# OpenGL mesh implementation

"""
    GPUMesh

OpenGL handles for a single mesh's GPU buffers.
"""
mutable struct GPUMesh <: AbstractGPUMesh
    vao::GLuint
    vbo::GLuint     # vertex positions
    nbo::GLuint     # normals
    ubo::GLuint     # UV coordinates
    ebo::GLuint     # element (index) buffer
    wbo::GLuint     # bone weights (layout 3)
    ibo_bones::GLuint  # bone indices (layout 4)
    index_count::Int32
    has_skinning::Bool

    GPUMesh() = new(GLuint(0), GLuint(0), GLuint(0), GLuint(0), GLuint(0),
                    GLuint(0), GLuint(0), Int32(0), false)
end

get_index_count(mesh::GPUMesh) = mesh.index_count

"""
    GPUResourceCache

Maps EntityIDs to their GPU-side resources. Provides lazy creation and explicit cleanup.
"""
mutable struct GPUResourceCache <: AbstractGPUResourceCache
    meshes::Dict{EntityID, GPUMesh}

    GPUResourceCache() = new(Dict{EntityID, GPUMesh}())
end

"""
    upload_mesh!(cache::GPUResourceCache, entity_id::EntityID, mesh::MeshComponent) -> GPUMesh

Upload a MeshComponent's data to GPU buffers. Creates VAO/VBO/EBO.
If the entity already has a GPUMesh, the old buffers are destroyed first.
"""
function upload_mesh!(cache::GPUResourceCache, entity_id::EntityID, mesh::MeshComponent)
    if haskey(cache.meshes, entity_id)
        destroy_gpu_mesh!(cache.meshes[entity_id])
    end

    gpu = GPUMesh()

    # Generate VAO
    vao_ref = Ref(GLuint(0))
    glGenVertexArrays(1, vao_ref)
    gpu.vao = vao_ref[]
    glBindVertexArray(gpu.vao)

    # Vertex positions (layout = 0)
    vbo_ref = Ref(GLuint(0))
    glGenBuffers(1, vbo_ref)
    gpu.vbo = vbo_ref[]
    glBindBuffer(GL_ARRAY_BUFFER, gpu.vbo)
    glBufferData(GL_ARRAY_BUFFER, sizeof(mesh.vertices), mesh.vertices, GL_STATIC_DRAW)
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, C_NULL)
    glEnableVertexAttribArray(0)

    # Normals (layout = 1)
    nbo_ref = Ref(GLuint(0))
    glGenBuffers(1, nbo_ref)
    gpu.nbo = nbo_ref[]
    glBindBuffer(GL_ARRAY_BUFFER, gpu.nbo)
    glBufferData(GL_ARRAY_BUFFER, sizeof(mesh.normals), mesh.normals, GL_STATIC_DRAW)
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, C_NULL)
    glEnableVertexAttribArray(1)

    # UV coordinates (layout = 2)
    if !isempty(mesh.uvs)
        ubo_ref = Ref(GLuint(0))
        glGenBuffers(1, ubo_ref)
        gpu.ubo = ubo_ref[]
        glBindBuffer(GL_ARRAY_BUFFER, gpu.ubo)
        glBufferData(GL_ARRAY_BUFFER, sizeof(mesh.uvs), mesh.uvs, GL_STATIC_DRAW)
        glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, 0, C_NULL)
        glEnableVertexAttribArray(2)
    end

    # Bone weights (layout = 3) — vec4 per vertex
    if !isempty(mesh.bone_weights) && !isempty(mesh.bone_indices)
        wbo_ref = Ref(GLuint(0))
        glGenBuffers(1, wbo_ref)
        gpu.wbo = wbo_ref[]
        glBindBuffer(GL_ARRAY_BUFFER, gpu.wbo)
        glBufferData(GL_ARRAY_BUFFER, sizeof(mesh.bone_weights), mesh.bone_weights, GL_STATIC_DRAW)
        glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, 0, C_NULL)
        glEnableVertexAttribArray(3)

        # Bone indices (layout = 4) — 4 x UInt16 per vertex, uploaded as integer attribute
        # Pack NTuple{4, UInt16} into a flat UInt16 array for GL upload
        n_verts = length(mesh.bone_indices)
        bone_idx_flat = Vector{UInt16}(undef, n_verts * 4)
        for i in 1:n_verts
            bi = mesh.bone_indices[i]
            bone_idx_flat[(i-1)*4 + 1] = bi[1]
            bone_idx_flat[(i-1)*4 + 2] = bi[2]
            bone_idx_flat[(i-1)*4 + 3] = bi[3]
            bone_idx_flat[(i-1)*4 + 4] = bi[4]
        end

        ibo_ref = Ref(GLuint(0))
        glGenBuffers(1, ibo_ref)
        gpu.ibo_bones = ibo_ref[]
        glBindBuffer(GL_ARRAY_BUFFER, gpu.ibo_bones)
        glBufferData(GL_ARRAY_BUFFER, sizeof(bone_idx_flat), bone_idx_flat, GL_STATIC_DRAW)
        glVertexAttribIPointer(4, 4, GL_UNSIGNED_SHORT, 0, C_NULL)
        glEnableVertexAttribArray(4)

        gpu.has_skinning = true
    end

    # Index buffer
    ebo_ref = Ref(GLuint(0))
    glGenBuffers(1, ebo_ref)
    gpu.ebo = ebo_ref[]
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gpu.ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(mesh.indices), mesh.indices, GL_STATIC_DRAW)
    gpu.index_count = Int32(length(mesh.indices))

    glBindVertexArray(GLuint(0))

    cache.meshes[entity_id] = gpu
    return gpu
end

"""
    get_or_upload_mesh!(cache::GPUResourceCache, entity_id::EntityID, mesh::MeshComponent) -> GPUMesh

Retrieve existing GPUMesh or upload if not yet cached.
"""
function get_or_upload_mesh!(cache::GPUResourceCache, entity_id::EntityID, mesh::MeshComponent)
    if haskey(cache.meshes, entity_id)
        return cache.meshes[entity_id]
    end
    return upload_mesh!(cache, entity_id, mesh)
end

"""
    destroy_gpu_mesh!(gpu::GPUMesh)

Delete OpenGL buffers for a mesh.
"""
function destroy_gpu_mesh!(gpu::GPUMesh)
    bufs = GLuint[gpu.vbo, gpu.nbo, gpu.ebo]
    if gpu.ubo != GLuint(0)
        push!(bufs, gpu.ubo)
    end
    if gpu.wbo != GLuint(0)
        push!(bufs, gpu.wbo)
    end
    if gpu.ibo_bones != GLuint(0)
        push!(bufs, gpu.ibo_bones)
    end
    glDeleteBuffers(length(bufs), bufs)
    vaos = GLuint[gpu.vao]
    glDeleteVertexArrays(1, vaos)
    gpu.vao = GLuint(0)
    gpu.vbo = GLuint(0)
    gpu.nbo = GLuint(0)
    gpu.ubo = GLuint(0)
    gpu.ebo = GLuint(0)
    gpu.wbo = GLuint(0)
    gpu.ibo_bones = GLuint(0)
    gpu.has_skinning = false
end

"""
    destroy_all!(cache::GPUResourceCache)

Cleanup all GPU resources.
"""
function destroy_all!(cache::GPUResourceCache)
    for (_, gpu) in cache.meshes
        destroy_gpu_mesh!(gpu)
    end
    empty!(cache.meshes)
end
