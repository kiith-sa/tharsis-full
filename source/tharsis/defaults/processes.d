//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

// Provides access to all processes packaged with Tharsis by default.
module tharsis.defaults.processes;


import std.typecons;
import std.exception: assumeWontThrow;


import tharsis.defaults.components;
public import tharsis.defaults.copyprocess;
import tharsis.defaults.resources;

import tharsis.entity.componenttypeinfo;
import tharsis.entity.componenttypemanager;
import tharsis.entity.entity;
import tharsis.entity.entityid;
import tharsis.entity.entitymanager;
import tharsis.entity.entityprototype;
import tharsis.entity.resourcemanager;

import tharsis.util.pagedarray;


import tharsis.entity.entitypolicy;

/// The default spawner process to be used with DefaultEntityManager.
alias DefaultSpawnerProcess = SpawnerProcess!DefaultEntityPolicy;

/** Reads SpawnerComponents and various spawn conditions and spawns new entities.
 *
 * Can be derived to add support for more spawn condition component types.
 *
 *
 * The SpawnerProcess processes SpawnerMultiComponents in combination with spawn
 * condition components (right now only TimedTriggerMultiComponent).
 *
 * To be able to spawn new entities, an entity needs both one or more 
 * SpawnerMultiComponents and some kind of spawn condition component/s (for now
 * only TimedTriggerMultiComponent).
 *
 * For example (with YAMLSource):
 * -------------------
 * spawnerMulti:
 *     - spawn:     test_data/entity1.yaml
 *       triggerID: 1
 *       override:
 *     - spawn:     test_data/entity2.yaml
 *       triggerID: 2
 *       override:
 *           physics:
 *               x: 50.0
 *               y: 50.0
 *               z: 50.0
 * 
 * timedSpawnConditionMulti:
 *     - time:      0.03
 *       timeLeft:  0.03
 *       periodic:  true
 *       triggerID: 1
 *     - time:      1.03
 *       timeLeft:  0.03
 *       periodic:  false
 *       triggerID: 2
 * -------------------
 *
 * In this example our entity has 2 spawner components, the first of which spawns
 * "test_data/entity1.yaml" without changing any of its components and the second
 * spawns "test_data/entity2.yaml", but overrides (example) "physics"
 * (PhysicsComponent). (If there is no "physics" component in the spawned entity, it
 * is added by the override.) It also has 2 spawn condition components. The first
 * triggers the spawner component with triggerID 1 every 30 milliseconds while the 
 * second triggers the spawner component with triggerID 2 exactly once.
 *
 * Relative properties:
 *
 * While we don't (yet) have any comphrehensive way to modify spawned entities other
 * than overriding, most games need at least some way to set properties of a spawnee 
 * relative to the spawner (for example, spawning an entity in a position relative to
 * the spawner).
 *
 * SpawnerProcess can recognize some properties as "relative", meaning the value of the
 * property in a spawnee is added to the value of the same property in the spawner 
 * entity. To mark a property of a component as relative, add a string user-defined
 * attribute with value "relative" to the property. 
 *
 * Example:
 * --------------------
 * struct PhysicsComponent
 * {
 *     enum ushort ComponentTypeID = userComponentTypeID!2;
 * 
 *     enum minPrealloc = 16384;
 * 
 *     enum minPreallocPerEntity = 1.0;
 * 
 *     // not relative
 *     float mass;
 *     // these 3 are relative
 *     @("relative") float x;
 *     @("relative") float y;
 *     @("relative") float z;
 * }
 * --------------------
 */
class SpawnerProcess(Policy)
{
private:
    /** A function that takes an entity prototype and adds a new entity to the 
     *  EntityManager (at the beginning of the next game update).
     */
    AddEntity addEntity_;

    /// Manages EntityPrototype resources, both prototypes to spawn and override prototypes.
    ResourceManager!EntityPrototypeResource prototypeManager_;

    /**
     * Entity prototypes to spawn during the next game update.
     *
     * Cleared at the beginning of the next game update (after entity manager adds the
     * new entities).
     */
    PagedArray!EntityPrototype toSpawn_;

    /// Memory used by prototypes in toSpawn_ to store components.
    PartiallyMutablePagedBuffer toSpawnData_;

    /// Component type manager, to access component type info.
    AbstractComponentTypeManager componentTypeManager_;

    /// Number of bytes to reserve when creating a prototype to ensure any prototype can fit.
    size_t maxPrototypeBytes_;

public:
    /** A type of delegates that create a new entity.
     *
     * Params:  prototype = Prototype of the entity to create.
     *
     * Returns: ID of the newly created entity.
     */
    alias EntityID delegate (ref immutable(EntityPrototype) prototype) @trusted nothrow
        AddEntity;

    /** Construct a SpawnerProcess.
     *
     * Params: addEntity              = Delegate to add an entity.
     *         prototypeManager       = Manages entity prototype resources.
     *                                  inline in an entity.
     *         componentTypeManager   = The component type manager where all used
     *                                  component types are registered.
     *
     * Examples:
     * --------------------
     * // EntityManager entityManager
     * // ResourceManager!EntityPrototypeResource prototypeManager
     * // ComponentTypeManager componentTypeManager
     * auto spawner = new SpawnerProcess(&entityManager.addEntity, prototypeManager,
     *                                   componentTypeManager);
     * --------------------
     */
    this(AddEntity addEntity,
         ResourceManager!EntityPrototypeResource prototypeManager,
         AbstractComponentTypeManager componentTypeManager)
        @safe pure nothrow
    {
        addEntity_              = addEntity;
        prototypeManager_       = prototypeManager;
        componentTypeManager_   = componentTypeManager;
        maxPrototypeBytes_ = EntityPrototype.maxPrototypeBytes(componentTypeManager);
    }

    /// Called at the beginning of a game update before processing any entities.
    void preProcess() nothrow
    {
        // Delete prototypes from the previous game update; they are be spawned by now.
        destroy(toSpawn_).assumeWontThrow;
        toSpawnData_.clear();
    }

    /** Reads spawners and spawn conditions. Spawns new entities; doesn't write any
     * future components.
     */
    void process(ref const(Context) context,
                 immutable SpawnerMultiComponent[] spawners,
                 immutable TimedSpawnConditionMultiComponent[] spawnConditions) nothrow
    {
        // Spawner components are kept even if all conditions that may spawn them are
        // removed (i.e. if no condition matches the spawnerID of a spawner component).
        // This allows the spawner component to be triggered if a new condition matching
        // its ID is added.
        outer: foreach(ref spawner; spawners)
        {
            // Find conditions matching this spawner component, and spawn if found.
            foreach(ref condition; spawnConditions)
            {
                // Spawn condition must match the spawner component.
                if(condition.spawnerID != spawner.spawnerID) { continue; }

                const baseHandle = spawner.spawn;
                const overHandle = spawner.overrideComponents;

                // If the spawner is not fully loaded yet (any of its resources not in
                // the Loaded state), ignore it completely and move on to the next one.
                //
                // This means we miss spawns when a spawner is not loaded. We may add
                // 'delayed' spawns to compensate for this in future.
                if(!spawnerReady(baseHandle, overHandle)) { continue outer; }

                // We've not reached the time to spawn yet.
                if(condition.timeLeft > 0.0f) { continue; }

                spawn(context, baseHandle, overHandle);
            }
        }
    }

private:
    /// Context for the process() method.
    alias Context = EntityManager!Policy.Context;

    /** Are spawner resources ready (loaded) for spawning?
     *
     * Starts (async) loading of the resources if not yet loaded.
     *
     * Params: baseHandle = Handle to the base prototype of the entity to spawn
     *                      (e.g. a unit type).
     *         overHandle = Handle to a prototype storing components added to or
     *                      overriding those in base (e.g. unit position or other
     *                      components that may vary between entities of same 'type').
     *
     * Returns: True if the resources are loaded and can be used to spawn an entity.
     *          False otherwise.
     */
    bool spawnerReady(const ResourceHandle!EntityPrototypeResource baseHandle,
                      const ResourceHandle!EntityPrototypeResource overHandle)
    {
        const baseState  = prototypeManager_.state(baseHandle);
        const overState  = prototypeManager_.state(overHandle);
        if(baseState == ResourceState.New) { prototypeManager_.requestLoad(baseHandle); }
        if(overState == ResourceState.New) { prototypeManager_.requestLoad(overHandle); }

        return baseState == ResourceState.Loaded && overState == ResourceState.Loaded;
    }

    /** Spawn a new entity created by applying an overriding prototype to a base prototype.
     *
     * Params: baseHandle = Handle to the base prototype of the entity to spawn
     *                      (e.g. a unit type).
     *         overHandle = Handle to a prototype storing components added to or
     *                      overriding those in base (e.g. unit position or other
     *                      components that may vary between entities of same 'type').
     */
    void spawn(ref const(Context) context,
               const ResourceHandle!EntityPrototypeResource baseHandle,
               const ResourceHandle!EntityPrototypeResource overHandle) nothrow
    {
        // Entity prototype serving as the base of the new entity.
        auto base = prototypeManager_.resource(baseHandle).prototype;
        // Entity prototype storing components applied to (overriding) base to create
        // the new entity.
        auto over = prototypeManager_.resource(overHandle).prototype;
        // Allocate memory for the new component.
        auto memory = toSpawnData_.getBytes(maxPrototypeBytes_);

        auto componentTypes = componentTypeManager_.componentTypeInfo;
        // Create the prototype of the entity to spawn.
        EntityPrototype combined = mergePrototypesOverride(base, over, memory, componentTypes);

        auto combinedBytes = combined.lockAndTrimMemory(componentTypes);

        // Iterate over all components of the prototype of the new entity, and the
        // components of same types in the spawner entity (current entity),
        // looking for properties that should be initialized relative to a value of the
        // same property (if any) in the spawner.
        //
        // Properties that are relative are updated as follows:
        // "spawnee.property += spawner.property" (the addRightToLeft() call).
        foreach(ref RawComponent comp; combined.componentRange(componentTypes))
        {
            auto typeInfo = &componentTypes[comp.typeID];
            // Relative does not work for MultiComponents.
            if(typeInfo.isMulti) { continue; }
            auto spawnerComp =
                context.rawPastComponent(comp.typeID, context.currentEntity.id);
            // If the spawner doesn't have this component, we don't have anything to be
            // relative to so we just keep the unchanged value.
            if(spawnerComp.isNull) { continue; }
            foreach(ref prop; typeInfo.properties!"relative"())
            {
                prop.addRightToLeft(comp, spawnerComp);
            }
        }

        toSpawnData_.lockBytes(combinedBytes);

        // Add the prototype to toSpawn_ to ensure it exists until the
        // beginning of the next game update when it is spawned.  It will be
        // deleted before executing this process during the next game update.

        toSpawn_.appendImmutable(combined);
        // Spawn the entity (at the beginning of the next game update).
        addEntity_(toSpawn_.atImmutable(toSpawn_.length - 1));
    }
}


/** Updates timed triggers.
 *
 * Must be registered with the EntityManager for TimedTriggerComponents to work.
 */
class TimedTriggerProcess
{
private:
    /// A function that gets the length (seconds) of the last game update.
    GetUpdateLength getUpdateLength_;

public:
    /// A function type that gets the length (seconds) of the last game update.
    alias real delegate () @safe pure nothrow GetUpdateLength;

    alias TimedSpawnConditionMultiComponent FutureComponent;

    /// Construct a TimedSpawnConditionProcess using specified delegate to get the time
    /// length of the last game update in seconds.
    this(GetUpdateLength getUpdateLength) @safe pure nothrow
    {
        getUpdateLength_ = getUpdateLength;
    }

    /// Reads and updates timed spawn conditions.
    void process(immutable TimedSpawnConditionMultiComponent[] pastConditions,
                 ref TimedSpawnConditionMultiComponent[] futureConditions) nothrow
    {
        size_t index;
        foreach(ref past; pastConditions)
        {
            auto future = &futureConditions[index];
            *future = past;
            if(past.timeLeft <= 0.0)
            {
                // timeLeft < 0 triggers a spawn in SpawnerProcess (if there is a 
                // SpawnerComponent to which this condition applies). After a spawn, if
                // the condition is not periodic, we forget the spawn condition
                // component.
                if(!past.periodic) { continue; }

                // Start the next period.
                future.timeLeft += past.time;
            }

            future.timeLeft -= getUpdateLength_();
            ++index;
        }
        futureConditions = futureConditions[0 .. index];
    } 
}
