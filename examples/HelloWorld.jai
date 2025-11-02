#load "../module.jai";
#import "Basic";

trace_func :: (message: *u8) #c_call {
    push_context {
        print("%\n", message);
    }
}

Layers :: enum u32 {
    NON_MOVING :: 0;
    MOVING :: 1;
};
LAYERS_COUNT :: #run cast(u32) (enum_names(Layers)).count;

Broad_Phase_Layers :: enum u8 {
    NON_MOVING :: 0;
    MOVING :: 1;
};
BROAD_PHASE_LAYERS_COUNT :: #run cast(u32) (enum_names(Broad_Phase_Layers)).count;

main :: () {
    if !JPH_Init() {
        return;
    }
    defer JPH_Shutdown();

    JPH_SetTraceHandler(trace_func);
    // JPH_SetAssertFailureHandler(handler: JPH_AssertFailureFunc);

    job_system := JPH_JobSystemThreadPool_Create(null);
    defer JPH_JobSystem_Destroy(job_system);

    // We use only 2 layers: one for non-moving objects and one for moving objects
    object_layer_pair_filter_table := JPH_ObjectLayerPairFilterTable_Create(2);
    JPH_ObjectLayerPairFilterTable_EnableCollision(
        object_layer_pair_filter_table, xx Layers.NON_MOVING, xx Layers.MOVING);
    JPH_ObjectLayerPairFilterTable_EnableCollision(
        object_layer_pair_filter_table, xx Layers.MOVING, xx Layers.NON_MOVING);

    // We use a 1-to-1 mapping between object layers and broadphase layers
    broad_phase_layer_interface_table := JPH_BroadPhaseLayerInterfaceTable_Create(2, 2);
    JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
        broad_phase_layer_interface_table, xx Layers.NON_MOVING, xx Broad_Phase_Layers.NON_MOVING);
    JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
        broad_phase_layer_interface_table, xx Layers.MOVING, xx Broad_Phase_Layers.MOVING);

    object_vs_broad_phase_layer_filter := JPH_ObjectVsBroadPhaseLayerFilterTable_Create(
        broad_phase_layer_interface_table, 2, object_layer_pair_filter_table, 2);

    settings : JPH_PhysicsSystemSettings;
    settings.maxBodies = 65536;
    settings.numBodyMutexes = 0;
    settings.maxBodyPairs = 65536;
    settings.maxContactConstraints = 65536;
    settings.broadPhaseLayerInterface = broad_phase_layer_interface_table;
    settings.objectLayerPairFilter = object_layer_pair_filter_table;
    settings.objectVsBroadPhaseLayerFilter = object_vs_broad_phase_layer_filter;
    system := JPH_PhysicsSystem_Create(*settings);
    defer JPH_PhysicsSystem_Destroy(system);
    body_interface := JPH_PhysicsSystem_GetBodyInterface(system);

    floor_id : JPH_BodyID;
    defer JPH_BodyInterface_RemoveAndDestroyBody(body_interface, floor_id);
    {
        // Next we can create a rigid body to serve as the floor, we make a large box
        // Create the settings for the collision volume (the shape).
        // Note that for simple shapes (like boxes) you can also directly construct a BoxShape.
        box_half_extents := JPH_Vec3.{ x = 100.0, y = 1.0, z = 100.0 };
        floor_shape := JPH_BoxShape_Create(*box_half_extents, JPH_DEFAULT_CONVEX_RADIUS);

        floor_position := JPH_Vec3.{ x = 0.0, y = -1.0, z = 0.0 };
        floor_settings := JPH_BodyCreationSettings_Create3(
            xx floor_shape,
            *floor_position,
            null, // Identity
            .JPH_MotionType_Static,
            xx Layers.NON_MOVING);
        defer JPH_BodyCreationSettings_Destroy(floor_settings);

        // Create the actual rigid body
        floor_id = JPH_BodyInterface_CreateAndAddBody(body_interface, floor_settings, .JPH_Activation_DontActivate);
    }

    // Sphere
    sphere_id : JPH_BodyID;
    defer JPH_BodyInterface_RemoveAndDestroyBody(body_interface, sphere_id);
    {
        sphere_shape := JPH_SphereShape_Create(50.0);
        sphere_position := JPH_Vec3.{ x = 0.0, y = 2.0, z = 0.0 };
        sphere_settings := JPH_BodyCreationSettings_Create3(
            xx sphere_shape,
            *sphere_position,
            null, // Identity
            .JPH_MotionType_Dynamic,
            xx Layers.MOVING);
        defer JPH_BodyCreationSettings_Destroy(sphere_settings);

        sphere_id = JPH_BodyInterface_CreateAndAddBody(body_interface, sphere_settings, .JPH_Activation_Activate);
    }

    // Now you can interact with the dynamic body, in this case we're going to give it a velocity.
    // (note that if we had used CreateBody then we could have set the velocity straight on the body before adding it to the physics system)
    sphere_linear_velocity := JPH_Vec3.{ x = 0.0, y = -5.0, z = 0.0 };
    JPH_BodyInterface_SetLinearVelocity(body_interface, sphere_id, *sphere_linear_velocity);

    {
        CHARACTER_HEIGHT_STANDING := 1.35;
        CHARACTER_RADIUS_STANDING := 0.3;
        CHARACTER_HEIGHT_CROUCHING := 0.8;
        CHARACTER_RADIUS_CROUCHING := 0.3;
        INNER_SHAPE_FRACTION := 0.9;

        capsule_shape := JPH_CapsuleShape_Create(0.5 * CHARACTER_HEIGHT_STANDING, CHARACTER_RADIUS_STANDING);
        position := JPH_Vec3.{ 0.0, 0.05 * CHARACTER_HEIGHT_STANDING + CHARACTER_RADIUS_STANDING, 0.0 };
        standing_shape := JPH_RotatedTranslatedShape_Create(*position, null, xx capsule_shape);

        character_settings : JPH_CharacterVirtualSettings;
        JPH_CharacterVirtualSettings_Init(*character_settings);
        character_settings.base.shape = xx standing_shape;
        character_settings.base.supportingVolume =
            JPH_Plane.{ normal = .{ 0, 1, 0 }, distance = -CHARACTER_RADIUS_STANDING };
        CHARACTER_VIRTUAL_POSITION :: JPH_RVec3.{ -5, 0, 3 };

        animated_character_virtual :=
            JPH_CharacterVirtual_Create(*character_settings, *CHARACTER_VIRTUAL_POSITION, null, 0, system);
    }

    joint_settings : JPH_SixDOFConstraintSettings;
    JPH_SixDOFConstraintSettings_Init(*joint_settings);

    // We simulate the physics world in discrete time steps. 60 Hz is a good rate to update the physics system.
    DELTA_TIME :: 1.0 / 60.0;

    // Optional step: Before starting the physics simulation you can optimize the broad phase. This improves collision detection performance (it's pointless here because we only have 2 bodies).
    // You should definitely not call this every frame or when e.g. streaming in a new level section as it is an expensive operation.
    // Instead insert all new objects in batches instead of 1 at a time to keep the broad phase efficient.
    JPH_PhysicsSystem_OptimizeBroadPhase(system);

    step : u32 = 0;
    while (JPH_BodyInterface_IsActive(body_interface, sphere_id)) {
        // Next step
        step = step + 1;

        // Output current position and velocity of the sphere
        position : JPH_RVec3;
        velocity : JPH_RVec3;

        JPH_BodyInterface_GetCenterOfMassPosition(body_interface, sphere_id, *position);
        JPH_BodyInterface_GetLinearVelocity(body_interface, sphere_id, *velocity);
        print("Step %: Position = (%, %, %), Velocity = (%, %, %)\n", step, position.x, position.y, position.z, velocity.x, velocity.y, velocity.z);

        // If you take larger steps than 1 / 60th of a second you need to do multiple collision steps in order to keep the simulation stable. Do 1 collision step per 1 / 60th of a second (round up).
        COLLISION_STEPS :: 1;

        // Step the world
        JPH_PhysicsSystem_Update(system, DELTA_TIME, COLLISION_STEPS, job_system);
    }
}
