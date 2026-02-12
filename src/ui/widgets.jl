# UI widget functions — immediate-mode API

"""
    ui_rect(ctx::UIContext; x, y, width, height, color)

Draw a solid colored rectangle.
"""
function ui_rect(ctx::UIContext;
                 x::Real = 0, y::Real = 0,
                 width::Real = 100, height::Real = 100,
                 color::RGB{Float32} = RGB{Float32}(1, 1, 1),
                 alpha::Float32 = 1.0f0)
    _push_quad!(ctx, Float32(x), Float32(y), Float32(width), Float32(height),
                0.0f0, 0.0f0, 0.0f0, 0.0f0,  # no UVs for solid color
                Float32(red(color)), Float32(green(color)), Float32(blue(color)), alpha,
                UInt32(0), false)
    return nothing
end

"""
    ui_text(ctx::UIContext, text::String; x, y, size, color)

Draw text at the given position.
"""
function ui_text(ctx::UIContext, text::String;
                 x::Real = 0, y::Real = 0,
                 size::Int = 24,
                 color::RGB{Float32} = RGB{Float32}(1, 1, 1),
                 alpha::Float32 = 1.0f0)
    atlas = ctx.font_atlas
    if isempty(atlas.glyphs)
        return nothing
    end

    scale = Float32(size) / atlas.font_size
    cursor_x = Float32(x)
    cursor_y = Float32(y)
    r = Float32(red(color))
    g = Float32(green(color))
    b = Float32(blue(color))

    for ch in text
        if ch == '\n'
            cursor_x = Float32(x)
            cursor_y += atlas.line_height * scale
            continue
        end

        glyph = get(atlas.glyphs, ch, nothing)
        glyph === nothing && continue

        if glyph.width > 0 && glyph.height > 0
            gx = cursor_x + glyph.bearing_x * scale
            gy = cursor_y + (atlas.font_size - glyph.bearing_y) * scale
            gw = glyph.width * scale
            gh = glyph.height * scale

            _push_quad!(ctx, gx, gy, gw, gh,
                        glyph.uv_x, glyph.uv_y, glyph.uv_w, glyph.uv_h,
                        r, g, b, alpha,
                        atlas.texture_id, true)
        end

        cursor_x += glyph.advance_x * scale
    end
    return nothing
end

"""
    ui_button(ctx::UIContext, label::String; x, y, width, height, color, text_color) -> Bool

Draw a button. Returns true if clicked this frame.
"""
function ui_button(ctx::UIContext, label::String;
                   x::Real = 0, y::Real = 0,
                   width::Real = 120, height::Real = 40,
                   color::RGB{Float32} = RGB{Float32}(0.3, 0.3, 0.3),
                   hover_color::RGB{Float32} = RGB{Float32}(0.4, 0.4, 0.4),
                   text_color::RGB{Float32} = RGB{Float32}(1, 1, 1),
                   text_size::Int = 20,
                   alpha::Float32 = 1.0f0)
    fx = Float32(x)
    fy = Float32(y)
    fw = Float32(width)
    fh = Float32(height)

    # Hit test
    hovered = ctx.mouse_x >= fx && ctx.mouse_x <= fx + fw &&
              ctx.mouse_y >= fy && ctx.mouse_y <= fy + fh
    clicked = hovered && ctx.mouse_clicked

    # Draw background
    bg_color = hovered ? hover_color : color
    ui_rect(ctx, x=fx, y=fy, width=fw, height=fh, color=bg_color, alpha=alpha)

    # Center text
    if !isempty(ctx.font_atlas.glyphs)
        tw, th = measure_text(ctx.font_atlas, label, size=Float32(text_size))
        tx = fx + (fw - tw) / 2.0f0
        ty = fy + (fh - Float32(text_size)) / 2.0f0
        ui_text(ctx, label, x=tx, y=ty, size=text_size, color=text_color, alpha=alpha)
    end

    return clicked
end

"""
    ui_progress_bar(ctx::UIContext, fraction; x, y, width, height, color, bg_color)

Draw a progress bar (0.0 to 1.0).
"""
function ui_progress_bar(ctx::UIContext, fraction::Real;
                         x::Real = 0, y::Real = 0,
                         width::Real = 200, height::Real = 20,
                         color::RGB{Float32} = RGB{Float32}(0.2, 0.8, 0.2),
                         bg_color::RGB{Float32} = RGB{Float32}(0.2, 0.2, 0.2),
                         alpha::Float32 = 1.0f0)
    f = clamp(Float32(fraction), 0.0f0, 1.0f0)

    # Background
    ui_rect(ctx, x=x, y=y, width=width, height=height, color=bg_color, alpha=alpha)

    # Fill
    if f > 0.0f0
        ui_rect(ctx, x=x, y=y, width=Float32(width) * f, height=height, color=color, alpha=alpha)
    end
    return nothing
end

"""
    ui_image(ctx::UIContext, texture_id::UInt32; x, y, width, height, alpha)

Draw a textured image quad using a pre-uploaded GPU texture ID.
"""
function ui_image(ctx::UIContext, texture_id::UInt32;
                  x::Real = 0, y::Real = 0,
                  width::Real = 64, height::Real = 64,
                  alpha::Float32 = 1.0f0)
    _push_quad!(ctx, Float32(x), Float32(y), Float32(width), Float32(height),
                0.0f0, 0.0f0, 1.0f0, 1.0f0,
                1.0f0, 1.0f0, 1.0f0, alpha,
                texture_id, false)
    return nothing
end

# ---- Internal helpers ----

"""
Push a quad (2 triangles, 6 vertices) into the UI vertex buffer.
Each vertex: position.xy + uv.xy + color.rgba = 8 floats.
"""
function _push_quad!(ctx::UIContext,
                     x::Float32, y::Float32, w::Float32, h::Float32,
                     uv_x::Float32, uv_y::Float32, uv_w::Float32, uv_h::Float32,
                     r::Float32, g::Float32, b::Float32, a::Float32,
                     texture_id::UInt32, is_font::Bool)
    offset = length(ctx.vertices)

    # 6 vertices * 8 floats = 48 floats per quad
    # Triangle 1: top-left, top-right, bottom-right
    # Triangle 2: top-left, bottom-right, bottom-left
    x0, y0 = x, y
    x1, y1 = x + w, y + h
    u0, v0 = uv_x, uv_y
    u1, v1 = uv_x + uv_w, uv_y + uv_h

    append!(ctx.vertices, Float32[
        # Vertex 1 (top-left)
        x0, y0, u0, v0, r, g, b, a,
        # Vertex 2 (top-right)
        x1, y0, u1, v0, r, g, b, a,
        # Vertex 3 (bottom-right)
        x1, y1, u1, v1, r, g, b, a,
        # Vertex 4 (top-left)
        x0, y0, u0, v0, r, g, b, a,
        # Vertex 5 (bottom-right)
        x1, y1, u1, v1, r, g, b, a,
        # Vertex 6 (bottom-left)
        x0, y1, u0, v1, r, g, b, a,
    ])

    # Add draw command (try to merge with last command if same texture)
    if !isempty(ctx.draw_commands)
        last = ctx.draw_commands[end]
        if last.texture_id == texture_id && last.is_font == is_font
            # Merge: extend the last command
            ctx.draw_commands[end] = UIDrawCommand(
                last.vertex_offset, last.vertex_count + 6,
                texture_id, is_font
            )
            return nothing
        end
    end

    push!(ctx.draw_commands, UIDrawCommand(offset, 6, texture_id, is_font))
    return nothing
end
