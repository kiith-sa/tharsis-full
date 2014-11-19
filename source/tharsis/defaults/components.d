//          Copyright Ferdinand Majerech 2013-2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module tharsis.defaults.components;


import tharsis.defaults.resources;
import tharsis.entity.componenttypeinfo;
import tharsis.entity.entityprototype;
public import tharsis.entity.lifecomponent;
import tharsis.entity.resourcemanager;

/** Contains data about an entity to spawn.
 *
 * Condition to trigger the spawn is represented by a TimedTriggerMultiComponent and
 * may be represented by more trigger component types in future.
 *
 * See_Also: SpawnerProcess
 */
@("defaultsComponent")
struct SpawnerMultiComponent
{
    enum ComponentTypeID = maxBuiltinComponentTypes + 1;

    /// It's unlikely that one entity would spawn more than 8192 different entities.
    enum maxComponentsPerEntity = 8192;

    /// Cheap enough and won't be exceeded in most cases.
    enum minPrealloc = 16384;

    /// Assume a third of entities can spawn other entities (e.g. entities with weapons).
    enum minPreallocPerEntity = 0.3;

    /// Resource handle to the prototype of the entity to spawn.
    ResourceHandle!EntityPrototypeResource spawn;

    /** Resource handle to a prototype storing all components to apply on top of those
     * in spawn, overriding or adding to components of spawn.
     *
     * Used to modify spawnees directly in the spawner source.
     */
    @(PropertyName("override")) ResourceHandle!EntityPrototypeResource overrideComponents;

    /// Spawns are triggered by triggers matching this ID.
    ushort triggerID = 0;
}
unittest
{
    import tharsis.defaults.yamlsource;
    import tharsis.entity.componenttypemanager;
    auto compTypeMgr = new ComponentTypeManager!YAMLSource(YAMLSource.Loader());
    compTypeMgr.registerComponentTypes!SpawnerMultiComponent();
}


/** Triggers a spawn after specified time.
 *
 * Also supports periodic spawns.
 */
@("defaultsComponent")
struct TimedTriggerMultiComponent
{
    enum ComponentTypeID = maxBuiltinComponentTypes + 2;

    /// Should be enough even for extreme cases.
    enum maxComponentsPerEntity = 4096;

    /// Cheap enough and won't be exceeded in most cases.
    enum minPrealloc = 8192;

    /// Assume a third of entities can spawn (e.g. entities with weapons).
    enum minPreallocPerEntity = 0.3;


    /** Time since the creation of the entity when to spawn.
     *
     * If periodic, this is the period.
     */
    float time = 1.0f;
    /** The time left until the trigger is triggered.
     *
     * Can be set from the start to a different value to force the trigger to be
     * triggered earlier.
     */
    float timeLeft = 1.0f;
    /// If true, spawns periodically, not just once.
    bool periodic = false;
    /// ID of the trigger, used to determine what is being triggered.
    ushort triggerID;
}
