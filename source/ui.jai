GenerateNoiseTexture :: (tex : *GLuint,
    width : s32, height : s32,
    seed : u64, params : NoiseParams
) -> min_val : float, max_val : float
{
    static_offsets : [Perlin_Fractal_Max_Octaves]Vec2f;
    min_non_normalized := Math.FLOAT32_MAX;
    max_non_normalized := -Math.FLOAT32_MAX;

    octaves := Clamp (params.octaves, 1, Perlin_Fractal_Max_Octaves);
    offsets := MakeArray (octaves, static_offsets.data);

    rng : RNG;
    RandomSeed (*rng, seed);
    PerlinGenerateOffsets (*rng, offsets);

    buffer := Alloc (u32, width * height, Temp);

    max_val := cast (float) PerlinFractalMax (params.octaves, params.persistance);
    for y : 0..height - 1
    {
        for x : 0..width - 1
        {
            val := cast (float) PerlinFractalNoise (params, offsets, xx x, xx y);
            if val < min_non_normalized
                min_non_normalized = val;
            if val > max_non_normalized
                max_non_normalized = val;
            val = InverseLerp (-max_val, max_val, val);

            buffer[y * width + x] = ImGui.GetColorU32 (.{val, val, val, 1});
        }
    }

    if !tex.*
        glGenTextures (1, tex);

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glBindTexture (GL_TEXTURE_2D, tex.*);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, buffer);

    return min_non_normalized, max_non_normalized;
}

#scope_file

g_ui_perlin : struct
{
    texture_handle : GLuint;
    texture_size : s32 = 256;
    seed : u64;
    params := NoiseParams.{
        scale = 0.05,
        octaves = 3,
        persistance = 0.5,
        lacunarity = 1.5
    };
    min_value := Math.FLOAT32_MAX;
    max_value := -Math.FLOAT32_MAX;
};

#scope_export

UIShowNoiseParams :: (id : ImGui.ID, params : *NoiseParams) -> bool
{
    ImGui.PushID (cast (s32) id);
    defer ImGui.PopID ();

    result := false;
    result |= ImGui.SliderFloat ("Scale", *params.scale, 0.0001, 0.2, "%.6f", flags = .Logarithmic);
    result |= ImGui.SliderInt ("Octaves", *params.octaves, 1, Perlin_Fractal_Max_Octaves);
    result |= ImGui.SliderFloat ("Persistance", *params.persistance, 0.001, 1);
    result |= ImGui.SliderFloat ("Lacunarity", *params.lacunarity, 1, 10);

    return result;
}

UIShowPerlinTestWindow :: (opened : *bool)
{
    using g_ui_perlin;

    defer ImGui.End ();
    if !ImGui.Begin ("Perlin Test", opened)
        return;

    lines := 8;
    child_height := cast (float) ImGui.GetContentRegionAvail ().y - lines * ImGui.GetFrameHeightWithSpacing ();
    if child_height > 0
    {
        if ImGui.BeginChild ("Image", .{0, child_height}, true, .HorizontalScrollbar)
        {
            if texture_handle
                ImGui.Image (cast (ImGui.ImTextureID) texture_handle, .{xx texture_size, xx texture_size});
        }
        ImGui.EndChild ();
    }

    should_generate := false;

    if !texture_handle
        should_generate = true;

    ImGui.LabelText ("Min Value", "%.3f", min_value);
    ImGui.LabelText ("Max Value", "%.3f", max_value);

    if ImGui.SliderInt ("Size", *texture_size, 128, 4096)
        should_generate = true;

    if UIShowNoiseParams (0, *params)
        should_generate = true;

    if ImGui.Button ("Generate")
        should_generate = true;

    ImGui.SameLine ();

    if ImGui.Button ("Randomize") || !texture_handle
    {
        seed = RandomGetU64 (*context.random_number_generator);
        should_generate = true;
    }

    if should_generate
        min_value, max_value = GenerateNoiseTexture (*texture_handle, texture_size, texture_size, seed, params);
}

#scope_file

SurfaceColor :: struct
{
    min : s32;
    max : s32;
    color : Vec3f;
}

Deep_Ocean_Color :: Vec4f.{0.102, 0.136, 0.388, 1};
Water_Color :: Vec4f.{0.154, 0.273, 0.878, 1};
Beach_Color :: Vec4f.{0.947, 0.880, 0.149, 1};
Grass_Color :: Vec4f.{0.387, 0.700, 0.250, 1};
Mountain_Color :: Vec4f.{0.593, 0.689, 0.551, 1};
Snow_Color :: Vec4f.{0.914, 0.958, 1.000, 1};

GetSurfaceColor :: inline (using params : SurfaceParams, surface_level : float) -> u32 #must
{
    if surface_level < cast (float) water_level - 20
    {
        return ImGui.GetColorU32 (Deep_Ocean_Color);
    }
    else if surface_level < cast (float) water_level
    {
        return ImGui.GetColorU32 (Water_Color);
    }
    else if surface_level < cast (float) water_level + 5
    {
        return ImGui.GetColorU32 (Beach_Color);
    }
    else if surface_level < cast (float) water_level + 60
    {
        return ImGui.GetColorU32 (Grass_Color);
    }
    else if surface_level < cast (float) water_level + 110
    {
        return ImGui.GetColorU32 (Mountain_Color);
    }
    else
    {
        return ImGui.GetColorU32 (Snow_Color);
    }
}

#scope_export

GenerateTerrainTexture :: (tex : *GLuint, width : s32, height : s32, offset : Vec2f, scale : float, generator : *Generator, param : TerrainParam, use_threads := false)
{
    WorkerData :: struct
    {
        buffer : *u32;
        width, height : s32;
        working_x, working_y, working_w, working_h : s32;
        offset : Vec2f;
        scale : float;
        using generator : *Generator;
        param : TerrainParam;
    }

    WorkerProc :: (group : *Threads.Thread_Group, thread : *Threads.Thread, work : *void) -> Threads.Thread_Continue_Status
    {
        using data := cast (*WorkerData) work;

        if param == .Surface_Height
        {
            for y : working_y..working_y + working_h - 1
            {
                for x : working_x..working_x + working_w - 1
                {
                    surface_level := cast (float) CalculateTerrainParam (generator, param, offset.x + x * scale, offset.y + y * scale);
                    buffer[y * width + x] = GetSurfaceColor (surface_params, surface_level);
                }
            }
        }
        else
        {
            for y : working_y..working_y + working_h - 1
            {
                for x : working_x..working_x + working_w - 1
                {
                    val := cast (float) CalculateTerrainParam (generator, param, offset.x + x * scale, offset.y + y * scale);
                    buffer[y * width + x] = ImGui.GetColorU32 (.{val, val, val, 1});
                }
            }
        }

        return .CONTINUE;
    }

    buffer := Alloc (u32, width * height, Temp);

    start_time := Basic.current_time_monotonic ();
    if !use_threads
    {
        data : WorkerData;
        data.buffer = buffer;
        data.width = width;
        data.height = height;
        data.generator = generator;
        data.offset = offset;
        data.scale = scale;
        data.param = param;
        data.working_x = 0;
        data.working_y = 0;
        data.working_w = width;
        data.working_h = height;
        WorkerProc (null, null, *data);
    }
    else
    {
        thread_count := Clamp (System.get_number_of_processors (.PERFORMANCE_LOGICAL), 1, 200);

        threads_on_x := Max (cast (s32) Ceil (Sqrt (cast (float) thread_count)), 1);
        threads_on_y := threads_on_x;

        group : Threads.Thread_Group;
        Threads.init (*group, thread_count, WorkerProc);
        group.name = "GenerateTerrainTexture";
        group.logging = false;

        Threads.start (*group);

        worker_data := AllocArray (WorkerData, threads_on_x * threads_on_y, Temp, initialize = true);
        for y : 0..threads_on_y - 1
        {
            for x : 0..threads_on_x - 1
            {
                data := *worker_data[y * threads_on_x + x];
                data.buffer = buffer;
                data.width = width;
                data.height = height;
                data.offset = offset;
                data.scale = scale;
                data.generator = generator;
                data.param = param;

                data.working_x = x * (width / threads_on_x);
                data.working_y = y * (height / threads_on_y);
                if x == threads_on_x - 1
                    data.working_w = width - data.working_x;
                else
                    data.working_w = (width / threads_on_x);
                if y == threads_on_y - 1
                    data.working_h = height - data.working_y;
                else
                    data.working_h = (height / threads_on_y);

                Threads.add_work (*group, data, FormatString (Temp, "%,%,%,%", data.working_x, data.working_y, data.working_w, data.working_h));
            }
        }

        remaining := threads_on_y * threads_on_x;
        while remaining > 0
        {
            Basic.sleep_milliseconds (5);
            results := Threads.get_completed_work (*group);
            remaining -= xx results.count;
        }

        Threads.shutdown (*group);
    }

    if !tex.*
        glGenTextures (1, tex);

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glBindTexture (GL_TEXTURE_2D, tex.*);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, buffer);

    end_time := Basic.current_time_monotonic ();
    elapsed := cast (float) (Basic.to_float64_seconds (end_time - start_time));
}

#scope_file

g_ui_terrain_generator : struct
{
    offset : Vec2f;
    scale : float = 1;
    generator : Generator;
    texture_handle : GLuint;
    size : s32 = 1024;
    texture_size : s32 = 512;
    selected_param := TerrainParam.Surface_Height;
    show_param := TerrainParam.Surface_Height;
    use_threads := true;
    show_player_position := true;
};

#scope_export

UIShowTerrainGeneratorWindow :: (opened : *bool)
{
    using g_ui_terrain_generator;

    if !generator.surface_params.spline
        InitDefaultSurfaceSpline (*generator.surface_params);

    defer ImGui.End ();
    if !ImGui.Begin ("Terrain Generator", opened)
        return;

    should_generate := false;

    lines := 9;
    if selected_param < xx TerrainNoise.Count
        lines += 5;
    child_height := cast (float) ImGui.GetContentRegionAvail ().y - lines * ImGui.GetFrameHeightWithSpacing ();
    if child_height > 0
    {
        if ImGui.BeginChild ("Image", .{0, child_height}, true, .HorizontalScrollbar)
        {
            if texture_handle
            {
                draw_list := ImGui.GetWindowDrawList ();
                map_top_left := ImGui.GetCursorScreenPos ();

                ImGui.PushStyleVar (.FramePadding, .{0, 0});
                defer ImGui.PopStyleVar ();

                ImGui.ImageButton ("ImageButton", cast (ImGui.ImTextureID) texture_handle, .{xx texture_size, xx texture_size});
                if show_player_position
                {
                    player_pos_scale := (texture_size / cast (float) size) / scale;
                    player_pos := (Vec2f.{g_player.position.x, g_player.position.z} - offset) * player_pos_scale;
                    player_pos += map_top_left;
                    player_pos.x = Clamp (player_pos.x, map_top_left.x, map_top_left.x + xx texture_size);
                    player_pos.y = Clamp (player_pos.y, map_top_left.y, map_top_left.y + xx texture_size);

                    p0 := Rotate (Vec2f.{0, -1}, -g_player.orientation + PI * 0.5);
                    p1 := Rotate (Vec2f.{2,  0}, -g_player.orientation + PI * 0.5);
                    p2 := Rotate (Vec2f.{0,  1}, -g_player.orientation + PI * 0.5);

                    draw_list.AddCircleFilled (draw_list, player_pos, 7, ImGui.GetColorU32 (.{0,0,0,1}));
                    draw_list.AddTriangleFilled (draw_list, player_pos + p0 * 7, player_pos + p1 * 7, player_pos + p2 * 7, ImGui.GetColorU32 (.{0,0,0,1}));

                    draw_list.AddCircleFilled (draw_list, player_pos, 5, ImGui.GetColorU32 (.{1,1,1,1}));
                    draw_list.AddTriangleFilled (draw_list, player_pos + p0 * 5, player_pos + p1 * 5, player_pos + p2 * 5, ImGui.GetColorU32 (.{1,1,1,1}));
                }

                if ImGui.IsMouseDragging (.Left) && (ImGui.IsItemActive () || ImGui.IsItemHovered ())
                {
                    drag_scale := scale * (size / cast (float) texture_size);
                    offset -= ImGui.GetMouseDragDelta (.Left) * drag_scale;
                    ImGui.ResetMouseDragDelta (.Left);

                    should_generate = true;
                }
            }
        }
        ImGui.EndChild ();
    }


    if !texture_handle
        should_generate = true;

    ImGui.LabelText ("Seed", "%lld", generator.seed);
    ImGui.SliderInt ("Texture Size", *texture_size, 128, 4096);
    should_generate |= ImGui.SliderInt ("Size", *size, 16, 4096);
    should_generate |= ImGui.SliderFloat ("Scale", *scale, 1, 100);
    should_generate |= ImGui.SliderInt ("Water Level", *generator.surface_params.water_level, 0, 320);

    terrain_param_names := Alloc (*u8, cast (s64) TerrainParam.Count, Temp);
    for i : 0..xx TerrainParam.Count - 1
        terrain_param_names[i] = StringCloneToCString (type_info (TerrainParam).names[i], Temp);

    selected_param_s32 := cast (s32) selected_param;
    ImGui.Combo ("Edit Param", *selected_param_s32, terrain_param_names, xx TerrainParam.Count);
    selected_param = xx selected_param_s32;

    show_param_s32 := cast (s32) show_param;
    should_generate |= ImGui.Combo ("Show Param", *show_param_s32, terrain_param_names, xx TerrainParam.Count);
    show_param = xx show_param_s32;

    if selected_param < xx TerrainNoise.Count
    {
        should_generate |= ImGui.SliderFloat ("Amplitude", *generator.surface_params.noise_amplitudes[xx selected_param], 0.1, 5);
        should_generate |= UIShowNoiseParams (0, *generator.surface_params.noise_params[xx selected_param]);
    }

    ImGui.Checkbox ("Use Threads", *use_threads);

    ImGui.SameLine ();

    ImGui.Checkbox ("Show Player Position", *show_player_position);

    should_generate |= ImGui.Button ("Generate");

    ImGui.SameLine ();

    if !texture_handle
        generator.seed = g_world.seed;

    if ImGui.Button ("Randomize")
    {
        rng : RNG;
        RandomSeed (*rng, Basic.current_time_monotonic ().low);

        generator.seed = RandomGetU64 (*rng);
        should_generate = true;
    }

    ImGui.SameLine ();

    if ImGui.Button ("Set World Params")
    {
        WorldFree (*g_world);
        WorldInit (*g_world, generator.seed, generator.surface_params);
    }

    if should_generate
    {
        GenerateNoiseOffsets (*generator);
        GenerateTerrainTexture (*texture_handle, size, size, offset, scale, *generator, show_param, use_threads);
    }
}

UIShowTextureAtlasWindow :: (opened : *bool)
{
    defer ImGui.End ();
    if !ImGui.Begin ("Texture Atlas", opened)
        return;

    draw_list := ImGui.GetWindowDrawList ();
    avail_width := ImGui.GetContentRegionAvail ().x;
    min := ImGui.GetCursorScreenPos ();

    Checkerboard_Grid_Size :: 16;
    checkerboard_size := cast (int) (avail_width / Checkerboard_Grid_Size);
    for y : 0..checkerboard_size - 1
    {
        for x : 0..checkerboard_size - 1
        {
            if (x + y) % 2 == 0
                continue;

            draw_list.AddRectFilled (draw_list,
                min + .{xx (x * Checkerboard_Grid_Size), xx (y * Checkerboard_Grid_Size)},
                min + .{xx ((x + 1) * Checkerboard_Grid_Size), xx ((y + 1) * Checkerboard_Grid_Size)},
                ImGui.ColorConvertFloat4ToU32 (.{1, 1, 1, 0.5})
            );
        }
    }

    ImGui.Image (cast (ImGui.ImTextureID) g_texture_atlas, .{avail_width, avail_width});
}

UIShowGameMetricsWindow :: (opened : *bool)
{
    defer ImGui.End ();
    if !ImGui.Begin ("Game Metrics", opened)
        return;

    if ImGui.InputFloat3 ("XZY", *g_player.position.n, "%.3f")
        g_player.velocity = .{};
    ImGui.Checkbox ("Enable Collisions", *g_player.enable_collisions);
    ImGui.LabelText ("World Seed", "%lld", g_world.seed);
    ImGui.LabelText ("Loaded Chunks", "%lld", g_world.all_loaded_chunks.count);
    ImGui.LabelText ("Chunks Being Generated", "%lld", g_world.chunks_being_generated.count);
}

g_ui_show_demo_window := false;
g_ui_show_perlin_test_window := false;
g_ui_show_terrain_generator_window := false;
g_ui_show_texture_atlas_window := false;
g_ui_show_game_metrics_window := true;

UIUpdate :: ()
{
    if ImGui.BeginMainMenuBar ()
    {
        if ImGui.MenuItem ("Demo Window")
            g_ui_show_demo_window = true;
        if ImGui.MenuItem ("Perlin Test")
            g_ui_show_perlin_test_window = true;
        if ImGui.MenuItem ("Terrain Generator")
            g_ui_show_terrain_generator_window = true;
        if ImGui.MenuItem ("Texture Atlas")
            g_ui_show_texture_atlas_window = true;
        if ImGui.MenuItem ("Game Metrics")
            g_ui_show_game_metrics_window = true;

        ImGui.EndMainMenuBar ();
    }

    if g_ui_show_demo_window
        ImGui.ShowDemoWindow (*g_ui_show_demo_window);

    if g_ui_show_perlin_test_window
        UIShowPerlinTestWindow (*g_ui_show_perlin_test_window);

    if g_ui_show_terrain_generator_window
        UIShowTerrainGeneratorWindow (*g_ui_show_terrain_generator_window);

    if g_ui_show_texture_atlas_window
        UIShowTextureAtlasWindow (*g_ui_show_texture_atlas_window);

    if g_ui_show_game_metrics_window
        UIShowGameMetricsWindow (*g_ui_show_game_metrics_window);
}
