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

/** Reads SpawnerComponents and various triggers and spawns new entities.
 *
 * Can be derived to add support for more trigger component types.
 *
 *
 * The SpawnerProcess processes SpawnerMultiComponents in combination with trigger
 * components (right now only TimedTriggerMultiComponent).
 *
 * To be able to spawn new entities, an entity needs both one or more
 * SpawnerMultiComponents and some kind of trigger component/s (for now only
 * TimedTriggerMultiComponent).
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
 * timedTriggerMulti:
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
 * "test_data/entity1.yaml" without changing any of its components and the second spawns
 * "test_data/entity2.yaml", but overrides (example) "physics" (PhysicsComponent).
 * (If there is no "physics" component in the spawned entity, it is added by the
 * override.) It also has 2 trigger components. The first triggers the spawner component
 * with triggerID 1 every 30 milliseconds while the second triggers the spawner
 * component with triggerID 2 exactly once.
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
     * Params: addEntity            = Delegate to add an entity.
     *         prototypeManager     = Manages entity prototype resources.
     *         componentTypeManager = The component type manager where all used
     *                                component types are registered.
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
        addEntity_            = addEntity;
        prototypeManager_     = prototypeManager;
        componentTypeManager_ = componentTypeManager;
        maxPrototypeBytes_    = EntityPrototype.maxPrototypeBytes(componentTypeManager);
    }

    /// Called at the beginning of a game update before processing any entities.
    void preProcess() nothrow
    {
        // Delete prototypes from the previous game update; they are be spawned by now.
        destroy(toSpawn_).assumeWontThrow;
        toSpawnData_.clear();
    }

    /// Reads spawners and triggers. Spawns new entities; doesn't write any future components.
    void process(ref const(Context) context,
                 immutable SpawnerMultiComponent[] spawners,
                 immutable TimedTriggerMultiComponent[] triggers) nothrow
    {
        // Spawner components are kept even if all triggers that may spawn them are
        // removed (i.e. if no trigger matches the triggerID of a spawner component).
        // This allows the spawner component to be triggered if a new trigger matching
        // its ID is added.

        // Find triggers matching this spawner component, and spawn if found.
        outer: foreach(ref spawner; spawners) foreach(ref trigger; triggers)
        {
            // Spawn trigger must match the spawner component.
            if(trigger.triggerID != spawner.triggerID) { continue; }

            // If the spawner is not fully loaded (any of its resources not in the
            // Loaded state), ignore it completely and move on to the next one. This
            // means we miss spawns when a spawner is not loaded. We may add 'delayed'
            // spawns to compensate for this in future.
            if(!spawnerReady(spawner)) { continue outer; }

            // Is it time to spawn?
            if(trigger.timeLeft <= 0.0f) { spawn(context, spawner); }
        }
    }

protected:
    /// Context for the process() method.
    alias Context = EntityManager!Policy.Context;

    /** Are spawner resources used by a spawner component ready (loaded) for spawning?
     *
     * Starts (async) loading of the resources if not yet loaded.
     *
     * Params: spawner = The spawner component to check.
     *
     * Returns: True if the resources are loaded and can be used to spawn an entity.
     *          False otherwise.
     */
    final bool spawnerReady(ref const SpawnerMultiComponent spawner) nothrow
    {
        // Handle to the base prototype of the entity to spawn (e.g. a unit type).
        const baseHandle = spawner.spawn;
        // Handle to a prototype storing components added to or overriding those in base
        // (e.g. position or other components that may vary between entities of same 'type').
        const overHandle = spawner.overrideComponents;
        const baseState  = prototypeManager_.state(baseHandle);
        const overState  = prototypeManager_.state(overHandle);
        if(baseState == ResourceState.New) { prototypeManager_.requestLoad(baseHandle); }
        if(overState == ResourceState.New) { prototypeManager_.requestLoad(overHandle); }

        return baseState == ResourceState.Loaded && overState == ResourceState.Loaded;
    }

    /** Spawn a new entity created by applying an overriding prototype to a base prototype.
     *
     * Params: spawner = Spawner component to spawn from.
     */
    void spawn(ref const(Context) context, ref const SpawnerMultiComponent spawner)
        nothrow
    {
        // Handle to the base prototype of the entity to spawn (e.g. a unit type).
        const baseHandle = spawner.spawn;
        // Handle to a prototype storing components added to or overriding those in base
        // (e.g. position or other components that may vary between entities of same 'type').
        const overHandle = spawner.overrideComponents;

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
        // components of same types in the spawner entity (current entity), looking for
        // properties that should be initialized relative to a value of the same property
        // (if any) in the spawner.
        //
        // Properties that are relative are updated as follows:
        // "spawnee.property += spawner.property" (the addRightToLeft() call).
        foreach(ref RawComponent comp; combined.componentRange(componentTypes))
        {
            auto typeInfo = &componentTypes[comp.typeID];
            // Relative does not work for MultiComponents.
            if(typeInfo.isMulti) { continue; }
            auto spawnerComp = context.rawPastComponent(comp.typeID, context.entity.id);
            // If the spawner doesn't have this component, we don't have anything to be
            // relative to so we just keep the unchanged value.
            if(spawnerComp.isNull) { continue; }
            foreach(ref prop; typeInfo.properties!"relative"())
            {
                prop.addRightToLeft(comp, spawnerComp);
            }
        }

        auto hookRange = combined.componentRange(componentTypes);
        spawnHook(hookRange);

        toSpawnData_.lockBytes(combinedBytes);

        // Add the prototype to toSpawn_ to ensure it exists until the
        // beginning of the next game update when it is spawned.  It will be
        // deleted before executing this process during the next game update.

        toSpawn_.appendImmutable(combined);
        // Spawn the entity (at the beginning of the next game update).
        addEntity_(toSpawn_.atImmutable(toSpawn_.length - 1));
    }

    /** Called right before spawning an entity.
     *
     * Can be used by derived SpawnerProcess implementations to modify components
     * of an entity just before spawning.
     *
     * Currently, it is only possible to modify components already present, not add or
     * remove components.
     *
     * Params:
     *
     * components = A range of (modifiable) components in an entity that's about to spawn.
     */
    void spawnHook(ref EntityPrototype.GenericComponentRange!(No.isConst) components)
        @system nothrow
    {
        return;
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

    alias FutureComponent = TimedTriggerMultiComponent;

    /** Construct a TimedTriggerProcess using specified delegate to get the time
     * length of the last game update in seconds.
     */
    this(GetUpdateLength getUpdateLength) @safe pure nothrow
    {
        getUpdateLength_ = getUpdateLength;
    }

    /// Reads and updates timed triggers.
    void process(immutable TimedTriggerMultiComponent[] pastTriggers,
                 ref TimedTriggerMultiComponent[] futureTriggers) nothrow
    {
        size_t index;
        foreach(ref past; pastTriggers)
        {
            auto future = &futureTriggers[index];
            *future = past;
            if(past.timeLeft <= 0.0)
            {
                // timeLeft <= 0 also triggers a spawn in SpawnerProcess (if there is a
                // SpawnerComponent to which this trigger applies). After a spawn, if
                // the trigger is not periodic, we forget the trigger component.
                if(!past.periodic) { continue; }

                // Start the next period.
                future.timeLeft += past.time;
            }

            future.timeLeft -= getUpdateLength_();
            ++index;
        }
        futureTriggers = futureTriggers[0 .. index];
    }
}


/** A dummy process type.
 *
 * ProcessSig must be a function/delegate and is used to specify the signature of the
 * process() method of the DummyProcess.
 */
class DummyProcess(alias ProcessSig)
{
private:
    // Overhead pattern between processed entities.
    uint[] entityOverheadPattern_;

    // Overhead pattern between frames.
    uint[] frameOverheadPattern_;

    // Index of the current entity among the entities processed by this process.
    //
    // (i.e. not *all entities*)
    size_t entity_;

    // Index of the current frame.
    size_t frame_;

    // process() does writes here to ensure they are not optimized away by the compiler.
    ulong writeDummy_;

public:
    /** Construct a DummyProcess.
     *
     * Params:
     *
     * entityOverheadPattern = Overhead pattern between processed entitites.
     *
     *                         E.g. if this is [1, 2], the first entity will have
     *                         'single overhead', the second will have 'doubled overhead',
     *                         the third will again have 'single overhead', etc.
     *
     * frameOverheadPattern  = Overhead pattern between frames.
     *
     *                         E.g. if this is [1, 2, 4], the first frame will have
     *                         'single overhead', the second will have 'doubled overhead',
     *                         the third will have quadrupled overhead, the fourth will
     *                         again have 'single overhead', etc.
     */
    this(uint[] entityOverheadPattern, uint[] frameOverheadPattern) @safe pure nothrow
    {
        entityOverheadPattern_ = entityOverheadPattern;
        frameOverheadPattern_  = frameOverheadPattern;
    }

    /// Sets the current frame/entity
    void preProcess() nothrow
    {
        ++frame_;
        entity_ = 0;
    }

    import std.traits;
    import std.string: format, join;


    // pragma(msg, generateParams());


    /// Simulates process overhead.
    mixin(q{
    void process(%s) nothrow
    {
        ++entity_;
        // Determine how much overhead to simulate.
        const overhead = entityOverheadPattern_[entity_ %% entityOverheadPattern_.length] *
                         frameOverheadPattern_[frame_ %% frameOverheadPattern_.length];

        import tharsis.entity.processtypeinfo;
        alias paramInfo = processMethodParamInfo!(process);
        // Simulating 'real' overhead including reading the past components and writing
        // the future component.
        foreach(i; 0 .. overhead)
        {
            import tharsis.util.typetuple;
            // Iterate over all params
            foreach(p; Sequence!(0, ParamTypes.length))
            {
                alias Info = paramInfo[p];
                static if(Info.isComponent)
                {
                    // Past component - read and update writeDummy_
                    static if(!isMutable!(Info.Component))
                    {
                        // Read the past component by bytes and update writeDummy_.

                        // writeDummy_ is basically the sum of bytes of all past
                        // components read so far
                        foreach(b; 0 .. Info.Component.sizeof)
                        {
                            mixin(q{
                            writeDummy_ += (cast(ubyte*)(&param%%s))[b];
                            }.format(p));
                        }
                    }
                    // Future component - write
                    else
                    {
                        // Write to the future component using writeDummy_ as a base.
                        foreach(b; 0 .. Info.Component.sizeof)
                        {
                            mixin(q{
                            (cast(ubyte*)(&param%%s))[b] = (writeDummy_ + b) %%%% ubyte.max;
                            }.format(p));
                        }
                    }
                }
            }
        }
    }
    }.format(generateParams()));

    // ProcessSig determines whether or not we write to any future component.
    static if(hasFutureComponent!(process))
    {
        alias FutureComponent = FutureComponentType!process;
    }

private:
    import tharsis.entity.processtypeinfo;

    alias ParamTypes = ParameterTypeTuple!ProcessSig;

    // Generate the parameter list of process()
    static string generateParams()
    {
        alias ParamStorageClasses = ParameterStorageClassTuple!ProcessSig;
        string[] parts;
        foreach(i, Type; ParamTypes)
        {
            string part = "ParameterTypeTuple!ProcessSig[%s] param%s".format(i, i);
            if(ParamStorageClasses[i] & ParameterStorageClass.out_)
            {
                part = "out " ~  part;
            }
            if(ParamStorageClasses[i] & ParameterStorageClass.ref_)
            {
                part = "ref " ~  part;
            }
            parts ~= part;
        }
        return parts.join(", ");
    }
}
unittest
{
    struct Data
    {
        uint data;
    }

    alias Dummy1 = dummyComponent!(userComponentTypeID!1, Data);
    alias Dummy2 = dummyComponent!(userComponentTypeID!2, Data);

    auto process = new DummyProcess!((ref const Dummy1 a, ref const Dummy2 b) => 2)([1], [1]);
}
